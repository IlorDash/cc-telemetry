# cc-telemetry vs token-dashboard и claude-code-karma

Сравнение подходов к сбору статистики Claude Code и список идей, которые можно перенести
в cc-telemetry (данные + UI в Grafana). Дата анализа: 2026-11-14.

| Проект | Стек | Источник данных |
| --- | --- | --- |
| **cc-telemetry** (наш) | OTel Collector → ClickHouse → Grafana (Docker) | OTLP-события, которые Claude Code шлёт сам (`CLAUDE_CODE_ENABLE_TELEMETRY`) |
| **token-dashboard** (nateherkai) | Python stdlib + SQLite + vanilla JS/ECharts | JSONL-транскрипты `~/.claude/projects/**/*.jsonl` |
| **claude-code-karma** (JayantDevkar) | FastAPI + SQLite + SvelteKit/Chart.js | JSONL-транскрипты + весь `~/.claude/` + свои хуки Claude Code |

---

## 1. Как они собирают данные

Да, оба читают JSONL-транскрипты. Но устроено по-разному.

### token-dashboard
- `scanner.py` обходит `~/.claude/projects/<slug>/<session>.jsonl` **инкрементально**: в таблице
  `files` хранит mtime и байтовое смещение, при повторном скане читает только новые строки
  (раз в 30 с, обновление UI через SSE).
- Из каждой строки берёт `message.usage` (input / output / cache_read /
  `cache_creation.ephemeral_5m` / `ephemeral_1h`), `message.model`, `stop_reason`, `cwd`,
  `gitBranch`, `isSidechain`, `agentId`, текст промпта.
- Из блоков `tool_use` достаёт «цель» вызова (`file_path`, `command`, `pattern`, `url`, …), из
  блоков `tool_result` — **размер результата** (символы / 4 ≈ токены) и `is_error`.
- **Дедупликация**: Claude Code пишет один ответ модели 2–3 раза по мере стриминга; сканер
  оставляет только последний снимок по `(session_id, message.id)`. Без этого токены
  завышаются.
- **Стоимость считает сам** по `pricing.json` (ручная таблица цен + fallback по слову
  `opus/sonnet/haiku` в имени модели). Таблицу надо обновлять руками.

### claude-code-karma
- API на FastAPI парсит JSONL в Pydantic-модели **по запросу** (ленивое чтение), метаданные
  индексирует в SQLite.
- Читает гораздо больше, чем транскрипты: `subagents/agent-*.jsonl`, `tool-results/*.txt`,
  todos, plans, `history.jsonl`, конфиг хуков и плагинов, debug-логи.
- **Свои хуки Claude Code** (основная фича, «Tier 2»):
  - `live_session_tracker.py` — на `SessionStart / UserPromptSubmit / PostToolUse /
    Notification / Stop / SessionEnd` пишет состояние сессии в
    `~/.claude_karma/live-sessions/<id>.json` → статусы LIVE / WAITING / STOPPED / STALE / ENDED;
  - `session_title_generator.py` — на `SessionEnd` генерирует название сессии через Haiku;
  - привязка сессий к тикетам по имени git-ветки.

### cc-telemetry (наш)
- Claude Code сам отправляет события (`api_request`, `tool_result`, `tool_decision`,
  `user_prompt`, `subagent_completed`, `skill_activated`, `hook_execution_*`) по OTLP на сервер.
- Collector → ClickHouse `otel.otel_logs` → плоские вью `cc.*` → один дашборд Grafana.

---

## 2. Чем подходы отличаются

| Критерий | JSONL (их) | OTel (наш) |
| --- | --- | --- |
| Установка | Ноль: запустил скрипт — и всё | Docker-стек + настройка каждого клиента |
| **Несколько ПК** | Нет: только машина, где лежат файлы | **Да**: все клиенты в одной базе, `host` / `project` |
| **История** | Только то, что лежит на диске; **Claude Code удаляет JSONL через ~30 дней** | **Хранится сколько угодно** в ClickHouse |
| Прошлое до установки | **Есть** (вся история за 30 дней сразу) | Нет: только с момента включения телеметрии |
| Сервер недоступен | Не важно | События теряются (короткий retry на клиенте) |
| Стабильность формата | JSONL — внутренний формат, **недокументирован**, меняется между версиями | OTel-события — **документированный** интерфейс |
| Стоимость | Своя таблица цен, ручное обновление, оценка | `cost_usd` считает сам Claude Code |
| Дубли при стриминге | Нужна дедупликация по `message.id` | Нет: одно `api_request` на запрос |
| Задержки | — | `duration_ms`, `ttft_ms` по каждому запросу, длительность инструментов |
| Решения о правах | Нет | `tool_decision` (accept/reject, источник: config / hook / user) |
| Хуки | Только конфиг (karma) | Время выполнения каждого хука |
| Атрибуция скиллов | Частичная (у token-dashboard — по `SKILL.md`) | `skill.name` прямо на `api_request` |
| Названия сессий | Есть (`custom-title`, `ai-title`) | **Нет** в телеметрии |
| Git-ветка, `cwd` | Есть на каждой строке | Нет (только `project` из `OTEL_RESOURCE_ATTRIBUTES`) |
| Разбивка cache 5m / 1h | Есть | Только сумма `cache_creation_tokens` |
| Текст ответов, вывод инструментов | Полностью | Ответ — опционально (мы его отбрасываем в collector), вывода инструментов нет |
| Размер результата инструмента | Есть (≈ токены) | Есть: `tool_result_size_bytes` |
| Live-статус сессии | karma — через хуки | Нет явного, но можно вывести из «последнего события» |

**Вывод: их способ не «лучше», он про другое.** JSONL — это «личный просмотрщик своей машины»:
мгновенный старт, вся история за 30 дней, полное содержимое диалогов. OTel — это «сервер
статистики»: несколько ПК, вечное хранение, официальный стабильный интерфейс, точная стоимость
от самого Claude Code, задержки, отказы прав, время хуков. Для нашей задачи (центральный сбор
с нескольких клиентов) OTel — правильная основа.

Реальные преимущества JSONL, которых нам не хватает: **бэкфилл истории**, **названия сессий**,
**git-ветка**, **разбивка кэша 5m/1h**.

### Гибрид (опционально, на будущее)
Небольшой импортёр JSONL на клиенте (`client/import-transcripts.ps1` или Python), который шлёт в
ClickHouse только то, чего нет в телеметрии: `session_id → title, git_branch, cwd`. Ключ
сопоставления — `session.id` (он совпадает с именем файла сессии); у ассистентских строк JSONL
есть `requestId`, который должен совпадать с `request_id` в `api_request` (**проверить**). Бэкфилл
токенов из JSONL возможен, но требует дедупликации и своей таблицы цен — рискованно смешивать с
точными `cost_usd`.

---

## 3. Что полезного взять (данные и логика)

Всё ниже реализуемо **на наших текущих данных** через новые вью / запросы, без изменения клиента.

| # | Идея | Откуда | Как у нас |
| --- | --- | --- | --- |
| 1 | **Движок подсказок (Tips)** | token-dashboard `tips.py` | Вью `cc.tips` (UNION нескольких правил) + таблица в Grafana. Правила ниже. |
| 2 | **Самые дорогие промпты** | token-dashboard, вкладка Prompts | `GROUP BY prompt_id` по `cc.api_requests` + `cc.tool_calls`: стоимость, токены, число инструментов, самый «тяжёлый» результат; ссылка в сессию |
| 3 | **Cache hit rate** | оба | `cache_read / (cache_read + input + cache_creation)` — stat + по проектам |
| 4 | **Разбивка по моделям** | token-dashboard | `model` уже есть в `cc.api_requests` → donut |
| 5 | **«Стоимость vs подписка»** | token-dashboard (`max-20x`, «pay $200/mo») | Константа-переменная `plan_monthly` в дашборде; stat «API-эквивалент / месяц» и коэффициент окупаемости |
| 6 | **Активные сейчас сессии** | karma, live sessions | `cc.sessions` с `last_event > now() - 2 min` → LIVE, `< 15 min` → IDLE; без хуков |
| 7 | **Ритм работы** | karma, «coding rhythm» | Heatmap час × день недели по `api_request` |
| 8 | **Main vs subagent по инструменту** | karma, tool detail | У нас уже есть `actor` — нужен только запрос |
| 9 | **Выбросы субагентов** | token-dashboard | max vs mean токенов по `agent_type` из `subagent_completed` |
| 10 | Объяснение метрик | token-dashboard «What do these numbers mean?» | Text-панель в свёрнутом ряду |

**Правила для Tips** (за последние 7 дней, пороги — как у token-dashboard, потом подстроить):
- низкий cache hit rate (< 40 %) в проекте;
- один файл читается > 10 раз (у нас уже есть панель 24 — превратить в подсказку);
- одна Bash-команда > 15 раз;
- ≥ 5 результатов инструментов > ~200 КБ (`tool_result_size_bytes`) — «режьте вывод head/tail»;
- много коротких ответов Opus (< 500 output tokens) — возможная экономия на Sonnet
  (считать по нашему `cost_usd`, а не по захардкоженным ценам);
- субагент с выбросом (max > 6 × mean и > 50k токенов);
- **наши собственные, которых у них нет**: частые отказы прав (`tool_decision = reject`) по
  одному инструменту — кандидат в allow-list; медленный хук (`hook_execution_complete`);
  высокий `ttft_ms`.

Чего у них **не брать**: свою таблицу цен (у нас точный `cost_usd`), дедупликацию снимков (у
нас нет дублей), браузер плагинов / хуков / тикетов karma (это просмотр локального конфига, не
телеметрия).

---

## 4. UI: можно ли сделать Grafana как на скриншоте

**Да, почти всё со скриншота token-dashboard делается штатными панелями Grafana 12.1.**
Сейчас дашборд — одна длинная страница из 4 stat-панелей и таблиц; визуально «бедно» в основном
из-за отсутствия графиков по дням, компактных KPI и навигации.

| Элемент скриншота | Как сделать в Grafana |
| --- | --- |
| Ряд из 7 KPI (Sessions, Turns, Input, Output, Cache read, Cache create, Est. cost) | 7 `stat`-панелей шириной ~3–4, unit `short` (даёт `7.7 Mil`) или `locale`, цвет стоимости через `fixedColor`, `graphMode: area` даёт спарклайн |
| Подпись «pay $200/mo on Max 20x» | `description` панели или отдельный маленький stat «окупаемость ×N» на переменной `plan_monthly` |
| Кнопки 7d / 30d / 90d / All | Временной пикер + `timepicker.quick_ranges` в JSON; либо dashboard links с `?from=now-7d` |
| «Your daily work» — стек input / output / cache create по дням | `timeseries` с `drawStyle: bars`, `stacking: normal`, группировка `toStartOfDay(ts)` (или `barchart`) |
| «Daily cache reads» отдельно | Отдельная панель — правильное решение у них: cache read на 1–2 порядка больше и «съедает» шкалу |
| Пояснения под заголовками графиков | `description` панели (иконка «i») или text-панель над графиком |
| «What do these numbers mean?» — раскрывающийся блок | Свёрнутый `row` с `text`-панелью (markdown) внутри |
| Tokens by project, share by model (donut), top tools | `barchart` / `bargauge`, `piechart` с `pieType: donut` |
| Recent sessions | Уже есть (панель 7) — добавить стоимость, cache hit, длительность, cell-подсветку |
| Вкладки Overview / Prompts / Sessions / … | **Несколько дашбордов** с общей полосой `links` (тег `cc`, `keepTime`, `includeVars`) — выглядит как меню вкладок |
| Тёмная тема | По умолчанию в Grafana |

**Где Grafana уступает кастомному фронту:** нет «клик по строке → раскрыть ответ и инструменты
прямо в таблице» (только переход по ссылке на другой дашборд / переменную), ограниченная
типографика карточек, нет произвольной вёрстки. Варианты, если понадобится больше:
1. плагин **Business Text** (`marcusolsson-dynamictext-panel`) — карточки на Handlebars/HTML из
   SQL-результата;
2. новые layouts с вкладками в Grafana 12 (dynamic dashboards, feature flag, экспериментально —
   **проверить** на 12.1 перед использованием);
3. свой фронт поверх HTTP-интерфейса ClickHouse — максимум гибкости, но это отдельный проект;
   **не рекомендую**, пока возможности Grafana не исчерпаны.

### Предлагаемая структура дашбордов

| Дашборд | Содержимое |
| --- | --- |
| **Overview** (домашний) | KPI-ряд (7 stat), daily work (стек), daily cache reads, токены по проектам, donut по моделям, top tools, recent sessions, cache hit rate, «активно сейчас», свёрнутое объяснение метрик |
| **Prompts** | Самые дорогие промпты; выбор промпта → его запросы, инструменты, размер результатов |
| **Sessions** | Текущие панели 7–8 + хронология выбранной сессии (запросы/инструменты по времени) |
| **Agents & skills** | Текущие 13–14, main vs subagent, выбросы субагентов |
| **Tools & files** | Текущие 16–24, отказы прав, Bash |
| **Tips** | Таблица `cc.tips`: категория, заголовок, текст, ссылка на источник |
| **Health** | Хуки, `ttft_ms`, `duration_ms`, ошибки инструментов, рабочий ритм (heatmap) |

---

## 5. Приоритеты

1. **Overview по образцу скриншота** — KPI-ряд, два дневных графика, donut по моделям,
   cache hit rate, объяснение метрик. Максимальный визуальный эффект, только JSON дашборда.
2. **Разбить на несколько дашбордов** с навигацией-ссылками (как вкладки).
3. **Prompts** — рейтинг дорогих промптов по `prompt_id`.
4. **Tips** — вью `cc.tips` + дашборд.
5. «Активно сейчас», heatmap ритма, «стоимость vs подписка».
6. (Опционально) импортёр JSONL для названий сессий и git-ветки.

Пункты 1–5 не требуют изменений на клиентах; правка `views.sql` применяется через
`docker compose run --rm views-init` и пересчитывает всю историю.

# cc-telemetry — улучшения дашборда и данных

## Backlog

### Производительность на слабом сервере

  - tags: [data, performance]
  - priority: low
  - workload: Hard
  - steps:
      - [ ] Замерить Overview и Tips после группы 3 на ARMv8.0 / ClickHouse 22.3
      - [x] Поднять refresh по умолчанию: дашборды обновляются раз в 5 мин и открываются на 24 ч, минимум в Grafana — 1 мин
      - [x] Лимиты ClickHouse для слабого сервера (low-resource.xml в config.d/users.d, cpus: 2) — на всех серверах
      - [ ] Замерить Overview на диапазоне All (now-10y) на ARM при refresh 5 мин
      - [ ] Проверить, что лимиты применяются на ClickHouse 25.8 (background_pool_size в профиле, см. pending-bugs)
      - [ ] Замерить cc.tips на ARM (8 правил поверх cc.events)
      - [ ] Если медленно: materialized-таблица для cc.session_project или кэш запросов Grafana
    ```md
    pending-bugs: каждый запрос к cc.events читает otel_logs ~4 раза. Отложено до появления
    реальных тормозов; группы 1–3 добавляют много новых панелей и cc.tips — риск растёт.
    Без группы: брать, только если замер покажет проблему.
    ```

### Обновить Grafana до 13.x

  - tags: [grafana, stack]
  - priority: low
  - workload: Normal
  - steps:
      - [ ] Проверить, что дашборды grafana/dashboards/*.json (schema v1) и плагин ClickHouse работают на 13.x
      - [ ] Переоценить вкладки (dynamic dashboards — GA в 13.x): URL вкладки, drill-down, keepTime
    ```md
    Итог исследований группы 1: и вкладки, и свежие версии Business Text (>= 6.2.3 требует
    Grafana 12.3+) упираются в версию Grafana. Не срочно.
    ```

## To Do

### README: описать новые дашборды

  - tags: [implement-group-5, docs]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Список дашбордов и что в каждом
      - [ ] Подсказки Tips и их пороги
      - [ ] Импортёр JSONL, если он сделан (для Windows- и Linux-клиентов)
      - [ ] Отметить: история хранится без срока, в отличие от JSONL (~30 дней)
    ```md
    README публичный: без личных данных. README уже описывает Windows и Linux — оба пути.
    Группа 5: описывает результат всех предыдущих групп.
    ```

## In Progress

## Done

### Импортёр JSONL: названия сессий и git-ветка

  - tags: [implement-group-4, data, client, research]
  - priority: low
  - workload: Hard
  - steps:
      - [x] Проверить: совпадает ли requestId из JSONL с request_id в api_request — да (req_…, 1:1)
      - [x] Проверить: session.id = имя файла сессии — да (<session>.jsonl, sessionId в каждой строке)
      - [x] Решить, куда писать и как доставлять с клиента — хук UserPromptSubmit (async) → OTLP/HTTP :4318 → otel_logs (ServiceName cc-session-meta)
      - [x] Этап 0 (проверено на CLI 2.1.323 логирующим хуком): см. заметку
      - [x] Сервер: 4318 следует за OTLP_BIND; setup-server.ps1 -EnableLan / setup-server.sh — фаервол и проброс для 4318
      - [x] Вью cc.session_meta: название (custom-title важнее ai-title), ветка, первый cwd
      - [x] Клиенты на Windows и Linux: вариант для setup-client.ps1 и setup-client.sh
      - [x] Импорт только того, чего нет в телеметрии: title, git_branch, cwd
      - [x] Использовать название вместо first_prompt в таблицах сессий
      - [x] cwd как самый надёжный источник project в cc.session_project (до label-эвристики по путям)
      - [x] Проверить на реальном клиенте (конфиг claude-guest → тестовый сервер, 2026-11-16): названия и ветки приходят, переименование уходит со следующим промптом
      - [ ] Продакшен (после закрытия карточки): git pull + setup-server.sh --update на сервере, setup-client -ImportHistory для основного конфига; Linux-клиент на самом сервере
      - [x] Удалить тестовые строки из otel_logs — 81 строка, после дампа (2026-11-16)
    ```md
    Итог: хук UserPromptSubmit (async) в setup-client.ps1 / .sh, -ImportHistory, -NoSessionMeta; 4318 следует за
    OTLP_BIND; вью cc.session_meta, проект: метка > папка cwd > пути; названия и ветка в таблицах и списке Session.
    Не проверено: Linux-клиент с jq без python3, Linux-клиент и setup-server.sh на настоящем Linux, ClickHouse 25.8.
    Проверено 2026-11-16 на Claude Code 2.1.325 (одна сессия): в JSONL есть ai-title, gitBranch и cwd
    в строках user / assistant; название появляется после первого ответа и не меняется, ветка одна,
    cwd меняется при переходе в подпапку — брать первый.
    Решение: один хук UserPromptSubmit с "async": true; отправляет только изменения (файл состояния) и
    догоняет другие JSONL, изменённые с прошлого запуска. SessionEnd не годится (окна просто закрывают),
    SessionStart не нужен. -ImportHistory / --import-history — разовая выгрузка старых сессий.
    Этап 0: на входе хука session_id, transcript_path, cwd, prompt_id, prompt (SessionStart: source
    startup / resume); env из settings доходит до хука, OTEL_* — нет (адрес сервера писать в команду хука);
    async-хук работает в фоне; /rename пишет custom-title, но UserPromptSubmit НЕ вызывает — новое имя
    уйдёт со следующим промптом или догонялкой; коллектор принимает OTLP/JSON на :4318 (curl из WSL и
    Invoke-RestMethod с Windows, кириллица цела). Тестовые строки ServiceName cc-session-meta-test в otel_logs.
    Гибрид OTel + JSONL. Токены из JSONL не импортировать: нужна дедупликация и своя
    таблица цен, нельзя смешивать с точным cost_usd.
    cwd закрыл бы ограничения угадывания проекта по путям (pending-bugs: cc.session_project).
    Группа 4: последний шаг меняет таблицы сессий в Overview и Sessions — после группы 3.
    ```

### Overview: ряд KPI из 7 карточек

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] Stat-панели Sessions, Turns, Input, Output, Cache read, Cache create, Cost
      - [x] Unit short / компактные числа, полные значения в tooltip
      - [x] Цвет стоимости через fixedColor, спарклайн (graphMode area)
      - [x] Все панели учитывают project / session / actor / skill и диапазон времени
    ```md
    Заменить текущие 4 stat-панели Summary рядом из 7 карточек, как в token-dashboard.
    Turns = число api_request с actor = main (или число user_prompt — решить при реализации).
    Задевает запись pending-bugs «Summary Sessions vs panel 7»: решить, как считать Sessions.
    Итог: 30 Sessions, 51 Turns (api_request с actor = main), 52–56 Input / Output / Cache read / Cache create / Cost.
    Sessions = сессии с запросом к модели (колонка requests в cc.sessions); то же правило в переменной
    session и таблицах сессий — запись pending-bugs закрыта. Summary 2–5 удалены.
    ```

### Overview: график «Daily work» по дням

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] Запрос: toStartOfDay(ts), суммы input / output / cache_creation
      - [x] timeseries с drawStyle bars и stacking normal (или barchart)
      - [x] Описание панели: что такое input / output / cache create
    ```md
    Стековые столбцы по дням: input, output, cache create. Cache read сюда не входит —
    он на 1–2 порядка больше и съедает шкалу.
    ```

### Overview: график «Daily cache reads»

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] Отдельная панель cache_read_tokens по дням
      - [x] Описание: cache read дешевле обычного input, высокие значения — это хорошо
    ```md
    Отдельный график рядом с Daily work, как на скриншоте token-dashboard.
    ```

### Overview: cache hit rate

  - tags: [implement-group-3, ui, overview, data]
  - priority: high
  - workload: Easy
  - steps:
      - [x] Stat: cache_read / (cache_read + input + cache_creation), unit percent
      - [x] Пороги цвета: < 40 % красный, 40–70 % жёлтый, > 70 % зелёный
      - [x] Таблица / bargauge hit rate по проектам
    ```md
    Метрика из обоих проектов-аналогов. Порог 40 % — как в правиле Tips у token-dashboard.
    ```

### Overview: токены по проектам

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] barchart / bargauge: total_tokens и cost_usd по project
      - [x] Ссылка с проекта на var-project
      - [x] unknown показывать отдельно, не прятать
    ```md
    Сравнение проектов на главной странице.
    project — эффективный: метка из OTEL_RESOURCE_ATTRIBUTES, иначе угаданный по путям инструментов.
    ```

### Overview: доля по моделям (donut)

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] piechart pieType donut по model из cc.api_requests
      - [x] Переключатель метрики не нужен: токены в donut, стоимость в легенде
    ```md
    Поле model уже есть в cc.api_requests — только запрос и панель.
    ```

### Overview: топ инструментов и последние сессии

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] bargauge: топ-10 инструментов по числу вызовов
      - [x] Таблица последних сессий: стоимость, токены, cache hit, длительность, первый промпт
      - [x] Подсветка ячеек стоимости (cell color по порогам)
      - [x] Ссылка session_id на дашборд Sessions
    ```md
    Нижняя часть Overview по образцу token-dashboard.
    Итог: 36 топ инструментов, 37 последние 10 сессий со ссылкой на cc-sessions (cache hit по тем же 10).
    ```

### Overview: блок «Что значат эти цифры?»

  - tags: [implement-group-3, ui, overview, docs]
  - priority: high
  - workload: Easy
  - steps:
      - [x] Свёрнутый row с text-панелью (markdown)
      - [x] Объяснить input, output, cache read, cache create, cost_usd, actor, aux
    ```md
    Аналог раскрывающейся панели «What do these numbers mean?» из token-dashboard.
    Подчеркнуть, что cost_usd считает сам Claude Code (API-эквивалент).
    ```

### Активные сейчас сессии

  - tags: [implement-group-3, data, ui, live]
  - priority: low
  - workload: Easy
  - steps:
      - [x] Статус по последнему событию: < 2 мин LIVE, < 15 мин IDLE
      - [x] Таблица на Overview: сессия, проект, host, статус, стоимость
    ```md
    Упрощённый аналог live sessions из karma — без хуков, только по телеметрии.
    Запрос прямо в панели, без новой вью (views.sql в группе 3 занят).
    Итог: панель 38 на Overview, учитывает project / session, игнорирует диапазон времени.
    ```

### Ритм работы (heatmap)

  - tags: [implement-group-3, ui, overview]
  - priority: low
  - workload: Easy
  - steps:
      - [x] Запрос: toHour(ts) × toDayOfWeek(ts), токены или запросы
      - [x] heatmap-панель (или таблица с cell color)
    ```md
    Аналог coding rhythm из karma.
    Итог: панель 39 — таблица день недели × час с цветом ячеек (время сервера, UTC в Docker).
    ```

### Стоимость против подписки

  - tags: [implement-group-3, ui, overview, cost]
  - priority: low
  - workload: Easy
  - steps:
      - [x] Переменная plan_monthly (custom: 0 / 20 / 100 / 200)
      - [x] Stat: API-эквивалент за месяц и коэффициент окупаемости
      - [x] Подпись «платите $N/мес» под карточкой Cost
    ```md
    Аналог переключателя плана из token-dashboard.
    Переменную plan_monthly добавить только в Overview — не трогать общие переменные.
    Итог: панель 40 «Last 30 days: API equivalent vs plan ($N/month)» — сумма за 30 дней и коэффициент.
    Подпись про план — в заголовке панели 40, не под карточкой Cost.
    ```

### Дашборд Sessions: хронология сессии

  - tags: [implement-group-3, ui, sessions, grafana]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] Текущие панели 7–8
      - [x] Хронология выбранной сессии: запросы и инструменты по времени (state timeline / table)
      - [x] Токены и стоимость по ходу сессии (накопительно)
    ```md
    Аналог вкладки Sessions (token-dashboard) и Session Timeline (karma).
    Итог: 100 хронология (UNION ALL, до 1000 событий), 101 / 102 накопительные стоимость и токены —
    только при выбранной сессии (заголовок «pick a session», noValue-подсказка).
    ```

### Дашборд Agents & skills

  - tags: [implement-group-3, ui, agents, grafana]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] Текущие панели 13–14
      - [x] Main vs subagent по каждому инструменту (по actor)
      - [x] Выбросы субагентов: max vs mean токенов по agent_type из subagent_completed
    ```md
    Идеи из karma (main vs subagent split) и token-dashboard (subagent outliers).
    Итог: 120 main vs subagents по инструменту, 121 выбросы (x mean = max / mean, от 6 подсвечено).
    ```

### Дашборд Tools & files

  - tags: [implement-group-3, ui, tools, grafana]
  - priority: medium
  - workload: Easy
  - steps:
      - [x] Перенести панели 16–24
      - [x] Топ результатов инструментов по tool_result_size_bytes
      - [x] Доля ошибок по инструменту (success = false)
    ```md
    В основном перенос существующих панелей плюс размер результатов.
    Итог: row 143 — 140 самые большие результаты, 141 доля ошибок, 142 размер результатов по инструменту.
    ```

### Дашборд Health

  - tags: [implement-group-3, ui, health, grafana]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] Время хуков (панель 26)
      - [x] ttft_ms и duration_ms запросов: p50 / p95 по модели и по дням
      - [x] Длительность инструментов, ошибки инструментов
    ```md
    Метрики, которых нет у JSONL-аналогов: задержки и накладные расходы хуков.
    Итог: 160–165. 160 / 161 дублируют логику actor из cc.api_requests (ttft_ms нет в cc.api_requests).
    ```

### Prompts: рейтинг самых дорогих промптов

  - tags: [implement-group-3, data, ui, prompts]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] Вью cc.prompts: GROUP BY prompt_id — текст, сессия, стоимость, токены, число запросов и инструментов, самый большой результат
      - [x] Дашборд Prompts: таблица, сортировка по стоимости / токенам
      - [x] Выбор промпта (переменная) → его запросы и вызовы инструментов
      - [x] Ссылка на сессию
      - [x] Проверить на живом стеке: суммы совпадают с cc.sessions
      - [x] Работает на ClickHouse 22.3–25.8: соединения через ON, не несколько USING
    ```md
    Аналог вкладки Prompts из token-dashboard. prompt.id есть на каждом событии.
    Текст промпта есть только при OTEL_LOG_USER_PROMPTS=1.
    Единственная карточка группы 3, которая меняет views.sql.
    Итог: вью #11 cc.prompts (GROUP BY session_id, prompt_id), суммы совпали с cc.sessions на живом стеке.
    180 рейтинг, переменная prompt, 181 текст, 182 / 183 запросы и инструменты промпта (без фильтра времени).
    ```

### Tips: дашборд

  - tags: [implement-group-3, ui, tips, grafana]
  - priority: medium
  - workload: Easy
  - steps:
      - [x] Таблица cc.tips с цветом по категории
      - [x] Ссылки на источник (сессия, файл, агент)
      - [x] Счётчик подсказок на Overview (в своей панели-заготовке)
    ```md
    Скрытие подсказок (dismiss, как у token-dashboard) в Grafana нет — не делаем.
    Зависит от вью cc.tips (группа 1).
    Итог: 200 счётчик, 201 по категориям, 202 таблица со ссылками. На Overview — 58 (число подсказок,
    клик открывает Tips) и 59 (самая частая категория), явные размеры шрифта.
    Ссылки cc.tips открывают одну панель-доказательство: viewPanel=panel-<id> с project / session / actor.
    Номера панелей 19, 24, 26, 57, 100, 140, 161, 180 используются в cc.tips — не перенумеровывать.
    Правила подсказок не менялись; repeated-read считает и чтения субагентов (ложные срабатывания).
    ```

### Разбить на несколько дашбордов с навигацией

  - tags: [implement-group-2, ui, grafana, structure]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] Дашборды: Overview (домашний), Prompts, Sessions, Agents & skills, Tools & files, Tips, Health
      - [x] Общая полоса links по тегу cc, keepTime и includeVars
      - [x] Одинаковые переменные project / session / actor / skill во всех
      - [x] Перенести текущие панели 7–26 в профильные дашборды (10–11 остались на Overview)
      - [x] Обновить drill-down ссылки: панель 7 → cc-sessions, 13/14 → cc-agents; ссылки cc.tips → профильные дашборды
      - [x] GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH → overview.json
      - [x] Зафиксировать uid: cc-usage (Overview), cc-sessions, cc-agents, cc-tools, cc-health, cc-prompts, cc-tips
      - [x] Разметить Overview заготовками: id 30–43 (42 — свёрнутый row «Что значат эти цифры?», 43 внутри)
      - [x] claude-context/scripts/check-dashboard.js: все файлы в grafana/dashboards/ + проверка provisioning
      - [x] Проверить setup-server.sh --update: файлы дашбордов подхватываются раз в 30 с, смена env пересоздаёт grafana (по коду и compose up -d на живом стеке)
    ```md
    cc-usage.json заменён на overview.json (uid cc-usage сохранён — старые закладки работают).
    Prompts и Tips — заготовки (id 1), их наполняет группа 3.
    Заготовки Overview для группы 3: 30 KPI, 31 Daily work, 32 Daily cache reads, 33 cache hit rate,
    34 токены по проектам, 35 donut моделей, 36 топ инструментов, 37 последние сессии,
    38 активные сессии, 39 heatmap, 40 стоимость vs подписка, 41 счётчик Tips, 42/43 «Что значат эти цифры?».
    Summary 2–5 работают, пока карточка KPI их не заменит.
    Риски: настоящий --update со сменой файла на сервере не прогонялся (возможно короткое окно без
    дашборда); кнопки в полосе ссылок идут по алфавиту — Overview не первая.
    README отстаёт (один дашборд) — карточка группы 5.
    ```

### Быстрые диапазоны 5m / 1h / 24h / 7d / 30d / All

  - tags: [implement-group-1, ui, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [x] timepicker.quick_ranges в JSON дашборда: 5m, 1h, 24h, 7d, 30d, All (= now-10y); 90d не нужен
      - [x] Проверить, что All не грузит ClickHouse чрезмерно: на 2 сутках данных 23 запроса ~3 с, самый тяжёлый ~230 мс
      - [x] Проверить в браузере, что Grafana 12.1 показывает эти пункты в пикере
    ```md
    quick_ranges заменяет стандартный список пикера — короткие диапазоны добавлены явно.
    All — окно в 10 лет, а не «всё». Дашборд обновлялся раз в 10 с: на All это был частый полный скан
    (позже refresh поднят до 5 мин, диапазон по умолчанию — 24 ч).
    Замер на ARM перенесён в «Производительность на слабом сервере».
    Группа 1: разбивка (группа 2) копирует timepicker во все дашборды.
    ```

### Tips: вью cc.tips

  - tags: [implement-group-1, data, tips]
  - priority: medium
  - workload: Hard
  - steps:
      - [x] Низкий cache hit rate (< 40 %) в проекте за 7 дней
      - [x] Файл прочитан > 10 раз за 7 дней
      - [x] ~~Bash-команда выполнена > 15 раз~~ — убрано: bash_cmd содержит только первое слово (cd, git), правило давало шум
      - [x] ≥ 5 результатов инструментов > ~200 КБ
      - [x] Много коротких ответов Opus (< 500 output tokens) — оценка экономии по нашему cost_usd
      - [x] Выброс субагента (max > 6 × mean и > 50k токенов)
      - [x] Частые отказы прав по одному инструменту — кандидат в allow-list
      - [x] Медленный хук
      - [x] Высокий ttft_ms
      - [x] Колонки: category, title, body, scope, metric, link
      - [x] ClickHouse 22.3: работает, новых JOIN нет (25.8 не проверена)
      - [x] Время запроса: count() из cc.tips 0,5 с на ~4,9 тыс. событий (22.3); замер на ARM — в «Производительность»
    ```md
    8 правил UNION ALL за 7 дней; в cc.events_raw добавлены result_bytes и ttft_ms.
    На живых данных срабатывают repeated-read, short-opus, slow-hook; cache, big-results,
    agent-outlier, denials, slow-ttft реального срабатывания ещё не видели — пороги подстроить.
    Замечания ревью: repeated-read может показать абсолютный путь вне проекта в title;
    metric у short-opus — верхняя граница экономии, формулировку пересмотреть.
    ```

### Проверить вкладки в Grafana 12 (dynamic dashboards)

  - tags: [implement-group-1, ui, research, grafana]
  - priority: low
  - workload: Normal
  - steps:
      - [x] Есть ли tabs layout в 12.1 и под каким feature flag
      - [x] Совместим ли с file provisioning (schema v2)
    ```md
    Решение: вкладки не делать, группа 2 без изменений (отдельные дашборды + полоса links).
    12.0–12.1: experimental, флаг dashboardNewLayouts (+ kubernetesDashboards для v2), «не для
    production». 12.4 — public preview, 13.x — GA и включено по умолчанию.
    Tabs есть только в schema v2; file provisioning v2 — только в Kubernetes-формате
    (apiVersion dashboard.grafana.app/v2): переписать весь JSON, миграция в 12.x необратима.
    Time range общий для всех вкладок; URL вкладки и drill-down на вкладку не документированы.
    Пересмотреть в карточке «Обновить Grafana до 13.x».
    ```

### Оценить плагин Business Text

  - tags: [implement-group-1, ui, research, grafana]
  - priority: low
  - workload: Normal
  - steps:
      - [x] Попробовать marcusolsson-dynamictext-panel для карточек сессий / промптов (по документации, без установки)
      - [x] Решить, стоит ли добавлять плагин в GF_PLUGINS_PREINSTALL_SYNC — нет
    ```md
    Решение: не добавлять — для группы 3 хватает Stat и Table (data links, цвет по порогам,
    перенос текста). Плагин даёт только вид «карточки», новых данных нет.
    Совместимость: 6.2.3+ требует Grafana >= 12.3; на 12.1.0 максимум 6.2.0
    (marcusolsson-dynamictext-panel@6.2.0; формат id@version на стеке не проверен).
    Риск XSS: текст промптов выводить только через {{...}}, не {{{...}}} и не из afterRender.
    Вернуться, только если Table не справится с длинным текстом промптов.
    ```

### Анализ token-dashboard и claude-code-karma

  - tags: [research]
  - priority: medium
  - workload: Normal
    ```md
    Отчёт: claude-context/research/jsonl-dashboards-vs-otel.md
    ```

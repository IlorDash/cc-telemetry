# cc-telemetry — редизайн Grafana по шаблону (ветка grafana-redesign)

## Backlog

### Боковая панель вровень с контентом

  - tags: [ui, rail, grafana]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Подобрать высоту последней панели боковой панели под каждый дашборд
    ```md
    Шаблон: «последняя панель боковой панели добирает разницу, чтобы панель кончалась вровень с контентом».
    Сейчас высоты фиксированы в rail.json и одинаковы для всех дашбордов — ниже пустой фон.
    sync-rail.js копирует одни высоты во все файлы: нужна высота по дашборду.
    ```

### Мелкие несоответствия в дашбордах (найдены при сверке README)

  - tags: [ui, grafana, links]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Ссылки на сессию: из Sessions сохраняют Actor/Skill, из Overview, Prompts, Agents сбрасывают — выбрать одно правило
      - [ ] «Prompts in this session» открывает Prompts без сужения периода, в отличие от остальных ссылок
      - [ ] ⓘ Timeline: не упомянуты Biggest subagent runs и подсказка agent-outlier; ⓘ Recent sessions: не сказано, что Actor/Skill не действуют
      - [ ] Плитка «Most frequent» в боковой панели без заголовка
    ```md
    Только по решению пользователя.
    ```

### Проверить API errors на настоящих ошибках

  - tags: [data, health]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Когда придёт первое событие api_error: проверить панели 493 и 495 (status_code, error)
      - [ ] Проверить, есть ли у api_error skill.name — иначе при выбранном Skill ошибки покажут ноль
    ```md
    На 2026-11-19 событий api_error не было ни одного; запросы проверены только на пустых данных.
    ```

## To Do

## In Progress

## Done

### Обновить claude-context после редизайна

  - tags: [docs, context]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] modules/dashboard.md: боковая панель, Efficiency, новый Overview, удалённые панели и id, plan_monthly
      - [x] modules/telemetry-data.md: request_id в cc.api_requests, фазы ответа
      - [x] context-claude.md: упоминания cc-tips
      - [x] modules/dashboard.md: Sessions и Prompts (панели и id, extra_cols, shown_cols, session_header, переменная prompt удалена, from_ms/to_ms и сужение периода, timeline по длительности, длина сессии как время работы)
      - [x] modules/dashboard.md: новая раскладка Efficiency и заголовки после единого стиля
      - [x] modules/telemetry-data.md: ссылка agent-outlier в cc.tips с from/to
      - [x] context-claude.md: guides/grafana-style.md
      - [x] modules/dashboard.md: Agents & skills, Tools & files, Health (панели и id, удалённые id, ссылка 476 с зумом, Hook time без Skill)
      - [x] modules/telemetry-data.md: событие api_error, колонки status_code и error в events_raw, ttft_ms в cc.api_requests
    ```md
    Только по команде пользователя (context-auditor). Сделано 2026-11-19: dashboard.md переписан, telemetry-data.md,
    context-claude.md, pending-bugs.md (api_error не проверен на живых данных).
    ```

### Коммит 9: README и завершение

  - tags: [docs, readme]
  - priority: medium
  - workload: Normal
  - steps:
      - [x] README: все семь дашбордов, переменные, клики, время, подсказки
      - [x] Сверить README с дашбордами после коммитов 7–8
      - [x] Clicks: ссылка agent-outlier сужает период до сессии
      - [x] Указать, что дашборды рассчитаны на экран от 1920 px
    ```md
    Клики — списком по дашбордам. Ссылка agent-outlier несёт from/to дважды (свои + ${__url_time_range}):
    Grafana берёт первые, сужение работает (проверено в браузере).
    ```

### Коммит 8: Agents & skills, Tools & files, Health по шаблону

  - tags: [ui, agents, tools, health, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [x] Agents & skills: 4 stat, Subagent types, cost_usd per day by actor, Skills, Biggest subagent runs
      - [x] Tools & files: 4 stat, Calls by tool, Rejected tool calls, Files re-read, Largest tool results, Bash by first word, Most edited files
      - [x] Health: 4 stat, TTFT по дням (порог 3 s), Hook time, API errors, API request duration
      - [x] Панели-доказательства для cc.tips сохранили id (cc-tools 19, 24, 140; cc-health 26, 161)
      - [x] Удалено всё, чего нет в шаблоне
      - [x] Оформление по grafana-style.md; у столбчатых диаграмм со значениями ось Y скрыта (и на Efficiency, Prompts)
      - [x] views.sql: status_code и error из api_error, ttft_ms в cc.api_requests
      - [x] Проверка в браузере на 1920 px, ревьюер
    ```md
    Решения пользователя: Files re-read и Largest tool results — LIMIT 50 со скроллом (список по данным,
    а не статичный набор); остальные LIMIT-таблицы подобраны под высоту (Calls by tool 7, Most edited 5,
    Biggest subagent runs 5).
    Отступления: панели с полосами выше, чем в шаблоне (без скролла); полосы синие по гайду, а не
    оранжевые/фиолетовые; Calls by tool — таблица с колонкой Errors (bar gauge не держит вторую колонку);
    Median result — байты (токенов результата нет); Target — путь или первое слово Bash (команда не
    передаётся); Hook time без фильтра Skill (у хуков нет request_id); выбросы — отдельная колонка Outlier
    (ячейку нельзя покрасить по другой колонке); квадратики цвета у типов агентов невозможны в таблице.
    ```

### Единый стиль дашбордов и style guide

  - tags: [ui, style, grafana, docs]
  - priority: high
  - workload: Normal
  - steps:
      - [x] claude-context/guides/grafana-style.md, строка в CLAUDE.md
      - [x] Overview, Efficiency, Sessions, Prompts приведены к гайду
      - [x] Проверка в браузере, ревьюер
    ```md
    Решения пользователя: гайд важнее шаблона. Плитки — два уровня (главные 13/42 h4, выбранной
    сессии 13/30 h3); заголовок = имя + максимум одна подсказка про клик, остальное в ⓘ; bar gauge
    сплошной, имя над полосой 15/14; в таблицах нет фильтров колонок.
    Исключение: Tips и Affected в Efficiency — прежний вид (Tips · 7d, 15/56, h8) в одном ряду с
    Affected tokens by category (h8 под 5 категорий).
    Поддерживаем только Full HD (1920 px) и шире: на 1280 px боковая панель и узкие плитки режут
    текст — оставлено как есть.
    ```

### Коммит 7: Sessions и Prompts по шаблону

  - tags: [ui, sessions, prompts, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [x] Sessions: 4 stat (Sessions, Median length, Median cost_usd, Sessions with errors)
      - [x] Sessions: таблица сессий (Name, Last prompt, Project, Branch, Model, Turns, Tokens, cost_usd, Hit, Errors), ссылка на var-session
      - [x] Sessions: переменная extra_cols (id, started, account) — скрытые по умолчанию колонки
      - [x] Sessions: заголовок выбранной сессии, 5 stat, State timeline (Prompts, Main · API, Subagents, Tools)
      - [x] Sessions: накопительные cost_usd и токены (2 оси), промпты сессии
      - [x] Prompts: 4 stat (Prompts, Median cost_usd, p95 cost_usd, Requests per prompt)
      - [x] Prompts: Most expensive prompts, гистограмма по корзинам стоимости, средняя стоимость по модели
      - [x] Удалить всё, чего нет в шаблоне; проверить ссылки cc.tips на удалённые панели
      - [x] Клик по сессии сужает период до времени её работы (+3 %, не меньше 5 s); так же ссылка agent-outlier
      - [x] Длина сессии и длительность в заголовке — время работы (запросы и инструменты, без пересечений)
      - [x] Проверка в браузере, ревьюер
    ```md
    Решения пользователя: шкала Timeline и Cumulative подстраивается под сессию (сужение периода по клику);
    все промпты остаются, включая сообщения субагентов; Actor/Skill не меняют длину сессии.
    Отступления (Grafana не умеет): нет счётчика в заголовке таблицы; Columns — переменная, а не кнопки
    в заголовке; нет подсветки строки (applyToRow перекрашивает текст всех ячеек) — выбранная помечена ▶;
    нет моноширинного шрифта; заголовок сессии одного цвета; имя полосы bar gauge не красится, число
    промптов в имени; подпись stat над числом.
    ```

### Коммит 6: Overview по шаблону

  - tags: [ui, overview, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [x] 4 stat: cost_usd, Cache hit rate, Billable tokens, Tool error rate (подпись над числом, wideLayout false)
      - [x] Daily tokens & cache hit rate: стековые столбцы и линия hit rate на правой оси
      - [x] Projects (gauge cost_usd по колонке) и cost_usd by model (donut, rowsToFields)
      - [x] Work rhythm и Top tools
      - [x] Recent sessions: 6 последних, ссылка «all →» на Sessions
      - [x] Удалены панели вне шаблона, переменная plan_monthly и плитки подсказок
      - [x] README; проверка в браузере на 1920 и 1280 px; ревьюер
    ```md
    Решение пользователя: Overview ровно как в шаблоне — всё лишнее удалено.
    Отступления (Grafana не умеет): Work rhythm — таблица 8 блоков по 3 часа × 7 дней (колонка таблицы
    не уже 50 px, heatmap держит на X только время); «all →» — значок у заголовка; нет моноширинного шрифта;
    Recent sessions h8 вместо h7 (пользователь оставил 8). Часы в UTC, как и раньше.
    ```

### Efficiency: фаза Delegate и правила подсказок

  - tags: [ui, efficiency, grafana]
  - priority: medium
  - workload: Easy
  - steps:
      - [x] SendMessage, SubagentHandback, TaskStop считаются Delegate (вместе с Task и Agent)
      - [x] «How tips are made»: оставлена только таблица правил
    ```md
    Other нужна: MCP, веб-инструменты, ToolSearch, Skill, AskUserQuestion. После правки за 7 дней
    Other 86 ответов / $4.61 (было 261 / $12.43), Delegate 241 / $14.79 (было 66 / $6.98).
    Подсказка раздела Tips — во вкладке Info (описание заголовка), отдельной строки нет (решение пользователя).
    ```

### Коммит 5: Efficiency вместо Tips

  - tags: [ui, efficiency, tips, data, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [x] Раздел Tips (7 дней, без переменных): Tips · 7d, Affected · 7d, Affected tokens by category, Token tips, Time and friction tips
      - [x] Where cost goes: cost_usd по дням и сводка по фазе ответа (Explore, Edit, Run, Delegate, Talk, Other)
      - [x] Cache: паузы между запросами против 5-минутного кэша, cache hit rate по проектам
      - [x] request_id в cc.api_requests; ссылка подсказки cache на Efficiency
      - [x] Дашборд Tips удалён; навигация и плитки подсказок ведут на Efficiency
      - [x] Плитки Tips и Affected шириной 3 колонки, подпись над числом
      - [x] Affected tokens by category: «2.8 Mil · 2 tips» справа, названия категорий 13 px над полосками
    ```md
    Решение пользователя: Tips объединён с Efficiency (второй коммит шаблона).
    Отступления (Grafana не умеет): названия категорий над полосками — слева колонка имени меряется
    шрифтом ~11,7 px и режет самое длинное; серые подзаголовки вписаны в заголовки панелей.
    «n tips» после числа — через unit, который запрос отдаёт для каждой категории (rowsToFields).
    ```

### Коммит 4: боковая панель на всех дашбордах

  - tags: [ui, rail, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [x] grafana/rail/rail.json + sync-rail.js (--check), id 300–399
      - [x] Навигация: 7 пунктов с подсказками, текущий выделен, ссылки сохраняют время и переменные
      - [x] Usage · last 5 h: полоска на аккаунт против его 30-дневного пика
      - [x] Tips · 7 d: число подсказок и самая частая категория
      - [x] Строки (rows) заменены текстовыми заголовками, контент x=3, w=21
    ```md
    Решения пользователя: ширина 3 колонки (в шаблоне 4); без Live now; Usage — bar gauge, а не таблица
    со строкой «24 h · 7 d»; вместо Fix first — две stat-плитки (30 и 20 px).
    Grafana не умеет: library panels из файлов (поэтому sync-rail.js), жёлтая плашка с числом подсказок,
    меняющиеся подписи навигации («214 sessions»); санитайзер HTML режет line-height и overflow.
    ```

### Коммит 3: фильтр по аккаунту Claude

  - tags: [ui, grafana, account]
  - priority: high
  - workload: Normal
  - steps:
      - [x] Переменная Account (multi-value, e-mail или первые 8 символов uuid)
      - [x] Все дашборды фильтруются по аккаунту
    ```md
    Порядок переменных: Account → Project → Session → Actor → Skill.
    ```

### Коммиты 1–2: данные для редизайна

  - tags: [data, views]
  - priority: high
  - workload: Normal
  - steps:
      - [x] cc.sessions: account uuid, последний промпт, основная модель
      - [x] cc.tips: колонки affected (измеренные токены) и cost_usd, сортировка по affected
    ```md
    Деньги только из cost_usd события api_request — без таблиц цен.
    ```

### Игнорировать папку Playwright MCP

  - tags: [git]
  - priority: low
  - workload: Easy
  - steps:
      - [x] .playwright-mcp/ в .gitignore

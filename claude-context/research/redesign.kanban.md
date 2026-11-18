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

## To Do

### Коммит 7: Sessions и Prompts по шаблону

  - tags: [ui, sessions, prompts, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [ ] Sessions: 4 stat (Sessions, Median length, Median cost_usd, Sessions with errors)
      - [ ] Sessions: таблица сессий (Name, Last prompt, Project, Branch, Model, Turns, Tokens, cost_usd, Hit, Errors), ссылка на var-session
      - [ ] Sessions: переменная extra_cols (id, started, account) — скрытые по умолчанию колонки
      - [ ] Sessions: заголовок выбранной сессии, 5 stat, State timeline (Prompts, Main · API, Subagents, Tools)
      - [ ] Sessions: накопительные cost_usd и токены (2 оси), промпты сессии
      - [ ] Prompts: 4 stat (Prompts, Median cost_usd, p95 cost_usd, Requests per prompt)
      - [ ] Prompts: Most expensive prompts, гистограмма по корзинам стоимости, средняя стоимость по модели
      - [ ] Удалить всё, чего нет в шаблоне; проверить ссылки cc.tips на удалённые панели
      - [ ] Проверка в браузере на 1920 и 1280 px, ревьюер
    ```md
    Правило пользователя: дашборды 100% как в шаблоне, кроме того, что Grafana не умеет.
    Каждое отступление — проверить в браузере и назвать с причиной.
    ```

### Коммит 8: Agents & skills, Tools & files, Health по шаблону

  - tags: [ui, agents, tools, health, grafana]
  - priority: high
  - workload: Hard
  - steps:
      - [ ] Agents & skills: 4 stat, Subagent types, cost_usd per day by actor, Skills, Biggest subagent runs
      - [ ] Tools & files: 4 stat, Calls by tool, Rejected tool calls, Files re-read, Largest tool results, Bash by first word, Most edited files
      - [ ] Health: 4 stat, TTFT по дням (порог 3 s), Hook time, API errors, API request duration
      - [ ] Сохранить панели-доказательства для ссылок cc.tips (repeated-read, big-results, denials, slow-hook, slow-ttft, agent-outlier)
      - [ ] Удалить всё, чего нет в шаблоне
      - [ ] Проверка в браузере, ревьюер
    ```md
    Номера панелей в ссылках cc.tips: при смене id поправить views.sql.
    ```

### Коммит 9: README и завершение

  - tags: [docs, readme]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] README: все семь дашбордов, переменные, клики, время, подсказки
      - [ ] Сверить README с дашбордами после коммитов 7–8
    ```md
    README публичный: без личных данных.
    ```

### Обновить claude-context после редизайна

  - tags: [docs, context]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] modules/dashboard.md: боковая панель, Efficiency, новый Overview, удалённые панели и id, plan_monthly
      - [ ] modules/telemetry-data.md: request_id в cc.api_requests, фазы ответа
      - [ ] context-claude.md: упоминания cc-tips
    ```md
    Только по команде пользователя (context-auditor).
    ```

## In Progress

## Done

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

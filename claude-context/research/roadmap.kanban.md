# cc-telemetry — улучшения дашборда и данных

## Backlog

### Проверить вкладки в Grafana 12 (dynamic dashboards)

  - tags: [implement-group-1, ui, research, grafana]
  - priority: low
  - workload: Normal
  - steps:
      - [ ] Есть ли tabs layout в 12.1 и под каким feature flag
      - [ ] Совместим ли с file provisioning (schema v2)
    ```md
    Экспериментальная функция. Альтернатива нескольким дашбордам со ссылками.
    Группа 1: результат нужен до разбивки на дашборды (группа 2) — он может поменять её подход.
    ```

### Оценить плагин Business Text

  - tags: [implement-group-1, ui, research, grafana]
  - priority: low
  - workload: Normal
  - steps:
      - [ ] Попробовать marcusolsson-dynamictext-panel для карточек сессий / промптов
      - [ ] Решить, стоит ли добавлять плагин в GF_PLUGINS_PREINSTALL_SYNC
    ```md
    Только если штатных панелей Grafana окажется мало.
    Группа 1: решение нужно до наполнения дашбордов (группа 3).
    ```

### Импортёр JSONL: названия сессий и git-ветка

  - tags: [implement-group-4, data, client, research]
  - priority: low
  - workload: Hard
  - steps:
      - [ ] Проверить: совпадает ли requestId из JSONL с request_id в api_request
      - [ ] Проверить: session.id = имя файла сессии
      - [ ] Решить, куда писать (отдельная таблица ClickHouse) и как доставлять с клиента
      - [ ] Импорт только того, чего нет в телеметрии: title, git_branch, cwd
      - [ ] Использовать название вместо first_prompt в таблицах сессий
    ```md
    Гибрид OTel + JSONL. Токены из JSONL не импортировать: нужна дедупликация и своя
    таблица цен, нельзя смешивать с точным cost_usd.
    Группа 4: последний шаг меняет таблицы сессий в Overview и Sessions — после группы 3.
    ```

## To Do

### Быстрые диапазоны 7d / 30d / 90d / All

  - tags: [implement-group-1, ui, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] timepicker.quick_ranges в JSON дашборда
      - [ ] Проверить, что All не грузит ClickHouse чрезмерно (views не materialized)
    ```md
    Аналог кнопок диапазона на скриншоте.
    Группа 1: делается в текущем cc-usage.json, разбивка (группа 2) копирует timepicker во все дашборды.
    ```

### Tips: вью cc.tips

  - tags: [implement-group-1, data, tips]
  - priority: medium
  - workload: Hard
  - steps:
      - [ ] Низкий cache hit rate (< 40 %) в проекте за 7 дней
      - [ ] Файл прочитан > 10 раз за 7 дней
      - [ ] Bash-команда выполнена > 15 раз
      - [ ] ≥ 5 результатов инструментов > ~200 КБ
      - [ ] Много коротких ответов Opus (< 500 output tokens) — оценка экономии по нашему cost_usd
      - [ ] Выброс субагента (max > 6 × mean и > 50k токенов)
      - [ ] Частые отказы прав по одному инструменту — кандидат в allow-list
      - [ ] Медленный хук
      - [ ] Высокий ttft_ms
      - [ ] Колонки: category, title, body, scope, metric, link
    ```md
    Аналог tips.py из token-dashboard на SQL (UNION правил). Пороги потом подстроить.
    Своей таблицы цен не заводить — только cost_usd.
    Группа 1: трогает только views.sql; в группе 3 views.sql занят вью cc.prompts.
    ```

### Разбить на несколько дашбордов с навигацией

  - tags: [implement-group-2, ui, grafana, structure]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] Дашборды: Overview (домашний), Prompts, Sessions, Agents & skills, Tools & files, Tips, Health
      - [ ] Общая полоса links по тегу cc, keepTime и includeVars
      - [ ] Одинаковые переменные project / session / actor / skill во всех
      - [ ] Перенести текущие панели 7–26 в профильные дашборды
      - [ ] Обновить drill-down ссылки (сейчас ведут на /d/cc-usage)
      - [ ] GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH → Overview
      - [ ] Зафиксировать uid всех дашбордов (на них ссылаются группа 3 и cc.tips)
      - [ ] Разметить Overview заготовками: по одной пустой панели с фиксированными id и gridPos на каждую карточку группы 3
    ```md
    Ссылки между дашбордами выглядят как вкладки token-dashboard.
    Текущий uid cc-usage сохранить за Overview, чтобы старые закладки не сломались.
    Группа 2 — одна, потому что меняет все файлы дашбордов. Заготовки на Overview нужны,
    чтобы в группе 3 каждая карточка меняла только свою панель и не конфликтовала с соседями.
    ```

### Overview: ряд KPI из 7 карточек

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] Stat-панели Sessions, Turns, Input, Output, Cache read, Cache create, Cost
      - [ ] Unit short / компактные числа, полные значения в tooltip
      - [ ] Цвет стоимости через fixedColor, спарклайн (graphMode area)
      - [ ] Все панели учитывают project / session / actor / skill и диапазон времени
    ```md
    Заменить текущие 4 stat-панели Summary рядом из 7 карточек, как в token-dashboard.
    Turns = число api_request с actor = main (или число user_prompt — решить при реализации).
    ```

### Overview: график «Daily work» по дням

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] Запрос: toStartOfDay(ts), суммы input / output / cache_creation
      - [ ] timeseries с drawStyle bars и stacking normal (или barchart)
      - [ ] Описание панели: что такое input / output / cache create
    ```md
    Стековые столбцы по дням: input, output, cache create. Cache read сюда не входит —
    он на 1–2 порядка больше и съедает шкалу.
    ```

### Overview: график «Daily cache reads»

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] Отдельная панель cache_read_tokens по дням
      - [ ] Описание: cache read дешевле обычного input, высокие значения — это хорошо
    ```md
    Отдельный график рядом с Daily work, как на скриншоте token-dashboard.
    ```

### Overview: cache hit rate

  - tags: [implement-group-3, ui, overview, data]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] Stat: cache_read / (cache_read + input + cache_creation), unit percent
      - [ ] Пороги цвета: < 40 % красный, 40–70 % жёлтый, > 70 % зелёный
      - [ ] Таблица / bargauge hit rate по проектам
    ```md
    Метрика из обоих проектов-аналогов. Порог 40 % — как в правиле Tips у token-dashboard.
    ```

### Overview: токены по проектам

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] barchart / bargauge: total_tokens и cost_usd по project
      - [ ] Ссылка с проекта на var-project
    ```md
    Сравнение проектов на главной странице.
    ```

### Overview: доля по моделям (donut)

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] piechart pieType donut по model из cc.api_requests
      - [ ] Переключатель метрики не нужен: токены в donut, стоимость в легенде
    ```md
    Поле model уже есть в cc.api_requests — только запрос и панель.
    ```

### Overview: топ инструментов и последние сессии

  - tags: [implement-group-3, ui, overview, grafana]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] bargauge: топ-10 инструментов по числу вызовов
      - [ ] Таблица последних сессий: стоимость, токены, cache hit, длительность, первый промпт
      - [ ] Подсветка ячеек стоимости (cell color по порогам)
      - [ ] Ссылка session_id на дашборд Sessions
    ```md
    Нижняя часть Overview по образцу token-dashboard.
    ```

### Overview: блок «Что значат эти цифры?»

  - tags: [implement-group-3, ui, overview, docs]
  - priority: high
  - workload: Easy
  - steps:
      - [ ] Свёрнутый row с text-панелью (markdown)
      - [ ] Объяснить input, output, cache read, cache create, cost_usd, actor, aux
    ```md
    Аналог раскрывающейся панели «What do these numbers mean?» из token-dashboard.
    Подчеркнуть, что cost_usd считает сам Claude Code (API-эквивалент).
    ```

### Активные сейчас сессии

  - tags: [implement-group-3, data, ui, live]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Статус по последнему событию: < 2 мин LIVE, < 15 мин IDLE
      - [ ] Таблица на Overview: сессия, проект, host, статус, стоимость
    ```md
    Упрощённый аналог live sessions из karma — без хуков, только по телеметрии.
    Запрос прямо в панели, без новой вью (views.sql в группе 3 занят).
    ```

### Ритм работы (heatmap)

  - tags: [implement-group-3, ui, overview]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Запрос: toHour(ts) × toDayOfWeek(ts), токены или запросы
      - [ ] heatmap-панель (или таблица с cell color)
    ```md
    Аналог coding rhythm из karma.
    ```

### Стоимость против подписки

  - tags: [implement-group-3, ui, overview, cost]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Переменная plan_monthly (custom: 0 / 20 / 100 / 200)
      - [ ] Stat: API-эквивалент за месяц и коэффициент окупаемости
      - [ ] Подпись «платите $N/мес» под карточкой Cost
    ```md
    Аналог переключателя плана из token-dashboard.
    Переменную plan_monthly добавить только в Overview — не трогать общие переменные.
    ```

### Дашборд Sessions: хронология сессии

  - tags: [implement-group-3, ui, sessions, grafana]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] Текущие панели 7–8
      - [ ] Хронология выбранной сессии: запросы и инструменты по времени (state timeline / table)
      - [ ] Токены и стоимость по ходу сессии (накопительно)
    ```md
    Аналог вкладки Sessions (token-dashboard) и Session Timeline (karma).
    ```

### Дашборд Agents & skills

  - tags: [implement-group-3, ui, agents, grafana]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] Текущие панели 13–14
      - [ ] Main vs subagent по каждому инструменту (по actor)
      - [ ] Выбросы субагентов: max vs mean токенов по agent_type из subagent_completed
    ```md
    Идеи из karma (main vs subagent split) и token-dashboard (subagent outliers).
    ```

### Дашборд Tools & files

  - tags: [implement-group-3, ui, tools, grafana]
  - priority: medium
  - workload: Easy
  - steps:
      - [ ] Перенести панели 16–24
      - [ ] Топ результатов инструментов по tool_result_size_bytes
      - [ ] Доля ошибок по инструменту (success = false)
    ```md
    В основном перенос существующих панелей плюс размер результатов.
    ```

### Дашборд Health

  - tags: [implement-group-3, ui, health, grafana]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] Время хуков (панель 26)
      - [ ] ttft_ms и duration_ms запросов: p50 / p95 по модели и по дням
      - [ ] Длительность инструментов, ошибки инструментов
    ```md
    Метрики, которых нет у JSONL-аналогов: задержки и накладные расходы хуков.
    ```

### Prompts: рейтинг самых дорогих промптов

  - tags: [implement-group-3, data, ui, prompts]
  - priority: medium
  - workload: Normal
  - steps:
      - [ ] Вью cc.prompts: GROUP BY prompt_id — текст, сессия, стоимость, токены, число запросов и инструментов, самый большой результат
      - [ ] Дашборд Prompts: таблица, сортировка по стоимости / токенам
      - [ ] Выбор промпта (переменная) → его запросы и вызовы инструментов
      - [ ] Ссылка на сессию
      - [ ] Проверить на живом стеке: суммы совпадают с cc.sessions
    ```md
    Аналог вкладки Prompts из token-dashboard. prompt.id есть на каждом событии.
    Текст промпта есть только при OTEL_LOG_USER_PROMPTS=1.
    Единственная карточка группы 3, которая меняет views.sql.
    ```

### Tips: дашборд

  - tags: [implement-group-3, ui, tips, grafana]
  - priority: medium
  - workload: Easy
  - steps:
      - [ ] Таблица cc.tips с цветом по категории
      - [ ] Ссылки на источник (сессия, файл, агент)
      - [ ] Счётчик подсказок на Overview (в своей панели-заготовке)
    ```md
    Скрытие подсказок (dismiss, как у token-dashboard) в Grafana нет — не делаем.
    Зависит от вью cc.tips (группа 1).
    ```

### README: описать новые дашборды

  - tags: [implement-group-5, docs]
  - priority: low
  - workload: Easy
  - steps:
      - [ ] Список дашбордов и что в каждом
      - [ ] Подсказки Tips и их пороги
      - [ ] Импортёр JSONL, если он сделан
      - [ ] Отметить: история хранится без срока, в отличие от JSONL (~30 дней)
    ```md
    README публичный: без личных данных.
    Группа 5: описывает результат всех предыдущих групп.
    ```

## In Progress

## Done

### Анализ token-dashboard и claude-code-karma

  - tags: [research]
  - priority: medium
  - workload: Normal
    ```md
    Отчёт: claude-context/research/jsonl-dashboards-vs-otel.md
    ```

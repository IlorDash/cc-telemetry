# Решение проблем

На этой странице перечислено, что может пойти не так и что с этим делать; разделы соответствуют
тому, чем вы занимались. Найдите в таблице сообщение или симптом, прочитайте причину, выполните
действие. Скрипты установки печатают `FAIL <сообщение>` и останавливаются либо `WARN <сообщение>`
и продолжают работу. Любой скрипт можно безопасно запустить снова, когда причина устранена.

---

## Что приложить к отчёту

Если в строке написано сообщить об ошибке или ничего подходящего здесь нет, создайте обращение на
[github.com/IlorDash/cc-telemetry/issues](https://github.com/IlorDash/cc-telemetry/issues) и
приложите:

- полный вывод упавшего скрипта с первой строки, а не только последнее сообщение;
- сведения о сервере: Linux или Windows, а для Windows — работает ли Docker в Docker Desktop или в
  WSL;
- вывод этих команд на сервере, из папки `cc-telemetry` (с префиксом `wsl -d Ubuntu --`, если
  Docker работает в WSL):

    ```bash
    git log -1 --oneline
    docker compose ps
    docker compose logs --tail 100 otel-collector
    docker compose logs --tail 100 clickhouse
    docker compose logs --tail 100 views-init
    ```

- если проблема на клиенте: вывод клиентского скрипта и `claude --version`.

!!! warning "Никогда не прикладывайте `.env`"
    В `.env` лежат пароли ClickHouse и Grafana. Не вставляйте его и не вставляйте содержимое
    `backup/`, где лежат ваши промпты. Перед отправкой перечитайте приложенный вывод: в нём могут
    быть ваши IP-адреса, имена ПК и пути к папкам.

Сообщения, где написано *сообщите об ошибке* (report it), — не ошибки оператора: скрипт сделал то,
чего не должен был, и повтор операции не поможет.

---

## Установка сервера

Сообщения скриптов установки с причиной и решением для каждого собраны на [странице
сервера](server.md#если-что-то-не-работает). Здесь — те, что встречаются чаще всего.

| Сообщение или симптом | Причина | Что делать |
| --- | --- | --- |
| `No Docker found. Install Docker Desktop ...` | Windows: не найден ни Docker Desktop, ни дистрибутив WSL | Установите что-то одно и запустите скрипт снова |
| `Docker Desktop is not running. Start it and run this script again.` | Windows: Docker Desktop не отвечает | Запустите его, дождитесь готовности, запустите скрипт снова |
| `systemd is off in WSL 'Ubuntu'. ...` | Windows: без systemd скрипт не может установить Docker в WSL | Сделайте, что сказано в сообщении: добавьте `[boot]` и `systemd=true` в `/etc/wsl.conf`, выполните `wsl --terminate Ubuntu`, запустите скрипт снова |
| `TCP port 3000 is already in use by another program, so Grafana cannot publish it. ...` | Linux: порт Grafana занят другой программой | `bash setup-server.sh --grafana-port 3001` |
| `WARN GRAFANA_BIND was missing and OTLP_BIND=0.0.0.0: Grafana is now published on 0.0.0.0, ...` | Linux: в `.env` от старой версии есть `OTLP_BIND`, но нет `GRAFANA_BIND`, поэтому Grafana теперь доступна из сети | Чтобы оставить Grafana только на этом ПК, задайте `GRAFANA_BIND=127.0.0.1` в `.env` и запустите скрипт снова или используйте `--local-only`. См. [страницу сервера](server.md#порты-и-доступ-на-linux) |
| `permission denied` для `docker` | Linux: вы не в группе `docker` | `sudo usermod -aG docker $USER`, затем войдите заново |
| `views-init did not finish cleanly (<state>)` | Представления `cc.*` не созданы | Прочитайте лог `views-init`, который напечатал скрипт, и запустите скрипт снова; если повторится — сообщите об ошибке |
| `Grafana does not answer yet; check: docker compose logs grafana` | Grafana ещё запускается или не скачался её плагин ClickHouse (нет интернета при первом запуске) | Подождите минуту и откройте Grafana; восстановите интернет и выполните `docker compose restart grafana` |
| `localhost:<port> is closed; check: docker compose logs otel-collector` | Коллектор не слушает этот порт | Прочитайте лог коллектора |
| `Illegal instruction` в логе `clickhouse`, контейнер перезапускается | Linux: ARM-процессор слишком старый для ClickHouse 22.10 и новее (Raspberry Pi 4) | Запустите `setup-server.sh` снова или задайте `CLICKHOUSE_VERSION=22.3.20.29` в `.env`, см. [страницу сервера](server.md#порты-и-доступ-на-linux) |
| После перезагрузки стек не работает (Linux) | Служба `docker` не запускается при загрузке | `systemctl is-enabled docker`; `sudo systemctl enable docker` или запустите `setup-server.sh` снова |
| Стек время от времени останавливается (Windows, Docker в WSL) | `wsl -l -v` показывает дистрибутив как `Stopped`: keepalive не работает | Запустите `setup-server.ps1` снова: он запустит keepalive и добавит его в папку автозагрузки |

### Другие ПК не достают до сервера

| Симптом | Причина | Что делать |
| --- | --- | --- |
| Порт 4317 или 4318 закрыт с другого ПК, но открыт на `localhost` сервера (сервер на Windows) | Не выполнялся `-EnableLan` (серверу, настроенному до хука сессий, нужен повторный запуск ради 4318), изменился адрес сервера в сети или сеть помечена как Public | Запустите `setup-server.ps1 -EnableLan`. Если скрипт предупреждает о сети `Public`, следуйте сообщению |
| То же (сервер на Linux) | Скрипт запускали с `--local-only` (`OTLP_BIND=127.0.0.1` в `.env`) или порт блокирует брандмауэр, отличный от `ufw` и `firewalld` | `bash setup-server.sh --lan`; откройте порт в своём брандмауэре |
| Grafana не открывается с другого ПК (сервер на Linux) | `GRAFANA_BIND=127.0.0.1` в `.env` или порт блокирует брандмауэр, отличный от `ufw` и `firewalld` | `bash setup-server.sh --lan`; адрес `http://<server-ip>:<GRAFANA_PORT>` (по умолчанию `3000`) |
| Grafana не открывается с другого ПК (сервер на Windows) | Так задумано: в Windows Grafana опубликована только на `localhost` | Открывайте её на ПК с сервером |

---

## Клиент

Сообщения клиентских скриптов описаны на [странице клиентов](clients.md#если-что-то-не-работает).

| Сообщение или симптом | Причина | Что делать |
| --- | --- | --- |
| `server <address>:4317 reachable: False` | Сервер выключен, адрес неверный или порт закрыт на сервере | Проверьте адрес, затем см. таблицу выше |
| `server <address>:4318 (session titles) reachable: False` | Порт 4318 закрыт | Запустите серверный скрипт снова (Windows: `-EnableLan`; Linux: без `--local-only`), затем клиентский |
| Клиентский скрипт не запускается (Windows) | Политика выполнения его блокирует | `powershell -ExecutionPolicy Bypass -File .\setup-client.ps1 ...` |
| `ERROR: python3, or jq 1.6 or newer, is required ...` | Linux: нет инструмента для правки JSON | Установите один из них, например `sudo apt install jq` |
| `ERROR: <file> is not valid JSON after the update; restore it from <file>.bak` | Linux: запись прошла неправильно | Восстановите файл из `<file>.bak` и сообщите об ошибке |
| Не появляются названия сессий, git-ветка или проект | Порт 4318 недоступен, хук не установлен (`-NoSessionMeta`) или сессия старше хука | Исправьте порт 4318, как выше; запустите клиентский скрипт без `-NoSessionMeta`; для старых сессий — `-ImportHistory`. После неудачной отправки хук делает паузу на 10 минут, а название новой сессии приходит со следующим промптом |
| `project` равен `unknown` | Нет явной метки, нет рабочей папки от хука, и сессия не трогала файлы с абсолютными путями | Задайте метку проекта через `-Project` / `--project`; проверьте, что `OTEL_LOG_TOOL_DETAILS` равен `1`; папка должна быть доверенной в Claude Code. См. [Проект](clients.md#проект) |
| У проекта странное имя (`data`, ...) | Его папка лежит в необычном месте | Задайте метку через `-Project` / `--project` |

---

## В Grafana нет данных

Идите по списку и остановитесь на первом шаге, который не проходит.

1. На клиенте проверьте соединение: последние строки клиентского скрипта показывают
   `reachable: True` или `False` для портов 4317 и 4318. В Windows проверку повторяет
   `Test-NetConnection <SERVER_IP> -Port 4317`.
2. На клиенте проверьте, что `CLAUDE_CODE_ENABLE_TELEMETRY` равен `1` в разделе `env` файла
   `settings.json` и что Claude Code **2.1.310 или новее** (`claude --version`).
3. Перезапустите сессию Claude Code. Настройки читаются при запуске; в VS Code выполните
   *Developer: Reload Window*, в терминале выйдите и продолжите командой `claude -c`.
4. Если дело в настройках проекта: они читаются только в доверенной папке. Откройте папку в Claude
   Code один раз и подтвердите диалог доверия.
5. На сервере прочитайте `docker compose logs otel-collector`. Ошибка ClickHouse там значит, что
   события приходят, но не сохраняются: прочитайте и `docker compose logs clickhouse`.
6. Сделайте запрос и подождите несколько секунд, затем обновите дашборд. Первые события наполнят
   **Обзор**.

---

## Дашборды

| Симптом | Причина | Что делать |
| --- | --- | --- |
| Панели пусты | В периоде нет событий или переменная отфильтровывает всё | Расширьте период; поставьте переменные в `All`. См. [Период и обновление](dashboards.md#период-и-обновление) |
| Ошибка, что таблицы или представления `cc.events` не существует | Представлений `cc.*` нет | `docker compose logs views-init`, затем `docker compose run --rm views-init` |
| Список переменной пуст | Запрос переменной не выполнился | Настройки дашборда, Variables, откройте переменную, **Run query**, затем сохраните дашборд |
| Плагин ClickHouse не загружается | Нет интернета при первом запуске | Восстановите его и выполните `docker compose restart grafana` |
| **Сессии**: «Сессия не выбрана» под таблицей | Так задумано: панели под таблицей показывают только выбранную сессию | Щёлкните имя сессии или выберите её в переменной **Сессия**. См. [Переменные](dashboards.md#переменные) |
| **Использовано навыков** и **Навыки** пусты, `0` | В **Исполнитель** выбран агент: активации навыков сообщает только основная сессия | Поставьте **Исполнитель** в `All` или `main` |
| `actor = agent?` | Субагент ещё работает и его имя не пришло, или Claude Code старше 2.1.310 | Дождитесь конца запуска; обновите Claude Code |
| Панели **Ошибки API** на дашборде **Состояние** пусты | Событий `api_error` ещё не было | Ничего: они заполнятся с первым неудачным запросом |
| В списке **Аккаунт** вместо e-mail 8 символов | В событиях нет e-mail, только ID аккаунта | Исправлять нечего; см. [Переменные](dashboards.md#переменные) |
| На узком экране раскладка выглядит неправильно | Поддерживаются только экраны Full HD (1920 px по ширине) и шире | Используйте экран пошире |

---

## Обновление

Сообщения `bash setup-server.sh --update` в порядке шагов. Сами шаги описаны на [странице
«Обслуживание»](maintenance.md#обновление-сервера). До проверки данных стек не затрагивается.

| Сообщение | Причина | Что делать |
| --- | --- | --- |
| `.env not found: this folder is not a configured server yet. Run: bash setup-server.sh` | В этой папке нет `.env` | Сначала запустите `bash setup-server.sh` |
| `ClickHouse does not answer, so no safety dump is possible. Start the stack (docker compose up -d), wait until it is healthy and run --update again.` | Стек не запущен | Сделайте, что сказано в сообщении |
| `The git working tree has local changes (listed above): ...` | Отслеживаемые файлы изменены; pull мог бы не пройти или слить их | Закоммитьте, спрячьте (`git stash`) или отмените изменения и запустите `--update` снова |
| `Cannot create backup/pre-update-<date>-<time>. ...` | `backup/` принадлежит root (создана предыдущим запуском с `sudo`) | `sudo chown -R $(id -un) backup`, затем снова `--update` |
| `Not enough free disk space for the safety dump: ...` | Для копии нужно столько места, сколько занимают несжатые данные | Освободите место или удалите старые папки `backup/pre-update-*`; ничего не изменено |
| `free disk space is tight: ...` | Предупреждение: свободно меньше 1,5 размера копии | Освободите место; обновление продолжается |
| `The safety dump failed (see above). Nothing was changed.` или `Could not count the rows. Nothing was changed.` | Ошибка ClickHouse во время копирования | Прочитайте вывод выше и запустите `--update` снова; если повторится — сообщите об ошибке |
| `git pull --ff-only failed (a diverged branch or no network). The stack was not touched.` | В вашей ветке есть коммиты, которых нет на сервере, или нет сети | Исправьте репозиторий (например, посмотрите `git status`) и запустите `--update` снова |
| `the current branch has no upstream: nothing is pulled, continuing with the files as they are.` | Предупреждение: отсоединённый `HEAD` или локальная ветка, например после отката | `git checkout main`, затем снова `--update` |
| `this folder is not a git repository` или `no git repository: continuing with the files as they are.` | Предупреждение: `git pull` невозможен | Получите новую версию сами, затем запустите `--update` или обычный скрипт |
| `The update did not finish. The safety dump from before it is in: <folder>` | Один из шагов после копирования не удался | Устраните ошибку, показанную выше, и запустите `--update` снова. Тома с данными не удаляются; копия — страховочная |
| `LOST <table>: <n> rows before, <m> now` с баннером `DATA MAY HAVE BEEN LOST DURING THE UPDATE` | В таблице строк меньше, чем до обновления | Пока не запускайте `restore`: он дописывает строки. Сверьте числа, восстанавливайте только пустые сейчас таблицы, см. [Резервная копия и восстановление](maintenance.md#резервная-копия-и-восстановление). Затем сообщите об ошибке |
| `docker compose restart <service> failed, see the output above.` | Изменённая конфигурация коллектора или Grafana не загрузилась | Прочитайте лог этого сервиса; исправьте файл и перезапустите сервис вручную |

Чтобы вернуться к прежней версии, см. [Откат](maintenance.md#откат). В Windows `--update` нет:
`git pull` и `setup-server.ps1` вы запускаете сами, см. ту же страницу.

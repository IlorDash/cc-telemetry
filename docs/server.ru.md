# Установка сервера

Сервер — это один ПК, на котором в Docker работает весь стек: OTel Collector, ClickHouse и
Grafana. Устанавливается он один раз одним скриптом; скрипт можно безопасно запускать повторно.

## Перед началом

| Что нужно | Сервер на Windows | Сервер на Linux |
| --- | --- | --- |
| Система | Windows 10 22H2 или Windows 11 с Docker Desktop (бэкенд WSL2) **либо** более старая Windows 10 с WSL2 | Дистрибутив с systemd |
| Docker | Docker Desktop, запущенный до старта скрипта; либо Docker Engine внутри дистрибутива Ubuntu в WSL2 с включённым systemd (скрипт ставит его сам) | Docker Engine с плагином compose; на Debian, Ubuntu и производных скрипт установит его, если его нет |
| Оболочка | Windows PowerShell | bash, от обычного пользователя |
| Интернет | При первом запуске: скачиваются образы и плагин ClickHouse для Grafana | То же |
| Порты | На этом ПК свободны `4317` (OTLP gRPC), `4318` (OTLP HTTP, названия сессий) и `3000` (Grafana) | То же; для Grafana можно выбрать другой порт |
| Диск | Место под образы Docker и под данные: они хранятся бессрочно и растут по мере работы | То же |

Другие дистрибутивы Linux: сначала сами установите [Docker Engine с плагином
compose](https://docs.docker.com/engine/install/).

---

## Установка на Windows

1. Запустите Docker Desktop. С Docker Engine в WSL запускать ничего не нужно.
2. Скачайте репозиторий и откройте его папку в PowerShell:

    ```powershell
    git clone https://github.com/IlorDash/cc-telemetry.git
    cd cc-telemetry
    ```

3. Запустите скрипт. По умолчанию сервер доступен только с этого ПК: Grafana опубликована на
   `localhost`, а брандмауэр Windows держит порты OTLP закрытыми для сети.

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\setup-server.ps1
    ```

4. Если Docker Desktop не найден, а в дистрибутиве WSL нет Docker, скрипт спросит `Docker is not
   installed in WSL 'Ubuntu'. Install Docker Engine there now? [Y/n]`. Ответьте `Y` или
   запустите скрипт с `-Yes`, чтобы вопроса не было.
5. Дождитесь шага `Done`. Он выводит адрес Grafana и команду для клиента.
6. Чтобы принимать данные с других ПК, запустите скрипт ещё раз с `-EnableLan`. Скрипт запросит
   права администратора через UAC; подтвердите запрос.

    ```powershell
    powershell -ExecutionPolicy Bypass -File .\setup-server.ps1 -EnableLan
    ```

Шаг `Done` также выводит команду для других ПК с LAN-адресом сервера, если находит его (и до
`-EnableLan`). Этот адрес понадобится,
когда вы будете [подключать ПК](clients.md).

!!! tip "Закрепите адрес сервера"
    Закрепите IP-адрес сервера в DHCP-настройках роутера. Если адрес изменился, запустите
    `setup-server.ps1 -EnableLan` ещё раз и повторите клиентский скрипт на каждом ПК с новым
    адресом.

### Параметры для Windows

| Параметр | Что делает |
| --- | --- |
| `-Mode <mode>` | Где работает Docker: `auto` (по умолчанию), `desktop` или `wsl`. `auto` берёт Docker Desktop, если он отвечает, иначе дистрибутив WSL; остальные два значения отключают определение |
| `-Distro <name>` | Дистрибутив WSL для режима `wsl` (по умолчанию `Ubuntu`) |
| `-EnableLan` | Принимать данные с других ПК: правила брандмауэра и, для WSL, проброс портов (права администратора через UAC) |
| `-LanIp <address>` | LAN-адрес, который нужно использовать и вывести, если скрипт определил его неверно |
| `-Yes` | Установить Docker в WSL без вопроса |

---

## Установка на Linux

1. Скачайте репозиторий и откройте его папку:

    ```bash
    git clone https://github.com/IlorDash/cc-telemetry.git
    cd cc-telemetry
    ```

2. Запустите скрипт от обычного пользователя, не через `sudo`. По умолчанию сервер доступен из
   локальной сети, потому что серверы на Linux обычно работают без монитора:

    ```bash
    bash setup-server.sh
    ```

    Чтобы оставить всё только на этом ПК:

    ```bash
    bash setup-server.sh --local-only
    ```

3. Ответьте на вопросы. Скрипт спрашивает, прежде чем использовать `sudo`: для установки Docker,
   для автозапуска службы `docker` и для правил брандмауэра. `--yes` отвечает «да» на все вопросы.
4. Дождитесь шага `Done`. Он выводит адрес Grafana и клиентские команды для Windows и для Linux
   с уже подставленным адресом сервера.

Если вашего пользователя нет в группе `docker`, скрипт запускает Docker через `sudo` и сообщает
об этом. Чтобы `sudo` не требовался, выполните `sudo usermod -aG docker $USER` и войдите в
систему заново.

### Параметры для Linux

| Параметр | Что делает |
| --- | --- |
| `--local-only` | Открыть 4317, 4318 и Grafana только на этом ПК (`OTLP_BIND` и `GRAFANA_BIND` = `127.0.0.1` в `.env`) |
| `--lan` | Снова открыть их на всех интерфейсах после прежнего `--local-only`. `--enable-lan` — то же самое |
| `--lan-ip <addr>` | LAN-адрес для вывода, если скрипт определил его неверно |
| `--grafana-port <n>` | Порт Grafana на хосте, 1-65535, по умолчанию 3000. Сохраняется как `GRAFANA_PORT` в `.env`; используйте, если 3000 занят |
| `--clickhouse-version <tag>` | Тег образа ClickHouse, сохраняется как `CLICKHOUSE_VERSION` в `.env` (по умолчанию 25.8) |
| `--update` | Обновить работающий сервер без потери данных. См. страницу «Обслуживание» |
| `--yes` | Не спрашивать перед установкой Docker, использованием `sudo` и включением службы. `-y` — то же самое |
| `--help` | Вывести список параметров. `-h` — то же самое |

`--local-only` и `--lan` исключают друг друга. Неизвестный параметр останавливает скрипт
сообщением `Unknown option: <option>` и списком параметров.

### Порты и доступ на Linux

| Команда | Результат |
| --- | --- |
| `bash setup-server.sh` | 4317, 4318 и Grafana открыты на всех интерфейсах; скрипт добавляет для них правила `ufw` или `firewalld` (какой из них активен, после вопроса) |
| `bash setup-server.sh --local-only` | Три порта остаются только на этом ПК |
| `bash setup-server.sh --lan` | Снова все интерфейсы |

Docker открывает порты собственными правилами `iptables`, которые `ufw` и `firewalld` не
фильтруют. Поэтому скрипт управляет доступом через адрес, на котором опубликован каждый порт:
строки `OTLP_BIND` (порты 4317 и 4318) и `GRAFANA_BIND` (Grafana) в `.env`, каждая со значением
`0.0.0.0` (любой ПК, который достаёт до этого хоста) или `127.0.0.1` (только этот ПК). Правила
брандмауэра лишь пропускают трафик; они не ограничивают, кто может подключаться.

Повторный запуск без `--lan` и `--local-only` сохраняет значения, уже записанные в `.env`.
`--local-only` не удаляет правила брандмауэра, добавленные раньше: удалите их сами командой
`ufw delete allow <port>/tcp` или `firewall-cmd --remove-port=<port>/tcp`.

!!! warning "Только доверенная сеть"
    Grafana работает по обычному HTTP за логином `admin`. У OTLP (4317 и 4318) нет
    аутентификации. Режим LAN включайте только в доверенной домашней или офисной сети. В
    остальных случаях используйте `--local-only`.

!!! note "Raspberry Pi 4 и другие старые ARM-процессоры"
    Образы ClickHouse новее 22.3 завершаются с `Illegal instruction` на ARM-процессоре без
    возможности `lrcpc`. На таком процессоре скрипт записывает в `.env`
    `CLICKHOUSE_VERSION=22.3.20.29` и предупреждает об этом. Поддержка ClickHouse 22.3 давно
    закончилась: используйте его только в доверенной сети.

---

## Что делает скрипт

| Шаг | Windows | Linux |
| --- | --- | --- |
| 1. Docker | Находит Docker Desktop или Docker Engine в WSL; предлагает установить его в WSL | Проверяет, что `docker`, плагин compose и демон отвечают; на Debian и Ubuntu предлагает их установить |
| 2. `.env` | Создаёт его со случайными паролями; существующий `.env` не трогает | То же, и записывает `OTLP_BIND`, `GRAFANA_BIND` и `GRAFANA_PORT` |
| 3. Стек | Запускает его и ждёт, пока создадутся представления `cc.*` | Останавливается, если порт Grafana занят (занятый 4317 или 4318 — лишь предупреждение), затем запускает стек и ждёт представления |
| 4. Проверки | Grafana на `localhost:3000`, OTLP на `localhost:4317` и `localhost:4318` | То же на опубликованных адресах; также проверяет, что служба `docker` стартует при загрузке |
| 5. Дальше | Только WSL: запускает скрытый keepalive и добавляет его в папку «Автозагрузка» (`cc-telemetry-keepalive.vbs`), чтобы WSL не остановил стек | Режим LAN: правила брандмауэра и LAN-адрес сервера |
| 6. `-EnableLan` | Правила брандмауэра для TCP 4317 и 4318 (частные сети) и, для WSL, проброс обоих портов с LAN-адреса | (часть шага 5) |

На Windows Grafana опубликована только на `localhost`; скрипт никогда не открывает её для сети.

Запускайте скрипт повторно, когда нужна быстрая проверка состояния. Он никогда не пересоздаёт
`.env` и не удаляет данные.

---

## Проверка работы

1. Откройте `http://localhost:3000` на серверном ПК. На сервере Linux, доступном из сети,
   остальные ПК открывают `http://<server-ip>:3000` (с вашим `GRAFANA_PORT`, если вы его
   меняли).
2. Войдите как `admin`. Пароль — `GRAFANA_ADMIN_PASSWORD` из файла `.env` в папке
   `cc-telemetry`.
3. Домашней страницей открывается дашборд **Overview**. Он пуст, пока ни один ПК не прислал
   первые события.
4. Проверьте контейнеры (на сервере Windows с Docker в WSL добавьте перед командой
   `wsl -d Ubuntu --`):

    ```bash
    docker compose ps
    ```

    Все сервисы в состоянии `Up`, а `views-init` — `Exited (0)`.

---

## Если что-то не работает

!!! warning "Если что-то не работает"
    Скрипт печатает `FAIL <message>` и останавливается либо `WARN <message>` и продолжает.
    Устраните причину и запустите скрипт снова.

    | Сообщение | Причина | Что делать |
    | --- | --- | --- |
    | `No Docker found. Install Docker Desktop (Windows 10 22H2+ / Windows 11), or on older Windows install WSL2 with Ubuntu (admin: wsl --install -d Ubuntu), reboot, and run this script again.` | Windows: не найден ни Docker Desktop, ни дистрибутив WSL | Установите что-то одно и запустите скрипт снова |
    | `Docker Desktop is not running. Start it and run this script again.` | Windows: указан `-Mode desktop`, а Docker не отвечает | Запустите Docker Desktop и дождитесь готовности |
    | `WSL distro 'Ubuntu' not found (wsl -l -v). Use -Distro <name>.` | Windows: нет дистрибутива с таким именем | Передайте имя из `wsl -l -v` в `-Distro` |
    | `systemd is off in WSL 'Ubuntu'. Add to /etc/wsl.conf:  [boot]  systemd=true  then run 'wsl --terminate Ubuntu' and this script again.` | Windows: без systemd скрипт не может установить Docker | Сделайте то, что написано в сообщении |
    | `Docker installation in WSL failed, see the output above.` или `Docker installation failed, see the output above.` | Установщик Docker завершился с ошибкой | Прочитайте вывод над сообщением и устраните ошибку |
    | `Docker was installed but does not answer. Run: wsl -d <distro> -- docker info` | Windows: Docker установлен в WSL, но не запускается | Выполните команду из сообщения и прочитайте ошибку |
    | `Docker is installed but does not answer. Start it: sudo systemctl start docker, then run this script again.` | Linux: демон остановлен | Запустите его и запустите скрипт снова |
    | `No permission to use Docker and sudo is not available. Add yourself to the docker group (sudo usermod -aG docker $USER), log in again and re-run.` | Linux: вас нет в группе `docker`, и нет `sudo` | Сделайте то, что написано в сообщении |
    | `Docker (with the compose plugin) is missing. Install Docker Engine and the compose plugin for your distribution (https://docs.docker.com/engine/install/), then run this script again.` | Linux: не Debian и не Ubuntu, поэтому скрипт Docker не ставит | Установите Docker Engine и плагин compose и запустите скрипт снова |
    | `Docker is required.` | Вы ответили `n` на предложение установить Docker, либо спросить было некого (нет терминала) | Запустите снова и ответьте `Y` либо используйте `-Yes` / `--yes` |
    | `TCP port 3000 is already in use by another program, so Grafana cannot publish it. Pick a free port, for example: bash setup-server.sh --grafana-port 3001` | Linux: порт Grafana занят другой программой | Запустите с `--grafana-port 3001`; порт сохранится в `.env` |
    | `TCP port <p> is already in use by another program: the collector cannot start until it is freed.` | Linux: предупреждение; 4317 или 4318 занят другой программой | Остановите эту программу. Порты OTLP изменить нельзя |
    | `docker compose up failed, see the output above.` или `docker compose <args> failed (exit <n>)` | Стек не запустился | Прочитайте ошибку Docker над сообщением |
    | `views-init did not finish cleanly (<state>)` | Представления `cc.*` не созданы; скрипт сначала печатает журнал `views-init` | Прочитайте этот журнал; запустите скрипт снова |
    | `Grafana does not answer yet; check: docker compose logs grafana` | Предупреждение; Grafana ещё запускается или не скачался её плагин ClickHouse | Подождите минуту и откройте Grafana; если при первом запуске не было интернета, восстановите его и выполните `docker compose restart grafana` |
    | `localhost:<port> is closed; check: docker compose logs otel-collector` | Предупреждение; коллектор не слушает этот порт | Прочитайте журнал коллектора |
    | `admin rights were not granted; LAN access is not configured` | Windows: вы отклонили запрос UAC | Запустите с `-EnableLan` снова и подтвердите запрос |
    | `Could not find the LAN address. Re-run with -LanIp <address>.` | Windows: не найден сетевой адаптер со шлюзом по умолчанию | Передайте адрес в `-LanIp`. На Linux то же предупреждение просит `--lan-ip <address>` |
    | `network '<alias>' is Public, the firewall rule does not apply to it. ...` | Windows: правило брандмауэра действует только для частных сетей | Если это ваша домашняя или офисная сеть, выполните от администратора команду из сообщения |
    | `<address>:<port> is not reachable yet` | Предупреждение; брандмауэр, проброс порта или адрес пока не в порядке | Запустите скрипт снова; проверьте профиль сети и адрес |
    | `--local-only and --lan exclude each other` | Linux: вы передали оба параметра | Передайте только один из них |
    | `--lan-ip '<value>' is not an IPv4 address (like 192.168.1.10)` | Linux: значение не является адресом IPv4 | Передайте адрес вида `192.168.1.10` |
    | `--grafana-port '<value>' is not a port number (1-65535)` | Linux: значение не является номером порта | Передайте число от 1 до 65535 |
    | `--clickhouse-version '<value>' is not an image tag (like 25.8 or 22.3.20.29)` | Linux: значение не является допустимым тегом образа | Передайте тег вида `25.8` |

→ Устранение неполадок и обновление сервера описаны на страницах «Устранение неполадок» и
«Обслуживание». Дальше: [подключение ПК](clients.md).

# CLAUDE.md — контекст проекта fspirat-router

Ты работаешь с проектом домашнего VPN-роутера пользователя и веб-панели к нему
на https://fspirat.online/router/. Общайся с пользователем **по-русски**, объясняй
простыми словами, давай команды по одной-две за раз. Пользователь на Windows (PowerShell),
подключается к машинам по SSH.

## Схема

```
Устройства дома ─ Wi-Fi/кабель ─► Роутер Xiaomi AX3000T (OpenWrt 25.12.5, 192.168.7.1)
                                   │  PassWall 2 + Xray, подписка nosok (VPN-провайдер)
                                   │  узел Split (shunt): MyDirect → напрямую, остальное → сервер nosok
                                   │
                                   └─ SSH-туннель (dbclient, служба fstunnel) ─►
Сервер NL Aeza 193.39.143.202 (Ubuntu 24.04)
   127.0.0.1:8081 ─► LuCI роутера (через туннель)
   nginx:
     router.fspirat.online  → весь LuCI (basic auth + пароль роутера)
     fspirat.online/router/ → страница web/index.html (basic auth)
     fspirat.online/router/api → CGI /cgi-bin/fspirat на роутере (nginx добавляет токен cookie)
   cron: fspirat-watch раз в минуту → уведомления в Telegram (@FSRouter_bot)
   fail2ban: sshd, nginx-http-auth, 3x-ipl
```

## Файлы репозитория → где живут

| В репозитории | Где на самом деле | Как выкладывать |
|---|---|---|
| `web/index.html` | сервер `/var/www/fspirat.online/router/index.html` | push в main → GitHub Actions (`deploy-web.yml`) |
| `router/bin/fspirat-ping` | роутер `/usr/bin/fspirat-ping` (cron */5) | `bash scripts/deploy-router.sh` |
| `router/www/cgi-bin/fspirat` | роутер `/www/cgi-bin/fspirat` | `bash scripts/deploy-router.sh` |
| `router/etc/init.d/fstunnel` | роутер `/etc/init.d/fstunnel` | `bash scripts/deploy-router.sh` |
| `router/passwall/*.txt` | вставлены вручную в правила PassWall (Rule Manage) | вручную через LuCI |
| `server/bin/fspirat-watch` | сервер `/usr/local/bin/fspirat-watch` | `bash scripts/deploy-server.sh` |
| `server/fail2ban/fspirat.local` | сервер `/etc/fail2ban/jail.d/fspirat.local` | `bash scripts/deploy-server.sh` |
| `server/nginx/...` | сервер `/etc/nginx/...` | вручную, осторожно (certbot дописывал SSL) |
| `*.example` | шаблоны для файлов с секретами | секреты только на машинах, не в git |

Проверка, что всё живо: `bash scripts/check.sh`.

## Важные константы

- ID узла Split в PassWall: **`9DxG2j8l`** (он же `passwall2.@global[0].node`).
  Если Split пересоздать, ID изменится — тогда поправить `SHUNT=` в fspirat-ping и в CGI.
- Группа узлов подписки: `nosok`. Текущий сервер VPN = `uci get passwall2.9DxG2j8l.default_node`.
- Исключены из списка и автопереключения: имена с `LTE|Россия|Обход` (переменная `EXCLUDE`).
- SOCKS-порт основного узла PassWall: **1070** (`node_socks_port`). Через него идёт
  настоящая проверка и тест скорости «через VPN». Отдельный SOCKS 1080 НЕ настроен.
- `localhost_proxy='0'`: собственный трафик роутера идёт напрямую (не через VPN).
- Токен CGI: `/etc/fspirat.token` на роутере, тот же — в `/etc/nginx/snippets/fspirat-router.conf`.
- Временные данные роутера: `/tmp/fspirat/` (ping.json, history, switch.log, speed_*.json) —
  стираются при перезагрузке.

## API страницы (CGI на роутере)

`GET /router/api?action=...`
- `status` — всё для страницы: running, split_active, current, ping{nodes,real,socks},
  history, log, speed{vpn,direct}, devices, sys{cpu,ram,disk,tmp,temp,uptime,net}
- `net` — только скорость WAN за 1 с
- `ping` — запустить fspirat-ping (~20 с) и вернуть status
- `switch&id=XXXX` — сменить сервер (default_node в Split) + перезапуск PassWall
- `restart` / `update` (подписка) / `reboot`
- `speedtest&via=vpn|direct` — тест через Cloudflare (~25 с)

## Правила работы

1. **Секреты никогда не коммить**: токен CGI, токен Telegram, пароли, ключи. Репозиторий
   держать приватным (в нём IP сервера и схема).
2. Роутер — **BusyBox ash**, не bash. Без массивов, `[[ ]]`, `local -a` и т.п. Проверять `sh -n`.
   Утилиты: curl, tcping, jsonfilter, uci, lua+nixio есть; `date +%N` не работает.
3. Перед действиями, которые рвут связь (перезапуск PassWall, перезагрузка роутера,
   перезапуск fstunnel, `nginx reload` с новым конфигом) — **спроси пользователя**.
4. Файлы на роутер передавать без CRLF (`tr -d '\r'`), deploy-скрипты это делают.
5. Перед правкой nginx: `nginx -t` и только потом `systemctl reload nginx`.
6. После изменений — проверить: `bash scripts/check.sh` и страницу в браузере.

## Грабли, на которые уже наступили (не повторять)

- **uhttpd не передаёт в CGI свои заголовки** (X-Fspirat-Token терялся) → токен идёт cookie.
- **procd-служба без `HOME=/root`** → dbclient падал молча (known_hosts). Поэтому `env HOME=/root`.
- **Домен fspirat.online обслуживает Cloudflare DNS**, а не Reg.ru. Записи DNS — в Cloudflare
  (для certbot — «DNS only», серое облако).
- **Speedtest Cloudflare**: `/meta` отдаёт `{}` → IP/страну берём из `/cdn-cgi/trace`;
  файлы >~100 МБ не отдаются → качаем кусками по 25 МБ.
- **PassWall «App not supported» / «Limit of devices reached»** — это узлы-заглушки от
  провайдера (нет HWID / лимит устройств), а не ошибка роутера.
- **Global node должен быть Split**, а не конкретная страна — иначе MyDirect не работает.
- **fail2ban не стартует**, если нет `/var/log/x-ui/3xipl.log` (jail 3x-ipl от 3x-ui).
- Пользователь часто вставляет команды не в тот терминал: всегда пиши, где выполнять
  (роутер `root@OpenWrt` / сервер `root@occasional-coffe`).

## Ближайшие задачи (TODO)

1. **Защитить папку router/ от деплоя основного сайта.** Репозиторий `fspirat/project_hex`
   выкладывает `sites/fspirat.ru/` → `/var/www/fspirat.online/` через rsync. Если там `--delete`,
   он сотрёт `/router/`. Добавить в `project_hex/.github/workflows/deploy.yml` к rsync
   `--exclude 'router/'` (и убрать оттуда `sites/fspirat.ru/router/`, если он был добавлен).
2. **Wi-Fi клиенты по диапазонам**: для каждого устройства 2,4 ГГц / 5 ГГц / кабель,
   сигнал dBm, скорость соединения. Данные: `iwinfo <iface> info` (частота) +
   `iwinfo <iface> assoclist`. Сначала посмотреть вывод `iwinfo` на роутере.
3. **Тест скорости точнее**: 4 параллельных потока; для «напрямую» — российский сервер
   (Cloudflare в РФ замедляют). Сравнить с тарифом пользователя.
4. **История и журнал переживают перезагрузку**: раз в час копировать
   `/tmp/fspirat/{history,switch.log}` в `/etc/fspirat/`, при старте восстанавливать.
5. Сменить токен CGI (`/etc/fspirat.token` + nginx snippet) — старый засветился в чате.
6. Удалить с сервера `/var/www/fspirat.online/router/setup/` (больше не нужна).
7. Идеи: включение/выключение гостевой Wi-Fi со страницы; PWA-иконка для телефона.

Подробности по всей инфраструктуре — `docs/infrastructure.md`, история решений — `docs/history.md`.

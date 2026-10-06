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
     router.fspirat.online  → весь LuCI (вход через страницу fspirat.online/router/login + пароль роутера)
     fspirat.online/router/ → страница web/index.html (вход через свою страницу, см. ниже)
     fspirat.online/router/api → CGI /cgi-bin/fspirat на роутере (nginx добавляет токен cookie)
   cron: fspirat-watch раз в минуту → уведомления в Telegram (@FSRouter_bot)
   fail2ban: sshd, nginx-http-auth, 3x-ipl
```

## Файлы репозитория → где живут

| В репозитории | Где на самом деле | Как выкладывать |
|---|---|---|
| `web/index.html` | сервер `/var/www/fspirat.online/router/index.html` | push в main → GitHub Actions (`deploy-web.yml`) |
| `router/bin/fspirat-ping` | роутер `/usr/bin/fspirat-ping` (cron */5) | workflow `Deploy router` (или `bash scripts/deploy-router.sh` из дома) |
| `router/www/cgi-bin/fspirat` | роутер `/www/cgi-bin/fspirat` | workflow `Deploy router` |
| `router/etc/init.d/fstunnel` | роутер `/etc/init.d/fstunnel` | workflow `Deploy router` (перезапуск туннеля — только с разрешения) |
| `router/passwall/*.txt` | вставлены вручную в правила PassWall (Rule Manage) | вручную через LuCI |
| `server/bin/fspirat-watch` | сервер `/usr/local/bin/fspirat-watch` | `bash scripts/deploy-server.sh` |
| `server/fail2ban/fspirat.local` | сервер `/etc/fail2ban/jail.d/fspirat.local` | `bash scripts/deploy-server.sh` |
| `server/nginx/...` | сервер `/etc/nginx/...` | вручную, осторожно (certbot дописывал SSL) |
| `*.example` | шаблоны для файлов с секретами | секреты только на машинах, не в git |

Проверка, что всё живо: `bash scripts/check.sh`.

## Управление сервером из Claude Code

Прямого SSH из облачной сессии нет. Команды на VPS выполняет workflow **`.github/workflows/ops.yml`**
(Actions → Server ops → Run workflow, поле `cmd`; или `workflow_dispatch` через API) — от root по ключу
`OPS_SSH_KEY`. Без `cmd` только проверяет секреты и вход root/deploy. Вывод — в логе запуска
(репозиторий приватный). Секреты: `OPS_SSH_KEY` (root), `SSH_KEY` (deploy), `SSH_HOST`.
Правила те же: перед `nginx reload` — `nginx -t`; не печатать в лог файлы с секретами
(`snippets/fspirat-router.conf`, `/etc/fspirat-watch.conf`, `/etc/fspirat.token`).

## Доступ к роутеру с сервера

Туннель fstunnel пробрасывает ещё `127.0.0.1:8022` на сервере → SSH роутера (dropbear). Ключ сервера
`/root/.ssh/router_key` (`fspirat-vps`) — в `/etc/dropbear/authorized_keys` роутера; у пользователя `tunnel`
на сервере `permitlisten` для 8081 и 8022. Команда на роутер из ops: `ssh -p 8022 -i /root/.ssh/router_key root@127.0.0.1 '...'`.
Время на роутере — Europe/Samara (+04).

## История, журнал, имена (server/auth/data.php)

fspirat-watch раз в минуту пишет в `/var/lib/fspirat/`: `history.tsv` (время, отклик ms: 0 — VPN не прошёл,
-1 — роутер не на связи; 35 дней), `events.tsv` (журнал: смены сервера, перезапуски, пропадания связи,
перезагрузки), `offline_since`, `last_ok`. `GET /router/data?range=day|week|month` отдаёт это странице
(работает и без туннеля), `POST /router/data mac=&name=` — свои имена устройств
(`/var/lib/fspirat-router-auth/names.json`). Манифест и иконки PWA (`web/manifest.webmanifest`, `icon-*.png`) — без входа.

## Вход в панель (server/auth)

Вместо окна браузера (auth_basic) — своя страница `fspirat.online/router/login` (PHP в `/var/www/router-auth/`).
nginx перед каждым запросом спрашивает `check.php` (`auth_request /_fsr_auth`); cookie `fsr_session` на домен
`fspirat.online` — один вход и для `/router/`, и для `router.fspirat.online`.
- Пароль: пока нет `/var/lib/fspirat-router-auth/password`, проверяется по `/etc/nginx/.htpasswd_router` (apr1),
  после первого входа сохраняется там же в bcrypt. Сменить пароль: удалить этот файл и обновить .htpasswd_router
  (`htpasswd /etc/nginx/.htpasswd_router bob`).
- 5 неверных паролей — блокировка IP на 15 минут + fail2ban (jail `fspirat-router-auth`) + сообщение в Telegram.
- Журнал: `/var/log/fspirat-router-auth.log` (OK / FAIL / LOCKED / LOGOUT). fspirat-watch шлёт «🔑 Вход в панель».
- Выкладка: workflow `Deploy server` (deploy-server.yml); nginx правит `server/auth/nginx-apply.py`
  (копии `*.bak-auth-*`, `nginx -t`, откат при ошибке).

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
- `speedtest&via=vpn|direct` — 4 потока ~35 с: загрузка напрямую с Selectel (РФ), через VPN с Hetzner (DE),
  отдача на Cloudflare (на частые замеры отвечает 429 → `up_limited`)
- в `devices` у Wi-Fi клиентов `band` (2g/5g), `signal` dBm, `rate` Мбит/с (iwinfo assoclist), у остальных онлайн — `wired`

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

1. ~~Защитить папку router/ от деплоя основного сайта~~ — сделано 06.10: в `project_hex` deploy.yml
   rsync идёт с `--exclude '/router/'`.
2. ~~Wi-Fi клиенты по диапазонам~~ — сделано 06.10. Было: **Wi-Fi клиенты по диапазонам**: для каждого устройства 2,4 ГГц / 5 ГГц / кабель,
   сигнал dBm, скорость соединения. Данные: `iwinfo <iface> info` (частота) +
   `iwinfo <iface> assoclist`. Сначала посмотреть вывод `iwinfo` на роутере.
3. ~~Тест скорости точнее~~ — сделано 06.10. Было: **Тест скорости точнее**: 4 параллельных потока; для «напрямую» — российский сервер
   (Cloudflare в РФ замедляют). Сравнить с тарифом пользователя.
4. ~~История и журнал переживают перезагрузку~~ — сделано 06.10 (хранит сервер). Было: **История и журнал переживают перезагрузку**: раз в час копировать
   `/tmp/fspirat/{history,switch.log}` в `/etc/fspirat/`, при старте восстанавливать.
5. Сменить токен CGI (`/etc/fspirat.token` + nginx snippet) — старый засветился в чате.
6. Удалить с сервера `/var/www/fspirat.online/router/setup/` (больше не нужна).
7. ~~PWA-иконка~~ — сделано 06.10. Гостевой Wi-Fi пользователю не нужен.

Подробности по всей инфраструктуре — `docs/infrastructure.md`, история решений — `docs/history.md`.

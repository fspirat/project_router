# iOS-приложение: техническое приложение к плану (этап 1, 13.10.2026)

> Составлено чтением кода (5 разборов + независимая проверка каждого + проверка полноты). Ничего на серверах не запускалось. Ссылки path:line — на ветку claude/new-session-8gynnf.

# Техническое приложение к этапу 1. iOS-приложение «Роутер»

**Ссылки и сокращения.** Ссылки даны в виде `путь:строка` от `/home/user/project_router`.
- `cgi` — `router/www/cgi-bin/fspirat`;
- `PW` — перезапуск PassWall (`passwall2 restart`);
- `app.js`, `index.html`, `app.css`, `theme.js` — файлы в `web/`.

**Как велась работа.** Только чтение. Секретов в тексте нет, адреса — примеры из документации.

## 0. Источники и перепроверка

**Из чего собрано приложение:**
- опись веб-панели и опись CGI, у каждой своя сверка (правки и пропуски сверки внесены ниже);
- проект сервера (вход и API);
- проект экранов и сборки.

**Что я перепроверил по коду перед сведением:**
- `server/auth/check.php:11-53`, `server/auth/logout.php:7-17`;
- `server/auth/lib.php:20-29,75-81,130-151,164-201,242,246-262`;
- `server/auth/login.php:20-70`;
- `server/auth/data.php:41-145`;
- `server/auth/tgbot.php:11-56,125,246-300,314`;
- разбор action в `cgi:28-41,185-428`;
- `.github/workflows/rotate-router-token.yml:27-46`;
- `.github/workflows/deploy-server.yml:37-41,61,66,91-92,98-122`;
- `server/bin/fspirat-vdsstat:3-9`, `server/bin/fspirat-watch:33-48,61-71,136-165,189-221,271`;
- `router/bin/fspirat-ping:12,47-63`;
- `server/nginx/conf.d/fsr-limits.conf:4-5`, `server/auth/nginx-apply.py:12`;
- `server/fail2ban/fspirat.local:18-25`, `server/fail2ban/filter.d/fspirat-router-auth.conf`, `server/logrotate/fspirat-router-auth`;
- `server/mtproxy/sni-443.conf`, `server/mtproxy/realip-proxy-protocol.conf`;
- `router/passwall/mydirect-domains.txt`.

С описью код в основном совпал. Расхождения исправлены в тексте. Мои собственные находки помечены «(новое)».

---

## 1. Доступ и вход сегодня

### 1.1 Цепочка запроса
**Путь запроса.**
1. Браузер обращается к nginx на `fspirat.xyz`. Порт 443 принимает nginx stream: по SNI он отправляет `nl.*` в Xray, а остальное на сайты, передавая `proxy_protocol` (`server/mtproxy/sni-443.conf`). Сайты берут настоящий IP клиента через realip (`server/mtproxy/realip-proxy-protocol.conf`).
2. `location = /router/api` передаёт запрос дальше: `proxy_pass http://127.0.0.1:8081/cgi-bin/fspirat$is_args$args` (`server/nginx/snippets/fspirat-router.conf.example:9-16`).
3. Обратный SSH-туннель fstunnel `-R 127.0.0.1:8081:<LAN-IP>:80` (`router/etc/init.d/fstunnel:12`) приводит запрос в uhttpd роутера.
4. uhttpd запускает CGI.

**Что nginx делает с запросом:**
- заменяет `Cookie` на `fspirat_token=<токен роутера>` (snippet:13);
- обнуляет `Authorization` (snippet:14);
- ставит `proxy_read_timeout 60s` (snippet:15).

Токен идёт в cookie, потому что uhttpd не передаёт в CGI нестандартные заголовки (snippet:4).

**PHP на сервере.** Адреса `/router/data`, `/router/login`, `/router/logout`, `/router/tg-hook` и внутренний `/_fsr_auth` обслуживает PHP из `/var/www/router-auth/`. Сокет `unix:/run/php/php8.5-fpm.sock` (`nginx-apply.py:12`).

### 1.2 Проверки nginx
- **Вход.** `/router/api` и `/router/data` закрыты `auth_request /_fsr_auth`, его обрабатывает `check.php` (`nginx-apply.py:25,110-111`). Без сессии nginx отвечает `401 {"error":"auth"}` с `default_type application/json` (`@fsr_api_401`, `nginx-apply.py:122`).
- **Заголовок X-FSR.** Если `X-FSR` пуст или его нет, ответ `403 '{"error":"csrf"}'` с Content-Type не JSON (`nginx-apply.py:35,84`).
- **Лимит частоты:**
  - зона `limit_req_zone $binary_remote_addr zone=fsr_api:1m rate=5r/s`, ответ `limit_req_status 429` (`server/nginx/conf.d/fsr-limits.conf:4-5`);
  - `burst=30 nodelay` на `/router/api`, `/router/data` и `/router/tg-hook`, зона у них общая (`nginx-apply.py:68,95`);
  - ответ 429 приходит в HTML.
- **Страница `/router/`.**
  - `location ^~`.
  - CSP: `default-src 'none'; script-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self' https://speed.cloudflare.com; manifest-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'`.
  - `Cache-Control: private, no-store` (`nginx-apply.py:59-61,67,85`).
  - HSTS, `nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY` стоят и на API (`nginx-apply.py:62-68`).
- **Что открыто без входа:**
  - `/router/fonts/` (expires 30d);
  - `manifest.webmanifest`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png` (expires 7d);
  - `/router/login`, `/router/logout` (`nginx-apply.py:36-37,70,93-95,118-120`).
- **Перенаправление на вход.** `/router/` без сессии отвечает 302 на `/router/login?next=$uri` (`nginx-apply.py:121-122`, `lib.php:237-244`).

### 1.3 check.php (auth_request)
- **Нет сессии** → 401 (`check.php:22`).
- **Не-GET/HEAD к `/router/(api|data)`.** Проверяются два условия:
  - `Origin` == `https://<домен панели>` — обычное сравнение строк (`fsr_origin()`/`fsr_panel()`, `lib.php:62-73`);
  - `X-FSR` == `fsr_csrf()` = `substr(hash_hmac('sha256','fspirat-csrf-v1',<токен сессии>),0,48)` — через `hash_equals` (`lib.php:214-218`, `check.php:30-31`).
- **Проверка не прошла.** В журнал действий пишется `DENY <action> csrf/origin`, ответ 403 без тела. nginx настроен только на `error_page 401`, поэтому клиент получает HTML-страницу 403 (`check.php:25-34`).
- **Проверка прошла.** В журнал пишется `ACTION <action> [id=][sid=][mac=][via=]`. Берутся только значения из query, подходящие под `^[A-Za-z0-9:_]{1,40}$`. Для `/router/data` действие всегда `rename`, а mac лежит в теле и в журнал не попадает (`check.php:26-38`).
- **Telegram** — только для действий, у которых в `FSR_ACTIONS` стоит true (`check.php:11-18,39-40`). Сообщение уходит после ответа (`fastcgi_finish_request`, `check.php:50-53`) с подписью «Из панели, IP …».
- **Сбой базы** → 500. nginx отдаёт свою HTML-страницу 500 (`check.php:43-47`).
- **GET** проверяется только по сессии. Значение `X-FSR` у GET не сверяется.

### 1.4 Сессия, вход, код из Telegram, блокировка
- **Сессия.**
  - Cookie `fsr_session` — 64 hex (256 бит). В таблице `sessions` хранится `sha256` от неё.
  - Флаги: HttpOnly, Secure, SameSite=Strict, домен панели. Cookie общая с `router.<домен>` (`lib.php:22-23,155-177`).
  - Срок: 12 ч (`FSR_TTL_SHORT`), с «Запомнить» — 30 дней (`FSR_TTL_LONG`). Оба считаются от `seen`, то есть от последнего действия. `seen` продлевается не чаще раза в 300 с (`lib.php:24-25,180-192`). Без «Запомнить» cookie сессионная, `expires=0` (`lib.php:175`).
- **Пароль.** Хранится в `/var/lib/fspirat-router-auth/password` (bcrypt). До первого входа проверяется по `.htpasswd_router` (apr1) (`lib.php:115-130`).
- **Блокировка подбора.**
  - Таблица `fails(ip, ts)`. 5 ошибок за 900 с — вход закрыт. `fsr_fail()` возвращает, сколько попыток осталось (`lib.php:26-27,134-151`). Ошибки кода из Telegram тоже идут в `fails` (`login.php:36-41`).
  - На неверный пароль: пауза `usleep(300–700 мс)`, запись `FAIL`, ответ 403 (`login.php:60-66`).
  - `LOCKED` пишется только при попытке войти, когда вход уже закрыт (`login.php:25-27`). Сообщение сторожа «Подбор пароля» приходит именно по этой строке (`server/bin/fspirat-watch:43`).
  - fail2ban `fspirat-router-auth`: фильтр `(FAIL|LOCKED) ip=<HOST>`, maxretry 5, findtime 10m, bantime 1h, `port = http,https` (`server/fail2ban/fspirat.local:18-25`, `server/fail2ban/filter.d/fspirat-router-auth.conf`). **(новое)** Бан закрывает весь 443, а он общий с Xray своего NL-сервера (§5 п.32).
- **Код из Telegram (вторая защита).**
  - Только на новом браузере: 6 цифр, 300 с, 5 попыток, привязка к cookie `fsr_2fa`.
  - Знакомый браузер (cookie `fsr_dev`) помнится 30 дней (`lib.php:246-262,315-361`, `login.php:28-59`).
  - Нет `telegram.json` — вход по одному паролю (`login.php:47`). Если `telegram.json` есть, но отправить код не удалось, — 503 и `CODEFAIL` (`login.php:52-58`).
  - POST `/router/login` с непустым чужим `Origin` → 403 (`login.php:22-24`).
- **Журнал входов** — `/var/log/fspirat-router-auth.log`.
  - Строка: `ДАТА ВРЕМЯ ЧТО ip=… ua="…"` (`lib.php:77-81`).
  - Значения `ЧТО`: `OK, FAIL, LOCKED, CODE, CODEFAIL, LOGOUT, LOGOUT_ALL`.
  - Сторож разбирает журнал и шлёт «Вход в панель» (`server/bin/fspirat-watch:33-48`).
  - Файл создаётся с владельцем www-data и правами 0640 (`.github/workflows/deploy-server.yml:66`). logrotate использует `create 0640 www-data adm` (`server/logrotate/fspirat-router-auth`). Поэтому PHP может его читать.
- **Журнал действий** — `/var/log/fspirat-router-audit.log` (`lib.php:228-234`).
- **IP клиента.** `fsr_ip()` = `REMOTE_ADDR` (`lib.php:75`). Это верно, пока выполняются два условия:
  - Cloudflare работает в режиме «DNS only»;
  - nginx stream передаёт `proxy_protocol`, а realip его разбирает (`server/mtproxy/sni-443.conf`, `server/mtproxy/realip-proxy-protocol.conf`).

### 1.5 Выход
- **`GET /router/logout`.** Удаляет текущую сессию, пишет `LOGOUT`, ставит `Clear-Site-Data: "cache"` и `Cache-Control: no-store`, отвечает 303 на `/router/login` (`logout.php:7-17`).
- **`POST /router/logout all=1`** — HTML-форма без подтверждения (`index.html:272-275`).
  - Если Origin совпал и сессия действительна: `DELETE FROM sessions` (все браузеры), `LOGOUT_ALL` в аудит и журнал.
  - Иначе молча закрывается только текущая сессия (`logout.php:9-14`, `lib.php:195-201`).
  - Таблица `devices` (запомненные браузеры) не трогается.

### 1.6 CGI роутера: общие правила
- **Токен.**
  - Лежит в `/etc/fspirat.token`.
  - Берётся из `${HTTP_COOKIE#*fspirat_token=}` до первого `;`. Если `fspirat_token=` в cookie нет, берётся первая пара cookie.
  - Сравнение — обычное строковое. Не совпал или файла нет → `403 {"error":"forbidden"}` (`cgi:12-13,19`).
  - До проверки токена CGI уже выполняет uci (SHUNT), lua `fspirat-subs groups` и `mkdir /tmp/fspirat` (`cgi:4-11`).
- **Действие и метод.**
  - `action` — `^[a-z]{1,20}$` (`cgi:28`).
  - Чтение (`status net pingone mydirect zapret tgws led subs`) принимает любой метод. Остальное — только POST, иначе `405 {"error":"method"}` (`cgi:38-41`).
  - Неизвестное действие: GET → 405, POST → `400 {"error":"unknown action"}` (`cgi:428`).
- **Параметры.**
  - Берутся из QUERY_STRING, в том числе у POST (`param()`, `cgi:22`). При повторе имени — последнее вхождение. Исключение — `list` у settargets: берётся первое (`cgi:314`).
  - URL-декодирования нет. Исключения: `mac %3A`, `svcdirect name` (`cgi:24-27,284`), settargets (lua, `cgi:316`), subadd (`cgi:412`).
- **Тело POST.** Читается, только если `CONTENT_LENGTH` от 1 до 2048. Используется только в subadd (`bparam`, `cgi:30-32`). Тело больше 2048 байт молча игнорируется.
- **Валидаторы** (`cgi:33-35`). Значение, не прошедшее проверку, становится пустой строкой.
  - `id` — `^[A-Za-z0-9]{1,32}$`. Поэтому `_direct` не проходит, для режима без VPN нужно `direct`.
  - `sid` — `^[A-Za-z0-9_]{1,32}$`.
  - `mac` — после `%3A→:` и `A-F→a-f` проверяется по `^([0-9a-f]{2}:){5}[0-9a-f]{2}$`.
- **Узел Split (SHUNT).** Ищется по порядку (`cgi:4-6`; то же в ping, zapret, svcping, subs):
  1. `/etc/fspirat/config`;
  2. `passwall2.@global[0].node`, если это `_shunt`;
  3. первый `_shunt` в конфиге.

  Константа `9DxG2j8l` в коде не зашита. В `/etc/fspirat/config` можно переопределить и `EXCLUDE` (`fspirat-ping:8-10`).
- **Группы узлов** — названия подписок и `fspirat`, без учёта регистра (`cgi:8-9`).
- **Ответ.**
  - `Content-Type: application/json`, `Cache-Control: no-store` (`cgi:15`).
  - Ошибка — `{"error":"<код>"}`. У subadd и subdel код берётся из stderr lua через `tr -dc 'a-z '` (`cgi:413,424`).
- **Фоновые задачи.** `bg()` = `( setsid sh -c … & )` (`cgi:17`): ответ `{"ok":true}` приходит сразу, результата и идентификатора задачи нет.
- **Время.** Метки — unix-секунды по часам роутера. Строки журнала и расписание — местное время роутера (Europe/Samara, +04), без года.
- **Другие входы в CGI.** CGI доступен из LAN (`http://<LAN-IP>/cgi-bin/fspirat`) и через `router.fspirat.xyz` — тот проксирует весь uhttpd (`server/nginx/sites-available/luci.example.org:6-12`). Без токена — 403.

### 1.7 Кто ещё вызывает CGI (мимо nginx, лимитов и check.php)
- **fspirat-watch.**
  - `status` раз в минуту, токен из nginx-сниппета.
  - Ответ, который не разбирается как JSON, считается «роутер не на связи» (`server/bin/fspirat-watch:13,111-114`).
- **Бот.**
  - Токен из `fsr_dir()/router.token`.
  - Действия: `status`; `ping` (POST, 90 с); `speedtest via=direct` (90 с); `switch`, `block`/`unblock`, `restart`, `update`, `reboot`.
  - Кнопки живут 600 с. Проверяется только чат, `from.id` не проверяется.
  - Журнал `TG` (`tgbot.php:46-53,152,167,248-289,292-293`).
- **Workflows.** `deploy-router.yml:96-97` (Verify) и `rotate-router-token.yml:32` (`action=net`).
- **(новое) Дефект.** `rotate-router-token.yml:27-46` меняет токен на роутере и в сниппете, но не трогает `/var/lib/fspirat-router-auth/router.token`. Этот файл пишет только `deploy-server.yml:102`. Поэтому бот, а потом и приложение, получают 403 до следующего Deploy server. Сторож при этом работает: он берёт токен из сниппета (`fspirat-watch:13`).

### 1.8 Коды ответов по слоям
| Код | Кто отвечает | Тело |
|---|---|---|
| 200 | CGI / PHP | JSON. У `targets` и `subs` при сбое — пустое; у `settargets` — некорректный JSON |
| 400 | CGI | `{"error":"<код>"}` |
| 401 | nginx `@fsr_api_401` | `{"error":"auth"}`, тип JSON |
| 403 | nginx (нет X-FSR) | `{"error":"csrf"}`, тип не JSON |
| 403 | check.php (CSRF/Origin) | HTML-страница nginx |
| 403 | data.php (Origin) | `{"error":"origin"}` |
| 403 | CGI | `{"error":"forbidden"}` |
| 405 | CGI | `{"error":"method"}` |
| 409 | CGI | `{"error":"busy"}`: speedtest, zapretset, zapretcheck |
| 429 | nginx | HTML |
| 500 | CGI | `no rule`, `subscribe.lua not found`, `nft` |
| 500 | nginx (упал check.php) | HTML |
| 502 / 504 | nginx | HTML: туннель оборван или прошло 60 с |
| 503 | CGI | `not installed` |

---

## 2. Полная опись API (проверено)

**Опасность** (none / low / medium / high / критично) сведена из обеих описей и их сверки, решение — в §6.

**TG** — уведомление по `FSR_ACTIONS` (`check.php:11-18`):
- «да» — уведомляет;
- «false» — есть в карте с false;
- «—» — нет в карте.

### 2.1 Действия CGI `/router/api?action=…` (31 действие и «неизвестное»)
| # | action | Метод | Параметры | Ответ | Побочные эффекты и время | Опасн. | Подтверждение в вебе | TG | Источник |
|---|---|---|---|---|---|---|---|---|---|
| 1 | status | любой (веб: GET) | — | §3.1 | 1,5–4 с: `sleep 1`, ~10 процессов на запись DHCP, lua `fspirat-subs list`. Пишет `/tmp/fspirat/wifi.txt` и `traf.txt` — гонка при параллельных вызовах. `fspirat-fw counters` создаёт `inet fspirat` и делает `touch /etc/fspirat/blocked` (запись на флеш) | none | — (опрос раз в 30 с; 502/504 → «не на связи») | — | `cgi:70-119,163-185`; `fspirat-fw:16,18-48,79-80`; `app.js:835-842` |
| 2 | net | любой | — | `{dev, rx, tx (бит/с), rx_total, tx_total (байт)}` | Замер за 1 с на WAN (`ifstatus wan` → l3_device, иначе `wan`) | none | — (раз в 3 с, только на вкладке «Сеть») | — | `cgi:44-57,186`; `app.js:540-546,865-868` |
| 3 | ping | POST | — | Полный status | Синхронно `fspirat-ping all`: обычно 10–25 с, в худшем случае больше 60 с → nginx 504, а работа на роутере продолжается. Если cron держит `/tmp/fspirat/lock` (pidfile, неатомарно), сразу отдаёт старые данные. Добавляет точку в history. При 2 неудачах подряд (`FAILS_TO_SWITCH=2`, счётчик общий с cron) или если текущего узла больше нет — **автосмена сервера и PW**; `_direct` не трогает; если живых узлов нет — ничего, счётчик fails растёт. Синхронно `fspirat-targets` (2×8 с на сайт); в фоне `svcping`, а в :00–:04 или при пустом sub.json — `fspirat-sub` | low* | нет («Проверяю…», ~20 с) | — | `cgi:187`; `fspirat-ping:19-21,23,33-126`; `app.js:871-878` |
| 4 | targets | POST | — | `{ts, list}` или 200 с пустым телом | Синхронно `fspirat-targets`: 1–10 с, при 8 медленных сервисах больше 60 с → 504. Пишет targets.json | none | веб и бот не вызывают | — | `cgi:188`; `fspirat-targets:1-49` |
| 5 | pingone | любой (в наборе READ) | `id` узла из групп | `{id, ms (0 — нет ответа), ts}`; 400 `bad node` | tcping ×3 (до 2 с каждый), берётся лучший. `sed -i` правит ms в ping.json — побочный эффект на GET. Принимает Hysteria2 и исключённые узлы, хотя TCP-пинг для Hysteria2 бессмыслен | none | не вызывается | — | `cgi:34,189-198`; `app.js:6` |
| 6 | switch | POST | `id` узла из групп или `direct` (→ `_direct`) | `{"ok":true}`; 400 `bad node` | `uci set passwall2.<SHUNT>.default_node` + commit (флеш), `fails=0`, в switch.log «вручную -> id», PW в фоне — даже если узел тот же. Живость узла не проверяется. `_direct` пускает весь трафик без VPN и отключает автосмену. После update/subadd/subupdate старые ID дают 400 | high (`direct` — критично) | ask «Подключить «X»? VPN перезапустится…» или «Пустить весь трафик напрямую, без VPN?». Состояние меняется сразу, тишина 15 с, перечитывание через 10 с. Неживой свой сервер выбрать можно (`app.js:243-244,648`) | false | `cgi:199-207`; `fspirat-ping:87-88`; `app.js:632-650` |
| 7 | restart | POST | — | `{ok}` | switch.log, PW в фоне | high | ask «Перезапустить VPN?»; занято 15 с, тишина 15 с, перечитывание через 15 с | да | `cgi:208-211`; `app.js:939-955` |
| 8 | update | POST | — | `{ok}`; 500 `subscribe.lua not found` | В фоне `subscribe.lua start all manual; sleep 5; fspirat-sub; fspirat-ping`, ~1–2 мин. ID узлов могут смениться; если текущий узел пропал — автосмена и PW. Перезапускает ли subscribe.lua сам PassWall, неясно: скрипта нет в репозитории, а тексты противоречат друг другу (§5 п.31) | high | ask «Обновить подписки?»; занято 5 с, тишины нет, перечитывание через 60 с | да | `cgi:212-216`; `fspirat-ping:89-90,98-115`; `app.js:939-955` |
| 9 | speedtest | POST | `via` = `vpn` или `direct`, иначе 400 `bad via` | `{via, ts, down, up (бит/с), latency (мс), ip, country, server ("Hetzner (Германия)" / "Selectel (Россия)"), streams:4, up_limited}`; 409 `busy` | Синхронно 25–35 с, в худшем случае ~50 с: trace Cloudflare ≤8 с; задержка — лучший TTFB из 3 (≤5 с); загрузка 4×10 с (vpn — Hetzner через SOCKS 1070, direct — Selectel); отдача 4 потока на Cloudflare `/__up` блоками по 8 МБ, до ~15 с, при 429 — `up_limited`. Блокировка `speed.lockd` (mkdir), одна на оба вида; зависшая снимается через 180 с. `speed_<via>.json` пишется неатомарно. Тест забивает канал, тест через VPN тратит трафик подписки | low | нет (обе кнопки отключены, «~35 сек»); данные сервера перечитываются через 5 с | — | `cgi:121-161,217-228`; `app.js:925-937` |
| 10 | block | POST | `mac` | `{ok, mac, blocked:true}`; 400 `bad mac`; 500 `nft` (на практике не бывает) | `fspirat-fw block`: `/etc/fspirat/blocked` (через общий `blocked.tmp`) и nft set. Режется всё, кроме адресов самого роутера (LuCI и CGI по LAN-IP, DNS, DHCP); правило стоит раньше PassWall. Запись в switch.log. Если `network.lan.ipaddr` не в формате CIDR — ответ ok, но блокировки нет. Свой iPhone в домашнем Wi-Fi потеряет доступ к fspirat.xyz | high | ask (красная кнопка) «Выключить интернет «X»? …страница тоже станет недоступна»; меняется только локальное состояние | да | `cgi:229-233`; `fspirat-fw:14,30-41,53-62`; `app.js:474-489` |
| 11 | unblock | POST | `mac` | `{ok, mac, blocked:false}` | То же. Во время окна расписания снимает блок до конца окна, но в status остаётся `sblocked:true` | low | **нет** | да | `cgi:229-233`; `fspirat-fw:70-77`; `app.js:457,486` |
| 12 | direct | POST | `mac`; `on=1` — мимо VPN; **любое другое значение или его отсутствие** — снова через VPN | `{ok, direct}`; 400 `bad mac` | ACL `passwall2.fsp_<mac без :>` (remarks «FSPIRAT: мимо VPN», sources=mac), пересчёт `acl_enable`, commit, switch.log. PW — всегда, даже если ничего не изменилось | high | ask «Пускать «X» мимо VPN?» / «…снова через VPN?»; тишина 12 с | — | `cgi:234-245`; `app.js:482-485` |
| 13 | schedule | POST | `mac`; пустой `off` — убрать расписание (`on` игнорируется); иначе `off` и `on` в формате ЧЧММ (00–23, 00–59) и `off≠on`, иначе 400 `time`. Окно может переходить через полночь, время — роутера | `{ok}` | `/etc/fspirat/schedule` (через `schedule.tmp`), затем **сразу** `fspirat-fw schedule`: блок, если окно уже идёт, разблок при снятии. Дальше cron раз в минуту (`deploy-router.yml:88`). В switch.log не пишет | medium/high | диалог-форма, отдельного подтверждения нет; перечитывание через 3 с | — | `cgi:246-257`; `fspirat-fw:63-78`; `app.js:519-537` |
| 14 | mydirect | любой | — | `{domains, added}`: domains — вся domain_list, включая `geosite:` и `domain:`; added — из `mydirect_added`, может устареть. 500 `no rule` | — | none | — (при первом открытии «Сети» и после изменений) | — | `cgi:258-263`; `app.js:597-611,830` |
| 15 | diradd | POST | `d`: приводится к нижнему регистру, без URL-декодирования; шаблон домена (метки до 63), ≤100, иначе 400 `domain`. Кириллица — только punycode | `{ok}` или `{ok, same:true}` (без PW); 500 `no rule` | Домен ставится в начало MyDirect и в `mydirect_added`; commit, switch.log, PW. Наличие проверяется `grep -qx` — это регулярное выражение (точка = любой символ), поэтому возможен ложный `same` | high | ask «Пускать d напрямую?»; тишина 12 с; список перечитывается; тост успеха показывается и при `same` | — | `cgi:264-282`; `app.js:613-621` |
| 16 | dirdel | POST | `d` | `{ok}` или `{ok, same:true}`; 400 `domain`; 500 `no rule` | Удаляет **любую** простую строку domain_list, в том числе заданную в LuCI. Проверка через регулярное выражение может пройти без точного совпадения: тогда удаление (`grep -vxF`) ничего не уберёт, но commit и PW всё равно будут | high | ask (красная кнопка) «Убрать d из MyDirect?»; тишина 12 с | — | `cgi:264-282`; `app.js:622-629` |
| 17 | svcdirect | POST | `name` (URL-декодируется) — имя из списка сервисов, иначе 400 `no target` (так же сразу после перезагрузки, пока нет targets.default); `on=1`, иначе выключить | `{ok}`; 400 `resolve`; 500 `no rule` | Сначала `grep -vxF` убирает прежние записи сервиса — все одинаковые строки, включая добавленные вручную. web: хост без схемы, пути и `www.` в domain_list, без проверки на дубль. mc: `nslookup` → IPv4 `/32` в ip_list. Учёт в `/etc/fspirat/svc_direct`; commit, switch.log, PW | high | ask «Пускать X напрямую?» / «X снова через VPN?»; тишина 12 с | — | `cgi:283-311`; `app.js:651-660` |
| 18 | settargets | POST | `list=kind~name~addr!…` в query (первое вхождение). Ошибки 400: `long` — закодировано больше 3000; `many` — больше 8 строк; `bad` — строка не `буквы~…~…`; `kind` — не web/mc; `name` — не 1–40 байт после trim или есть управляющие символы, `~!"<>&\` или вертикальная черта; `url` — web не `^https?://[\w.-]+[\w\-./?=]*$` или длиннее 200 (нельзя порт, `&`, `%`, `#`); `host` — mc не `host[:port]`, хост ≤100, порт 1–65535 (по умолчанию 25565); `inner` — внутренний адрес (localhost, без точки, .local, .lan, .home.arpa, .internal, 0/8, 10/8, 127/8, 100.64/10, 169.254/16, 172.16/12, 192.168/16, 198.18/15, ≥224, IP одним числом, hex, сокращённый). Пустой список — по умолчанию YouTube, Discord, Telegram | `{"ok":true,"list":"…<TAB>…"}` — **некорректный JSON** (сырой TAB), если список не пустой | `/etc/fspirat/targets` атомарно; `rm svc/*.json`, включая direct.json; в фоне `fspirat-targets` и `svcping` — до ~2 мин, второй Xray ~30 МБ. Если svcping уже идёт, svc остаётся неполным до 30 мин | low/medium (пустой список = сброс) | нет (форма, «Сохраняю…»). После успеха `api()` падает на разборе JSON: веб показывает ошибку, форма остаётся открытой, `target_list` и перечитывание через 20 с не выполняются (`app.js:704-711`) | да | `cgi:312-363`; `fspirat-targets:13-17`; `app.js:670-712` |
| 19 | reboot | POST | — | `{ok}` | В фоне `sleep 2; reboot`. Дома нет интернета 1–2 мин; туннель переподключается (respawn, `-K 30 -I 90`); `/tmp/fspirat` стирается (§3.1); счётчики трафика устройств обнуляются | критично | ask (красная кнопка); занято 30 с, тишина 150 с, перечитывание через 150 с | да | `cgi:364-366`; `app.js:939-955` |
| 20 | zapret | любой | — | §3.3; без скрипта `{"installed":false,"absent":true}` | несколько `nft list` | none | — (раз в 30 с; раз в 3 с, пока busy или checking) | — | `cgi:369-371`; `fspirat-zapret:226-242` |
| 21 | zapretset | POST | `on` = 0 или 1, иначе 400 `bad on` | `{ok}`; 503 `not installed`; 409 `busy` | Порядок проверок: on → наличие скрипта → каталог `/tmp/fspirat/zapret/lock`. Каталог может держать другое действие, сторож cron `ensure` (раз в минуту) или зависшая блокировка. В фоне ~5–15 с. on: конфиг на флеш, dry-run, `inet fspirat_zapret`, nfqws (≤5 с), правило fsZapret→Direct. off: правило убирается, nfqws останавливается, таблица удаляется. PW — **только если правило изменилось**. Ошибки появляются позже в `zapret.error`. При занятой блокировке фоновая команда молча выходит с кодом 2 | high | ask в обе стороны; тишина 15 с; zapret перечитывается через 1,5 с, затем раз в 3 с | — | `cgi:372-377`; `fspirat-zapret:47-55,125-131,149-166`; `.github/workflows/zapret-install.yml:83` |
| 22 | zapretstrat | POST | `n` = 1, 2 или 3, иначе 400 `bad strategy` | `{ok}`; 503 | CGI блокировку не проверяет. В фоне `lock()`: если владелец блокировки жив, команда **молча теряется**; если мёртв — зависшая блокировка снимается. Затем dry-run, конфиг, перезапуск только nfqws (если zapret включён). PassWall не трогается | low | **нет**; zapret перечитывается через 2 с | — | `cgi:378-382`; `fspirat-zapret:51,167-174` |
| 23 | zapretcheck | POST | — | `{ok}`; 503; 409 (флаг `checking`) | В фоне `touch checking; check; rm checking`, без блокировки zapret — может идти одновременно с on/off. ~10–40 с, до ~76 с: какой IP видит Discord и 4 пробы через SOCKS 1070. Если проверку убили, `checking` остаётся до перезагрузки | none/low | нет; опрос раз в 3 с | — | `cgi:383-387`; `fspirat-zapret:200-221,249` |
| 24 | tgws | любой | — | `{installed, auto, redirected, enabled, running, listening, host (LAN-IP), port:1443, version}`; без скрипта `{"installed":false,"absent":true}`. Секрета и ссылки в ответе нет | — | none | — (раз в 60 с) | — | `cgi:389-391`; `fspirat-tgws:80-90` |
| 25 | tgwsset | POST | `on` = 0 или 1, иначе 400 `bad on` | `{ok}`; 503 | В фоне. on: служба включается и перезапускается, ожидание порта :1444 до 20 с, затем `inet fspirat_tg` перенаправляет Telegram всех устройств LAN; если нет прокси или python3 — exit 1 **молча**, поля error нет. off: таблица удаляется, служба останавливается. Без блокировки; PassWall не трогает; в switch.log не пишет. Сторож cron снимает перехват, если 1444 не слушает | medium | ask в обе стороны; тоста успеха нет; перечитывание через 3 и 8 с | — | `cgi:392-396`; `fspirat-tgws:61-77`; `.github/workflows/tgws-install.yml:91` |
| 26 | led | любой | — | `{on, items:[{name, on}]}` — фактическое состояние из sysfs; или `{absent:true}` | — | none | — (раз в 300 с) | — | `cgi:398-400`; `fspirat-led:3,14-21` |
| 27 | ledset | POST | `on` = 0 или 1 | новое `{on, items}`; 400 `bad on`; 503 | Синхронно: `uci system.fspirat_led_*` + commit (флеш), `/etc/init.d/led restart`, ~0,5–1 с | none | **нет** (переключатель в шапке), тост | — | `cgi:401-405`; `fspirat-led:22-38`; `app.js:1055-1072` |
| 28 | subs | любой | — | `[{id, name, host (только хост), hwid, nodes, ts?, up?, down?, total?, expire?}]`; при сбое lua — 200 с пустым телом | — | none | веб не вызывает (берёт `status.subs`) | — | `cgi:407`; `fspirat-subs:66-77` |
| 29 | subadd | POST | **Тело** `application/x-www-form-urlencoded`, ≤2048 байт (больше — тело не читается, ответ 400 `sub name`). `name` — 1–48 байт, без управляющих символов, `"'\$;&<>{}%`, обратной кавычки и вертикальной черты, не «fspirat». `url` — `https://host[:port]/путь` (путь обязателен), ≤500, не внутренний адрес. `hwid`: `0` → 0, иначе 1. Веб проверяет имя строже: `^[\p{L}\p{N} ._-]{1,32}$` | `{ok, id}`; 400 `sub name`, `sub url`, `inner`, `sub many` (уже 8), `sub exists` (имя без учёта регистра или та же ссылка); 500 `subscribe.lua not found` | Новая секция `subscribe_list` с настройками первой подписки (без remark, url, md5, hwid); commit; в switch.log «подписка добавлена». В фоне `subscribe.lua start <id> manual; sleep 5; fspirat-sub; fspirat-ping`. В успешный ответ попадает stdout и stderr lua (`2>&1`) | high | форма + ask «Добавить подписку «X»?…»; «Добавляю…»; перечитывание через 45 с | да | `cgi:30-32,408-416`; `fspirat-subs:79-98`; `app.js:780-796` |
| 30 | subupdate | POST | `sid` — необязателен. Без `sid` **или с `sid` неверного формата** обновляются ВСЕ подписки | `{ok}`; 400 `bad sub` (нет такой); 500 | В switch.log «обновление подписки <remark>». В фоне — то же, что у subadd | high | **нет**; кнопка занята на время запроса и ещё 3 с; перечитывание через 45 с | false | `cgi:33,417-422`; `app.js:797-806` |
| 31 | subdel | POST | `sid` | `{ok, switched:bool}`; 400 `bad sub` — неизвестный или кривой sid, пустое имя, группа fspirat | Если текущий узел из этой подписки — переключение: лучший живой узел из других групп → первый свой (даже неживой) → **`_direct`** (только если своих узлов нет). Затем удаление секции, commit, `subscribe.lua truncate <name>` (наличие скрипта не проверяется: без него узлы останутся в конфиге, но пропадут из панели). Удаляется `sub/<id>.json`, но не `sub.json` — до часа `status.sub` показывает удалённую подписку. switch.log; `fails=0`; в фоне **всегда** `passwall2 restart; sleep 8; fspirat-ping`. Куда переключилось — видно только в журнале | критично | ask (красная кнопка) с текстом о переключении; тишина 12 с; перечитывание через 8 с | да | `cgi:423-427`; `fspirat-subs:104-130`; `app.js:807-812` |
| 32 | неизвестный или некорректный action | любой | — | GET → 405 `method`; POST → 400 `unknown action` | — | — | «Страница устарела» | — | `cgi:28,38-41,428` |

\* `ping` сам по себе безопасен. Но если VPN уже дважды подряд не прошёл, он переключит сервер и перезапустит PassWall.

### 2.2 Маршруты сервера (PHP)
| Маршрут | Метод | Параметры | Ответ | Побочные эффекты | Опасн. | Веб | Источник |
|---|---|---|---|---|---|---|---|
| `/router/data?csrf=1` | GET | заголовок `X-FSR: 1` | `{"csrf":"<48 hex>"}`; 401 | — | none | при старте страницы; токен кэшируется и запрашивается заново на 403 | `data.php:22`; `lib.php:214-218`; `app.js:69-75` |
| `/router/data?range=day/week/month` | GET | `range` (неизвестный → day), `X-FSR` | §3.2 | работает без туннеля | none | раз в 60 с и при смене периода; на 401 — вход, другие ошибки молча | `data.php:41-145`; `app.js:845-863` |
| `/router/data` (переименование) | POST | тело `mac=&name=`; `X-FSR=<csrf>`; `Origin`; тело ≤4 КБ | `{ok, names}`; 400 `bad mac`; 403 `origin` | `names.json` на сервере: имя ≤40 символов, управляющие символы удаляются, пустое имя удаляет своё. Аудит `ACTION rename` без mac | low | без подтверждения; сохраняется по Enter **и при потере фокуса**; один повтор на 403 | `data.php:24-39`; `nginx-apply.py:26`; `check.php:27`; `app.js:492-516` |
| `/router/logout` | GET | — | 303 на `/router/login`, `Clear-Site-Data: "cache"` | конец текущей сессии | low | ссылка «Выйти» | `logout.php:1-17`; `index.html:48` |
| `/router/logout` | POST | форма `all=1`; `Origin` | 303 | если Origin и сессия в порядке — `DELETE FROM sessions` и `LOGOUT_ALL`; иначе только текущая сессия | low | **без подтверждения** | `logout.php:9-17`; `index.html:272-275` |
| `/router/login?next=` | GET/POST | `password`, `remember`, `code` | HTML; 403 при неверном пароле или коде; 503, если код не удалось отправить | сессия, cookie `fsr_dev`, таблица `fails`, журнал | — | — | `login.php:20-70`; `lib.php:237-262` |
| `/router/tg-hook` | POST | заголовок секрета бота; пускаются только подсети Telegram | 200 сразу, работа после ответа | команды и кнопки бота, вызовы CGI | — | — | `nginx-apply.py:94-95`; `tgbot.php:14-23,292-293` |
| `/_fsr_auth` (внутренний) | — | `FSR_ORIG_URI`, `FSR_ORIG_METHOD` | 204 / 401 / 403 / 500 | аудит, Telegram | — | — | `check.php:1-53` |

### 2.3 Что есть только в интерфейсе веба
- **Тест скорости в браузере** (`app.js:880-923`). Результат не сохраняется.
  - Задержка: 6 запросов `GET https://speed.cloudflare.com/__down?bytes=0`, площадка — из заголовка `cf-meta-colo`.
  - Загрузка: 6 потоков `__down?bytes=50000000`, 8 с.
  - Отдача: 4 потока `POST __up` блоками по 2 МБ, 8 с.
  - Первая секунда не считается.
- **Тема.** `localStorage fsr-theme` = light или dark; режим «как в системе» = ключ удалён. `meta theme-color` — #F6F8FB или #090B0F (`theme.js:1-41`).
- **Ссылка LuCI.** Берётся из `data.site.luci`, если подходит под `^https://[\w.-]+(:\d+)?/?$`, открывается в новой вкладке. LuCI закрыт той же cookie `fsr_session` (`app.js:733-738`).
- **Переход на вход.** На 401 — `/router/login?next=<pathname>` (`app.js:48,72,100,848`).
- **Вкладки веба:** VPN, Сеть, Устройства, Журнал (`index.html:30-33`, `app.js:821`). zapret и «Telegram через Cloudflare» лежат на вкладке VPN (`index.html:141-161`), MyDirect, «Роутер» и «Безопасность» — на вкладке «Сеть».

### 2.4 Карта Telegram `FSR_ACTIONS` (`check.php:11-18`)
- **true:** `reboot, restart, update, block, unblock, settargets, subadd, subdel`.
- **false:** `switch, subupdate, rename`.
- **Нет в карте** (только аудит): `ping, speedtest, svcdirect, diradd, dirdel, direct, schedule, zapretset, zapretstrat, zapretcheck, tgwsset, ledset`.

---

## 3. Схемы ответов

### 3.1 `status` (`cgi:163-182`)
```
running: bool          // pidof xray — ЛЮБОЙ xray, в т.ч. временный от svcping (cgi:166, fspirat-svcping:29)
split_active: bool     // passwall2.@global[0].node == SHUNT; false — MyDirect не работает
current: "<nodeId>" | "_direct" | ""   // "" — Split не найден
ping: null | { updated, current, socks: bool /*false = SOCKS 1070 rc=7*/,
               real: ms | null /*0 = VPN не прошёл, null = SOCKS недоступен*/,
               nodes: [{id, name, ms /*0 = нет ответа*/, group, own?: true}] }
     // real — проверка «через VPN 204»: два запроса по одному соединению через SOCKS 1070 к
     //   http://www.gstatic.com/generate_204, успех только при коде 204; задержка — второй запрос (без рукопожатий),
     //   иначе первый; лучший из 2 попыток (fspirat-ping:12,47-63). Cron */5 (deploy-router.yml:86) + ручной ping
     // nodes: VLESS из групп с адресом и портом, кроме LTE|Россия|Обход, + текущий; Hysteria2 нет (fspirat-ping:34-41)
     // name/group экранируются только \ и " — управляющий символ ломает JSON (fspirat-ping:75,78)
log: ["ДД.ММ ЧЧ:ММ текст", …≤8]          // switch.log, время роутера без года
history: [[ts, ms], …≤288]               // точку пишет КАЖДЫЙ запуск fspirat-ping: шаг неравномерный
targets: null | {ts, list: [{kind: "web"|"mc", name, host, vpn: ms /*0 = нет ответа*/}]}
sub: null | {ts, up, down, total /*0 = без лимита*/, expire /*0 = без срока*/, title}  // раньше всех кончится
subs: null | [{id, name, host, hwid, nodes, ts?, up?, down?, total?, expire?}]    // [] — подписок нет; null — сбой lua
svc_direct: [name…], target_list: ["kind|name|addr"…]   // у mc всегда :port
svc: {"<nodeId>": {ts, list}, "direct": {ts, base /*TCP до ya.ru*/, list}}, svc_running: bool
speed: {vpn: Speed|null, direct: Speed|null}
devices: [{name /*DHCP, может быть ""*/, ip, mac, online, band?: "2g"|"5g"|"6g"|"wired", signal?: dBm, rate?: Мбит/с,
           up, dn /*байт IPv4 НАКОПЛЕННО с создания nft-таблицы, обнуляются при перезагрузке; за день — только в /router/data*/,
           blocked?, sblocked?, direct?, sched?: "ЧЧММ-ЧЧММ"}]
sys: {cpu %, cores, load "1 5 15", mem_total, mem_avail, disk_total, disk_used /*overlay*/, tmp_total, tmp_used /*кБ*/,
      temp: °C|null /*thermal_zone0; null — нет датчика (cgi:113-114)*/, uptime с, model, fw, xray_rss кБ,
      net: {dev, rx, tx, rx_total, tx_total}}
Speed = {via, ts, down, up, latency, ip, country, server, streams: 4, up_limited}
```
**Как заполняются поля:**
- `devices` строится только из `/tmp/dhcp.leases`. Устройства со статическим IP или с истёкшей арендой не видны, вместе с их блокировкой и расписанием.
- `online` = флаг ARP `0x2` или наличие в assoclist (`cgi:75-94`).
- `temp` веб показывает как «нет датчика», если пришёл null (`app.js:564`). Предупреждение включается от 85 °C (`app.js:162`). Есть ли датчик у AX3000T, из репозитория не видно.

**После перезагрузки:**
- ping, targets, sub — null, а history и log — [] до первого cron, это ≤5 мин;
- `speed` — null до ручного теста скорости;
- `svc` — {} до svcping: в минуты :00–:04 или :30–:34, то есть до ~30 мин;
- `target_list` — [], если своего списка нет, до первого `fspirat-targets`.

**Чего в status нет:**
- zapret, tgws, led — это отдельные действия;
- имена, трафик за день и месяц и история — берутся из `/router/data`;
- нет списка заблокированных MAC и расписаний вне DHCP.

### 3.2 `/router/data?range=` (`data.php:41-145`)
```
now, range, step (0 | 1800 | 7200)
points: day [[ts, ms]] | week/month [[mid, avg | 0 | -1, fails, off]]   // -1 — нет удачных и пропусков >=3 (data.php:67)
stats: {avg, min, max, fails, offline_min}       // offline_min — минутные точки с -1
events: [[ts, kind, text]]                       // последние 300 строк events.tsv, в пределах периода, до 100, новые сверху (data.php:72,136)
offline_since | null, last_ok | null
names: {mac: name}, tpoints: {name: [[ts, ms]]}
traffic: {mac: {d: [up, down], m: [up, down]}}   // прирост по дням считает fspirat-watch раз в минуту (fspirat-watch:154-165)
speed: [[ts, via, down, up, latency]]            // 90 дней
mtg: {active, conns, since, ts} | null           // null — site.mtg пуст или нет mtg.json (mtg выключен 12.10.2026)
site: {luci, bot, mtg, panels}
```
**Трафик устройств (уточнено).**
- Ключ дня в `traffic.json` — системная дата сервера в момент записи (`fspirat-watch:158`, `date +%F`), хранится 62 дня.
- «Сегодня» и «месяц» data.php выбирает по Москве (`lib.php:29`, `data.php:102`), а бот берёт «сегодня» по UTC (`tgbot.php:125`).
- Судя по `fspirat-watch:271`, сервер работает в UTC. Тогда в вебе «сегодня» около 3 ч после полуночи МСК равно 0 (§5 п.30).
- Учитывается только IPv4, по IP из аренды DHCP. Telegram через tg-ws-proxy не учитывается (`docs/tgws.md:31`).

**Виды событий** пишет `server/bin/fspirat-watch:120-243`:
- `offline`, `vpn_down` → ошибка;
- `auto`, `xraymem`, `reboot`, `newdev` → внимание;
- `online`, `vpn_up` → успех;
- `manual`, `restart`, `update`, `router` → действие (`app.js:386-387`).

Строки switch.log роутера сторож переносит в `events.tsv` (`fspirat-watch:189-214`):
- «авто» → `auto`, «вручную» → `manual`, «перезапуск» → `restart`, «обновление» → `update`;
- всё остальное → `router`: «MyDirect ±», «мимо VPN / снова через VPN», «интернет выключен/включён», «<сервис>: напрямую», «подписка добавлена/удалена».

Время такой строки — момент, когда сторож её заметил (до 1 мин). Исключение — первый запуск.

**Новое устройство.** Текст события: `Новое устройство: <info> (<mac>)` (`fspirat-watch:150`). Список известных MAC (`$KNOWN`) хранится без времени (`fspirat-watch:136-151`).

### 3.3 Остальные ответы
- **zapret:**
  - `installed` — есть nfqws, списки и модуль nfnetlink_queue. `absent` — нет самого скрипта.
  - `enabled`; `strategy` (1–3, по умолчанию 3).
  - `engine` — nfqws запущен; `nft`; `route_cfg`; `route_live` — правило попало в работающий Xray.
  - `fallback` — движок отказал, YouTube и Discord временно через VPN.
  - `error` — строка ≤200 без `"`, `\` и перевода строки.
  - `pkts_tcp`, `pkts_udp`.
  - **`vpn_excluded` — 0 или 1**, есть ли хоть один элемент в vpn4, а не число адресов.
  - `version`.
  - `busy` — есть каталог блокировки, в том числе от сторожа.
  - `checking`.
  - `check`: `null`, `{"error":"xray"}` или `{ts, via: isp/vpn/unknown, list: [{name, ok (коды 2xx/3xx/4xx), code (СТРОКА, например «204», «000»), ms (time_total), queued (пакетов в очередь nfqws)}]}`.
  - Источник: `fspirat-zapret:201-242`.
- **tgws:**
  - `auto` — таблица перехвата есть; `redirected` — число пакетов.
  - **`listening` проверяет порт 1443**, а не прозрачный 1444 (`fspirat-tgws:14-15,40,66,75,87`).
- **led:** `{on, items}` или `{absent:true}`.
- **Ответы действий:**
  - `mydirect`: `{domains, added}`; `net`: `{dev, rx, tx, rx_total, tx_total}`;
  - `subadd`: `{ok, id}`; `subdel`: `{ok, switched}`;
  - `block`/`unblock`: `{ok, mac, blocked}`; `direct`: `{ok, direct}`;
  - `settargets`: `{ok, list}` — с сырым TAB;
  - `diradd`/`dirdel`: `{ok[, same]}`; `ledset`: `{on, items}`;
  - остальные — `{ok:true}`.

---

## 4. Поведение веб-клиента: что повторить и что исправить

### 4.1 Опрос
`every()` не начинает новый запрос, пока не закончился прежний, и пропускает тик, если вкладка скрыта. При возврате на вкладку сразу вызываются `tLoad, tData, tZap, tTg, tLed`; `net` при этом не опрашивается (`app.js:1076-1093`).

| Таймер | Интервал | Запрос |
|---|---|---|
| tLoad | 30 с | `status` |
| tData | 60 с и при смене периода | `/router/data?range=` |
| tZap | 30 с; раз в 3 с, пока busy или checking | `zapret` |
| tTg | 60 с | `tgws` |
| tLed | 300 с | `led` |
| loadNet | 3 с, только на вкладке «Сеть», вне тихого окна | `net` |
| tickUpdated | 5 с | без запроса |

**(Дефект)** `lastOk` («обновлено N с назад») обновляется после любого удачного запроса, включая `net`. Подпись может выглядеть свежей, когда `status` устарел (`app.js:97`).

### 4.2 Что веб делает после действий
**Тишина** (`quietUntil`) — пока она идёт, ошибки не показываются и экран «не на связи» не включается.

| Действие | Занято | Тишина | Перечитать |
|---|---|---|---|
| ping | на время запроса | — | ответ — полный status |
| restart | 15 с | 15 с | status через 15 с |
| update | 5 с | 0 | status через 60 с |
| reboot | 30 с | 150 с | status через 150 с |
| switch | — | 15 с | status через 10 с; состояние меняется сразу |
| svcdirect, direct, diradd, dirdel | — | 12 с | status не перечитывается; MyDirect — через loadMd |
| subdel | — | 12 с | status через 8 с |
| subadd | на время запроса | — | status через 45 с |
| subupdate | на время запроса + 3 с | — | status через 45 с |
| settargets | на время запроса | — | задумано через 20 с, но из-за битого JSON не выполняется (`app.js:704-711`) |
| zapretset | на время запроса | 15 с | zapret через 1,5 с, затем раз в 3 с |
| zapretstrat | — | — | zapret через 2 с |
| tgwsset | на время запроса | — | tgws через 3 и 8 с |
| schedule | — | — | status через 3 с |
| speedtest | обе кнопки | — | data через 5 с |

### 4.3 Ошибки → текст в вебе (`app.js:93-107`)
| Ситуация | Текст |
|---|---|
| fetch упал | «Нет связи с сайтом…» |
| 401 | `toLogin()`, «Вход истёк — открываю страницу входа.» |
| 502 / 504 | «Роутер временно недоступен…»; у status — режим «не на связи» |
| 409 | у speedtest «Тест скорости уже идёт…», у остальных «Это действие уже выполняется.» |
| 429 | «Слишком много запросов подряд…» |
| 405 | «Страница устарела — обнови её (Ctrl+F5).» |
| 403 `forbidden` | «Роутер отклонил запрос: ключ сервера не совпадает с роутером.» |
| другие 403 | «Запрос отклонён. Обнови страницу (Ctrl+F5).» |
| 400 | «Роутер не принял запрос: » + перевод из словаря ERR, иначе сам код |
| 500 / 503 | «Роутер не смог выполнить действие…» |

**Словарь ERR** (`app.js:77-86`) используется **только при 400**: `bad mac, bad node, bad via, name, url, host, many, inner, long, domain, time, resolve, no target, no rule, bad sub, sub url, sub name, sub exists, sub many, bad on, bad strategy, not installed`.
- `no rule` (500) и `not installed` (503) на деле не переводятся.
- `bad`, `kind` и `unknown action` выводятся как есть.

**Исключения:**
- `loadData` на 401 уходит на вход, остальные ошибки молча пропускает.
- `loadLed`, `loadTgws`, `loadNet` глотают ошибки, кроме 401.
- `loadZap`: если состояния ещё нет, блок остаётся скрытым; если есть — ошибка видна в красной плашке.
- Переименование: 401 на сам POST даёт тост. Но 401 при повторном получении CSRF-токена уводит на вход.
- (Дефект) api() повторяет POST на **любой** 403, в том числе на `forbidden` от роутера. Получается два запроса к роутеру (`app.js:95`).
- Если первый status упал не с 502/504, а `state` ещё пустой, карточка всё равно пишет «Роутер — не на связи» (`app.js:156-158,837-841`).

### 4.4 «Роутер не на связи»
- **Когда включается.** Только по 502/504 на status вне тихого окна (`app.js:836-841`).
- **Текст.** «Не на связи с {offline_since или last_ok} · уже N мин · последний ответ …» (`app.js:739-754`).
- **(Дефект)** `body.is-down` отключает только `[data-act]`, `#ping-btn`, `#ping-all`, `#led-btn` и строки серверов (`app.css:509-511`). Подписки, zapret, tgws, MyDirect, меню устройства, тест скорости и редактор сервисов остаются нажимаемыми и получают 502.
- **Что остаётся видно.** История, журнал, трафик и имена — из `/router/data`.

### 4.5 Правила итоговой карточки (`app.js:152-201`)
- **Роутер.** warn, если RAM > 90% (`1 - mem_avail/mem_total`), флеш > 90% или `temp >= 85`. Подпись — первое подходящее: «XX°C», «мало памяти», «флеш почти полон», иначе «в сети».
- **VPN.**
  - `current = _direct` → warn «выключен — всё напрямую»;
  - `!running` → err «остановлен»;
  - `!vpnOk` → err «не проходит», где `vpnOk = running && (!ping.socks || ping.real > 0)`;
  - `real > 250` → warn;
  - иначе ok.
- **Интернет.** ok, если `vpnOk || svc.direct.base > 0`.
- **Серверы.** «живых из всего»: ≥2 — ok, 1 — warn, 0 — err.
- **Сервисы.** Пункт есть, только если список не пуст: warn «нет ответа: …».
- **Подписка.** Берётся та, что кончится раньше всех (запасной вариант — `sub`): ≤3 дн. — warn, <1 дн. — err «закончилась».
- **Split.** `!split_active` → warn и плашка «В PassWall выбран не узел Split… Basic Settings → Node».
- **KPI «Задержка»** (это и есть проверка «через VPN 204»). socks и real>0 → «N ms», цвет по `msCls`: <120 / <250 / дольше. socks без real → красное «нет». Без socks → «—».
- **Плитка «Сегодня ↓»** — сумма `traffic[*].d[1]`, только если больше 0.

### 4.6 Форматирование (`app.js:23-40,129-132,281,376-385,568-569`)
- **speed** — Мбит/с или кбит/с; **mb** — ГБ/МБ (на входе кБ); **ago** — до часов; **upt**; **minutes**; **plural**; **flag** (эмодзи).
- **pingLv** (уровень пинга): 5 — <60, 4 — <120, 3 — <250, 2 — <400, 1 — дольше, 0 — нет ответа.
- **Полоски пинга:** #10B981 (уровни 5–4), #F59E0B (3), #EF4444 (2–1), неактивные #94A3B8 с непрозрачностью 0,35; у уровня 0 — красный крестик.
- **Сигнал Wi-Fi:** > -55 — 4, > -65 — 3, > -75 — 2, иначе 1, без значения — 0.
- **«Скрытый MAC»:** второй символ 2, 6, A или E, и у устройства нет имени.
- `bars`, `level`, `pingHtml` (`app.js:15-24`) — мёртвый код.

### 4.7 Стиль для повторения в SwiftUI (`app.css:1-60`, `web/fonts/README.md:3-7`)
**Цветовые токены** (тёмная / светлая):

| Токен | Тёмная | Светлая |
|---|---|---|
| bg | #090B0F | #F6F8FB |
| surface | #11151B | #F1F5F9 |
| card | #161B22 | #FFFFFF |
| raise | #1C222B | #FFFFFF |
| hover | #1A2029 | #F4F7FA |
| border | #252B35 | #E2E8F0 |
| border-2 | #313946 | #CBD5E1 |
| line | #1F252E | #EDF1F5 |
| text | #F1F5F9 | #0F172A |
| dim | #94A3B8 | #64748B |
| faint | #64748B | #94A3B8 |
| acc / acc-fill | #34D399 | #059669 |
| acc-tx | #34D399 | #047857 |
| acc-hov | #4ADEA8 | #047857 |
| on-acc | #052E1F | #FFFFFF |
| acc-soft / acc-ring | rgba(52,211,153,.10/.32) | rgba(5,150,105,.08/.30) |
| warn | #FBBF24 | #B45309 |
| warn-soft / warn-bd | rgba(251,191,36,.10/.30) | rgba(217,119,6,.09/.30) |
| err | #F87171 | #DC2626 |
| err-fill | #DC2626 | #DC2626 (наведение #B91C1C) |
| err-soft / err-bd | rgba(248,113,113,.10/.32) | rgba(220,38,38,.06/.28) |
| info | #60A5FA | #2563EB |
| info-soft / info-bd | rgba(96,165,250,.10/.30) | rgba(37,99,235,.07/.25) |
| sel | rgba(52,211,153,.07) | rgba(5,150,105,.06) |
| chart-grid | rgba(148,163,184,.09) | rgba(100,116,139,.12) |
| area | rgba(52,211,153,.10) | rgba(5,150,105,.10) |
| offline | rgba(148,163,184,.10) | rgba(100,116,139,.10) |
| cline | rgba(241,245,249,.35) | rgba(15,23,42,.30) |
| backdrop | rgba(3,5,8,.72) | rgba(15,23,42,.35) |
| glow | rgba(52,211,153,.06) | rgba(5,150,105,.05) |

**Тени:**
- `--shadow`: тёмная `0 1px 2px rgba(0,0,0,.35), 0 10px 30px -18px rgba(0,0,0,.8)`; светлая `0 1px 2px rgba(15,23,42,.04), 0 6px 20px -12px rgba(15,23,42,.12)`.
- `--shadow-pop`: тёмная `0 18px 50px -12px rgba(0,0,0,.75), 0 2px 6px rgba(0,0,0,.4)`; светлая `0 18px 44px -14px rgba(15,23,42,.25), 0 2px 6px rgba(15,23,42,.06)`.

**Логотип:** градиент 145° #34D399 → #047857.

**Шрифты:**
- Inter (100–900) — весь интерфейс: базовый текст 14.5/1.5, `cv11`, `ss01`.
- JetBrains Mono (100–800) — числа, мс, IP, MAC, время; цифры табличные.
- Лицензия обоих — SIL OFL 1.1, их можно положить в приложение, но брать TTF из официальных релизов, а не woff2 из `web/fonts`.
- Twemoji Country Flags (код MIT, рисунки CC-BY 4.0) на iOS не нужен.
- Размеры: итог 20/650, сервер 22/650, h2 15/600, sub-h 11.5/600 ЗАГЛАВНЫЕ .06em, KPI моно 14/600, «Интернет сейчас» моно 26/600, таблица моно 12.5/500, tag 11/500, заголовок окна 17/650.

**Формы и размеры:**
- Скругления: 14 — панели, 10 — плитки, 8 — кнопки, 16 — окна, 12 — меню, 999 — чипы.
- Кнопки 36 (small — 32); квадратная кнопка 36×36, иконка 18; чип высотой 30.
- Сегменты: высота 28, радиус 7. Переключатель: 28×16, бегунок 12.
- Полоска заполнения 6: от 65% жёлтая, от 85% красная. Точки состояния 7–8 px с кольцом 3 px.
- «Лампа» 44×44, радиус 12. График: линия 1,75, высота 140 (малый — 110).
- `prefers-reduced-motion` отключает анимации.

**Иконки:** Lucide 0.460.0 (ISC), обводка 1,75.
- Используются 49: `router, wifi, wifi-off, server, activity, monitor-smartphone, shield-check, scroll-text, settings, moon, sun, sun-moon, refresh-cw, power, lock-keyhole, lightbulb, lightbulb-off, gauge, cpu, memory-stick, hard-drive, thermometer, clock, globe, arrow-down, arrow-up, arrow-right, log-out, search, check, x, plus, pencil, ellipsis, ban, rotate-ccw, timer, box, zap, circle-check, circle-alert, cable, trash-2, link, rss, brand-youtube, brand-discord, brand-telegram, brand-instagram`.
- Не используются 8: `external-link, triangle-alert, chevron-down, arrow-up-down, send, play, list-filter, info`.
- Иконка сервиса выбирается по хосту (`app.js:121-128`).
- Соответствие SF Symbols — в §9.4.

---

## 5. Дефекты и особенности, которые влияют на контракт
1. **settargets** отдаёт некорректный JSON (сырой TAB, `cgi:363`). Веб после успешного сохранения показывает ошибку, форма остаётся открытой, перечитывания нет (`app.js:704-711`).
2. **`running`** = любой процесс xray. Во время svcping работает временный Xray (svcping:29), поэтому `running` может быть true при упавшем основном.
3. **subupdate** с кривым sid молча обновляет все подписки (`cgi:33,419`).
4. **direct и svcdirect** без `on` выключают режим.
5. **block/unblock:** ошибка nft до клиента не доходит. При LAN не в формате CIDR блокировки нет (`fspirat-fw:14,56-62`).
6. **zapret и блокировки:**
   - zapretstrat при живой чужой блокировке молча теряется;
   - zapretset даёт 409 и во время работы сторожа;
   - зависший lock снимает вызов zapretstrat, зависший `checking` — только перезагрузка (`fspirat-zapret:47-55,248`).
7. **ping при занятой блокировке cron** без ошибки отдаёт старые данные; в худшем случае идёт дольше 60 с и получает 504.
8. **В `ping.nodes` нет Hysteria2 и узлов «LTE / Россия / Обход»** (кроме текущего), хотя switch и pingone их принимают.
9. **switch на тот же узел** всё равно перезапускает PassWall; живость узла не проверяется.
10. **После перезагрузки** поля из `/tmp` пустые (§3.1), счётчики устройств обнуляются.
11. **unblock во время окна расписания** оставляет `sblocked:true`.
12. **`log`** — только 8 строк, время роутера без года.
13. **Ошибки nginx** (403 от check.php, 429, 500, 502, 504) приходят в HTML; 403 csrf — JSON-текст без типа JSON.
14. **subdel:**
    - не обновляет `sub.json` (fspirat-subs:128);
    - не проверяет, есть ли subscribe.lua;
    - уходит на первый свой узел, даже неживой, а без своих — в `_direct` (fspirat-subs:117-122).
15. **diradd и dirdel** проверяют наличие домена регулярным выражением (`cgi:271,275`). dirdel удаляет и записи, сделанные в LuCI.
16. **Устройства вне DHCP-аренды** не видны, вместе с их блокировкой и расписанием.
17. **Типы полей:** `zapret.vpn_excluded` — 0 или 1; `check.code` — строка; `tgws.listening` проверяет порт 1443.
18. **subs и targets** при сбое отдают 200 с пустым телом.
19. **Ошибки subadd и subdel** — stderr lua с фильтром. В успешный ответ subadd идёт `2>&1`, и предупреждение lua сломает JSON.
20. **Общие `.tmp`-файлы без блокировки** — `blocked.tmp`, `schedule.tmp`, `mydirect_added.tmp`, `svc_direct.tmp`, `targets.json.tmp`. Две одновременные правки одного вида могут потерять запись.
21. **Неатомарная запись** `speed_<via>.json` и `svc/<id>.json`: status изредка может вернуть битый JSON.
22. **Имя узла с управляющим символом** ломает JSON status. Сторож тогда считает роутер выключенным (`fspirat-watch:111-114`).
23. **fspirat-ping:** блокировка не атомарна, при почти одновременном старте возможна двойная автосмена.
24. **svcping** при свободной памяти меньше 70 МБ прекращает весь оставшийся замер (svcping:25-26).
25. **mcping:** при прямом подключении у connect нет таймаута (mcping:43-44,53-54).
26. **tgwsset:** сбой «тихий», поля error нет.
27. **(новое)** Workflow смены токена роутера не обновляет `router.token` (§1.7).
28. **(новое)** Сообщение сторожа о новом устройстве ссылается на `/router/#net`, а выключить интернет устройству можно на `#dev` (`fspirat-watch:147-149`).
29. **Веб:**
    - «Telegram через Cloudflare» спрятан внутри секции zapret (`index.html:141-161`);
    - в режиме «не на связи» часть кнопок остаётся активной;
    - проверка имени подписки на странице (32 символа) расходится с сервером (48 байт);
    - журнал зависит от переключателя периода у графика (`app.js:858-863`).
30. **(новое) Граница суток трафика.** Запись — по системной дате сервера (`fspirat-watch:158`), выбор «сегодня» в вебе — по Москве (`data.php:102`, `lib.php:29`), в боте — по UTC (`tgbot.php:125`). Если сервер в UTC, «сегодня» в вебе около 3 ч после полуночи МСК равно 0. PLAUSIBLE: проверить `timedatectl` (§8.5).
31. **(новое) Противоречие текстов о подписках.** Бот на /update пишет «VPN не перезапускается» (`tgbot.php:314`), а веб при добавлении подписки — «потом VPN перезапустится» (`app.js:789`). subscribe.lua в репозитории нет. Выяснить через ops (только чтение) до написания текстов окон.
32. **(новое) fail2ban и свой VPN.** Jail-ы `fspirat-router-auth` (и будущий app-jail) банят `port = http,https` (`fspirat.local:20`). Порт 443 nginx stream делит по SNI с Xray своего NL-сервера (`server/mtproxy/sni-443.conf`, `server/vpn-nl/setup.sh:3`).
    - Бан домашнего IP провайдера (5 FAIL с устройства «мимо VPN» или в режиме `_direct`) на час отрезает дом от своего NL: роутер ходит к NL с IP провайдера, `localhost_proxy=0`.
    - Дальше 2 провала проверки → автосмена.
33. **(новое) Сообщение о подборе пароля** приходит только при следующей попытке: `LOCKED` пишется, когда вход уже закрыт (`login.php:25-27`, `fspirat-watch:43`).
34. **(новое) Без Telegram API** новый браузер не войдёт: 503, `CODEFAIL` (`login.php:52-58`). По одному паролю веб пускает только без `telegram.json` (`login.php:47`).

---

## 6. Расхождения между проектами сервера и экранов и мои решения
| Тема | Проект сервера (вход и API) | Проект экранов и сборки | Решение |
|---|---|---|---|
| Способ входа | (б′) пароль + сверка числа в боте | (б) сверка числа; на деле тоже с паролем | **(б′)**: пароль + 3 кнопки и «Это не я». Режим без пароля — только как настройка `APP_LOGIN_PASSWORD=0`, по умолчанию 1. Сверки числа, как у VDS, в этом репозитории нет: в `lib.php:242` есть только переход на `/vds/` — это панель homeserver. Строим заново; для единообразия запросить её устройство у сессии homeserver (только описание, без секретов). Не путать с командой бота `/vds` и путём `/router/app/v1/vds` (свои VPN-серверы) |
| Неверное число и «Это не я» | Оба → общий замок на 1 ч | — | **Неверное число** → `410 login_denied` + `fsr_fail()` только для этого IP. **«Это не я»** → общий замок входа приложения по паролю на 1 ч + тревога в Telegram с советом сменить пароль (удалить `/var/lib/fspirat-router-auth/password` и обновить `.htpasswd_router` через ops) |
| Face ID | Проверка сервером (Secure Enclave) — этап 2b, не в v1 | Face ID в приложении для критичных действий | **v1:** `LAContext` в приложении на открытие и на критичные действия: reboot, switch→direct, revoke-all. «Выйти на этом iPhone» — только окно. **2b** (позже, по желанию): ключ P-256 в Secure Enclave подписывает `confirm` |
| Состав действий v1 | subadd, subdel, settargets входят (с подтверждением) | Не входят (остаются в вебе) | **v1 без них**: на сервере отвечают `404 not_in_v1`. Спецификация описана и включается в v1.1 по решению владельца. Причины: секретная ссылка; уход на другой или неживой узел и в `_direct`; битый JSON |
| pingone | Не входит (GET с побочным эффектом) | «Проверить сейчас» в карточке сервера | **Входит** как `POST /action/pingone {id}` без подтверждения, лимит 20 в минуту. Сервер обращается к CGI через GET (CGI принимает любой метод) |
| «Проверить» (ping) при неработающем VPN | Без подтверждения | Без подтверждения | **Окно в приложении**, если `ping.socks && ping.real == 0`: «роутер может сам переключить сервер, VPN перезапустится». Сервер `confirm` не требует |
| Свои VDS (NL, DE) | Нет | Карточка «Свои VPN-серверы» | **`GET /vds`** — читает `/var/lib/fspirat/vds.json`. Поля `{ts, servers:[{name, local?, stat:{up, load, cores, mem_total, mem_avail, disk, rx, tx, xray, conns}}]}`, адресов хостов в файле нет (`fspirat-watch:61-71`, `fspirat-vdsstat:5-9`). Сервер пропускает только эти поля. В v1 — по решению владельца |
| Журнал входов | `logins` из `app_logins` | Строки OK/FAIL/LOCKED/LOGOUT из журнала входов | **`GET /devices`** отдаёт оба списка: `logins` (20 последних входов приложения) и `auth_log` (30 последних строк журнала входов: ts, what, ip). Журнал www-data читать может (`deploy-server.yml:66`, logrotate `create 0640 www-data adm`) |
| Новые устройства | Нет | Нужен `first_seen` | **`newdevs:[{ts, mac}]`** в ответе `/data` для приложения: события `newdev` за 7 дней по всему `events.tsv` (не только 300 последних строк); MAC — из текста `(…)` (`fspirat-watch:150`) |
| Долгие ping и speedtest | Задачи: 202 и `/jobs/{id}` | Таймаут 75 с или задачи | **Задачи.** Глобально одна долгая задача сразу (flock) — бережём воркеры php-fpm |
| Подтверждения | 428 + `confirm` для списка действий | Уровни критичный / высокий / средний / низкий | **Объединено в матрицу §7.8.** Сервер требует `confirm` для всего уровня «средний» и выше, кроме отзыва одного устройства. Уровень и Face ID решает приложение |
| subupdate | С подтверждением | Высокий | С подтверждением (в вебе его нет) |
| schedule | С подтверждением при установке | Высокий, если окно уже идёт, иначе средний | Сервер требует `confirm` при любой установке, снятие — без него. Текст окна выбирает приложение: оно считает, идёт ли окно, по времени `Europe/Samara` |
| tgwsset | С подтверждением | Средний | С подтверждением, обычная (не красная) кнопка |
| «Выйти везде» в вебе | Отзывать и токены приложения | Вопрос владельцу | Рекомендация — да. Плюс `DELETE FROM devices`: после этого на любом браузере снова спросят код. Решает владелец |
| `/subs` | Чтение входит | Не нужно (берётся `status.subs`) | **Не публикуем**: дублирует `status.subs`, при сбое отдаёт пустое тело |
| dirdel | Любой домен | Только записи из `added` | Сервер в v1 разрешает `dirdel` **только для доменов из `mydirect.added`**: перед вызовом делает GET `mydirect`. Так не тронутся записи из LuCI и не сработает регулярное выражение на чужие строки |
| Токен в адресе | nginx `if` по `$args` + PHP | — | **Только PHP** (§7.4 п.3): nginx-`if` отвечал бы 400 раньше PHP, и утёкший токен не отзывался бы |
| Чистка таблицы токенов | Раз в сто запросов | — | Строки отозванных и истёкших токенов хранить до `hard_expires + 30 дн`, чтобы старый телефон получал `token_revoked`/`token_expired`, а не `token_invalid` (тот считается в fail2ban) |
| Офлайн | — | Отключены все кнопки к роутеру | Как в проекте экранов (строже веба) |
| «Обновлено N с назад» | — | Только по удачному status | Как в проекте экранов |
| Журнал | `/data?range=` | Свой период, только события сервера | Свой выбор периода в приложении, `status.log` не используется: строки switch.log уже приходят через `events.tsv` (§3.2) |

---

## 7. Спецификация `/router/app/v1` (этап 2)

### 7.1 Принципы
- **Отдельный путь.** `location ^~ /router/app/v1/` → `server/auth/app.php`. Нет `auth_request`, нет cookie (`fastcgi_param HTTP_COOKIE ""`), принимается только `Authorization: Bearer`.
- **Веб не трогается.** `/router/api`, `/router/data`, check.php, CSRF и Origin остаются как есть. Bearer-токен там не работает, cookie не работает в `/app/v1`.
- **Обращение к роутеру — как у бота.** PHP вызывает CGI роутера, как это делает `tgbot.php:46-53`, через общую функцию `fsr_router_call()` в `lib.php`.
- **Сервер всё делает сам.** Прямой вызов обходит лимиты nginx, check.php и `proxy_read_timeout`. Поэтому аудит, Telegram, лимиты и проверку параметров (теми же правилами, что CGI, §1.6 и §2.1) сервер выполняет сам.
- **Ответ всегда JSON:** `Content-Type: application/json; charset=utf-8`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`. CORS нет, `OPTIONS` → 405.
- **Методы:** чтение — GET; всё остальное — POST, тело `application/json` ≤4 КБ.
  - Не JSON → 415; больше 4 КБ → 413.
  - `json_decode(…, true, 4, JSON_THROW_ON_ERROR)`.
  - Неизвестные поля → 400 `bad_param`.
- **Query-параметры** — только `range` у `/data`, любой другой → 400 `bad_param` (кроме случаев §7.4 п.3, они проверяются раньше).
- **Строка запроса к CGI** собирается `http_build_query(…, PHP_QUERY_RFC3986)`. Значения передаются только после проверки формата.

### 7.2 Вход (б′)
**Ход входа:**
1. `POST /auth/login {password, device:{name, model, os, app}}`.
2. Сервер проверяет: рубильник → лимиты → общий замок «Это не я» → `fsr_locked()` → `fsr_password_ok()`.
   - **(ревью 13.10.2026)** `fsr_locked()` и запись попытки в `fails` — одной транзакцией (`BEGIN IMMEDIATE`) **до** bcrypt: `fsr_attempt()` в `lib.php`, верный пароль убирает запись (`fsr_attempt_ok()`). Иначе пачка параллельных запросов с одного IP, пока каждый ждёт bcrypt и паузу, видела «0 ошибок» и проверяла пароль вся (≈ число воркеров + 5 попыток), а её ошибки закрывали вход приложения всем (подбор «с разных адресов»). Так же в `login.php`.
   - Неверный пароль → `fsr_fail()`, запись `FAIL`, пауза 300–700 мс, ответ `401 bad_password {left}`.
   - Верный пароль → `login_id = random_bytes(32)`, `number = random_int(10,99)` и 2 других числа 10..99 в случайном порядке (CSPRNG).
3. Запись в `app_logins` хранит `hash = sha256(login_id)`, `tg_ref` (12 hex), number, state = pending.
4. `fsr_tg_call(sendMessage)` с кнопками, **без parse_mode**. Текст: «Вход в приложение. Устройство: «имя» · модель · iOS · IP. Нажми число с экрана…».
   - Кнопки: `al:<tg_ref>:<число>|<ts>` и `an:<tg_ref>|<ts>`, не больше 30 байт.
   - Обрабатываются в `on_button()` **до** общего правила «600 с» (`tgbot.php:254-255`). Срок кнопок входа — 120 с.
   - Проверки: `from.id === chat`, `message_id === tg_msg`, `state = pending`.
5. Ответ приложению: `200 {login_id, number, expires_in:120, poll_every:2}`.
6. Приложение раз в 2 с шлёт `POST /auth/poll {login_id}`.
   - `pending` → `{state:"pending"}`.
   - `approved` → `BEGIN IMMEDIATE`, токен выдаётся один раз, `state = issued`. Ответ `{state:"approved", token, device_id, expires, hard_expires}`. Повторный опрос → 410.
7. **Исходы.**
   - **Неверное число** → `410 login_denied`, `APP_DENIED`, `fsr_fail()` для IP входа. Общего замка нет: одно случайное нажатие владельца не закрывает вход на час.
   - **«Это не я»** → `410 login_denied`, `APP_DENIED`, `fsr_fail()`, общий замок входа приложения по паролю на 1 ч (файл `fsr_dir()/app_login_lock` с временем). Тревога в Telegram с советом сменить пароль. Веб-вход не затрагивается: он защищён кодом.
   - Прошло 120 с → `410 login_expired`.
   - `POST /auth/cancel` → `cancelled`.
   - **(ревью 13.10.2026)** Замок («Это не я», подбор) и «Выйти на всех устройствах» (веб и `/devices/revoke-all`) закрывают и входы, которые ждут нажатия или одобрены, но ключ ещё не забран (`expired`, сообщение в боте поправляется). Пока стоит замок, ключ по одобренному входу не выдаётся → `410 login_denied`.
8. **Защита от перебора и спама.**
   - Блокировка общая с вебом: 5 ошибок за 15 мин.
   - Больше 30 записей в `fails` за час со всех IP → вход приложения по паролю закрыт на час, одно сообщение в Telegram.
   - Не больше 5 `login` в час с одного IP и 10 в час всего.
   - Одновременно ожидают не больше 2 входов, иначе 429 `busy`.
   - Устройств не больше 10, иначе `409 too_many_devices`.
9. **Без Telegram** (`fsr_tg()` пуст или нет `tgbot.json`) → `503 tg_unavailable`. Пускать по одному паролю, как веб без `telegram.json` (`login.php:47`), приложение не должно.

### 7.3 Токен и таблицы (`auth.sqlite`, лениво через `CREATE TABLE IF NOT EXISTS` в `fsr_app_db()`)
**Формат токена.**
- Токен: `'fsr1_' . base64url(random_bytes(32))`, всего 48 символов, `^fsr1_[A-Za-z0-9_-]{43}$`.
- В базе только `sha256` в hex. Открытый `device_id` = 16 hex, из токена не выводится.

**Таблицы:**
- `app_devices(id PK, token_hash UNIQUE, name ≤40 без \x00-\x1f\x7f, model/os/app ≤32 [\x20-\x7e], created, seen, expires, hard_expires, ip, last_ip, revoked, revoked_by)`.
  - `revoked_by`: `self`, `app:<id>`, `web`, `all`, `tg`, `url_leak`, `ops`.
  - Индекс `(revoked, expires)`.
- `app_logins(hash PK, tg_ref UNIQUE, number, tg_msg, created, decided, state, device_id, name, model, os, app, ip, ua)` — хранится 30 дней, индекс `(ip, created)`.
- `app_confirms(hash PK, device, action, params, created)` — живёт 60 с, одноразовый.
- `app_actions(device, action, ts)` — для лимитов, хранится 2 суток.
- `app_jobs(id PK, device, action, created, done, http, result)` — хранится 1 ч.

**Срок действия.**
- `expires = min(seen + 90 дн, hard_expires)`, `hard_expires = created + 365 дн`.
- `seen` обновляется не чаще раза в 300 с.
- При продлении токен не меняется.

**Чистка** — раз в сто запросов. Строки `app_devices` удаляются только после `hard_expires + 30 дн` (и отозванные тоже). Так старый телефон получает `token_revoked`/`token_expired`, а не `token_invalid`, который считается в fail2ban.

**Почему sha256, а не bcrypt.** У токена 256 бит случайности, перебрать его по утёкшей базе нельзя. Сессии веба устроены так же (`lib.php:173-174`).

### 7.4 Порядок проверки запроса
1. Есть файл `fsr_dir()/app_disabled` → `503 app_disabled`.
2. Есть заголовок `Origin` или `Sec-Fetch-Site` → `403 browser_request`. URLSession их не шлёт, в ошибки входа это не идёт.
3. **Токен в адресе** — проверяет только PHP; в nginx такой проверки нет (§8.2). Условие: в `REQUEST_URI` есть `fsr1_` или параметр `access_token|token|bearer|authorization|auth`.
   - если по хэшу это настоящий токен — отозвать (`url_leak`);
   - записать `APP_URLTOKEN`, сообщить в Telegram;
   - ответить `400 token_in_url`.
4. Пути `/auth/login`, `/auth/poll`, `/auth/cancel` проходят без токена.
5. Проверка `HTTP_AUTHORIZATION`:
   - заголовка нет → `401 token_missing`, в fail2ban не считается;
   - не подходит под шаблон или хэша нет в базе → `401 token_invalid` + `APP_BADTOKEN`, это считается в fail2ban;
   - **(ревью 13.10.2026)** шаблон — `^Bearer fsr1_…$` **с учётом регистра**, как map ключа `fsr_app_dev` (§8.1): «bearer …» с настоящим ключом проходил бы мимо лимита на устройство, поэтому не принимается (`token_invalid`);
   - отозван → `401 token_revoked`; истёк → `401 token_expired`. Оба случая fail2ban **не** считает: старый телефон не должен банить домашний IP;
   - ко всем 401 добавляется `WWW-Authenticate: Bearer error="invalid_token"`.
6. Скользящее продление срока (§7.3).

### 7.5 Коды ошибок
**Формат:** `{"error":"<код>","message":"<понятный русский текст>"[,"source":"router"]}`.

| Код | `error` |
|---|---|
| 400 | `bad_param`, `token_in_url`, `too_long`, `confirm_invalid`, коды CGI (`bad node`, `bad mac`, `domain`, `time`, …) |
| 401 | `token_missing`, `token_invalid`, `token_expired`, `token_revoked`, `bad_password {left}` |
| 403 | `browser_request` |
| 404 | `not_found`, `not_in_v1` |
| 405 | `method` (+ `Allow`) |
| 409 | `busy`, `too_many_devices` |
| 410 | `login_denied`, `login_expired` |
| 413 / 415 | `too_large` / не JSON |
| 428 | `confirm_required` |
| 429 | `rate_limited`, `locked`, `busy` (вход: уже ждут два; роутер: заняты места, §7.11) (+ `retry_after`, `Retry-After`) |
| 500 | `server_error`, `server_config` (нет router.token), `router_token` (роутер ответил `forbidden`; сообщение в Telegram не чаще раза в час) |
| 502 | `router_offline`, `router_bad_reply`, `server_unavailable` |
| 503 | `app_disabled`, `tg_unavailable`, `not installed` |
| 504 | `router_timeout` |

### 7.6 Вход и устройства
| Метод и путь | Тело | Ответ | Лимит | Журнал и TG |
|---|---|---|---|---|
| POST `/auth/login` | `{password, device:{name, model, os, app}}` | §7.2 | §7.2 | `APP_LOGIN` / `FAIL` / `LOCKED`; кнопки |
| POST `/auth/poll` | `{login_id}` | `pending` / `approved` + токен / 410 | nginx по IP | `APP_OK`; «Вход в приложение: имя · модель · iOS · IP. Устройств: N. Отозвать — /apps» |
| POST `/auth/cancel` | `{login_id}` | `{ok}` | — | правка сообщения |
| POST `/auth/logout` | — | `{ok}` | — | `APP_REVOKE`; TG. В приложении — окно без Face ID |
| GET `/me` | — | `{device:{id, name, created, expires, hard_expires}, now}` | общий | — |
| GET `/devices` | — | `{apps:[{id, name, model, os, app, created, seen, last_ip, expires, hard_expires, current}], web:[{ref (16 hex от хэша), created, seen, ip, ua}], logins:[{ts, name, ip, result}], auth_log:[{ts, what, ip}]}` | общий | — |
| POST `/devices/revoke` | `{id}` или `{web_ref}` | `{ok}` | 30 в час | аудит, TG «Доступ приложения отозван: «имя» (кем)» |
| POST `/devices/revoke-all` | `{web:bool}` + `confirm` | `{ok, revoked:N}` | 5 в час | аудит, TG |

**В веб-панели:**
- `GET /router/data?devices=1` отдаёт то же, что `/devices`;
- `POST /router/data?op=apprevoke` с телом `id=` проходит обычную проверку CSRF и Origin в check.php.

**В боте:** команда `/apps` показывает список, кнопка `ar:<id>|ts` отзывает устройство.

**«Выйти на всех устройствах» в вебе** (если владелец согласится): в `fsr_session_end(true)` (`lib.php:195-201`) добавить `UPDATE app_devices SET revoked=?, revoked_by='all' WHERE revoked IS NULL` и, по желанию, `DELETE FROM devices`.

### 7.7 Чтение (GET)
| Путь | Источник | Таймаут | Примечание |
|---|---|---|---|
| `/status` | CGI `status` | 20 с | §3.1; при битом JSON — одна попытка исправить (экранировать управляющие символы внутри строк), иначе `502 router_bad_reply` |
| `/net` | CGI `net` | 5 с | |
| `/zapret` | CGI `zapret` | 10 с | |
| `/tgws` | CGI `tgws` | 10 с | |
| `/led` | CGI `led` | 10 с | |
| `/mydirect` | CGI `mydirect` | 10 с | |
| `/data?range=day/week/month` | PHP `fsr_data_payload()` (вынести из `data.php:41-145` в `data-lib.php`) + `newdevs` | — | работает без туннеля. Границу суток трафика привести к одному поясу (§5 п.30) |
| `/vds` | `/var/lib/fspirat/vds.json`, только разрешённые поля | — | по решению владельца |
| `/jobs/{id}` | `app_jobs` | — | `{state: running}` / `{state: done, http, result}` / `{state: error, error}`; только задачи своего устройства, иначе 404 |

**Не публикуем:** `subs` (дублирует `status.subs`) и `targets` (пустое тело, синхронно дольше 60 с).

### 7.8 Действия: `POST /action/<имя>`, тело — JSON
| Действие | Тело (проверка на сервере) | CGI | Уровень | `confirm` (428) | Face ID в приложении | Лимит | TG |
|---|---|---|---|---|---|---|---|
| ping | `{}` | `ping` → **задача** 202 | низкий* | нет на сервере; в приложении окно, если `ping.socks && ping.real == 0` | — | 1 за 30 с, 30 в час | — |
| speedtest | `{via: vpn/direct}` | `speedtest&via=` → **задача** | низкий | нет (подпись про канал и трафик) | — | 1 за 2 мин, 10 в час; от CGI может прийти 409 | — |
| pingone | `{id}` | `pingone&id=` (GET) | низкий | нет | — | 20 в мин | — |
| switch | `{id}`: id узла или `"direct"` | `switch&id=` | высокий; `direct` — критично | да | только `direct` | PW | false |
| restart | `{}` | `restart` | высокий | да | — | PW | да |
| update | `{}` | `update` | высокий | да | — | PW + 6 в час | да |
| subupdate | `{sid}` или `{all:true}`; кривой sid не пропускается | `subupdate&sid=` | высокий | да | — | PW + 10 в час | false |
| reboot | `{}` | `reboot` | критично | да | да | 1 за 5 мин, 3 в час на всех | да |
| block | `{mac}` | `block&mac=` | высокий (красная кнопка, текст про свой iPhone) | да | — | 30 в час | да |
| unblock | `{mac}` | `unblock&mac=` | низкий | нет | — | 30 в час | да |
| direct | `{mac, on:bool}`, `on` всегда явный | `direct&mac=&on=1/0` | высокий | да | — | PW | — |
| schedule (установить) | `{mac, off:"HHMM", on:"HHMM"}` | `schedule&…` | средний; если окно идёт — высокий | да | — | 30 в час | — |
| schedule (убрать) | `{mac, off:"", on:""}` | `schedule&off=&on=` | низкий | нет | — | 30 в час | — |
| diradd | `{d}` | `diradd&d=` | высокий | да | — | PW | — |
| dirdel | `{d}`, только из `added` | `dirdel&d=` | высокий (красная кнопка) | да | — | PW | — |
| svcdirect | `{name, on:bool}` | `svcdirect&name=<urlenc>&on=` | высокий | да | — | PW | — |
| zapretset | `{on:bool}` | `zapretset&on=` | высокий | да | — | PW | — |
| zapretstrat | `{n:1/2/3}` | `zapretstrat&n=` | низкий | нет (приложение проверяет, применилось ли) | — | 10 в мин | — |
| zapretcheck | `{}` | `zapretcheck` | низкий | нет | — | 1 за 30 с | — |
| tgwsset | `{on:bool}` | `tgwsset&on=` | средний | да | — | 10 в час | — |
| ledset | `{on:bool}` | `ledset&on=` | низкий | нет | — | 10 в мин | — |
| rename | `{mac, name}` (пустое — сброс) | PHP `fsr_names_set()` | низкий | нет | — | 30 в час | false |
| subadd / subdel / settargets | v1.1 | — | — | — | subdel — Face ID | — | да |

\* См. сноску к §2.1: при двух подряд провалах VPN ping сам меняет сервер и перезапускает PassWall.

**Проверка параметров на сервере:**
- `id` — `^[A-Za-z0-9]{1,32}$` или ровно `direct`;
- `sid` — `^[A-Za-z0-9_]{1,32}$`;
- `mac` — `^([0-9a-f]{2}:){5}[0-9a-f]{2}$` (приложение приводит к нижнему регистру);
- `d` — `^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$`, ≤100;
- ЧЧММ — `^([01][0-9]|2[0-3])[0-5][0-9]$` и `off ≠ on`;
- `via` — `vpn` или `direct`;
- `on` — bool, превращается в `1` или `0`;
- имя у rename — ≤40 символов без управляющих;
- имя у svcdirect — 1–40 байт без управляющих символов и символов `~!"<>&\|`.

**Ответ** — тело CGI как есть. Пустое или не-JSON тело → `502 router_bad_reply`. На будущее (v1.1) для settargets: `str_replace("\t", '\t')`, затем `list` превращается в массив.

**Действия по одному.** Пока идёт вызов CGI, держится `flock(fsr_dir().'/app-action.lock', LOCK_EX|LOCK_NB)`; занято → `409 busy`. Веб и бот этот замок обходят.

**Класс PW** — действия с перезапуском PassWall: `switch, restart, update, subupdate, direct, diradd, dirdel, svcdirect, zapretset` (+ `subadd, subdel`). Между ними **общая для всех устройств пауза 15 с**, плюс не больше 30 в час на устройство.

**(ревью 13.10.2026) Что идёт в лимиты.** Действие записывается в `app_actions` до вызова CGI (параллельный запрос уже видит паузу), но запись убирается, если роутер его **точно не выполнил**: запрос до роутера не дошёл (нет `router.token`, порт туннеля закрыт — «Connection refused», «роутер молчит» ниже), CGI отказал своей ошибкой (400/409/500/503 — до изменений, §2.1) или не принял ключ (`router_token`). Иначе switch на устаревший id (`bad node` после обновления подписки) закрывал бы смену сервера всем телефонам на 15 с, а оборванный туннель — reboot на 5 минут. `504 router_timeout` и обрыв после отправки считаются: роутер мог выполнить. Так же у задач ping/speedtest.

**Подтверждения:** не больше 20 `confirm` в минуту на устройство.

### 7.9 Подтверждение: 428 → `confirm`
1. **Первый запрос без `confirm`.** Сервер ничего не делает и отвечает `428 {error:"confirm_required", confirm:"<32 hex>", expires_in:60, danger, title, text, button}`. В `app_confirms` записывается `sha256(confirm)`, устройство, действие и `sha256` канонического JSON проверенных параметров.
2. **Приложение** показывает окно (и Face ID, если он нужен), затем повторяет **то же тело** + `"confirm"`.
3. **Сервер проверяет:** то же устройство, то же действие, тот же хэш параметров, `created ≥ now − 60`.
   - Совпало → запись удаляется, действие выполняется.
   - Не совпало → `400 confirm_invalid`.
   - Истекло → снова 428.

**Тексты окон приходят с сервера**, чтобы не расходились у приложения, веба и бота. Особые тексты:
- `switch direct` — «весь трафик без VPN, автопереключение отключится»;
- `block` и `schedule` — «если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет»;
- `switch` на неживой узел (ms = 0) — «сервер не отвечает — дом может остаться без VPN до автопереключения (~10 мин)»;
- `update`/`subupdate` — текст про перезапуск VPN согласовать после выяснения §5 п.31;
- `subdel` (v1.1) — «переключит на другой сервер, возможно неживой свой; без своих — без VPN».

### 7.10 Долгие задачи
**Порядок:**
1. `POST /action/ping` или `/action/speedtest` → сразу `202 {job, poll_every:3}`.
2. `fastcgi_finish_request()`, `set_time_limit(120)` — как у бота (`tgbot.php:21-23`).
3. Вызов CGI с таймаутом 90 с, результат записывается в `app_jobs`.
4. Приложение опрашивает `GET /jobs/{id}`.

**Ограничение:** глобально не больше одной долгой задачи сразу (свой flock), иначе 409.

**Если fspirat-ping уже идёт по cron,** CGI быстро вернёт старые данные. Приложение пишет «данные с последней проверки».

### 7.11 Лимиты
| Уровень | Правило |
|---|---|
| nginx, IP: `fsr_app_ip` | 5 r/s, `burst=40 nodelay` — отдельно от веба |
| nginx, устройство: `fsr_app_dev` | 2 r/s, `burst=20`. Ключ — первые 12 символов токена после `fsr1_` (72 бита), пустой ключ не считается; «Bearer» — с учётом регистра, как в app.php (§7.4) |
| PHP, вызовы роутера | **(ревью 13.10.2026)** роутер одновременно ждут не больше 2 запросов приложения (места — flock), остальные ждут место до 4 с, потом `429 busy`; роутер промолчал (504 или обрыв дольше 2 с) — 30 с без вызовов, сразу `502 router_offline` (и действия — без окна подтверждения); все вызовы роутера в одном запросе — в общий срок 25 с (nginx ждёт php-fpm 30 с; dirdel — это mydirect и dirdel подряд). Долгая задача — мимо мест (одна на всех). См. §11 п.3 |
| PHP | вход (§7.2), класс PW, лимиты по действиям (§7.8) |
| Ответ | `429 {error:"rate_limited", retry_after}` + `Retry-After`; от nginx — через `@fsr_app_429` |

### 7.12 Журналы и Telegram
- **`FSR_ACTIONS`** переносится из `check.php:11-18` в `lib.php`. Добавляются `apprevoke` и `apprevokeall` с флагом true. check.php работает как прежде.
- **Журнал действий:** `fsr_audit('APP', "<action> id=… sid=… mac=… via=… on=… n=… d=… → 200|400:<код>", 'a:'.$deviceId)`; отказы — `APP_DENY <action> rate|confirm|param`. Чтение в журнал не пишется. Ссылки подписок, пароль, `login_id` и токены не пишутся никогда.
- **Журнал входов:** новые значения `APP_LOGIN, APP_OK, APP_DENIED, APP_BADTOKEN, APP_URLTOKEN, APP_REVOKE` строго в формате `ДАТА ВРЕМЯ ЧТО ip=… ua="…"`. Сторож их не трогает (`fspirat-watch:38-44`) — сообщения шлёт сам PHP, без дублей. Фильтр `fspirat-router-auth` (`(FAIL|LOCKED) ip=`) их тоже не ловит.
- **Telegram:**
  - те же 8 действий, что у веба, с подписью «Из приложения «имя», IP …», сообщение после ответа;
  - вход, отзыв, неверное число, «Это не я» (с советом сменить пароль), токен в адресе, распределённый подбор.

### 7.13 `fsr_router_call()` (в `lib.php`)
**Сигнатура:** `fsr_router_call(string $action, array $q = [], string $method = 'GET', int $timeout = 20, string $body = ''): array` → `[код, массив|null]`.

**Как работает:**
- Токен берётся из `fsr_dir()/router.token` и проверяется по `^[A-Za-z0-9]{16,128}$`. Нет или не подходит → `[500, server_config]`.
- Адрес: `FSR_ROUTER`, по умолчанию `http://127.0.0.1:8081/cgi-bin/fspirat` (переменная уже используется ботом, `tgbot.php:11`).
- Токен идёт только в `Cookie: fspirat_token=…` и в журналы не попадает.
- `ignore_errors` включён; код ответа берётся из `$http_response_header[0]`.
- `false` по таймауту → 504 `router_timeout`, иначе 502 `router_offline`.
- `403 forbidden` → `[500, router_token]`.

**Бот** (`router()` в `tgbot.php:46-53`) переходит на эту функцию.

### 7.14 Что меняется в файлах
| Файл | Изменение |
|---|---|
| `server/auth/app.php` (новый) | маршруты, проверки, вход, устройства, чтение, действия, `confirm`, задачи, лимиты, журналы, токен в адресе |
| `server/auth/app-lib.php` (новый) | `fsr_app_db()`, токены, `app_logins`, `confirm`, лимиты, чистка (с хранением отозванных строк) |
| `server/auth/data-lib.php` (новый) | `fsr_data_payload()`, `fsr_names_set()`, `fsr_app_devices_list()`; защита `if (!defined('FSR'))`. Новые функции — с префиксом `fsr_`: `names()` уже есть и в `tgbot.php:54`, и в `data.php:19` |
| `server/auth/lib.php` | `FSR_ACTIONS`, `fsr_audit(…, ?string $ref)`, `fsr_tg_call()` (из `tgbot.php:26-32`), `fsr_router_call()`, отзыв в `fsr_session_end(true)` |
| `server/auth/data.php` | обёртка над `data-lib`; `GET ?devices=1`; `POST ?op=apprevoke` |
| `server/auth/check.php` | `$action` для `/router/data`: `op=apprevoke` → `apprevoke`, иначе `rename` (строка 27); `FSR_ACTIONS` из lib.php |
| `server/auth/tgbot.php` | кнопки `al`/`an` (с проверкой `from.id`), `ar`, команда `/apps`, `router()` → `fsr_router_call()` |
| `server/auth/tgbot-commands.json` | `/apps` |
| `server/auth/nginx-apply.py` | этап 7 `app_api()` |
| `server/nginx/conf.d/fsr-limits.conf` | зоны и map |
| `server/fail2ban/fspirat.local`, `server/fail2ban/filter.d/fspirat-router-app.conf` | новый jail |
| `.github/workflows/deploy-server.yml` | тесты, фильтр, `app_password` в site.json, Verify |
| `.github/workflows/rotate-router-token.yml` | переписать `router.token` **сразу за роутером** (вместе со сниппетом, до проверок — иначе бот и приложение несколько секунд получали бы 403 и ложную тревогу с часом тишины), после успеха убрать `router_token_alert`; при откате вернуть прежний (не было — удалить) |
| `server/auth/tests/app-test.sh` + заглушки | §10 |
| `web/index.html`, `web/app.js` | список устройств и «Отозвать» в разделе «Безопасность» (`index.html:269-276`) |
| `.gitignore` | `*.p8`, `*.p12`, `*.mobileprovision`, `ios/*.xcodeproj/`, `DerivedData/`, `ios/build/` |
| роутер | **не трогается** — дефекты CGI сервер обходит сам |

---

## 8. nginx, выкладка, fail2ban, откат

### 8.1 `server/nginx/conf.d/fsr-limits.conf` (контекст http)
Регулярное выражение map — с учётом регистра (`~`), и app.php принимает только «Bearer» (§7.4 п.5): иначе «bearer fsr1_…» давал бы пустой ключ и обходил зону устройства.
```nginx
limit_req_zone $binary_remote_addr zone=fsr_app_ip:1m rate=5r/s;
map $http_authorization $fsr_app_key {
    "~^Bearer fsr1_(?<fsr_k>[A-Za-z0-9_-]{12})"  $fsr_k;
    default "";
}
limit_req_zone $fsr_app_key zone=fsr_app_dev:1m rate=2r/s;
```

### 8.2 Блок в сниппете (этап 7 `nginx-apply.py`, между метками `# --- fsr-app v1 (begin)` и `(end)`)
```nginx
location ^~ /router/app/ { default_type application/json; return 404 '{"error":"not_found"}'; }
location ^~ /router/app/v1/ {
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Cache-Control "no-store" always;
    default_type application/json;
    limit_req zone=fsr_app_ip burst=40 nodelay;
    limit_req zone=fsr_app_dev burst=20 nodelay;
    client_max_body_size 4k;
    error_page 429 = @fsr_app_429;
    error_page 413 = @fsr_app_413;
    error_page 502 504 = @fsr_app_5xx;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME /var/www/router-auth/app.php;
    fastcgi_param HTTP_COOKIE "";
    fastcgi_read_timeout 30s;
    fastcgi_pass unix:/run/php/php8.5-fpm.sock;
}
location @fsr_app_429 { default_type application/json; add_header Retry-After 2 always; return 429 '{"error":"rate_limited","retry_after":2}'; }
location @fsr_app_413 { default_type application/json; return 413 '{"error":"too_large"}'; }
location @fsr_app_5xx { default_type application/json; return 502 '{"error":"server_unavailable"}'; }
```
- **Почему путь не перехватывается страницей.** `^~ /router/app/v1/` длиннее `^~ /router/`, к тому же regex-локации отключены. Поэтому страница и её `auth_request` этот путь не перехватывают.
- **Токен в адресе nginx не проверяет (исправлено).** В черновике был `if ($args ~* "(^|&)(access_token|token|…)=")`, но он отвечал бы 400 раньше PHP: утёкший `?access_token=fsr1_…` не отзывался бы и оставался в access_log. Всю проверку делает PHP (§7.4 п.3).
- **`Authorization`** в стандартный `access_log` не пишется.

### 8.3 Повторный запуск без лишних изменений и откат
- **`nginx-apply.py`.** `app_api(s)` удаляет прежний блок любой версии `vN` и вставляет текущий; `snippet()` = `app_api(tghook(snippet_auth(s)))` (`nginx-apply.py:100-101`).
  - Повторный запуск пишет «уже настроен» (`:155-157`).
  - Если `nginx -t` не прошёл, копии `.bak-auth-*` возвращаются сами (`:162-167`).
  - Сниппет с токеном в журнал не выводится (`:6`).
- **`deploy-server.yml`:**
  - Checks (37-41): `php -l` уже проверит новые файлы; добавить `bash server/auth/tests/app-test.sh` (php-cli и php-sqlite3).
  - Install (52-84): `install $D/auth/*.php` (57) возьмёт новые PHP-файлы сам; установить фильтр fail2ban и добавить `app_password` в site.json (61).
  - nginx (86-96): `fsr-limits.conf` устанавливается до `nginx-apply` (91-92).
  - Бот (98-110): `setMyCommands` возьмёт `/apps`.
  - Verify (112-123) — §10.2.
- **Порядок:**
  1. Deploy server: веб не меняется.
  2. Verify.
  3. Правка веба (список устройств) через deploy-web.
  4. Сборка приложения.
- **Откат:**
  - копии `snippets/fspirat-router.conf.bak-auth-<время>`;
  - быстрый рубильник через ops: `touch /var/lib/fspirat-router-auth/app_disabled`;
  - отозвать все токены: `UPDATE app_devices SET revoked=…, revoked_by='ops' WHERE revoked IS NULL`.

### 8.4 fail2ban
- **Jail `[fspirat-router-app]`:** `logpath = /var/log/fspirat-router-auth.log`, maxretry 10, findtime 10m, bantime 15m (решение владельца 13.10.2026; в спецификации было 1h).
- **Фильтр:** `failregex = ^(?:\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)?\s*APP_(?:BADTOKEN|DENIED|URLTOKEN) ip=<HOST>` — дата необязательная: fail2ban вырезает её из строки до сравнения, и `^\S+ \S+ …` не совпало бы ни с чем.
- **Ошибки пароля** из приложения попадают в существующий jail `fspirat-router-auth`. **(исправлено при ревью 13.10.2026)** Его фильтр `^\S+ \S+ (FAIL|LOCKED)` по той же причине не совпадал ни с одной строкой — jail не банил никого, ни для веба, ни для приложения. Теперь `^(?:<дата>)?\s*(?:FAIL|LOCKED) ip=<HOST>`, и бан начинает работать по-настоящему (риск §5 п.32: maxretry/bantime — вопрос владельцу).
- **Verify** шлёт только запросы без токена: `token_missing` в fail2ban не считается, `ignoreself` включён.
- **(новое) Чем опасен бан.** Оба jail-а банят `port = http,https`, а 443 общий с Xray своего NL-сервера (§5 п.32). Поэтому бан домашнего IP провайдера на час лишает дом своего NL. Что смягчает:
  - отозванные и истёкшие токены не считаются (§7.4);
  - строки токенов не удаляются раньше срока (§7.3);
  - неверное число не ставит общий замок (§7.2).

  Сузить порт бана до одних сайтов нельзя: SNI-разбор идёт после TCP. Вопрос владельцу — не менять ли bantime.

### 8.5 Проверить на сервере до кода (через ops, только чтение, без вывода секретов)
1. `grep -E 'request_terminate_timeout|max_execution_time|pm.max_children' /etc/php/8.5/fpm/pool.d/www.conf /etc/php/8.5/fpm/php.ini`.
   - Задачам нужно не меньше 120 с.
   - `pm.max_children` нужно знать (§11, риск 3).
2. `router.token` совпадает со сниппетом: `cmp -s <(grep -o 'fspirat_token=[A-Za-z0-9]*' /etc/nginx/snippets/fspirat-router.conf | head -1 | cut -d= -f2) /var/lib/fspirat-router-auth/router.token && echo same`.
3. `php -m | grep -i sqlite` на сервере и в CI.
4. В Cloudflare для `fspirat.xyz` включён режим «DNS only».
5. В `telegram.json` `chat` — личный чат владельца (положительное число).
6. Часовой пояс сервера: `timedatectl | grep 'Time zone'` — для границы суток трафика (§5 п.30).
7. realip действует: `nginx -T 2>/dev/null | grep -E 'real_ip_header|set_real_ip_from|proxy_protocol'` (без вывода сниппета с токеном — фильтр только по этим словам).
8. Роутер, только чтение и с разрешения владельца:
   - `uci show uhttpd` (max_requests, script_timeout);
   - формат `network.lan.ipaddr`;
   - есть ли домен панели в MyDirect;
   - `grep -n 'passwall2.*restart' /usr/share/passwall2/subscribe.lua` — для §5 п.31.

---

## 9. iOS-клиент и сборка

### 9.1 Устройство приложения
- **Требования:** SwiftUI, iOS 17+, только iPhone (`TARGETED_DEVICE_FAMILY=1`), русский интерфейс, без сторонних зависимостей в приложении. XcodeGen — только инструмент сборки, в приложение не входит.
- **Структура папок:**
  - `ios/project.yml` — XcodeGen, `.xcodeproj` в `.gitignore`;
  - `ios/Router/` — интерфейс;
  - `ios/RouterCore/` — Swift-пакет: модели Codable, разбор, правила итоговой карточки, форматирование. Его тесты можно гонять на Linux.
- **Сеть.**
  - `URLSessionConfiguration.ephemeral`: `httpShouldSetCookies=false`, `urlCache=nil`.
  - Только `https://fspirat.xyz/router/app/v1/`, ATS по умолчанию, пиннинга нет (Let's Encrypt меняет ключи).
  - Базовый адрес — одна настройка сборки `APP_BASE_URL` в Info.plist (не секрет). Домен только что сменили (12.10.2026); при новой смене нужна новая сборка.
  - Таймауты: обычные запросы — 15 с, `status` — 20 с; ping и speedtest работают как задачи с опросом раз в 3 с.
- **Хранение.**
  - Токен — Keychain, `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - Пароль нигде не хранится.
  - Кэша на диске нет, данные только в памяти.
- **Защита экрана.**
  - `LAContext` `.deviceOwnerAuthentication` — при запуске и после фона (сразу / 1 / 5 мин) и для критичных действий. `NSFaceIDUsageDescription`.
  - В переключателе приложений — заглушка вместо экрана.
- **Состояние.** Один `@Observable RouterStore`.
  - На каждый вид запроса — один поток, без параллельных повторов.
  - Опрос идёт, пока экран виден (`.task` и `scenePhase`): status 30 с, net 3 с (только при видимой карточке), data 60 с, zapret 30 с (3 с при busy/checking, но не дольше 2 мин), tgws 60 с, led 300 с.
  - В фоне (`scenePhase != .active`) все таймеры остановлены; фоновых задач (BGTaskScheduler) нет.
  - `.refreshable` только перечитывает данные.
- **Тихие окна:** switch и restart — 15 с, direct / MyDirect / svcdirect — 12 с, zapretset — 15 с, reboot — 150 с. В это время кнопки класса PW отключены.
- **Офлайн:** 502 или 504 на status вне тихого окна. Все кнопки, которые идут к роутеру, отключены; данные сервера и `/vds` остаются видны.
- **Ошибки:**
  - 401 → экран входа, опрос прекращается;
  - 409 → «Это уже выполняется», у zapretset — «повтори через несколько секунд»;
  - 429 → «подожди», с `retry_after`;
  - 502 / 504 → «роутер не на связи», но у задачи ping 504 значит «долго»;
  - 400 → словарь ERR;
  - 500 `no rule` → «В PassWall нет правила MyDirect — проверь в LuCI»;
  - 500 `subscribe.lua not found` → «нет модуля подписок»;
  - 503 `not installed` → «компонент не установлен».
- **Время.** Расписание и «сейчас на роутере» показываются в `Europe/Samara` явно.
- **Отклик и доступность.** `.sensoryFeedback` на успех и ошибку. Уровни в журнале обозначены цветом **и** словом — для VoiceOver.

### 9.2 Экраны
Экраны описаны в отчёте владельцу, §2. Источники данных: `status`, `data`, `zapret`, `tgws`, `led`, `mydirect`, `vds`, `devices`. Правила итоговой карточки — §4.5. Проверка «через VPN 204» — `ping.real`/`ping.socks` (§3.1).

### 9.3 Стиль
- **Цвета** — динамические `Color(light:dark:)` по токенам из §4.7. Тема хранится в `@AppStorage("theme")` и применяется через `.preferredColorScheme`.
- **Шрифты** — Inter и JetBrains Mono TTF через `Font.custom(…, relativeTo:)`, с запасными SF Pro и SF Mono. Вес 650 заменяется на SemiBold.
- **Компоненты:** карточки 14 / `card` / рамка; плитки 10 / `surface`.
- **Графики** — Swift Charts: `LineMark` + `AreaMark`, `RuleMark` для сбоев, `RectangleMark` для «не на связи».
- **Пустые состояния** — `ContentUnavailableView`.

### 9.4 Lucide → SF Symbols
`router` → `wifi.router`; `wifi`/`wifi-off` → `wifi`/`wifi.slash`; `server` → `server.rack`; `activity` → `waveform.path.ecg`; `monitor-smartphone` → `macbook.and.iphone`; `shield-check` → `checkmark.shield`; `scroll-text` → `scroll`; `settings` → `gearshape`; `sun`/`moon`/`sun-moon` → `sun.max`/`moon`/`circle.lefthalf.filled`; `refresh-cw`/`rotate-ccw` → `arrow.clockwise`/`arrow.counterclockwise`; `power` → `power`; `lock-keyhole` → `lock`; `lightbulb`/`-off` → `lightbulb`/`lightbulb.slash`; `gauge` → `gauge.with.dots.needle.67percent`; `cpu`/`memory-stick`/`hard-drive` → `cpu`/`memorychip`/`internaldrive`; `thermometer` → `thermometer.medium`; `clock`/`timer` → `clock`/`timer`; `globe` → `globe`; стрелки → `arrow.down`/`arrow.up`/`arrow.right`; `log-out` → `rectangle.portrait.and.arrow.right`; `search` → `magnifyingglass`; `check`/`x`/`plus` → `checkmark`/`xmark`/`plus`; `pencil`/`ellipsis` → `pencil`/`ellipsis.circle`; `ban` → `nosign`; `box` → `cube`; `zap` → `bolt`; `circle-check`/`circle-alert` → `checkmark.circle.fill`/`exclamationmark.circle.fill`; `cable` → `cable.connector`; `trash-2`/`link` → `trash`/`link`; `rss` → `dot.radiowaves.up.forward`.

Дополнительно:
- уровни пинга — `cellularbars` с `variableValue`;
- сигнал Wi-Fi — `wifi` с `variableValue`;
- Обход/MyDirect — `arrow.triangle.branch`, расписание — `calendar.badge.clock`, Face ID — `faceid`.

**Значки брендов.** В SF Symbols их нет. Замены: `play.rectangle` (YouTube), `bubble.left.and.bubble.right` (Discord), `paperplane` (Telegram), `camera` (Instagram). Либо 4 SVG Lucide (ISC) как шаблонные изображения.

### 9.5 Сборка: `.github/workflows/ios-testflight.yml` (рекомендуемый вариант)
- **Запуск:**
  - `workflow_dispatch`;
  - `schedule` раз в 2 месяца (например, `0 3 1 */2 *`) — сборка TestFlight обновляется сама до истечения 90 дней, около 60–120 минут квоты за раз;
  - push в `ios/**` в main — по желанию: каждая сборка стоит 60–120 минут квоты, поэтому по умолчанию выключен.
- **Защита:** `permissions: contents: read`, `concurrency: ios-testflight`, `timeout-minutes: 40`.
- **Раннер:** `macos-26` (дату выхода в GA и путь к Xcode проверить по документации GitHub на момент этапа 3), Xcode закреплён через `xcode-select`.
- **Шаги:**
  1. `.p8` → `$RUNNER_TEMP` (600), удаляется в шаге `always()`.
  2. XcodeGen закреплённой версии с проверкой SHA-256.
  3. `xcodebuild archive -scheme Router -destination 'generic/platform=iOS' -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID … DEVELOPMENT_TEAM=$APPLE_TEAM_ID CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`.
  4. `xcodebuild -exportArchive` с `ExportOptions.plist`: `method=app-store-connect`, `destination=upload`, `signingStyle=automatic`, `teamID`.
- **Сертификат.** Облачный сертификат распространения выпускает и хранит Apple. `.p12` и профилей в репозитории и в Secrets нет.
- **Info.plist:** `ITSAppUsesNonExemptEncryption=NO`, `CFBundleDisplayName=Роутер`, `APP_BASE_URL`, дата сборки (для напоминания о 90 днях).
- **Секреты:** `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.
- **Роль ключа API:** вероятно, нужна Admin (облачная подпись) — проверить на первом запуске.
- **Тесты RouterCore** — `swift test` на `ubuntu-latest` (множитель ×1). Есть ли там Swift, проверить.
- **Требование Apple** (по проекту экранов, проверить): с 28.04.2026 загрузка только из Xcode 26+ с iOS 26 SDK. Минимальная iOS приложения остаётся 17.
- **Минуты и деньги.**
  - Множитель macOS ×10 для приватных репозиториев. На текущей странице GitHub о множителях, по данным проекта экранов, больше не пишут — проверить в Billing.
  - Цена сверх квоты — примерно $0,06–0,08 за минуту.
  - Для варианта 2б (свой раннер на MacBook): GitHub объявлял поминутную плату за свои раннеры в приватных репозиториях и откладывал её — проверить в Billing.
- **TestFlight:** до 100 внутренних тестировщиков, сборка действует 90 дней, проверка Apple для внутренней группы не нужна. После первой загрузки владелец один раз создаёт группу Internal Testing и добавляет себя.
- **Вариант 2 (Xcode на MacBook).**
  - Свободно 238 ГБ, места хватит.
  - Согласовать с сессией homeserver.
  - `xcodebuild` по SSH возможен, но подпись требует разблокированной связки ключей пользователя, то есть вход владельца в macOS.

### 9.6 Bundle ID и App Store Connect
- **Bundle ID:** `xyz.fspirat.router` (Explicit). После первой загрузки его не поменять.
- **На будущее:** виджет `xyz.fspirat.router.widget`, App Group `group.xyz.fspirat.router`.
- **Capabilities** в v1 не нужны.
- **Запись в App Store Connect:** SKU `fspirat-router-ios`, основной язык русский, имя уникальное во всём App Store (например, «FSpirat Router»).
- **Где нажать** (для инструкции владельцу):
  - developer.apple.com → Account → Membership details (Team ID);
  - Certificates, Identifiers & Profiles → Identifiers → «+» → App IDs → App;
  - App Store Connect → Apps → «+» → New App;
  - Users and Access → Integrations → App Store Connect API → Team Keys → «+»;
  - GitHub → Settings → Secrets and variables → Actions → New repository secret;
  - App Store Connect → TestFlight → Internal Testing → «+».

---

## 10. План тестов

### 10.1 Сервер — `server/auth/tests/app-test.sh` (CI, без сети)
**Окружение:**
- временные `FSR_DIR`, `FSR_LOG`, `FSR_AUDIT`, `FSR_WATCH`, `FSR_HTPASSWD`, `FSR_ORIGIN`, `FSR_COOKIE_DOMAIN=""`;
- заглушка Telegram (`FSR_TG_API` → `php -S`);
- заглушка CGI (`FSR_ROUTER`): 200, 400, 409, пустое тело, сырой TAB, сон дольше таймаута, выключена;
- `app.php` и `tgbot.php` с заголовком секрета и `callback_query`.

| # | Проверка | Ожидание |
|---|---|---|
| T1 | Нет `Authorization` | 401 `token_missing`, `WWW-Authenticate`, нет `APP_BADTOKEN` |
| T2 | `Bearer abc`, `Basic …`, `Bearer fsr1_` + 43 случайных символа | 401 `token_invalid`, по одной строке `APP_BADTOKEN` на каждый |
| T3 | `expires = now−1`; `created = now−366 дн` | 401 `token_expired`, без `APP_BADTOKEN` |
| T4 | `seen = now−400 с` | `expires = min(now+90 дн, hard_expires)` |
| T5 | Отзыв: `/devices/revoke`, `/auth/logout`, `/devices/revoke-all`, кнопка `ar`, веб `op=apprevoke`, веб `logout.php all=1` | следующий запрос → 401 `token_revoked`; ушло сообщение в Telegram |
| T6 | `GET /me?x=fsr1_<настоящий>` и `GET /me?access_token=fsr1_<настоящий>` | 400 `token_in_url`; токен отозван (`url_leak`) в обоих случаях; `APP_URLTOKEN`; Telegram |
| T7 | Cookie `fsr_session` вместо Bearer | 401 `token_missing` |
| T8 | Токен + `Origin: https://evil.example` или `Sec-Fetch-Site: cross-site` | 403 `browser_request`, роутер не вызван |
| T9 | Вход: 3 разных числа, одно совпадает; нажатие → токен; повторный `poll` | 410; в базе только `sha256`; `APP_LOGIN`, `APP_OK` |
| T10 | Неверное число / «Это не я» / 120 с / чужой `message_id` / `from.id` ≠ владелец / `cancel` | 410 `login_denied` + `FAIL` для IP, общего замка нет / 410 `login_denied` + общий замок 1 ч + TG с советом сменить пароль / 410 `login_expired` / нажатие игнорируется / игнорируется / `cancelled` |
| T11 | 5 неверных паролей | 6-я попытка → 429 `locked`; `login.php` с того же IP тоже закрыт |
| T12 | 3-й одновременный вход / 6-й за час / нет `telegram.json` | 429 `busy` / 429 `rate_limited` / 503 `tg_unavailable` |
| T13 | `reboot` без `confirm` | 428, роутер не вызван |
| T14 | Повторный `confirm` / с другого устройства / другой `id` у switch / через 61 с | 400 `confirm_invalid` или 428; роутер не вызван |
| T15 | Правильный `confirm` | CGI вызван ровно 1 раз; аудит `APP reboot → 200`; Telegram |
| T16 | 2 ping за 30 с; 4-й reboot за час; switch через 5 с после restart | 429 + `Retry-After` |
| T17 | Два действия параллельно (CGI спит 3 с); две долгие задачи | 200 и 409 `busy` |
| T18 | Параметры: `mac` с заглавными или `%3A`; `id=_direct`; `sid=a/b`; subupdate без `sid` и без `all`; лишнее поле; `?foo=1`; `direct` без `on` | 400, вызовов CGI 0 |
| T19 | dirdel домена не из `added` | 400, CGI-действие не вызвано |
| T20 | subadd / subdel / settargets | 404 `not_in_v1` |
| T21 | Роутер выключен / дольше таймаута / 403 forbidden / битый JSON status (управляющий символ) | 502 `router_offline` / 504 `router_timeout` / 500 `router_token` + одно сообщение / исправлено или 502 `router_bad_reply`; `/data` при этом → 200 |
| T22 | Задачи ping и speedtest | 202 → `running` → `done`; чужое устройство → 404 |
| T23 | pingone `{id}` | CGI через GET, 200; лимит 20 в мин |
| T24 | `/vds` | только разрешённые поля, нет хостов и IP серверов |
| T25 | Секреты в журналах | `grep -E 'fsr1_\|<тестовый токен роутера>\|<тестовый пароль>'` по журналам → пусто |
| T26 | **Веб-CSRF не изменился** (`docs/audit-2026-10.md:98-100`) | GET без токена → 204; POST с токеном и Origin → 204; `X-FSR: 1` → 403; чужой Origin → 403; без Origin → 403; без сессии → 401; `op=apprevoke` без токена → 403 |
| T27 | Строки `APP_*` и сторож | разбираются `read -r d t what ipkv` (`fspirat-watch:38`) без лишних сообщений; фильтр `fspirat-router-auth` их не ловит |
| T28 | Rotate router token (сухой прогон на заглушках) | `router.token` обновлён; при откате возвращён прежний |

**Сверх таблицы (ревью 13.10.2026):** T2 — «bearer»/«BEARER» с настоящим ключом → 401 `token_invalid`; T11 — 12 неверных паролей параллельно с одного IP (приложение и `login.php`) → ровно 5 попыток; T16, T21, T22 — отказ CGI, закрытый порт туннеля, `router_token` не идут в лимиты; T17 — места для вызова роутера (третий ждёт до 4 с, потом `429 busy`); T21 — «роутер молчит»: после 504 следующие запросы → 502 сразу, роутер не вызван; T19 — mydirect + dirdel в общем сроке запроса (`FSR_APP_BUDGET`); T28 — `router.token` новый уже на проверке нового токена.
| T29 | Чистка: отозванный токен после 100 запросов | строка осталась; ответ `token_revoked`, не `token_invalid`; `APP_BADTOKEN` нет |

### 10.2 Verify в `deploy-server.yml` (без токенов и секретов)
1. `/router/app/v1/me` → 401.
2. `…/me?access_token=x` → 400 `token_in_url` (ответ PHP).
3. `Origin: https://evil.example` → 403.
4. `X-FSR: 1` + `Bearer fsr1_xxx…` на `/router/api?action=net` → 401: Bearer не открывает веб-API.
5. Старые проверки не меняются (`deploy-server.yml:115-122`).
6. 60 быстрых запросов без токена → часть ответов 429 с JSON; `fail2ban-client status fspirat-router-app` → jail активен.
7. Второй запуск `nginx-apply.py` → «уже настроен».

### 10.3 Приложение
**Модульные тесты RouterCore на Linux:**
- разбор образцов status: обычный; после перезагрузки (`null` и пустые поля); `subs: null` и `[]`; `_direct`; `split_active=false`; узел с `ms = 0`; `temp: null`; `ping.socks=false`;
- `/data` day, week, month;
- zapret `absent`, `installed=false`, `check {"error":"xray"}`; tgws `absent`; led `absent`;
- соответствие кодов ошибок текстам;
- правила итога (§4.5); форматирование (§4.6); уровни пинга и сигнала; «скрытый MAC»;
- окно расписания в `Europe/Samara`, включая переход через полночь;
- условие окна у «Проверить» (`ping.socks && ping.real == 0`).

**Ручная проверка на iPhone (этапы 3–5):**
- вход, отмена, «Это не я»;
- Face ID и блокировка после фона; заглушка в переключателе приложений;
- в фоне нет запросов (по журналу nginx);
- отзыв из веба и из бота → экран входа;
- «Выйти везде»;
- режим «не на связи» — без настоящего отключения, по заглушке в тестовой сборке;
- безопасные действия: подсветка, pingone, тест скорости, проверка zapret;
- опасные действия — один раз, вместе с владельцем и с его согласия;
- тёмная и светлая тема, крупный шрифт, VoiceOver на Сводке.

---

## 11. Риски
1. **Обход nginx и check.php прямым вызовом CGI.** Аудит, Telegram и лимиты нужно повторить в `app.php`. Закрыто спецификацией и тестами T13–T17 и T25.
2. **Наложение действий на роутере.** Замка на перезапуски PassWall на роутере нет. Замок приложения не видит веб и бота. Смягчение — общая пауза PW, тихие окна, действия по одному.
3. **php-fpm и uhttpd.**
   - Долгие задачи (до 90 с) и бот занимают воркеры php-fpm. Если `pm.max_children` мал, встанут `auth_request` веба. Смягчение — одна долгая задача сразу, проверить `pm.max_children`.
   - **(ревью 13.10.2026)** Короткие вызовы тоже: чтение ждёт роутер до 5–20 с, действие до 25 с, а «висящий» туннель (дом без интернета, sshd ещё держит 8081) держит воркер до таймаута. На сервере `pm.max_children = 5` (проверено 13.10.2026), пул общий с check.php, входом, ботом и fspirat.ru. Смягчение в app.php — места (не больше 2 вызовов роутера сразу), «роутер молчит» на 30 с и общий срок запроса (§7.11). Роутер ждут не больше 3 воркеров приложения (2 места + задача), остальные его запросы держат воркер не дольше 4 с. Verify печатает `pm`/`pm.max_children`. Надёжнее — свой пул php-fpm для app.php (свой сокет в блоке nginx) — не в v1.
   - uhttpd по умолчанию (не проверено) — 3 параллельных CGI и 60 с.
4. **Вход зависит от Telegram.** Если бот не работает, новых входов нет (у веба для новых браузеров тоже, §5 п.34). Выданные токены продолжают работать.
5. **Блокировки по IP.**
   - Домена панели нет в `router/passwall/mydirect-domains.txt`. Значит, iPhone в домашнем Wi-Fi приходит на сервер с IP выхода VPN — общего у подписки или самого NL-сервера, если выбран свой узел.
   - Мобильный интернет — CGNAT.
   - Чужие ошибки с того же IP могут закрыть вход и вебу, и приложению. fail2ban с `ignoreself` сам сервер не банит.
   - Лимит по токену частично снимает проблему для nginx, но не для блокировки подбора.
6. **Cloudflare и realip.** В режиме прокси (оранжевое облако) `REMOTE_ADDR` станет адресом Cloudflare. Без `proxy_protocol`/realip — 127.0.0.1 у всех. В обоих случаях блокировки и fail2ban сломаются (§8.5 пп. 4, 7).
7. **Кража токена с телефона.** Keychain с `ThisDeviceOnly`. Face ID работает только на уровне приложения: при скомпрометированном телефоне токен можно использовать и без биометрии. Защита 2b — Secure Enclave. Ответ на потерю телефона — отзыв из веба или бота.
8. **Ключ App Store Connect с ролью Admin в Secrets GitHub.** Ключ даёт широкие права в аккаунте Apple. Смягчение: 2FA в GitHub, запуск только из main и вручную или по расписанию, отзыв ключа в один клик, `*.p8` в `.gitignore`.
9. **Сборка и выкладка.**
   - Минуты macOS ×10, сборка живёт 90 дней, требования Apple к SDK меняются.
   - Bundle ID не поменять.
   - Смягчение: лимит расходов $0, автопересборка по расписанию, напоминание в приложении, варианты 2б и 3 в запасе.
10. **Дефекты CGI** (§5). Сервер проверяет параметры строго и обходит их сам; править роутер в v1 не планируется.
11. **Ротация токена роутера** ломает бота и приложение, пока не исправлен workflow (§1.7).
12. **Хрупкий JSON status** (имена узлов, неатомарная запись). Приложение должно переживать редкий `502 router_bad_reply` и повторять запрос.
13. **Время и пояса.** Расписание и строки журнала — во времени роутера (+04). Трафик «за сегодня» — по суткам сервера (§5 п.30). Приложение показывает это явно.
14. **Приватность.** IP, MAC и имена устройств — только в памяти телефона, снимок экрана скрыт.
15. **(новое) Бан fail2ban отрезает свой NL-VPN** (§5 п.32, §8.4). Приложение не должно добавлять ложных срабатываний.
16. **(новое) Смена домена.** Адрес API зашит в сборку; при смене домена нужна новая сборка (`APP_BASE_URL`, §9.1).
17. **(новое) Сверка числа — новый код в боте.** Готового образца в этом репозитории нет; ошибки в `on_button()` могут задеть существующие кнопки бота. Смягчение — разбор кнопок входа до общего правила и тесты T9–T10.

## 12. Открытые вопросы
1. Способ входа: (б′), (а) с кодом или (б) без пароля (`APP_LOGIN_PASSWORD=0`).
2. «Выйти на всех устройствах» в вебе отзывает и токены приложения? Сбрасывать ли запомненные браузеры (`devices`)?
3. Слать ли в Telegram ещё `direct`, `zapretset`, `schedule`? Карта общая — изменится и веб.
4. Этап 2b — Face ID, который проверяет сервер (Secure Enclave)?
5. LuCI: ссылка в Safari (рекомендация) или убрать.
6. v1.1: subadd, subdel, settargets в приложении?
7. Карточка VDS (`/vds`) в v1?
8. Поведение роутера — проверить через ops, только чтение и с разрешения:
   - uhttpd: max_requests, script_timeout;
   - перезапускает ли `subscribe.lua start … manual` PassWall сам (§5 п.31);
   - прерывает ли uhttpd CGI при обрыве клиента;
   - формат `network.lan.ipaddr`;
   - есть ли `/sys/class/thermal/thermal_zone0/temp` (температура).
9. Исправлять ли дефекты CGI на роутере отдельным этапом (с `deploy-router` и разрешения владельца) или только обходить на сервере:
   - битый JSON у settargets;
   - кривой sid у subupdate;
   - регулярное выражение в diradd и dirdel;
   - `sub.json` после subdel;
   - `running`;
   - зависший `checking`;
   - `sblocked` после unblock;
   - экранирование в ping.json.
10. Показывать ли скрытые узлы (Hysteria2, «LTE / Россия / Обход»)? Рекомендация — нет.
11. Пересчитывать ли время роутера (+04) в пояс телефона? Рекомендация — показывать время роутера с явной подписью.
12. Сборка:
    - тариф GitHub и подтверждение множителя ×10;
    - Swift на `ubuntu-latest`;
    - путь к Xcode на `macos-26`;
    - роль ключа API;
    - автопересборка раз в 2 месяца — да или нет;
    - для вариантов 2 и 2б — версия macOS и процессор MacBook (спросить у сессии homeserver).
13. Модель iPhone и версия iOS владельца (нужна 17+).
14. Шрифты: класть Inter и JetBrains Mono (OFL) в приложение (рекомендация) или обойтись SF Pro и SF Mono.
15. Первая установка на iPhone уже на этапе 3 (рекомендация) или, как в задании, на этапе 5?
16. Часовой пояс сервера и единая граница суток трафика (§5 п.30): считать «сегодня» по Москве, Самаре (время роутера) или UTC? Рекомендация — по Самаре, как всё остальное на роутере.
17. bantime у jail-ов при общем 443 с Xray (§8.4): оставить 1 ч или сократить?
18. Устройство сверки числа у сессии homeserver (панель `/vds/`): запросить описание, чтобы кнопки и тексты были одинаковыми?
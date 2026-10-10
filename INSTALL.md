# Установка у себя

Панель «Router AX3000T» можно развернуть на своём роутере и своём сервере из форка этого репозитория.
Адреса вашей установки задаются в одном файле `deploy.conf`; секреты (ключи SSH, адрес сервера, токен бота)
в репозиторий не попадают — они лежат в секретах GitHub и на самих устройствах.

## Что понадобится

| Где | Что |
|---|---|
| Роутер | OpenWrt 23+ (проверено на 25.12.5, Xiaomi AX3000T) с PassWall 2 и Xray; `curl`, `lua`, `tcping`, nftables (fw4), dropbear `dbclient` |
| Сервер | Ubuntu 24.04 с публичным IP: nginx, PHP 8.1+ (php-fpm), certbot, `jq`, cron, fail2ban |
| Домен | домен панели (`PANEL_DOMAIN`) и поддомен для LuCI (`LUCI_DOMAIN`), оба — A-записью на сервер |
| Telegram | бот от @BotFather (коды входа, уведомления, команды) и ваш chat_id |
| VPN | подписка (одна или несколько) для PassWall 2 — добавляется уже из панели |

Как это связано: роутер держит обратный SSH-туннель до сервера (`fstunnel`). По нему nginx на сервере ходит в CGI
роутера (панель), в LuCI и по SSH (выкладка скриптов). Вход в панель — страница входа на сервере с кодом из Telegram.

## 1. Форк и настройки

1. Сделайте форк (лучше приватный).
2. Адреса установки — файл `deploy.conf`:

   ```sh
   PANEL_DOMAIN=example.org         # панель будет на https://example.org/router/
   LUCI_DOMAIN=luci.example.org     # LuCI через сервер; поддомен PANEL_DOMAIN — тогда вход общий
   TG_BOT=YourRouterBot             # имя вашего бота без @
   ```

   Можно поменять значения прямо в `deploy.conf` форка — или, чтобы адреса не лежали в git, положить такой же файл
   на сервер в `/etc/fspirat-router/deploy.conf` (он главнее). Значения подставляются при выкладке сервера,
   а страница панели берёт их с сервера сама.
3. В **Settings → Secrets and variables → Actions** добавьте секреты:

   | Секрет | Что |
   |---|---|
   | `SSH_HOST` | IP или имя сервера |
   | `OPS_SSH_KEY` | закрытый ключ root на сервере (base64 одной строкой: `base64 -w0 key`) |
   | `SSH_KEY` | закрытый ключ пользователя `deploy` для выкладки страницы (base64) |

   Проверка: **Actions → Server ops → Run workflow** с пустой командой — он покажет, какие ключи подходят.

## 2. Сервер

1. Сайт `PANEL_DOMAIN` в nginx с сертификатом (`certbot --nginx -d example.org`). В блок `listen 443` добавьте
   `include snippets/fspirat-router.conf;`, сам файл возьмите из `server/nginx/snippets/fspirat-router.conf.example`
   и впишите токен (п. 3.3).
2. LuCI: `server/nginx/sites-available/luci.example.org` → `/etc/nginx/sites-available/<LUCI_DOMAIN>`,
   замените в нём `server_name` на свой, включите сайт и выпустите сертификат.
3. Пароль панели: `htpasswd -c /etc/nginx/.htpasswd_router bob` (логин `bob` задан в `server/auth/lib.php`).
4. Бот: `/etc/fspirat-watch.conf` по образцу `server/fspirat-watch.conf.example` (`TG_TOKEN`, `TG_CHAT`), `chmod 600`.
5. Пользователь туннеля: `useradd -m -s /usr/sbin/nologin tunnel`, ключ роутера (п. 3.2) — в
   `/home/tunnel/.ssh/authorized_keys` с ограничениями:
   `restrict,port-forwarding,permitlisten="127.0.0.1:8081",permitlisten="127.0.0.1:8022",command="/bin/false" ssh-ed25519 …`
6. Ключ сервера для доступа к роутеру: `ssh-keygen -t ed25519 -f /root/.ssh/router_key` (открытая часть — на роутер, п. 3.2).
7. Пользователь `deploy` для выкладки страницы (папка `/var/www/<PANEL_DOMAIN>/router/`), его ключ — в секрет `SSH_KEY`.
   Потом **Restrict deploy key** ограничит этот ключ только выкладкой.
8. **Actions → Deploy server** (галочка nginx включена): страница входа, бот, наблюдатель, fail2ban;
   nginx переключается на свою страницу входа с копией и откатом при ошибке.

## 3. Роутер

1. PassWall 2 с Xray. Сделайте узел **Split** (тип «Shunt»): правила RU и MyDirect → «Direct», остальное → любой сервер.
   В **Basic Settings → Node** выберите Split — панель найдёт его сама.
2. Ключи: `dropbearkey -t ed25519 -f /root/.ssh/tunnel_key` — открытую часть на сервер (п. 2.5);
   открытый `router_key` сервера — в `/etc/dropbear/authorized_keys`.
3. Токен CGI: `head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9 > /etc/fspirat.token` — тот же токен впишите
   в `fspirat-router.conf` на сервере (п. 2.1). Сменить потом: **Rotate router token**.
4. Туннель: `mkdir -p /etc/fspirat && echo TUNNEL_HOST=адрес_сервера >> /etc/fspirat/config`, скопируйте `router/etc/init.d/fstunnel`
   в `/etc/init.d/fstunnel` и включите: `/etc/init.d/fstunnel enable && /etc/init.d/fstunnel start`.
   IP роутера туннель берёт из настроек LAN.
5. Когда туннель поднялся (на сервере слушают `127.0.0.1:8081` и `127.0.0.1:8022`), запустите **Actions → Deploy router**:
   скрипты, CGI и задачи cron попадут на роутер.

## 4. Первый вход

Откройте `https://<PANEL_DOMAIN>/router/` и войдите паролем и кодом из Telegram.

1. **VPN → Подписки → Добавить** — ссылка вашей подписки (галочка HWID включена: большинство подписок без неё
   не отдают серверы). Через минуту серверы появятся в таблице.
2. **VPN → Серверы → Сервисы** — что мерить через каждый сервер. По умолчанию YouTube, Discord и Telegram;
   можно добавить свои сайты и Minecraft-серверы (до 8).
3. **Сеть → Напрямую (MyDirect)** — сайты, которые должны открываться без VPN.

По желанию: **Zapret install** (YouTube и Discord напрямую через провайдера), **TG WS Proxy install**
(Telegram через Cloudflare мимо VPN) — оба включаются переключателями в панели; **Router backup** — архив настроек
роутера перед большими изменениями.

## Настройки роутера (`/etc/fspirat/config`)

Файл читают скрипты панели и туннель (`sh`, строки `ИМЯ=значение`); обязателен только `TUNNEL_HOST`:

| Имя | По умолчанию | Что |
|---|---|---|
| `TUNNEL_HOST` | — (обязательно) | адрес сервера для туннеля `fstunnel` (пользователь `tunnel`) |
| `LAN_IP` | IP из настроек LAN | адрес роутера, на который туннель ведёт LuCI и SSH |
| `SHUNT` | узел, выбранный в Basic Settings → Node (если это Shunt), иначе первый Shunt | узел Split, у которого панель меняет сервер |
| `EXCLUDE` | `LTE\|Россия\|Обход` | серверы с этими словами в названии не пингуются и не выбираются автоматически |

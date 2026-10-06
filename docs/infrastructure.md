# Инфраструктура FSPIRAT

Состояние на 06.10.2026. Пароли, UUID, ключи и токены здесь намеренно не записаны.

## 1. Домены

- `fspirat.ru` и `fspirat.online` куплены на Reg.ru (регистратор), хостинг Reg.ru больше не используется.
- **DNS обоих доменов обслуживает Cloudflare** (NS: laila / carter .ns.cloudflare.com).
  - `A fspirat.ru → 193.39.143.202`, `A www.fspirat.ru → 193.39.143.202` (DNS only) — с 06.10.2026.
  Записи меняются в панели Cloudflare, не в ispmanager Reg.ru.
  - `A fspirat.online → 193.39.143.202`
  - `A www.fspirat.online → 193.39.143.202`
  - `A router.fspirat.online → 193.39.143.202` (DNS only, серое облако)
- Хостинг Reg.ru Host-0 больше не нужен: fspirat.ru перенесён на VPS 06.10.2026, почта не используется.
  Его можно отключить (домены продлевать отдельно — они остаются у Reg.ru как у регистратора).

## 2. Сайт fspirat.online (основной, другой репозиторий)

- Репозиторий `fspirat/project_hex`, папка `sites/fspirat.ru/`:
  `/` главная, `/hex_generator/` HEX-генератор, `/fstweak/` страница мода FSTWEAK.
- Стиль: фон `#050605`, зелёные `#7fbf3a` / `#9be052`, пиксельные панели, Minecraft-шрифт.
- Выкладка: GitHub Actions `deploy.yml`, rsync `./sites/fspirat.ru/` → `/var/www/fspirat.online/`
  пользователем `deploy` (с `--exclude '/router/'`). Секреты `SSH_KEY` (base64 одной строкой), `SSH_HOST`.
- Эту же папку отдают оба домена: `fspirat.online` и `fspirat.ru` (nginx `sites-available/fspirat.ru`,
  без `/router/`). FTP-выкладки на Reg.ru больше нет.
- **Страница `/router/` теперь живёт в этом репозитории (fspirat-router)** — см. TODO в CLAUDE.md
  про `--exclude 'router/'` в project_hex.

## 3. Мод FSTWEAK (Fabric, клиентский) — репозиторий project_hex

- Minecraft 1.21.11, 26.1.2, 26.2. Кнопка ✦ над инвентарём / клавиша H открывает HEX GENERATOR.
- Сборка GitHub Actions, .jar в Releases.

## 4. Сервер NL (Aeza, NLs-1) — 193.39.143.202, Ubuntu 24.04

Вход: `ssh root@193.39.143.202` (hostname `occasional-coffe`).

| Порт | Что |
|---|---|
| 22 | SSH (fail2ban) |
| 80/443 | nginx: fspirat.online, fspirat.ru, router.fspirat.online (Let's Encrypt, автопродление certbot) |
| 12849 | панель 3x-ui |
| 8443 | VLESS Reality (подключение "router", из РФ режется ТСПУ) |
| 127.0.0.1:8081 | конец SSH-туннеля от роутера → LuCI |

Файлы:
- `/etc/nginx/sites-available/fspirat.online` — сайт; в блоке `listen 443` строка
  `include snippets/fspirat-router.conf;`
- `/etc/nginx/snippets/fspirat-router.conf` — /router/ и /router/api (с токеном)
- `/etc/nginx/sites-available/router.fspirat.online` — LuCI через туннель
- `/etc/nginx/sites-available/fspirat.ru` — сайт fspirat.ru (копия в `server/nginx/`)
- `/etc/nginx/.htpasswd_router` — логин `bob` для /router/ и router.fspirat.online
- `/home/tunnel/.ssh/authorized_keys` — ключ туннеля с ограничениями:
  `restrict,port-forwarding,permitlisten="127.0.0.1:8081",command="/bin/false" ssh-ed25519 ... root@OpenWrt`
- `/usr/local/bin/fspirat-watch`, `/etc/fspirat-watch.conf`, `/etc/cron.d/fspirat-watch`,
  состояние в `/var/lib/fspirat/`
- `/etc/fail2ban/jail.d/fspirat.local` (+ jail 3x-ipl от 3x-ui, лог `/var/log/x-ui/3xipl.log`)

Полезное: `x-ui settings`, `x-ui restart`, `nginx -t && systemctl reload nginx`,
`certbot renew --dry-run`, `fail2ban-client status`, `fail2ban-client set nginx-http-auth unbanip IP`.

## 5. Сервер РФ (relay) — 195.209.220.83

- Вход: `ssh -i "$env:USERPROFILE\.ssh\privatekey-1140917.pem" ubuntu@195.209.220.83`, затем `sudo -i`.
- ufw: 22, 80, 443, 23847 (панель 3x-ui).
- Был план: роутер → РФ-сервер (VLESS Reality :443) → NL по VLESS WebSocket+TLS через
  `fspirat.online/ws-7f3k9`. **Не доделан и сейчас не используется** — роутер ходит через nosok.

## 6. Роутер Xiaomi AX3000T — 192.168.7.1

- Прошивка: официальный OpenWrt 25.12.5 (`xiaomi_mi-router-ax3000t`, не ubootmod),
  менеджер пакетов apk. Вход `ssh root@192.168.7.1` (после перепрошивки `ssh-keygen -R 192.168.7.1`).
- Wi-Fi: `bob_vless_2G`, `bob_vless_5G`, WPA2/WPA3, страна RU. WAN: DHCP.
- PassWall 2 26.10.1, Xray 26.9.30, Geoview 0.2.6, без sing-box (поэтому узлы Hysteria2 не работают).
  Обновить ядро: `apk update && apk add --upgrade xray-core`.

### PassWall 2

- Подписка **nosok** (`https://sub.nosok-top.com/...` — ссылка = личный доступ, не публиковать).
  User-Agent v2rayN, **Send HWID включён** (без него провайдер отдаёт заглушку).
- **Basic Settings → Node = Split** (`9DxG2j8l`). Main switch включён.
- **Split** (Xray, Shunt), Group `default`, Shunt Rule Group **RU**:
  - `MyDirect` → Direct Connection (список: `router/passwall/mydirect-domains.txt`)
  - `AI` → Close (Claude заработал и так; список `router/passwall/ai-domains.txt` на будущее)
  - `Russia_Block`, `Russia` → Close
  - По умолчанию → текущий сервер nosok (меняется скриптом/страницей)
  - Domain Strategy IPOnDemand, «Direct DNS result write to IPSet» **выключено**
    (с ним прямые сайты не открывались).
- `node_socks_port=1070` — SOCKS основного узла (используется для проверок).
- `localhost_proxy=0` — трафик самого роутера мимо VPN.
- Geo: Loyalsoldier geoip/geosite, `/usr/share/v2ray/`.

### Наши файлы на роутере

- `/usr/bin/fspirat-ping` + cron `*/5 * * * * /usr/bin/fspirat-ping`
- `/www/cgi-bin/fspirat`, `/etc/fspirat.token` (chmod 600)
- `/etc/init.d/fstunnel` (enabled), ключ `/root/.ssh/tunnel_key` (dropbearkey ed25519)
- `/tmp/fspirat/` — данные (стираются при перезагрузке)

## 7. Telegram

Бот **@FSRouter_bot** (FSTweak_router). Токен и chat id — только в `/etc/fspirat-watch.conf`.
Сообщения: роутер пропал/вернулся (3 минуты без ответа), VPN остановлен/запущен,
смена сервера (вручную/авто), флеш ≥ 90%.

## 8. Как восстановить с нуля (кратко)

1. Роутер: OpenWrt → PassWall 2 (`sh -c "$(wget -qO- https://raw.githubusercontent.com/enxy0/passwall2_install/main/passwall2.sh)" -- --no-sing-box`)
   → подписка nosok (HWID) → правила RU/MyDirect → узел Split → Node = Split → localhost_proxy 0.
2. Туннель: `dropbearkey -t ed25519 -f /root/.ssh/tunnel_key`, публичный ключ на сервер
   пользователю `tunnel` с ограничениями (см. п.4), `router/etc/init.d/fstunnel` → enable/start.
3. `echo` токен в `/etc/fspirat.token`, `bash scripts/deploy-router.sh`.
4. Сервер: nginx-конфиги из `server/nginx`, `htpasswd -c /etc/nginx/.htpasswd_router bob`,
   certbot для router.fspirat.online, `bash scripts/deploy-server.sh`, `/etc/fspirat-watch.conf`.

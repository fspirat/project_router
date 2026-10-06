# fspirat-router

Домашний роутер с VPN и панель управления к нему на **https://fspirat.online/router/**.

- **Роутер**: Xiaomi AX3000T, OpenWrt 25.12.5, PassWall 2 + Xray, подписка nosok.
  Свои сайты (банки, госуслуги, маркетплейсы и всё `.ru`) — напрямую, остальное — через VPN.
- **Сервер**: Aeza (Нидерланды), nginx, туннель до роутера, Telegram-уведомления, fail2ban.
- **Страница**: статус VPN, график связи за сутки, выбор сервера, автопереключение,
  тест скорости, ресурсы роутера, устройства, кнопки управления.

## Структура

```
web/                     страница fspirat.online/router/ (выкладывается GitHub Actions)
router/bin/              fspirat-ping — пинг серверов, настоящая проверка, автопереключение
router/www/cgi-bin/      fspirat — API страницы (CGI на роутере)
router/etc/init.d/       fstunnel — SSH-туннель роутер → сервер
router/passwall/         списки доменов для правил PassWall (MyDirect, AI)
server/                  fspirat-watch (Telegram), nginx, fail2ban, cron
scripts/                 deploy-router.sh, deploy-server.sh, check.sh
docs/                    инфраструктура и история решений
CLAUDE.md                контекст для Claude Code
```

## Выкладка

- **Страница**: изменения в `web/` → push в `main` → GitHub Actions выложит сама.
  Нужны секреты репозитория `SSH_KEY` (приватный ключ пользователя `deploy`, одной строкой base64)
  и `SSH_HOST` = `193.39.143.202` — те же, что в `project_hex`.
- **Роутер** (из дома): `bash scripts/deploy-router.sh`
- **Сервер**: `bash scripts/deploy-server.sh`
- **Проверка**: `bash scripts/check.sh`

Чтобы скрипты не спрашивали пароль роутера, добавь публичный ключ компьютера
в `/etc/dropbear/authorized_keys` на роутере (LuCI → Система → Администрирование → SSH-ключи).

## Секреты (не в репозитории)

| Что | Где лежит |
|---|---|
| Токен CGI | роутер `/etc/fspirat.token`, сервер `/etc/nginx/snippets/fspirat-router.conf` |
| Пароль страницы (bob) | сервер `/etc/nginx/.htpasswd_router` |
| Telegram-бот | сервер `/etc/fspirat-watch.conf` |
| Ключ туннеля | роутер `/root/.ssh/tunnel_key`, сервер `/home/tunnel/.ssh/authorized_keys` |

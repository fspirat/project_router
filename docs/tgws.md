# Telegram через tg-ws-proxy

На роутере работает [tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) (Flowseal, MIT) — MTProto-прокси для
устройств дома: `<IP роутера>:1443`. Telegram с этим прокси ходит **мимо VPN, с IP провайдера**.

## Почему через Cloudflare

Проверено 09.10.2026: прямые адреса Telegram (`149.154.x.x`, в т.ч. `kws*.web.telegram.org`) провайдер **блокирует по IP**
(не открывается даже TLS с чужим именем), поэтому zapret тут не поможет. Встроенные домены CF-прокси проекта
(`kws*.<домен>` на Cloudflare) открываются напрямую за ~0,3 с, Cloudflare не замедляется (1 МБ за ~0,5 с).
Прокси запускается с `--pool-size 0` — сразу через Cloudflare, без попыток прямого WS.

```text
Telegram (телефон/ПК дома) ─MTProto─► роутер :1443 (tg-ws-proxy) ─WSS─► Cloudflare ─► Telegram DC
```

Трафик самого роутера PassWall не трогает (`localhost_proxy=0`), поэтому правила PassWall, firewall и DNS не меняются.
Порт 1443 открыт только в домашней сети (зона LAN; из WAN вход закрыт по умолчанию).

## Автоматический режим (без настройки Telegram)

Когда переключатель включён, своя таблица nftables `inet fspirat_tg` (nat prerouting, priority `dstnat - 10` — раньше
PassWall) перенаправляет TCP устройств дома (`ip saddr <LAN>`) к подсетям Telegram (`core.telegram.org/resources/cidr.txt`,
порты 80/443/5222) на порт **1444** роутера. Там `fspirat_transparent.py` принимает обычный обфусцированный заголовок
прямого подключения (ключ без секрета прокси), определяет DC (из заголовка или по адресу) и дальше использует код
tg-ws-proxy: WebSocket через Cloudflare. Код tg-ws-proxy не меняется (кроме скрытия секрета в логе).

- Сторож `fspirat-tgws ensure` (cron раз в минуту): перехват стоит **только пока прокси слушает 1444**; иначе таблица
  снимается и Telegram снова идёт через VPN (PassWall). При остановке службы таблица тоже снимается.
- Звонки Telegram (UDP) и веб-версия (`web.telegram.org`) идут как раньше — через VPN.
- Трафик Telegram, ушедший через прокси, не попадает в счётчики трафика устройств (он идёт на сам роутер).
- Ссылка `tg://proxy` (порт 1443) остаётся — для ручной настройки, если автоматический режим не подойдёт.

## Файлы

| В репозитории | На роутере |
|---|---|
| `router/bin/fspirat-tgws` | `/usr/bin/fspirat-tgws` — on / off / status / link / init |
| `router/etc/init.d/fspirat-tgws` | procd-служба (пользователь `nobody`, только при `ENABLED=1`) |
| `router/tgws/fspirat_transparent.py` | прозрачный режим (порт 1444) поверх tg-ws-proxy |
| `router/tgws/VERSION` | закреплённый коммит tg-ws-proxy (1.11.1) |
| `router/tgws/requirements.txt` | httpx, h2, certifi и др. — версии и SHA-256 |
| — | `/usr/share/fspirat-tgws/` — код прокси и библиотеки |
| — | `/etc/fspirat/tgws` (права 600) — `ENABLED=0|1`, `SECRET` |

Секрет создаётся на роутере один раз и в логи не пишется: при сборке строки лога с секретом и ссылкой `tg://proxy`
вырезаются (workflow проверяет, что патч применился). Ссылку с секретом выдаёт только панель (POST) или SSH.

## Установка и управление

1. **Router backup** → 2. **TG WS Proxy install** (ставит `python3-light` и модули через apk, пакет, службу; режим выключен).
3. Панель → вкладка VPN → блок Zapret → строка **Telegram**: переключатель и кнопка «Ссылка» (`tg://proxy?...`).
   Ссылку открыть на устройстве дома (или переслать себе в «Избранное» и нажать) — Telegram добавит прокси.

```sh
fspirat-tgws status   # JSON: установлен / включён / процесс / порт
fspirat-tgws on|off
fspirat-tgws link     # ссылка для Telegram (с секретом!)
logread -e tg_ws_proxy
```

Вне дома прокси недоступен: в Telegram на телефоне включён «прокси» — вне Wi-Fi его нужно выключить
(или оставить VPN/mtg на сервере).

## Откат

`fspirat-tgws off; sed -i '/fspirat-tgws ensure/d' /etc/crontabs/root; /etc/init.d/cron restart; /etc/init.d/fspirat-tgws disable; rm -rf /usr/share/fspirat-tgws /usr/bin/fspirat-tgws /etc/init.d/fspirat-tgws /etc/fspirat/tgws`,
по желанию `apk del python3-light python3-asyncio python3-openssl python3-ctypes python3-logging python3-urllib python3-email python3-codecs`.

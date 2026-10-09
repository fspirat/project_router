# YouTube и Discord через zapret

Режим отправляет **только YouTube и Discord** напрямую через провайдера и обрабатывает эти соединения
движком zapret (nfqws), чтобы обойти замедление и блокировку DPI. VPN (PassWall/Xray), Split, MyDirect,
выбор сервера, автопереключение, блокировки и расписания устройств, счётчики и туннель fstunnel не меняются.

> Это осознанное исключение из VPN: при включённом режиме YouTube и Discord видят **IP провайдера**.
> Голос и видео Discord (UDP на IP без имени) остаются через VPN — см. «Ограничения».

## Движок и источники

| Что | Версия / источник |
|---|---|
| Движок | [bol-van/zapret](https://github.com/bol-van/zapret) **v72.13**, `nfqws` для linux-arm64 из релиза `zapret-v72.13-openwrt-embedded.tar.gz` |
| Стратегии | [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) 1.10.3: `general`, `ALT`, `SIMPLE FAKE` — параметры перенесены в синтаксис nfqws и проверяются `nfqws --dry-run` |
| Лицензия | MIT (bol-van, Flowseal) — `router/zapret/LICENSE-zapret.txt` |
| Контрольные суммы | `router/zapret/VERSION` (архив релиза, nfqws, fake-файлы) |

**Почему zapret, а не zapret2.** Flowseal — Windows-сборка (winws.exe + WinDivert), а winws — это порт `nfqws`
из zapret v1: его стратегии напрямую переносятся в nfqws v72 (те же `--dpi-desync=multisplit/fakedsplit/hostfakesplit`,
`--filter-l7`, `--hostlist`). zapret2 (`nfqws2`, стратегии на Lua) — новая ветка с другим синтаксисом; перенос
стратегий Flowseal туда требует переписывания и отдельной проверки. Файлы `.bat`, `winws.exe` и WinDivert на роутер не копируются.

## Путь пакета

```text
LAN-клиент ─► prerouting: inet fspirat (блокировки/счётчики, raw) ─► PassWall2 TPROXY/REDIRECT :2001
          ─► Xray: sniffing SNI / HTTP Host / QUIC → правила Split по порядку:
               MyBlock (MyDirect) → Direct · fsZapret (YouTube, Discord) → Direct · остальное → VPN-сервер
          ─► Direct = НОВОЕ соединение самого Xray (freedom, SO_MARK 0xff) с IP провайдера
          ─► output → postrouting: inet fspirat_zapret (priority mangle+10):
               mark 0x40000000 (пакеты nfqws) → мимо
               mark ≠ 0xff (не Xray) → мимо
               адрес VPN-сервера (копия набора psw2_vps PassWall) → мимо
               TCP 80/443/2053/2083/2087/2096/8443 и UDP 443, первые 6 пакетов соединения → очередь 200 (bypass)
          ─► nfqws: меняет пакеты, только если имя (TLS SNI / HTTP Host / QUIC SNI) из youtube.txt / discord.txt
          ─► WAN
```

Важно: в Xray «Direct» — это не пересылка пакета клиента, а новое исходящее соединение процесса Xray. Поэтому
обработка стоит в `postrouting` для трафика самого роутера (метка Xray 0xff), а не в `forward`.
Flow offloading на роутере выключен, а исходящий трафик Xray всё равно не идёт через forward/offload.

Соединение Xray **с VPN-сервером** (тоже метка 0xff) в очередь не попадает: адреса серверов исключены, а
зашифрованный внешний туннель zapret не обрабатывает.

## Что выделяется и что нет

- **Списки** — `router/zapret/youtube.txt`, `router/zapret/discord.txt` (домен + поддомены). Они же — правило PassWall
  `fsZapret` (отдельное от MyDirect) и `--hostlist` у nfqws. Общие домены Google/Cloudflare, `ipset-all`, Game Filter,
  «любой IP» и весь UDP по порту **не** используются.
- **YouTube**: страницы, API (`youtubei.googleapis.com`), видео (`googlevideo.com`), картинки (`ytimg.com`, `yt3.ggpht.com`),
  QUIC/HTTP3 (Xray определяет имя в QUIC, nfqws шлёт fake QUIC Initial).
- **Discord**: вход, сообщения, API, вложения и CDN (`discord.com`, `discordapp.com/.net`, `discord.media`…), шлюз голоса по WebSocket.

## Ограничения (честно)

- **Голос/видео/демонстрация экрана Discord** идут по UDP на IP голосового сервера без имени — Xray не может отнести их
  к Discord по домену, поэтому они **остаются через VPN** (как раньше). Расширять обработку на UDP-порты 50000+ или
  диапазоны Cloudflare не стали: это задело бы чужой трафик.
- **Общие IP/CDN.** Выделение идёт по имени в каждом соединении (SNI), а не по IP, поэтому соседние сервисы Google/Cloudflare
  на тех же адресах остаются на прежнем маршруте. Но страница YouTube подгружает и общие домены Google (шрифты, `www.gstatic.com`) —
  они идут через VPN.
- **ECH / клиентский DoH.** Если браузер прячет имя (ECH, внешнее имя `cloudflare-ech.com`), соединение не совпадёт со списком
  и пойдёт прежним маршрутом (VPN). DoH клиента не мешает: маршрут решает имя в самом соединении, а не DNS.
- **DNS** для доменов правила PassWall резолвит «напрямую» (DNS провайдера). Для Discord на 09.10.2026 провайдер отдаёт
  настоящие адреса Cloudflare (проверено), подмены нет.
- **IPv6**: у устройств дома нет глобального IPv6 (только ULA), PassWall IPv6 не проксирует — режим работает по IPv4.
- **Стратегия зависит от провайдера.** Если YouTube/Discord не открываются — попробовать стратегию 2 или 3.
- **Отказ движка**: очередь с `bypass` — пока nfqws не работает, пакеты проходят без обработки; сторож (cron раз в минуту)
  возвращает YouTube и Discord в VPN и повторяет попытку раз в 10 минут. Остальной трафик на «напрямую» не переключается.
- Включение/выключение перезапускает PassWall (VPN пропадает ~5 с, открытые соединения переподключатся).

## Файлы

| В репозитории | На роутере |
|---|---|
| `router/bin/fspirat-zapret` | `/usr/bin/fspirat-zapret` — on/off/strategy/status/check/ensure |
| `router/etc/init.d/fspirat-zapret` | `/etc/init.d/fspirat-zapret` — procd-служба nfqws (только при ENABLED=1) |
| `router/zapret/*.txt`, `VERSION`, `LICENSE-zapret.txt` | `/usr/share/fspirat-zapret/` (+ `nfqws`, `fake/*.bin` из релиза) |
| — | `/etc/fspirat/zapret` — выбранный режим `ENABLED=0|1`, `STRATEGY=1..3` (постоянно) |
| — | `/tmp/fspirat/zapret/` — ошибки, признак отката, результат проверки (временно) |
| CGI `zapret`, `zapretset`, `zapretstrat`, `zapretcheck` | `/www/cgi-bin/fspirat` (из браузера — только `on=0|1` и номер стратегии) |

nftables: своя таблица `inet fspirat_zapret` (создаётся атомарно, удаляется только она). PassWall: своё правило `fsZapret`
и опция `passwall2.9DxG2j8l.fsZapret=_direct`. Cron: `* * * * * /usr/bin/fspirat-zapret ensure`.

## Установка и выкладка

1. **Router backup** (workflow) — архив с датой на роутере `/root/fspirat-backup/` и копия на сервере `/root/fspirat-backups/`.
2. **Zapret install** (workflow) — требует копию не старше суток; ставит `kmod-nft-queue`, nfqws (с проверкой SHA-256),
   списки, скрипт, службу, cron; проверяет стратегии `--dry-run`. **Режим остаётся выключенным.**
3. Панель — push в `main` (`web/`) выкладывает её сам; блок появляется, когда на роутере есть `fspirat-zapret`.
4. Дальше обычный **Deploy router** обновляет скрипт, службу и списки (если zapret установлен).

## Управление

Панель → вкладка VPN → «YouTube и Discord через zapret»: переключатель «Zapret: включён / выключен», стратегия, «Проверить доступность».

По SSH (роутер, `root@OpenWrt`; с сервера — `ssh -p 8022 -i /root/.ssh/router_key root@127.0.0.1`):

```sh
fspirat-zapret status        # JSON: выбрано / служба / nft / маршрут / ошибка / пакеты
fspirat-zapret on            # включить (≈10 с, перезапуск PassWall)
fspirat-zapret off           # выключить и вернуть YouTube/Discord в VPN
fspirat-zapret strategy 2    # другая стратегия (без перезапуска PassWall)
fspirat-zapret check; cat /tmp/fspirat/zapret/check.json
nft list table inet fspirat_zapret   # правила и счётчики очереди
```

## Как проверять

С **устройства дома** (не с роутера): видео на YouTube играет (в т.ч. 1080p, перемотка), Discord входит, грузит картинки,
голосовой канал соединяется. В панели: «Discord видит IP провайдера», счётчики «обработано zapret» растут, а при выключенном
режиме таблицы `inet fspirat_zapret` нет и `uci show passwall2 | grep fsZapret` пусто.

## Полный откат

1. `fspirat-zapret off` (или переключатель в панели) — маршрут и правила убраны, PassWall перезапущен.
2. Удалить установку: `/etc/init.d/fspirat-zapret disable; rm -rf /usr/share/fspirat-zapret /usr/bin/fspirat-zapret /etc/init.d/fspirat-zapret /etc/fspirat/zapret /tmp/fspirat/zapret; sed -i '/fspirat-zapret ensure/d' /etc/crontabs/root; /etc/init.d/cron restart`
3. По желанию — модуль ядра: `apk del kmod-nft-queue`.
4. Если что-то пошло не так — восстановить из архива (`RESTORE.txt` внутри архива «Router backup»).
5. В репозитории — `git revert` коммита интеграции (панель скроет блок сама, когда на роутере нет `fspirat-zapret`).

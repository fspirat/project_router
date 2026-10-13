# Stage 4 client contract: iOS app «Роутер» — tabs VPN, Устройства, Обход, Журнал, full Настройки

> **Справочный документ (этап 4, 13.10.2026).** Контракт клиента для вкладок VPN, Устройства, Обход, Журнал и полных Настроек.
> Дополняет `docs/ios/contract-stage3.md`; «stage 3 §N» ниже — раздел того документа.
> Выведен из кода сервера (`server/auth/*.php`, `tgbot.php`), CGI и скриптов роутера (`router/www/cgi-bin/fspirat`, `router/bin/*`),
> `server/bin/fspirat-watch` и веба (`web/app.js`, `web/index.html`). **При расхождении прав код** (прежде всего сервер).
> Образцы ответов из §10 в репозитории лежат в `ios/RouterCore/Sources/RouterCore/SampleJSON+Stage4.swift` (папки `Fixtures/` нет).
> Номера строк `app.js:N` и `index.html:N` — на 13.10.2026, потом могут сдвинуться. Макеты `*.dc.html` в репозиторий не входят.
> Адреса и MAC в образцах — из документационных диапазонов (203.0.113.x, 198.51.100.x, 192.168.1.x, 00:00:5E:00:53:xx).
> Подписи в готовом приложении местами короче (например, «Блокировать»: «Сразу» / «1 мин» / «5 мин»); точные тексты — в коде `ios/`.
>
> *Reference (stage 4, 13.10.2026): extends the stage 3 contract; derived from `server/auth/*.php`, the router CGI and `web/app.js`.
> The code wins on any disagreement.*

This document was the single source of truth for the stage 4 iOS coding agents (now a reference; the code wins). It **extends** `docs/ios/contract-stage3.md` (stage 3). Everything stage 3 says still holds unless a section here says **«replaces stage 3 §N»**. Read stage 3 §1 (transport), §2.10–2.12 (action pipeline, 428 flow, jobs), §3 (errors) and §10 (gotchas) first; they are not repeated.

**Sources.** Checked against the real code on 13.10.2026:
- `server/auth/app.php` (routes, `app_action_spec`, `app_confirm_text`, `app_dirdel_check`, jobs), `app-lib.php` (`FSR_APP_LIMITS`, `FSR_APP_PW`, confirms), `data-lib.php` (`fsr_data_payload`, `fsr_data_newdevs`, `fsr_vds`, `fsr_app_devices_list`, `fsr_auth_log_tail`), `lib.php` (`fsr_log` kinds, `fsr_router_call`, `FSR_ACTIONS`), `login.php`, `logout.php`;
- `router/www/cgi-bin/fspirat` (every action used here), `router/bin/fspirat-zapret`, `fspirat-tgws`, `fspirat-subs`, `fspirat-ping`, `fspirat-svcping`, `fspirat-targets`, `fspirat-fw`, `fspirat-sub`;
- `server/bin/fspirat-watch`, `fspirat-vdsstat`, `server/auth/tgbot.php` (`cmd_vds`);
- `web/app.js` (line numbers below are of the current file), `web/index.html`;
- `docs/ios/plan.md` §2, §3, §6, §7; `docs/ios/inventory.md` §3, §4, §6, §7, §9;
- Apple documentation JSON (developer.apple.com) for every iOS 26 API named in §8.

**Observed responses.** Everything marked *observed* was produced by running the real `app.php` locally (PHP 8.3 built-in server) against the repo's stubs `server/auth/tests/router-stub.php` / `tg-stub.php`, with the stub's router bodies replaced by realistic CGI bodies (`resp_<action>` files). (The run script and its raw output were temporary session files and are not kept in the repo.) Router-side bodies (CGI JSON) are passed through byte-for-byte, so their fixtures are built from the exact `printf` formats in the router scripts. Where code and docs disagree, **the code wins**; every case is in §11.

**Conventions** — as stage 3: "int" = JSON number without fraction (decode as 64-bit `Int`); `?` after a name = key may be absent; `|null` = key present, value may be `null`; timestamps are Unix seconds; Russian UI strings are verbatim; **(proposed)** marks new app texts not taken from the server or the web. `app.js:N` = line N of `web/app.js`.

**Reference time for all fixtures:** `now = 1791886560` = 13.10.2026 14:16:00 Europe/Samara (UTC+4). Samara midnight of that day = `1791835200`.

---

## 0. What changes against stage 3 (owner decisions 13.10.2026)

| # | Decision | Where |
|---|---|---|
| 1 | Bottom tab bar «Сводка · VPN · Устройства · Обход · Журнал»; full Настройки (gear) | §1, §5 |
| 2 | The app looks «плюс-минус в стиле Liquid Glass» (iOS 26) | §8 |
| 3 | **Data is NOT hidden in the app switcher by default.** New Settings toggle «Скрывать в переключателе приложений», default **OFF**. Face ID lock on return stays as configured | §1.3 (replaces stage 3 §7.8 last bullet) |
| 4 | Summary fixes: monospaced **digits only**, Russian **decimal comma**, the «Проверка через VPN · Задержка» label must not wrap | §9 (replaces stage 3 §5 decimal rule and §6 font rule) |
| 5 | Plan §6 recommendations stand for undecided questions: Face ID on open and for critical actions; «Выйти на всех устройствах» in the web also revokes phones (already in code); push — no; subscriptions and the services list — view only (except «Обновить», plan §2); own servers card `/vds` — **shown, read-only** | §5.1.9 |

---

## 1. App structure

### 1.1 Tabs
`TabView` with five tabs, each tab its own `NavigationStack` with a large title:

| Tab | Title | SF Symbol | Root view |
|---|---|---|---|
| 0 | «Сводка» | `gauge.with.dots.needle.67percent` | stage 3 Summary (with §9 fixes) |
| 1 | «VPN» | `lock.shield` | §5.1 |
| 2 | «Устройства» | `macbook.and.iphone` | §5.2 |
| 3 | «Обход» | `arrow.triangle.branch` | §5.4 |
| 4 | «Журнал» | `scroll` | §5.5 |

- Settings: a gear button (`gearshape`) in the **top-trailing toolbar of every tab**, opens Settings as a sheet (§5.6). The tab bar has no Settings tab.
- Build the tab bar with `.tabItem { Label(title, systemImage:) }` + `.tag(n)`. The `Tab` struct is iOS 18+ and the deployment target stays **iOS 17**; `tabItem(_:)` is deprecated only from iOS 27.2 (Apple doc metadata `deprecatedAt: 27.2`), so it is fine for the iOS 26.5 SDK. Built with the iOS 26 SDK, the standard `TabView` gets the Liquid Glass tab bar automatically.
- Remember the selected tab with `@SceneStorage("tab")` (per-scene, not on disk as data). Cold start → «Сводка».
- Tab badges (proposed, optional): «Устройства» shows the count of `newdevs` not yet seen (§5.2.4); «Журнал» none.

### 1.2 Shared state
One `@Observable RouterStore` (stage 3) grows these caches; all in memory only (no disk):

| Cache | Source | Notes |
|---|---|---|
| `status` | `/status`, ping job result | shared by Summary, VPN, Devices, Bypass |
| `data[range]` | `/data?range=day/week/month` | one cache per range; `names`, `traffic`, `newdevs`, `speed`, `site` are the same in every range → keep them from the **newest** response of any range |
| `zapret`, `tgws`, `mydirect`, `vds`, `devices` (access list), `led`, `net`, `me` | their GETs | |

### 1.3 App switcher privacy — **replaces stage 3 §7.8 «App switcher privacy»**
New setting: `@AppStorage("hideInSwitcher")`, default **`false`**. Settings row (Face ID section): toggle «Скрывать в переключателе приложений»; footer **(proposed)**: «Вместо экрана в переключателе приложений будет значок. Face ID при возврате работает, как настроено выше.»

| `hideInSwitcher` | Behaviour |
|---|---|
| **false (default)** | **No** privacy cover for `scenePhase == .inactive` or `.background`. The app switcher shows the real screen. |
| true | Stage 3 behaviour: opaque cover (logo on `bg`) whenever `scenePhase != .active`. |

Lock interaction (Face ID «При открытии» on), which must hold for both values:
- **Delay «Через 1 минуту» / «Через 5 минут»:** unchanged — decided on the way back while still `.inactive` (`AppLock.willEnterForeground`).
- **Delay «Сразу»:**
  - `hideInSwitcher == true`: unchanged — lock engages in `didEnterBackground` (the snapshot then shows the lock screen, which is fine).
  - `hideInSwitcher == false`: **do not engage in `didEnterBackground`** (that would put the lock screen into the switcher snapshot and hide the data again — exactly the owner's complaint). Instead engage on the way back: in `willEnterForeground` with `away >= 0`, i.e. whenever the app was really backgrounded (`backgroundedAt != nil`). Polling is already off while not active, so nothing new is fetched before the lock.
- Cold start: lock as before (`lockAtLaunch`).
- Face ID itself, Control Center, Notification Center and the switcher swipe make the scene `.inactive` **without** `.background`: never lock, never cover (when the toggle is off).
- The «Проверить?» pre-dialog and the 428 dialogs: with the toggle **off**, do **not** auto-close them on `.inactive` (stage 3 closed the ping pre-dialog because system alerts are drawn above the cover; without a cover there is nothing to protect). With the toggle on keep the stage 3 rule. A 428 dialog that was open > 55 s is still never resent (stage 3 §2.11 step 3).
- Sheets (`sheetChrome`): cover only when `includeLock && lock.isLocked`, or when `hideInSwitcher && scenePhase != .active`.
- The login screen and the bot-number screen follow the same toggle.

---

## 2. Reads (A)

### 2.1 `GET /status` — parts used by stage 4 screens
The schema is stage 3 §2.6 (unchanged). Stage 4 additionally relies on:

| Field | Type | Used by | Notes |
|---|---|---|---|
| `current` | string | VPN | node id, `"_direct"` (no VPN) or `""` (Split not found) |
| `split_active` | bool | VPN | false → show the stage 3 Split warning on VPN too |
| `ping.nodes[]` | `{id: string, name: string, ms: int, group: string, own?: true}` | VPN | `ms` 0 = no answer. `own` present only as `true` (group `fspirat`). `name` may have stray spaces and a leading flag emoji → trim for display. `group` = subscription remark (case as in PassWall) or `"fspirat"`. `"_direct"` is never a node. Hysteria2 and names matching `LTE|Россия|Обход` are not in the list unless current |
| `ping.updated` | int | VPN | «Проверено …» |
| `subs` | `[SubItem]|null` | VPN | `[]` no subscriptions; `null` lua failed → fall back as §5.1.7 |
| `sub` | `Sub|null` | VPN | fallback only |
| `svc` | `{string: Targets}` | VPN | key = node id or `"direct"`; always an object. Values exist only for nodes measured by svcping (every 30 min, «Проверить» starts it) |
| `svc.direct.base` | int? | VPN | TCP ms to ya.ru from the router without VPN; present only in `svc.direct` |
| `svc_running` | bool | VPN | svcping is measuring now → caption «Сервисы через другие серверы перемеряются…» **(proposed)** |
| `targets` | `Targets|null` | VPN, Bypass | the current server's fresh service values (every 5 min) |
| `target_list` | `[string]` | VPN, Bypass | `"kind|name|addr"`; `mc` addr always has `:port`; may be `[]` |
| `svc_direct` | `[string]` | Bypass | service **names** currently sent directly |
| `speed.vpn`, `speed.direct` | `Speed|null` | VPN | last router speed test per channel |
| `devices[]` | `Device` (stage 3 §2.6) | Devices | `band` `"2g"|"5g"|"6g"|"wired"` only when online; `signal` int dBm (0 = unknown); `rate` int Mbit/s (TX); `blocked`/`sblocked`/`direct` present only as `true`; `sched` `"HHMM-HHMM"` (off-on) |
| `log` | `[string]` ≤8 | VPN (fallback only) | «ДД.ММ ЧЧ:ММ текст», router time |

`Speed` = `{"via":"vpn"|"direct","ts":int,"down":int /*bit/s*/,"up":int /*bit/s; 0 when the upload failed or was limited*/,"latency":int /*ms, best TTFB of 3*/,"ip":string /*exit IP, may be ""*/,"country":string /*2 letters or ""*/,"server":string,"streams":int,"up_limited":bool}`.

### 2.2 `GET /data?range=day|week|month`
Built by PHP from fspirat-watch files; **works while the router is offline.** Query: only `range`; anything else → `400 bad_param` (*observed* for `range=year`). Omitted → `day`.

```
{
  "now": int,                       // server time
  "range": "day"|"week"|"month",
  "step": int,                      // 0 (day) | 1800 (week) | 7200 (month)
  "points": [...],                  // FORMAT DEPENDS ON RANGE, see below
  "stats": {"avg": int|null, "min": int|null, "max": int|null, "fails": int, "offline_min": int},
  "events": [[int ts, string kind, string text]],   // newest first, ≤100, within the range
  "offline_since": int|null, "last_ok": int|null,
  "names": {mac: string},           // always an object
  "tpoints": {serviceName: [[int ts, int ms]]},      // always an object; bucketed like points for week/month
  "traffic": {mac: {"d": [int up, int down], "m": [int up, int down]}},   // always an object; bytes; Samara day/month
  "speed": [[int ts, "vpn"|"direct", int down_bps, int up_bps, int latency_ms]],   // last 90 days, oldest first, SAME in every range
  "mtg": object|null,               // ignore (mtg is off since 12.10.2026)
  "site": {"luci": string, "bot": string, "mtg": string, "panels": [string]},
  "newdevs": [{"ts": int, "mac": string}]           // app-only, last 7 days, newest first, SAME in every range
}
```

**`points` by range** (`data-lib.php:52-72`):

| range | window | element | meaning |
|---|---|---|---|
| `day` | now − 86 400 | `[ts, ms]` (**2 ints**) | one point per minute from fspirat-watch: `ms > 0` ok; `0` VPN check failed; `-1` router offline |
| `week` | now − 7·86 400 | `[mid, value, fails, off]` (**4 ints**) | 30-min bucket; `mid = floor(ts/1800)·1800 + 900`; `value` = rounded average of the ok minutes, or — when the bucket has **no** ok minute — `-1` if `off ≥ 3`, else `0`; `fails` = minutes with 0; `off` = minutes with −1 |
| `month` | now − 30·86 400 | same 4 ints | 2-hour bucket, `mid = floor(ts/7200)·7200 + 3600` |

- `stats` always counts the **raw minute points** of the window (not buckets): `fails` = minutes with 0, `offline_min` = minutes with −1. *Observed:* week `{"avg":51,"min":40,"max":62,"fails":103,"offline_min":9}`.
- A bucket's `mid` can be **before** the window start (first bucket) or **after `now`** (current bucket, up to step/2). Clamp the chart x-domain to `[now − span, now]` and clip.
- `tpoints` for week/month: `[mid, avg-of-ms>0 | 0]` with the same bucket rule; for day: `[ts, ms]` raw (one point per 5-min router measurement).
- `events`: the server reads only the **last 300 lines** of `events.tsv`, filters to the window, sorts newest first and keeps **100**. So for 30 days the list can be incomplete even with fewer than 100 rows.
- `newdevs`: all `newdev` events of the last 7 days from the **whole** `events.tsv`; MAC taken from «(…)» at the end of the text and **lowercased** (*observed*: text `(00:00:5E:00:53:02)` → `"00:00:5e:00:53:02"`). Devices may have left DHCP since. Duplicates are possible if the watcher re-learned a MAC.
- `traffic`: keys are lowercase MACs; `d` = today, `m` = this month (Europe/Samara calendar); `[up, down]` order (**up first**).
- `speed`: only rows with via `vpn|direct`; `up_bps` may be 0 (failed or limited upload).

*Observed* (`range=week`, values trimmed to the parts that matter):
```json
{"now":1791899278,"range":"week","step":1800,"points":[[1791294300,51,0,0],"…",[1791899100,49,0,0]],"stats":{"avg":51,"min":40,"max":62,"fails":103,"offline_min":9},"events":[[1791899216,"manual","Сервер выбран вручную: _direct"],[1791896276,"router","MyDirect + gosuslugi.ru"],[1791812876,"auto","Автопереключение: fspiratDE -> fspiratNL 41ms"],[1791726876,"online","Роутер снова на связи (не было 6 мин)"],[1791726476,"offline","Роутер пропал со связи"],[1791380876,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5E:00:53:02)"]],"newdevs":[{"ts":1791380876,"mac":"00:00:5e:00:53:02"}],"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[52429800,1610614736]}},"names":{},"tpoints":{"YouTube":[[1791891900,61],[1791899100,0]],"Discord":[[1791899100,0]]},"speed":[[1791894276,"vpn",91234567,40123456,38],[1791893276,"direct",286000000,0,6]],"site":{"luci":"https://router.panel.example.test/","bot":"TestBot","mtg":"","panels":["panel.example.test"]},"offline_since":null,"last_ok":1791899246,"mtg":null}
```
(Note the observed manual event text with a raw `_direct`: it is a stub line; the real watcher writes «Напрямую (без VPN)», but the client must still replace `\b_direct\b`, stage 3 §2.9.)

**Decoding.** `points` elements are arrays of 2 **or** 4 ints: decode unkeyed; `DataPoint(ts, ms, fails?, offline?)` already exists in RouterCore — keep it; treat a 2-element point as `fails = nil, offline = nil`.

### 2.3 `GET /zapret` (CGI `zapret`, timeout 10 s)
Two shapes:
- script missing: `{"installed":false,"absent":true}` (no other keys);
- script present (`fspirat-zapret status`, `fspirat-zapret:237-241`), all keys always present:

```
{"installed": bool,          // nfqws + lists + kernel module nfnetlink_queue
 "enabled": bool,            // chosen mode (ENABLED=1)
 "strategy": int,            // 1|2|3 (default 3)
 "engine": bool,             // nfqws running
 "nft": bool,                // table inet fspirat_zapret has its queue rules
 "route_cfg": bool,          // Split has fsZapret → _direct in uci
 "route_live": bool,         // the rule is in the running Xray config
 "fallback": bool,           // engine failed: YouTube/Discord temporarily via VPN
 "error": string,            // "" or ≤200 chars, no " \ or newline
 "pkts_tcp": int, "pkts_udp": int,   // packets queued to nfqws (counters)
 "vpn_excluded": int,        // 0|1 — NOT a count (grep -c of "elements")
 "version": string,          // may be ""
 "busy": bool,               // lock dir exists (on/off/strategy running, or the 1-min cron "ensure")
 "checking": bool,           // a check is running
 "check": Check|null}
Check = {"error":"xray"}     // Xray not running at check time
      | {"ts": int, "via": "isp"|"vpn"|"unknown",
         "list": [{"name": string, "ok": bool, "code": string /*"204","000"…*/, "ms": int /*curl time_total, incl. handshakes*/, "queued": int}]}
```
List names are fixed: «YouTube», «YouTube видео», «Discord API», «Discord CDN». `ok` = HTTP 2xx/3xx/4xx.

*Observed* pass-through:
```json
{"installed":true,"enabled":true,"strategy":2,"engine":true,"nft":true,"route_cfg":true,"route_live":true,"fallback":false,"error":"","pkts_tcp":18234,"pkts_udp":5120,"vpn_excluded":1,"version":"v72.5","busy":false,"checking":false,"check":{"ts":1791886000,"via":"isp","list":[{"name":"YouTube","ok":true,"code":"204","ms":412,"queued":6},{"name":"YouTube видео","ok":true,"code":"200","ms":530,"queued":6},{"name":"Discord API","ok":true,"code":"200","ms":610,"queued":5},{"name":"Discord CDN","ok":false,"code":"000","ms":12001,"queued":0}]}}
```

### 2.4 `GET /tgws` (CGI `tgws`, timeout 10 s)
- script missing: `{"installed":false,"absent":true}`;
- otherwise (`fspirat-tgws:83-90`), all keys present:
```
{"installed": bool, "auto": bool /*nft redirect table exists*/, "redirected": int /*packets counted by the redirect rule ≈ connections*/,
 "enabled": bool, "running": bool /*proxy process*/, "listening": bool /*port 1443 — NOT the transparent 1444*/,
 "host": string /*router LAN IP, e.g. "192.168.1.1"*/, "port": int /*1443*/, "version": string}
```
*Observed:* `{"installed":true,"auto":true,"redirected":3412,"enabled":true,"running":true,"listening":true,"host":"192.168.1.1","port":1443,"version":"1.1.3"}`.
`host`/`port` are informational; never show a `tg://proxy` link (the secret is not exposed and must not be).

### 2.5 `GET /mydirect` (CGI `mydirect`, timeout 10 s)
`{"domains": [string], "added": [string]}`
- `domains` = the PassWall rule «MyDirect» `domain_list` as is: plain domains, prefixed entries (`geosite:…`, `domain:…`, `full:…`, `regexp:…`, matched by `^[a-z]+:`), and hosts added by «сервисы напрямую» (svcdirect, web kind: host without `www.`).
- `added` = domains added from the web panel or the app (`/etc/fspirat/mydirect_added`); only these can be removed (§3.2 `dirdel`). `added` items may also appear in `domains`; treat `domains ∖ added` as the read-only base list.
- Error: `500 {"error":"no rule","message":"В PassWall нет правила MyDirect.","source":"router"}` (*observed*).

*Observed:* `{"domains":["gosuslugi.ru","sberbank.ru","kinopoisk.ru","geosite:category-ru","mc.example.net"],"added":["kinopoisk.ru"]}`.

### 2.6 `GET /vds` (server file, works offline)
```
{"ts": int|null,              // when fspirat-watch wrote vds.json (every 5 min); null = no file
 "servers": [{"name": string /*≤60 chars*/, "local"?: true /*the panel server itself*/,
              "stat": null /*not reachable over SSH*/ | {
                 "up": int /*uptime s*/, "cores": int, "mem_total": int, "mem_avail": int /*KiB*/,
                 "rx": int, "tx": int /*bytes since boot of the default-route interface*/, "conns": int /*established TCP on :443/:10445*/,
                 "load": string /*"0.08 0.05 0.01"*/, "disk": string /*root fs use, e.g. "37%"*/, "xray": string /*systemctl is-active: "active"|"inactive"|"failed"|""…*/}}]}
```
- No file → `{"ts":null,"servers":[]}`.
- Unknown keys (e.g. a host address) are dropped by the server (*observed*: input `"host":"203.0.113.9"` and `"extra"` did not reach the client).

*Observed:*
```json
{"ts":1791899156,"servers":[{"name":"Сервер панели","local":true,"stat":{"up":1209600,"cores":2,"mem_total":2014084,"mem_avail":1302500,"rx":918273645123,"tx":905172634512,"conns":14,"load":"0.08 0.05 0.01","disk":"37%","xray":"active"}},{"name":"DE","stat":null},{"name":"NL2","stat":{"up":86400,"cores":1,"mem_total":1000000,"mem_avail":200000,"rx":1,"tx":2,"conns":0,"load":"0.50 0.40 0.30","disk":"81%","xray":"inactive"}}]}
```

### 2.7 `GET /devices` (who has access; server, works offline)
```
{"apps": [{"id": string /*16 hex*/, "name": string, "model": string, "os": string /*"iOS 26.0" or "" (old clients may send "18.1")*/,
           "app": string, "created": int, "seen": int, "last_ip": string, "expires": int, "hard_expires": int,
           "current": bool /*this phone*/}],          // active keys only (not revoked, not expired), ordered by seen DESC
 "web":  [{"ref": string /*16 hex, first 16 of the session hash*/, "created": int, "seen": int, "ip": string, "ua": string /*≤200*/,
           "current": bool /*always false for the app*/}],   // live web sessions, seen DESC
 "logins": [{"ts": int, "name": string, "ip": string,
             "result": "pending"|"approved"|"issued"|"expired"|"denied"|"notme"|"cancelled"}],   // last 20 app logins, newest first
 "auth_log": [{"ts": int, "what": string /*[A-Z_]{1,20}*/, "ip": string}]}               // last ≤30 lines of the login journal, newest first
```
- `auth_log.what` values written by the code: `OK` (web login), `FAIL` (wrong password or code, web or app), `LOCKED`, `CODE` (password ok, Telegram code sent), `CODEFAIL`, `LOGOUT`, `LOGOUT_ALL`, `APP_LOGIN` (app password ok, waiting for the bot), `APP_OK`, `APP_DENIED`, `APP_REVOKE`, `APP_BADTOKEN`, `APP_URLTOKEN`. Unknown → show the raw code.
- `auth_log.ts` is correct Unix time (the file is written in Moscow time and parsed back with the same zone).

*Observed:*
```json
{"apps":[{"id":"46740d2bc16e6a9d","name":"iPhone владельца","model":"iPhone15,2","os":"iOS 18.1","app":"1.0","created":1791899277,"seen":1791899277,"last_ip":"127.0.0.1","expires":1799675277,"hard_expires":1823435277,"current":true},{"id":"8df5a0cb8a35a59a","name":"Второй iPhone","model":"iPhone16,1","os":"iOS 26.0","app":"1.0 (12)","created":1791899277,"seen":1791726477,"last_ip":"198.51.100.7","expires":1799675277,"hard_expires":1823435277,"current":false}],"web":[{"ref":"8207c706de3f72c7","created":1791899277,"seen":1791899277,"ip":"203.0.113.50","ua":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/141.0","current":false}],"logins":[],"auth_log":[{"ts":1791897476,"what":"CODE","ip":"203.0.113.50"},{"ts":1791895676,"what":"FAIL","ip":"203.0.113.51"},{"ts":1791892076,"what":"OK","ip":"203.0.113.50"}]}
```
(The observed run used `CODEOK`, a string the code never writes; corrected to `CODE` here.)

---

## 3. Actions (B)

### 3.1 Common rules (recap; stage 3 §2.10–2.11 are normative)
- `POST /action/<name>`, JSON body with **exactly** the listed keys (+ `confirm` on confirmable actions). Any extra key, wrong JSON type or failed regex → `400 bad_param` «Неверные данные запроса — обнови приложение.» Validate on the client first and never send what would fail.
- Order on the server: params → rate limits (429, before any 428) → «router silent 30 s» (502, no dialog; **not** for `rename`) → [with `confirm`: action lock 409 / router slot 429, confirm not burned] → confirm check (428 / `confirm_invalid`) → call.
- **`confirm` is bound to the exact parameters** (sha256 of the canonical JSON). Resending with any changed value → `400 confirm_invalid` **and the confirm is consumed** (*observed*: 428 for `{"id":"Hd3Fs9Qa"}`, resend `{"id":"Pz1Yc4Ue","confirm":…}` → `confirm_invalid`). Always resend the identical body.
- `confirm` on a non-confirmable action → `400 bad_param` (*observed* for `unblock`). On `schedule` **clear** a `confirm` is accepted and ignored (*observed* 200).
- One action at a time per server (`app-action.lock`): a parallel second action → `409 busy` «Другое действие ещё выполняется — подожди немного.»
- Never retry a POST automatically. 504 on an action → stage 3 rule: show the message + «Действие могло выполниться — проверь состояние через минуту.»
- If the router certainly did not run the action (CGI 400/409/500/503, not reached), it does not count toward limits or the PW pause (*observed*: `switch` → `400 bad node`, then `restart` got its 428 at once, not 429).

### 3.2 Per action

Columns: body (exact; regex = server regex); confirm/danger; Face ID; limits; 200 body; client re-reads.
**PW** = class of actions that restart PassWall: `switch, restart, update, subupdate, direct, diradd, dirdel, svcdirect, zapretset` — one per **15 s across all devices** + 30 per hour per device (+ own limits).

| Action | Body | 428 / danger | Face ID | Server limits (per device unless «all») | 200 body | Re-read |
|---|---|---|---|---|---|---|
| `pingone` | `{"id": s}` `^[A-Za-z0-9]{1,32}$` (not `_direct`, not `direct`) | no | — | 20 / 60 s | `{"id":s,"ms":int,"ts":int}` (`ms` 0 = no answer; best of 3 TCP pings) | patch `status.ping.nodes[id].ms` locally |
| `switch` | `{"id": s}` node id `^[A-Za-z0-9]{1,32}$` or exactly `"direct"`; `"_direct"` → 400 (*observed*) | yes; `high`; `"direct"` → **`critical`** | only `direct` | PW | `{"ok":true}` | `/status` at +10 s (inside the quiet window) |
| `subupdate` | `{"sid": s}` `^[A-Za-z0-9_]{1,32}$` **or** `{"all": true}` (`false`/`{}` → 400, *observed*) | yes; `high` | — | PW + 10 / h | `{"ok":true}` | `/status` at +45 s and +90 s |
| `speedtest` | `{"via":"vpn"|"direct"}` | no | — | 1 / 120 s, 10 / h; global: one long job | **202** job (§3.5) | `/data` 5 s after `done` |
| `block` | `{"mac": s}` `^([0-9a-f]{2}:){5}[0-9a-f]{2}$` (**lowercase**; uppercase → 400, *observed*) | yes; `high` | — | 30 / h | `{"ok":true,"mac":s,"blocked":true}` | `/status` at +3 s |
| `unblock` | `{"mac": s}` | no | — | 30 / h | `{"ok":true,"mac":s,"blocked":false}` | `/status` at +3 s |
| `direct` | `{"mac": s, "on": bool}` (`on` required, *observed* 400 without) | yes; `high` | — | PW | `{"ok":true,"direct":bool}` | `/status` after the quiet window (+12 s) |
| `schedule` set | `{"mac": s, "off":"HHMM", "on":"HHMM"}` `^([01][0-9]|2[0-3])[0-5][0-9]$`, `off != on` (*observed* 400 for equal and for `"23:00"`) | yes; **`medium`** | — | 30 / h | `{"ok":true}` | `/status` at +3 s |
| `schedule` clear | `{"mac": s, "off":"", "on":""}` | **no** | — | 30 / h | `{"ok":true}` | `/status` at +3 s |
| `diradd` | `{"d": s}` `^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$`, ≤100 bytes | yes; `high` | — | PW | `{"ok":true}` or `{"ok":true,"same":true}` (already listed; PassWall not restarted) | `/mydirect` at once |
| `dirdel` | `{"d": s}`, same regex, **and must be in `mydirect.added`** | yes; `high` | — | PW | `{"ok":true}` or `{"ok":true,"same":true}` | `/mydirect` at once |
| `svcdirect` | `{"name": s, "on": bool}`; name 1–40 **bytes**, valid UTF-8, none of `\x00-\x1f \x7f ~ ! " < > & \ |` | yes; `high` | — | PW | `{"ok":true}` | `/status` at +12 s, `/mydirect` at once |
| `zapretset` | `{"on": bool}` | yes; `high` | — | PW | `{"ok":true}` (work continues in background) | `/zapret` at +1.5 s, then every 3 s while `busy` (≤ 2 min) |
| `zapretstrat` | `{"n": 1|2|3}` (JSON **int**; `"2"` → 400, *observed*) | no | — | 10 / 60 s | `{"ok":true}` (background) | `/zapret` at +2 s, verify (§5.4.2) |
| `zapretcheck` | none or `{}` | no | — | 1 / 30 s (*observed* 429 `retry_after: 30`) | `{"ok":true}` (background, 10–40 s) | `/zapret` every 3 s while `checking` (≤ 2 min) |
| `tgwsset` | `{"on": bool}` | yes; **`medium`** | — | 10 / h | `{"ok":true}` (background; failures are silent) | `/tgws` at +3 s and +8 s |
| `rename` | `{"mac": s, "name": s}`; name valid UTF-8, no `\x00-\x1f\x7f`; server trims; > 40 chars after trim → `400 too_long` (*observed*); `""` = remove own name | no | — | 30 / h | `{"ok":true,"names":{mac:name,…}}` — the **whole** names map | replace `names` in every `data[range]` cache |

Not available in v1 (server `404 not_in_v1`): `subadd`, `subdel`, `settargets`.

Server-side CGI behaviour the client must know:
- `switch` to the already current node still restarts PassWall (the 428 text says «Этот сервер уже подключён.»). The app does **not** offer «Подключить» for the current node.
- `switch` writes `echo 0 > fails` (resets the auto-switch counter).
- `subupdate` runs `subscribe.lua` in the background; PassWall restarts **after** the download (1–2 min), then `fspirat-sub` and `fspirat-ping` run. The 200 comes back at once.
- `block` with a MAC not in DHCP leases is accepted (blocks by MAC anyway).
- `unblock` during an active schedule window leaves `sblocked: true` until the window ends (the device stays without internet). Show the hint in §5.3.
- `schedule` is applied immediately by `fspirat-fw schedule` (window active now → internet off now; window over → back on).
- `diradd` lowercases nothing on the server path we use (the app regex already demands lowercase).
- `svcdirect` with a `mc` service resolves its IP on the router: `400 resolve` if DNS fails. `400 no target` if the name is not in the current target list (stale list).
- `zapretstrat` and `zapretset` run in the background under the zapret lock: if the lock is held (cron `ensure` runs every minute for a second or two, or another action), **`zapretstrat` is silently lost** and `zapretset` is answered `409 busy` by the CGI before starting.
- `tgwsset` waits up to 20 s on the router for the proxy to listen; the CGI answers 200 at once; failure is visible only in the next `/tgws`.

### 3.3 Exact 428 texts (`app_confirm_text`, all *observed* unless marked)
Common fragments: **PW** = «VPN перезапустится, связь через VPN пропадёт на несколько секунд.»; **IPH** = «Если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет.»; **DEV(mac)** = ««<own name>» (<mac>)» when `names[mac]` is set **on the server**, else «Устройство <mac>» (DHCP names are **not** used).

| Action / case | danger | title | text | button |
|---|---|---|---|---|
| `switch` node found in `status` | high | «Подключить «<trimmed node name>»?» | PW | «Подключить» |
| `switch` node is current | high | same | «Этот сервер уже подключён. » + PW | «Подключить» |
| `switch` node `ms <= 0` | high | same | PW + « Сервер сейчас не отвечает — дом может остаться без VPN до автопереключения (~10 мин).» | «Подключить» |
| `switch` node unknown, or router busy/silent while building the dialog (`try` mode) | high | «Подключить другой сервер?» | PW | «Подключить» |
| `switch` `direct` | **critical** | «Пустить весь трафик напрямую, без VPN?» | «Весь трафик пойдёт без VPN, с IP провайдера; автопереключение отключится. Правила Split остаются: MyDirect — напрямую, YouTube и Discord — через zapret, если он включён. Вернуть VPN — выбрать сервер. Связь пропадёт на несколько секунд.» | «Напрямую» |
| `subupdate` `{sid}` | high | «Обновить подписку «<subs[sid].name trimmed, or the sid>»?» | «Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. Если текущего сервера в подписке больше нет, роутер сам выберет другой.» | «Обновить» |
| `subupdate` `{all:true}` | high | «Обновить подписки VPN?» | same text | «Обновить» |
| `block` | high | «Выключить интернет устройству?» | DEV + « останется в Wi-Fi, но сайты и приложения перестанут открываться, пока не включишь обратно. » + IPH | «Выключить интернет» |
| `direct` on | high | «Пускать устройство мимо VPN?» | DEV + « будет ходить в интернет напрямую, как без VPN; заблокированные в России сайты на нём открываться не будут. » + PW | «Мимо VPN» |
| `direct` off | high | «Пускать устройство снова через VPN?» | DEV + « снова пойдёт через VPN. » + PW | «Через VPN» |
| `schedule` set | **medium** | «Включить расписание интернета?» | DEV + «: интернет выключается в HH:MM и включается в HH:MM (время роутера, Самара). Если сейчас как раз время «без интернета», он выключится сразу. » + IPH | «Сохранить» |
| `diradd` | high | «Пускать <d> напрямую?» | «Сайт будет открываться без VPN на всех устройствах дома (MyDirect). » + PW | «Добавить» |
| `dirdel` | high | «Убрать <d> из MyDirect?» | «Сайт снова пойдёт через VPN. » + PW | «Убрать» |
| `svcdirect` on | high | «Пускать <name> напрямую?» | «Сервис будет работать без VPN на всех устройствах дома (запись в MyDirect). » + PW | «Напрямую» |
| `svcdirect` off | high | «<name> снова через VPN?» | «Запись уберётся из MyDirect. » + PW | «Через VPN» |
| `zapretset` on | high | «Включить zapret для YouTube и Discord?» | «YouTube и Discord пойдут напрямую через провайдера, с IP провайдера (не через VPN). Остальное не меняется. VPN перезапустится примерно на 5 секунд, открытые видео и звонки переподключатся.» | «Включить» |
| `zapretset` off | high | «Выключить zapret?» | «YouTube и Discord снова пойдут через VPN. VPN перезапустится примерно на 5 секунд.» | «Выключить» |
| `tgwsset` on | medium | «Включить прокси Telegram?» | «Telegram на всех устройствах дома пойдёт через Cloudflare с IP провайдера, а не через VPN. Если прокси перестанет работать, Telegram сам вернётся на VPN. Режим экспериментальный.» | «Включить» |
| `tgwsset` off | medium | «Выключить прокси Telegram?» | «Telegram снова пойдёт через VPN.» | «Выключить» |
| `revoke-all` `web:false` | **critical** | «Выйти на всех устройствах?» | «Доступ отзывается у всех телефонов с приложением, и у этого тоже. Войти заново — пароль и число в Telegram.» | «Выйти везде» |
| `revoke-all` `web:true` | **critical** | same | same + « Также закроются все сессии веб-панели, и каждый браузер снова попросит код из Telegram.» | «Выйти везде» |
| (stage 3) `restart`, `update`, `reboot` | high/high/critical | stage 3 §2.11 | | |
| fallback (unknown action; never expected) | high | «Выполнить действие?» | `""` | «Да» |

*Observed examples:*
```json
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"036fd2bca4661cc3c46d27ad7ebe010b","expires_in":60,"danger":"high","title":"Подключить «🇫🇮 Финляндия»?","text":"VPN перезапустится, связь через VPN пропадёт на несколько секунд. Сервер сейчас не отвечает — дом может остаться без VPN до автопереключения (~10 мин).","button":"Подключить"}
```
```json
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"4d04926fe9ee90be9407a94746cb0920","expires_in":60,"danger":"medium","title":"Включить расписание интернета?","text":"«Телевизор» (00:00:5e:00:53:03): интернет выключается в 23:00 и включается в 07:00 (время роутера, Самара). Если сейчас как раз время «без интернета», он выключится сразу. Если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет.","button":"Сохранить"}
```

**Dialog rules (stage 4, replaces the style bullet of stage 3 §2.11 step 2):**
- Show `title`, `text` verbatim; buttons «Отмена» and `button`.
- **Destructive (red) confirm button** when `danger == "critical"` **or** the action is `block`, `dirdel` or `revoke-all` (plan §2: «окно с красной кнопкой»). Everything else: accent / `.glassProminent` (§8).
- **Face ID** (setting «Для опасных действий», default on) only for `danger == "critical"`: `switch direct`, `reboot`, `revoke-all`. Run after the tap, before the resend; failure → cancel silently. `block` is **not** Face ID (the mock-up showing Face ID for block is wrong, §11).
- **Schedule, window active now** (computed by the app, §5.3.3): above the server text show an extra line in `warn` colour **(proposed)**: «Сейчас как раз время без интернета — интернет у устройства выключится сразу.», and use the destructive button style. The server text stays verbatim below it.
- **`switch` while `status.split_active == false`** (proposed extra line): «В PassWall выбран не узел Split — смена сервера ни на что не повлияет.» (stage 3 §4.2 why-text). Still allowed.
- **`revoke-all`**: before sending the first request the app asks with an app sheet whether to include the web: toggle «Также закрыть все сессии веб-панели» (default **off**) — then sends `{"web": <bool>}`; the 428 text reflects the choice.

### 3.4 `/devices/revoke`, `/devices/revoke-all`
| Route | Body | Confirm | Limits | 200 | Errors |
|---|---|---|---|---|---|
| `POST /devices/revoke` | **exactly one of** `{"id": "<16 hex>"}` (app key) or `{"web_ref": "<16 hex>"}` (web session); both → 400 (*observed*) | **no server confirm** | 30 / h | `{"ok":true}` | `404 not_found` «Не найдено.» — already revoked or gone (*observed* on the second call) |
| `POST /devices/revoke-all` | `{"web": bool}` (+ `confirm`); empty body = `web:false` | **428 critical** | 5 / h | `{"ok":true,"revoked":int}` (count of app keys revoked, **including this phone**) | `confirm_invalid` when `web` differs from the 428 request (*observed*) |

Client rules:
- Revoke one: an **app** dialog before sending (no Face ID; proposed texts in §5.6.3). Never offer «Отозвать» for the row with `current: true` — that is «Выйти на этом iPhone» (stage 3 §7.9). If `id` equals our own device id anyway, after 200 run LOGOUT.
- Revoke-all 200 → this phone's key is revoked too: run LOGOUT at once (do not wait for a 401), banner **(proposed)** «Вы вышли на всех устройствах. Войти заново — пароль и число в Telegram.»
- After revoke one → re-read `/devices`. 404 → toast **(proposed)** «Этого входа уже нет — список обновлён.» and re-read.

### 3.5 Speed test job
- `POST /action/speedtest {"via":"vpn"|"direct"}` → `202 {"job":"<16 hex>","poll_every":3}` (*observed*).
- Poll `GET /jobs/{id}` every 3 s. The CGI test takes ~35–45 s; the server waits up to 90 s; the job reports `server_error` after 150 s; client stops at 160 s (stage 3 §2.12).
- `done`: `{"state":"done","action":"speedtest","http":200,"result":Speed}` (*observed*: `{"via":"vpn","ts":1791899279,"down":90000000,"up":40000000,"latency":12,"ip":"203.0.113.77","country":"DE","server":"Hetzner (Германия)","streams":4,"up_limited":false}`). Put `result` into `status.speed[via]`; re-read `/data` after 5 s (the watcher appends the point to `speed.tsv` within a minute; a second `/data` read on the normal 60 s cycle picks it up if the first misses it).
- Start errors: `409 busy` «Тест скорости или проверка уже идут — дождись результата.» (global long-job lock, shared with `ping`); `429 rate_limited` (1 per 120 s per device, *observed* `retry_after: 119`).
- Job `error` with `http: 409, error: "busy", source: "router"` = a speed test already runs on the router (web or bot started it). The server message is the generic «Другое действие ещё выполняется — подожди немного.» (*observed*); the app shows instead **(proposed, as the web app.js:111)**: «Тест скорости уже идёт — дождись результата.» This failure does not count toward the limits.
- `400 bad_param` for any other `via` (*observed* for `"wifi"`); router `400 bad via` cannot happen with valid input.

### 3.6 Rate-limit summary (stage 4 additions; server, per device unless «all»)
| Action | Limit |
|---|---|
| pingone | 20 / 60 s |
| speedtest | 1 / 120 s, 10 / h; one long job (ping or speedtest) at a time for all |
| PW class (`switch, restart, update, subupdate, direct, diradd, dirdel, svcdirect, zapretset`) | 1 / 15 s **all**, 30 / h |
| subupdate | + 10 / h |
| block, unblock, schedule, rename | 30 / h each |
| zapretstrat | 10 / 60 s |
| zapretcheck | 1 / 30 s |
| tgwsset | 10 / h |
| revoke | 30 / h |
| revoke-all | 5 / h |
| confirms issued (428) | 20 / 60 s |
On 429: message + « Повтори через N с.» (stage 3 §3.2), and disable that control for `retry_after` with a countdown.

### 3.7 After a successful action: quiet windows, banners, toasts, disabled controls
Quiet window = stage 3 §7.2 semantics (no error toasts from `/status`, offline mode cannot switch on, `/net` paused, banner shown). **PW lock-out**: after any PW action every PW control in the whole app is disabled for `max(quiet, 15 s)` (server pause), with the tooltip-less state.

| Action | Quiet | Banner | Toast (200) | Local state change at once |
|---|---|---|---|---|
| switch node | 15 s (inventory §9.1) | «VPN переключается на «<name>»…» **(proposed)** | «Подключаю «<name>». Статус обновится через 10 секунд.» (app.js:647) | `status.current = id` |
| switch direct | 15 s | «VPN выключается — всё пойдёт напрямую…» **(proposed)** | «Подключаю «Напрямую (без VPN)». Статус обновится через 10 секунд.» | `status.current = "_direct"` |
| subupdate | 0 | — | ««<name>»: список серверов обновляется, около минуты.» (app.js:810); all: «Подписки обновляются — список серверов обновится через 1–2 минуты, потом VPN перезапустится на несколько секунд.» (stage 3 update toast) | — |
| block | 0 | — | «Интернет для «<nm>» выключен.» (app.js:495) | `device.blocked = true` |
| unblock | 0 | — | «Интернет для «<nm>» снова включён.» | `device.blocked = false` |
| direct | 12 s | «VPN перезапускается…» | ««<nm>» теперь мимо VPN.» / ««<nm>» снова через VPN.» (app.js:494) | `device.direct = on` |
| schedule set | 0 | — | ««<nm>»: без интернета с HH:MM до HH:MM.» (app.js:535) | `device.sched = "HHMM-HHMM"` |
| schedule clear | 0 | — | «Расписание «<nm>» убрано.» | `device.sched = nil` |
| diradd | 12 s | «VPN перезапускается…» | «<d> теперь напрямую.» (app.js:626); `same:true` → «<d> уже был в списке.» **(proposed)**, no quiet | — |
| dirdel | 12 s | «VPN перезапускается…» | «<d> снова через VPN.» (app.js:634); `same` → «<d> уже не было в списке.» **(proposed)** | remove from `added` |
| svcdirect | 12 s | «VPN перезапускается…» | «<name> теперь напрямую.» / «<name> снова через VPN.» (app.js:665) | `svc_direct` add/remove |
| zapretset | 15 s | «Применяю… VPN перезапускается» **(proposed)** | «Включаю zapret — около 10 секунд.» / «Выключаю zapret — около 10 секунд.» (app.js:1020) | `zapret.busy = true` |
| zapretstrat | 0 | — | «Стратегия N выбрана.» (app.js:1025) after verification (§5.4.2) | — |
| zapretcheck | 0 | — | none | `zapret.checking = true` |
| tgwsset | 0 | — | «Прокси Telegram включается…» / «Прокси Telegram выключен.» **(proposed)** | — |
| pingone | 0 | — | none (value updates in place) | node `ms` |
| rename | 0 | — | «Имя сохранено.» (app.js:516) | `names` |
| speedtest | 0 | — | «Тест через VPN: <speed(down)> загрузка, <speed(up)> отдача.» / «Тест напрямую: …» (app.js:940) | `status.speed[via]` |
| revoke | 0 | — | «Доступ «<nm>» отозван: приложение на телефоне вышло.» (app.js:1126); web session: «Сессия веб-панели закрыта.» **(proposed)** | — |

Use `.sensoryFeedback(.success)` / `.error` (stage 3 §7.3).

---

## 4. Polling and offline mode (D)

### 4.1 Rules (stage 3 §7.1 still applies)
- Poll only while `scenePhase == .active`, the app is unlocked, and the tab (or sheet) that needs the kind is **visible**. Background: nothing (no BGTask).
- One in-flight request per kind; skip a tick while the previous one runs; honour `retry_after` of a 429 per kind.
- On tab appear: fetch every kind of that tab whose cache is older than its interval (or empty). On return to `.active`: refresh the visible tab's kinds at once (`/net` resumes on its own timer).
- Pull-to-refresh (`.refreshable`) on every tab re-reads that tab's kinds in parallel. It never triggers actions.

### 4.2 Per screen
| Screen | Kind | Interval | Notes |
|---|---|---|---|
| Сводка | stage 3 §7.1 (`/status` 30 s, `/net` 3 s while visible, `/data?range=day` 60 s, `/led` 300 s) | | unchanged |
| VPN | `/status` | 30 s | |
| | `/data?range=<chart range>` | 60 s | chart range default `day`; switching the range fetches it at once |
| | `/vds` | on appear + 300 s | the file changes every 5 min; works offline |
| Устройства | `/status` | 30 s | devices list |
| | `/data?range=day` | 60 s | names, today/month traffic, newdevs (any range carries them; day is the smallest) |
| Device card (sheet) | same as Устройства | | the card reads from the shared caches |
| Обход | `/zapret` | 30 s; **3 s while `busy` or `checking`**, at most 2 min of fast polling per trigger, then back to 30 s | inventory §9.1, app.js:1006-1011 |
| | `/tgws` | 60 s | + one-off reads at +3 s and +8 s after `tgwsset` |
| | `/mydirect` | on appear and after diradd/dirdel/svcdirect; **no timer** | |
| | `/status` | 30 s | `svc_direct`, `target_list`, `targets` for the services toggles |
| Журнал | `/data?range=<journal range>` | 60 s | default `day`; own range selector, independent from the VPN chart |
| Настройки (sheet) | `/me` | on open | stage 3 |
| | `/devices` | on open, after revoke, pull-to-refresh | no timer |
| | `/data` (any cached) | — | `site.luci`, `site.bot` for the links |

`/net` (3 s) is used **only** on Сводка while its «Интернет сейчас» card is on screen.

### 4.3 Offline mode per screen
Offline mode switches on/off exactly as stage 3 §7.5 (only `/status` 502/504 outside a quiet window). While offline:

| Screen | What stays | What is disabled / paused |
|---|---|---|
| all | the offline banner of stage 3 §4.12 at the top of every tab (compact one-line version on tabs other than Сводка **(proposed)**: «Роутер не на связи с HH:MM · уже N мин») | every control that reaches the router; `/zapret`, `/tgws`, `/mydirect`, `/net` polling paused (`/status` keeps polling every 30 s) |
| VPN | last known `status` (servers, subscriptions, last speed results) dimmed with the caption **(proposed)** «Последние известные данные роутера»; `/vds`; speed history and connection history from `/data` | mode switch, server rows, «Лучший сервер» chips, «Проверить сейчас», «Подключить», subscription «Обновить», speed test buttons |
| Устройства | last known list dimmed + caption; names, traffic, «Новые за неделю» from `/data` | block, unblock, direct, schedule. **«Переименовать» stays enabled**: `rename` is handled by the server without the router (app.php:654 skips the «router silent» check) |
| Обход | last known zapret/tgws/MyDirect dimmed | all toggles, strategy, «Проверить», add/remove site, services toggles |
| Журнал | everything (it is `/data`) | — |
| Настройки | everything (`/me`, `/devices`, revoke, revoke-all, logout are server-only) | — |

If the app never got a `status` (cold start offline): VPN shows `/vds` and the `/data` charts, and the server list empty state **(proposed)** «Роутер не на связи — список серверов появится, когда он вернётся.»; Devices shows «Новые за неделю» from `newdevs` (MAC only, plus `names`) and the empty state **(proposed)** «Роутер не на связи — список устройств появится, когда он вернётся.»; Bypass shows **(proposed)** «Роутер не на связи — настройки обхода появятся, когда он вернётся.»

Reads of `/zapret`, `/tgws`, `/mydirect` that fail with 502/504 do **not** switch offline mode on (only `/status` does); keep the last data and show nothing unless it happens twice in a row (as `router_bad_reply` in stage 3).

---

## 5. Screens (C)

General: every list/section has an empty state with `ContentUnavailableView` (iOS 17). Numbers follow §7 and §9 (digits monospaced, decimal comma, NBSP before units). All times in Europe/Samara.

Helper functions ported from `app.js` (put in RouterCore, unit-tested):
- `services(status)` (app.js:143-147): if `targets.list` non-empty → `[(name, kind, host)]` from it; else parse `target_list` `"kind|name|addr"` → `host = hostOf(addr)` (stage 3 §4.5).
- `svcOf(id)` (app.js:149-154): `id == "direct"` → `"_direct"`; result = `status.targets` if `id == status.current && targets != nil`, else `status.svc[id == "_direct" ? "direct" : id]`; nil unless it has a `list`.
- `svcVal(r, name)` (app.js:155): `r.list.first(name == name)?.vpn` (Int?, 0 = no answer, nil = not measured).
- `nodeName(id)` (app.js:158): `_direct`/`direct` → «Напрямую (без VPN)»; else trimmed `ping.nodes[id].name`, else the id.
- `devName(d)` (app.js:418): `names[mac.lowercased()]` if non-empty, else `d.name`, else `""` (display «Без имени»).
- `hiddenMac(mac)` (app.js:419): regex `^.[26ae]` (case-insensitive) — locally administered MAC.
- `sigLevel(dbm)` (app.js:420): `0` if dbm is 0/nil; `> -55` → 4; `> -65` → 3; `> -75` → 2; else 1. Use `wifi` SF Symbol with `variableValue: level/4`.
- `msTone` (stage 3): `< 120` ok, `< 250` mid (warn), else slow (err). `pingLevel` (stage 3) for `cellularbars`.

### 5.1 VPN
Order of sections top to bottom (mock-up `Vpn.dc.html` is a layout reference only):

#### 5.1.1 Mode
- Segmented control «Через VPN» / «Напрямую». Selected = `status.current == "_direct"` ? «Напрямую» : «Через VPN».
- Under it: «Подключён: <nodeName(current)>» + tag (stage 3 §4.3: «свой» / «Подписка <group>» / «без VPN»); `current == ""` → «—» and the Split warning.
- Tap «Напрямую» (when not direct) → `switch {"id":"direct"}` → 428 critical → Face ID → resend. The segment does **not** change until 200.
- Tap «Через VPN» (when direct) → no request; scroll to the server list and show the hint **(proposed)** «Выбери сервер ниже — VPN включится, когда подключишь его.»
- `!status.split_active` → the stage 3 Split warning box here too.

#### 5.1.2 «Лучший сервер для …» (app.js:269-275)
- For each service `x` in `services()`: `b` = alive nodes (ms > 0) with `svcVal(svcOf(n.id), x.name) > 0`, sorted by that value ascending → first. No `b` → no chip.
- Chip: service icon (stage 3 §4.5) + «<x.name>: <b trimmed name> <value> мс». If `b.id == current` → selected style + `checkmark`, disabled («Уже подключён»); else tap → the switch flow for `b.id` (428 high).
- Section title «Лучший сервер для»; hidden when no chips.

#### 5.1.3 Server list (port of `renderServers`, app.js:233-267)
- `nodes = ping.nodes ?? []`; `alive = nodes.filter(ms > 0).sorted(ms asc)`; `dead = nodes.filter(ms == 0 && own != true)`.
- **Groups in order:**
  1. «Свои серверы» — `nodes.filter(own)` sorted by the current sort (dead own servers stay here, shown dimmed).
  2. Subscription groups — `alive.filter(!own)` grouped by `group` (`""` → «Подписка»), group order = order of first appearance in `alive` (the group with the fastest server first); header «Подписка <group>». Headers are shown only if there are own servers or more than one subscription group (app.js:265); otherwise one untitled section.
  3. «Не отвечают: N» — collapsed `DisclosureGroup` with `dead` (each: `cellularbars` level 0 + trimmed name). Hidden when `dead` is empty. Rows inside are tappable (open the server card) but have no «Подключить» quick action.
  4. «Напрямую, без VPN» — one row, shown if `svc.direct != nil || current == "_direct"` (app.js:258).
- **Empty** (no own and no alive): «Ни один сервер не ответил. Нажми «Проверить».» (app.js:267, adapted: «Пинг всех» → «Проверить»).
- **Row:** trimmed name (+ tag «свой» for own), current row marked «сейчас» (accent) instead of a chevron; ping cell `cellularbars` + «41 мс» (tone by `msTone`) or «—» (err) for 0; a second line with service latencies «YouTube 61 · Discord — · Telegram 74» built from `svcOf(n.id)` (only for nodes with ms > 0; dead → nothing, app.js:252); the best value in each column (min among alive, > 0) shown bold/accent (app.js:241-242). `nil` value → «·» (faint, «ещё не мерили»); 0 → «—» (err).
- **Direct row** (app.js:256-259): title «Напрямую» + tag «без VPN»; ping = `svc.direct.base` (TCP to ya.ru) or «—»; services from `svcOf` of `targets` when direct is current, else `svc.direct`; a `web` service with value 0 while **not** current shows «блок» (faint) with accessibility hint «Без VPN этот сайт в России не открывается». Caption (proposed): «Пинг — до ya.ru».
- **Tap a row** → server card (§5.1.4). There is **no** swipe action and no tap-to-switch on the row itself (plan: dangerous actions never from gestures).
- **Sort** (menu in the section header «Сортировка: пинг / имя / <service>»; tapping the active key again flips the direction) — port of app.js:244-249:
  - key `name`: `name` with leading non-letter/non-digit characters removed (`^[^\p{L}\p{N}]+`), trimmed, lowercased; compare with `localizedStandardCompare` in `ru_RU` × dir;
  - key `ping` / `svc:<name>`: value = `ms` / `svcVal(svcOf(id), name)`; values not > 0 always **last** (regardless of dir), ties among them by `ms` asc; else `(x − y) × dir`, ties by `ms` asc;
  - if the sort key names a service that is no longer in `services()` → reset to `ping` asc;
  - the sort applies inside each group; default `ping` asc. Remember it with `@AppStorage("vpnSort")` (UI preference, not data).
- Footer caption: «Сервисы через другие серверы меряются раз в 30 минут.» (index.html tbl-hint, shortened) + «Проверено <ago(ping.updated)>»; if `svc_running` → «Сервисы перемеряются…» **(proposed)**.

#### 5.1.4 Server card (sheet, `.presentationDetents([.medium, .large])`)
- Header: name, tag («свой» / «Подписка <group>» / «без VPN»), «Подключён сейчас» if current.
- Ping: `cellularbars` + «N мс» or «нет ответа»; caption «Проверено <ago(ping.updated)>» or, after pingone, «только что».
- Services: a row per `services()` item: icon + name + value from `svcOf(id)` («N мс» / «нет ответа» / «ещё не мерили»), with `svcOf(id).ts` → «Замер <ago>».
- Buttons:
  - «Проверить сейчас» (`arrow.clockwise`) — `pingone {"id": id}`, **no dialog**; busy label «Проверяю…»; on 200 set the node's `ms` (and stamp «только что»). Not shown for the direct row (the server regex refuses `direct`/`_direct`).
  - «Подключить» (primary) — the switch flow (428 high; the server adds the «не отвечает» warning itself when `ms ≤ 0`). Hidden for the current node.
  - Direct row: «Напрямую, без VPN» (destructive style) — `switch {"id":"direct"}`, 428 critical + Face ID. Hidden when already direct.
- Both buttons are disabled in offline mode, during the PW lock-out, and while another action runs.

#### 5.1.5 Switch history
- Source: `data[range].events` with `kind ∈ {auto, manual}` (the VPN chart's range), newest first, texts with `_direct` replaced (stage 3 §2.9). Row: `when(ts)` · level chip (`auto` = «Внимание», `manual` = «Действие») · text, e.g. «Автопереключение: fspiratDE -> fspiratNL 41ms» — display `->` as «→» and `41ms` as «41 мс» **(proposed cosmetic regex `(\d+)ms\b` → `$1 мс`)**.
- Show the latest 5 with «Все в журнале» → switches to the Журнал tab with filter «Все» and the same range **(proposed)**.
- Fallback when `/data` never loaded: parse `status.log` (app.js:397-400): each line «ДД.ММ ЧЧ:ММ text» (no year, router time); keep lines whose text starts with «авто» or «вручную»; replace 8-char ids (`\b[A-Za-z0-9]{8}\b`) with node names and `_direct` with «Напрямую (без VPN)».
- Empty: «Смен сервера за этот период не было.» **(proposed)**

#### 5.1.6 Connection history (24 ч / 7 дн / 30 дн)
- Segmented range «24 ч» / «7 дн» / «30 дн» (app.js:129 labels «24 ч», «7 дней», «30 дней»; short forms for the segmented control). Default «24 ч».
- Series selector (app.js:291-296): «Связь» + one chip per service of `services()`; a chosen service that disappears → back to «Связь».
- **«Связь»** (port of app.js:323-353), source `data[range].points` (fallback for `day` only: `status.history` `[ts, ms]`):
  - x-domain `[now − span, now]` (span 86 400 / 604 800 / 2 592 000); clip points outside;
  - y-domain `0 … max(150, max ok ms) × 1.15`;
  - `value > 0` → `LineMark` + `AreaMark` (acc / area); a 4-element point with `fails > 0` and value > 0 also draws a short fail bar at the bottom (`err`);
  - `value == 0` → line break + fail bar (taller);
  - `value < 0` → line break + full-height `RectangleMark` band (`offline` token), width = `step` (week/month) or 300 s (day; app.js:329 uses 300 s for the day slot);
  - also break the line at time gaps > `max(step, 300) × 2.5` s **(deviation, as stage 3 §4.9)**;
  - a single isolated ok point → a 2-pt dot;
  - interaction: drag/tap shows a tooltip (app.js:361-379): time — for week/month a range «HH:mm–HH:mm» of the bucket (mid ± step/2), labelled «в среднем»; value «N мс», «сбой VPN» (0) or «роутер не на связи» (−1); for buckets with `fails > 0` add « · сбоев VPN: N»; nothing when the nearest point is farther than `max(step, 300) × 1.5`.
  - Stats row from `data.stats` (app.js:351-353): «Средняя» `avg` мс, «Лучшая» `min`, «Худшая» `max` («—» if null), «Сбоев» `fails`, «Без связи» `minutes(offline_min)` (or «0 мин»).
  - Caption: `pts.isEmpty` → «данных за этот период пока нет»; else «шкала до N мс».
- **Service series** (app.js:304-321): `data[range].tpoints[name]`; one line, fail bars for 0, line breaks at gaps > `(step || 300) × 2.5`; stats «Средняя», «Лучшая», «Худшая» from the ok values, «Не ответил» = count of points ≤ 0 + « раз»; empty → «истории пока нет — она копится на сервере». Title «<name> за 24 часа / 7 дней / 30 дней».
- Offline periods also appear in the switch history only as `offline`/`online` events in the Journal; the chart band is the visual.

#### 5.1.7 Subscriptions card (port of `subsList`/`renderSubs`, app.js:766-786; view + «Обновить» only)
- List: `status.subs` if non-nil; else if `status.sub` → one synthetic item `{id: "", name: sub.title or «Подписка», host: "", hwid: false, nodes: count of non-own nodes, ts/up/down/total/expire from sub}`; else empty.
- Header count: «N подписка/подписки/подписок» (`plural`).
- Item:
  - name (bold) + tag «HWID» if `hwid` (accessibility hint: «Подписка получает HWID — идентификатор роутера как устройства») + tag «сервер отсюда подключён» if the current node is not own and `node.group == item.name`;
  - small line: `host` (digits mono) · «N сервер/сервера/серверов» · «обновлено <ago(ts)>» (if ts);
  - meta: «осталось **N дн.**» (err if ≤ 3; `left = floor((expire − now)/86400)`, only if `expire > 0`; `left < 1` → «закончилась» **(proposed, as the Summary verdict)**), «израсходовано **X** из Y» or «израсходовано **X** · без лимита» (only if `up + down > 0`); expiry date «до 31 октября» (`dayMonth`) **(proposed, mock-up)**;
  - progress bar when `total > 0`: `pct = min(100, round(used/total·100))`, tone acc / warn ≥ 65 / err ≥ 85.
- Button «Обновить» per item → `subupdate {"sid": id}` (428 high). For the synthetic item (`id == ""`) send `{"all": true}`.
- Card button «Обновить все» **(proposed)** → `subupdate {"all": true}` (428 «Обновить подписки VPN?»). (Stage 3 Summary «Обновить подписки» uses the `update` action; both are fine.)
- No add / delete (plan §2 «Чего не будет»). Footer **(proposed)**: «Добавить или удалить подписку можно в веб-панели.»
- `subs == []` and `sub == nil` → «Подписок нет. Добавить подписку можно в веб-панели.» **(proposed)**

#### 5.1.8 Router speed test
- Two cards «С роутера, через VPN» and «С роутера, без VPN» (index.html:206, 215). Values from `status.speed.vpn/direct` (port of `renderSpeedCard`, app.js:577-586):
  - «Загрузка» `speed(down)`; «Отдача» `up > 0 ? speed(up) : (up_limited ? «позже» : «—»)`; «Задержка» `latency > 0 ? «N мс» : «—»`;
  - meta: «Выход: <flag(country)><ip>, » (if ip) + «проверено <ago(ts)>» + « · <server>, <streams> потока» + (`up == 0 && up_limited`: « · Cloudflare ограничил частые замеры отдачи, повтори через пару минут»);
  - `flag(cc)`: `^[A-Z]{2}$` → regional indicator symbols (U+1F1E6 + letter − «A») + space; else "";
  - nil → «Ещё не запускали.»
- Button «Запустить» on each card → speedtest job (§3.5); **no dialog**. While any long job runs (this app's ping or speedtest) both buttons are disabled; busy label «Идёт тест, ~35 сек…» (app.js:934).
- Caption under the cards (plan §2, proposed wording): «Тест займёт интернет дома примерно на 35 секунд. Тест через VPN тратит трафик подписки. Загрузка «напрямую» — с Selectel (Россия), «через VPN» — с Hetzner (Германия), отдача — на Cloudflare.»
- History chart «История загрузки, Мбит/с» (port of `renderSpeedHist`, app.js:588-601) from `data.speed` (90 days): x from the oldest row to now (span ≥ 86 400); y `0 … max(down) × 1.15`; one line + square points per via (`vpn` = acc, `direct` = info); legend «через VPN», «напрямую»; tooltip «через VPN: <speed>, <when>»; caption «<when(oldest)> · до N Мбит/с»; empty → «История появится после первых тестов». Optional second toggle «Отдача» **(proposed)**.

#### 5.1.9 Own servers (`/vds`, read-only)
- Title «Свои серверы» **(proposed)**; one row per `servers[]` (port of `cmd_vds`, tgbot.php:225-240):
  - title `name`; `local` → caption «Здесь же панель»;
  - `stat == nil` → err dot + «не отвечает по SSH»;
  - else: Xray line: `xray == "active"` → ok «VPN (Xray) работает» else err «VPN (Xray): <xray or «не запущен»>»; « · соединений <conns>»;
  - «Нагрузка <load> на <cores> ядр. · память <round((mem_total−mem_avail)/mem_total·100)>% из <mem_total/1048576 with 1 decimal> ГБ · диск <disk>»;
  - «Без перезагрузки <upt(up)> · трафик с запуска ↓<bytes(rx)> ↑<bytes(tx)>».
- Footer: `now − ts < 90` → «Данные свежие.» else «Данные <floor(age/60)> мин назад.»; `ts == nil` → «Данных о серверах пока нет — они собираются раз в 5 минут.» (tgbot.php:228).
- No actions. Works offline.

### 5.2 Устройства
Port of `renderDevices` (app.js:436-458) with plan §2 changes.

#### 5.2.1 Header, search, filter
- Summary line: list == all → «<online> в сети из <all>» else «найдено <n> из <all>» (app.js:449).
- `.searchable` prompt **(proposed)** «Имя, IP или MAC». Match (case-insensitive substring) on `devName(d)`, `d.name`, `d.ip`, `d.mac` (app.js:447).
- Filter (segmented): «Все» / «В сети» / «Не в сети» / «Ограничены» (index.html:293); «Ограничены» = `blocked || sblocked || sched != nil || direct` (app.js:446).
- Persist filter in `@SceneStorage` (UI state only).

#### 5.2.2 Groups (online first)
| Section | Devices | SF Symbol |
|---|---|---|
| «Wi-Fi 5 ГГц» | online, band `5g` or `6g` | `wifi` |
| «Wi-Fi 2,4 ГГц» | online, band `2g` | `wifi` |
| «По кабелю» | online, any other band (incl. `wired` and missing) | `cable.connector` |
| «Не в сети» | `!online` | `wifi.slash` |
- Section header shows the count. Empty sections are hidden. Sort inside: by `devName` with unnamed last (app.js:440 sorts «я» for empty), `localizedStandardCompare`.
- «Не в сети» is **collapsed** (`DisclosureGroup` «Не в сети: N») unless the filter is «Не в сети» or the search is non-empty, then expanded (app.js:455-456).
- Empty: list empty but devices exist → «Ничего не найдено — измени поиск или фильтр.»; no devices → «Устройства не найдены: роутер пока никому не выдал адрес.» (app.js:457).

#### 5.2.3 Row
- Leading: online dot (acc) / hollow (faint).
- Title: `devName(d)` or «Без имени».
- Labels (capsules), in this order (app.js:425-426): «без интернета» (err) if `blocked`; else «по расписанию» (err) if `sblocked`; «мимо VPN» (info) if `direct`; schedule `timer` + «23:00–07:00» (faint) if `sched` and not `sblocked`. The band label is not shown (the section says it).
- Subtitle: `ip` · «скрытый MAC» if `hiddenMac(mac) && devName(d) == ""` · rate «866 Мбит/с» if `rate > 0` (app.js:427; the MAC is shown in the card, not in the row).
- Trailing: Wi-Fi signal (`wifi` with `variableValue`) only if online and band ≠ `wired` (accessibility label «Сигнал −51 dBm»); today's traffic «↓ 1,5 ГБ» from `traffic[mac].d[1]` with small «сегодня» (only if the entry exists).
- Tap → device card (push or sheet). No swipe actions.

#### 5.2.4 «Новые за неделю» (top, plan §2)
- Source `data.newdevs` (already 7 days, newest first); dedupe by MAC (keep newest).
- Row: name (`devName` of the matching `status.devices` entry, else `names[mac]`, else «Без имени») · «<when(ts)>» (e.g. «вчера 21:44») · «Открыть» → device card. If the MAC is not in `status.devices` (lease gone) show the MAC and open a card with only MAC, traffic and rename.
- Hidden when empty. Section title «Новые за неделю». Up to 5 rows + «Ещё N» expander **(proposed)**.
- Tab badge (optional): count of newdevs with `ts` > the last time the user opened the Devices tab (`@AppStorage("devicesSeenAt")`, an Int timestamp; not router data).

### 5.3 Device card
#### 5.3.1 Fields
| Row | Value |
|---|---|
| title | `devName(d)` or «Без имени»; if an own name is set and `d.name` differs and is non-empty: caption «Имя в сети: <d.name>» **(proposed)** |
| status | online: «В сети · Wi-Fi 5 ГГц» / «В сети · Wi-Fi 6 ГГц» / «В сети · Wi-Fi 2,4 ГГц» / «В сети · кабель»; offline: «Не в сети» |
| IP | `ip` |
| MAC | full lowercase `mac`; if `hiddenMac(mac)`: caption «Скрытый MAC: телефон сам придумал этот адрес для приватности. Он может измениться.» **(proposed)** |
| Сигнал | Wi-Fi only: «−51 dBm · 866 Мбит/с» (signal 0 → «—»; use U+2212 minus) |
| Сегодня | `traffic[mac].d`: «↓ 1,5 ГБ · ↑ 50 МБ» |
| За месяц | `traffic[mac].m`: «↓ 27,0 ГБ · ↑ 700 МБ» |
| Интернет | «Есть» / «Выключен» (`blocked`) / «Выключен по расписанию» (`sblocked`) |
| Через VPN | «Да» / «Мимо VPN» (`direct`) |
| Расписание | «23:00–07:00» or «Нет» |
- Footer caption (plan §2): «Трафик считает сервер раз в минуту. Учитывается только обычный интернет устройства: Telegram через Cloudflare в нём не виден.»
- Device not in `status.devices` (only in newdevs/names): show MAC, traffic, rename; no other actions.

#### 5.3.2 Actions
| Button | When shown | Request | Dialog |
|---|---|---|---|
| «Переименовать» (`pencil`) | always | `rename` | **no dialog**; a sheet with a `TextField` (prefill `names[mac] ?? d.name`, placeholder `d.name` or «Имя устройства», limit 40 characters as typed, strip control characters) and **only** a «Сохранить» button (no save on dismiss/blur). Footer: «Пустое имя — как называет себя устройство.» (app.js:506). Empty → sends `""` (removes the own name). Works offline |
| «Выключить интернет» (`nosign`, destructive) | `!blocked` | `block {mac}` | 428 high, **red** button, no Face ID |
| «Включить интернет» (`checkmark`) | `blocked` | `unblock {mac}` | **no dialog**. If `sblocked` (window active) after 200 show **(proposed)**: «Сейчас идёт окно расписания — интернет вернётся после его конца или когда уберёшь расписание.» |
| «Пускать мимо VPN» / «Снова через VPN» | `!direct` / `direct` | `direct {mac, on: !direct}` | 428 high |
| «Расписание…» / «Расписание: 23:00–07:00» | always | sheet §5.3.3 | |
- Every router action is disabled in offline mode, during another running action, and (for `direct`) during the PW lock-out.
- Show the newest local state immediately after 200 (§3.7) and re-read `/status` as §3.2 says.

#### 5.3.3 Schedule sheet (plan §2; web `sched-dlg`, index.html:335-340)
- Title «Расписание: <nm>»; text: «В это время у устройства не будет интернета — каждый день. Можно через полночь, например 23:00 → 07:00.» + caption «Время роутера (Самара, UTC+4).»
- Two 24-hour time pickers «Выключать в» / «Включать в», default from `sched` or 23:00 / 07:00 (app.js:529). Use `DatePicker(.hourAndMinute)` with `TimeZone(identifier: "Europe/Samara")` and `Locale("ru_RU")`, or two wheels; send `HHMM` (zero-padded).
- «Сохранить» (disabled when off == on; inline text «Укажи разное время выключения и включения.», app.js:540) → `schedule {mac, off, on}` → 428 medium.
- **Window active now** (port of `fspirat-fw:284`, minute resolution in Samara time): `n = HHMM now` as int, `f = off`, `t = on`; active = `(f < t && n >= f && n < t) || (f > t && (n >= f || n < t))`. If active → the extra warning line and red button in the 428 dialog (§3.3).
- «Убрать расписание» (shown only if `sched` exists) → `schedule {mac, off:"", on:""}` — **no dialog** (plan §2).
- «Отмена» closes.

### 5.4 Обход
Sections: zapret · Telegram через Cloudflare · Сервисы напрямую · Сайты без VPN (MyDirect).

#### 5.4.1 zapret (YouTube и Discord без VPN) — port of `renderZap`, app.js:968-1005
State → presentation (`z` = `/zapret`):

| State | Condition | Summary line | Controls |
|---|---|---|---|
| not loaded | no successful read yet | placeholder «Загружаю…» | hidden |
| absent | `z.absent == true` | **(proposed)** «zapret на роутере не установлен.» | hidden |
| not installed | `!z.installed` | error box: «zapret не установлен на роутере (нет nfqws, списков или модуля ядра).» (app.js:994) | toggle, strategy, check disabled |
| busy | `z.busy` | «Применяю… PassWall перезапускается» (mid dot) | toggle and strategy disabled; poll 3 s |
| on, working | `enabled && engine && nft && route_live` | ok dot: «YouTube и Discord — **напрямую**, с IP провайдера» + small «<pkts_tcp> TCP · <pkts_udp> QUIC» | enabled |
| on, partial | `enabled && !(engine && nft && route_live)` | mid dot: «Включён, но работает не полностью» | enabled |
| off | `!enabled` | off dot: «YouTube и Discord — через VPN, как всё остальное» | enabled |

Error box (one, first match; app.js:993-998): `!installed` → text above; else `z.error` non-empty → `z.error` verbatim (includes fallback «… — YouTube и Discord временно идут через VPN»); else `!busy && enabled && !work` → «Расхождение: режим включён, но » + join(«, »)[«служба не работает» if !engine, «нет правил nftables» if !nft, «маршрут PassWall не применён» if !route_live] + «. Сторож попробует исправить в течение минуты.»; else `!busy && !enabled && (engine || nft || route_cfg)` → «Расхождение: режим выключен, но часть правил ещё активна. Сторож уберёт их в течение минуты.»

Details (`DisclosureGroup` «Подробнее», app.js:985-992): «Выбрано» включить/выключить; «Служба nfqws» работает / не работает (on) / остановлена (off); «Правила nftables» есть/нет; «Маршрут» «напрямую (IP провайдера)» / «через VPN»; «Обработано пакетов» (if nft); «Версия» `version` (if non-empty, proposed).

Controls:
- **Toggle** (`Toggle` bound to a proposed state, never flipped before 200): `zapretset {"on": !enabled}` → 428 high. Disabled when `!installed || busy`, offline, PW lock-out. After 200: §3.7.
- Caption under the toggle (mock-up): «Включение и выключение перезапускают VPN на несколько секунд.» **(proposed)**

#### 5.4.2 Strategy
- Segmented «1» «2» «3» (labels in a menu or footnote: «1 · multisplit», «2 · fake + fakedsplit», «3 · hostfakesplit», index.html:148-150); selected = `z.strategy`. Disabled when `!installed || busy`.
- Tap → `zapretstrat {"n": n}` — **no dialog** (plan §2).
- **Verify applied (plan: «приложение потом проверит, что она применилась»):** after 200 read `/zapret` at +2 s, +4 s, +7 s (stop early on success). Success = `strategy == n && !busy` → toast «Стратегия N выбрана.». If after the last read `strategy != n` → toast (error) **(proposed)** «Стратегия не применилась — роутер был занят. Попробуй ещё раз.» and show the real `strategy`. If `error` changed to «nfqws отклонил параметры стратегии N» → show it in the error box. Keep the segmented control showing the **server** value, with a spinner while verifying.

#### 5.4.3 Check YouTube и Discord
- Button «Проверить YouTube и Discord» (plan §2; web label «Проверить») — `zapretcheck {}` — **no dialog**. Disabled when `!installed || checking`, offline. Label while checking «Проверяю…».
- 200 → set `checking = true` locally and poll 3 s (≤ 2 min) until `!checking`. `409 busy` from the router (`source: "router"`) = a check already runs → treat as success (start polling, no toast). 429 → message with countdown.
- Results (`check.list`): one tile per item: name, `ok` → «<ms> мс» (ok tone) else «нет» (err); accessibility/footnote: ok with `queued > 0` → «обработано zapret: N пак.», ok without → «без обработки zapret», not ok → «не открывается» (app.js:1001).
- Caption: «Проверено <when(check.ts)>» + (`via == "isp"` → « · Discord видит IP провайдера»; `"vpn"` → « · Discord видит IP VPN»; else nothing) (app.js:1004). `check == {"error":"xray"}` → **(proposed)** «Проверка не удалась: VPN (Xray) не был запущен.» `check == nil` → no results block.
- `ms` is the full request time (connection + TLS + response), not a ping: label the tiles «время ответа» **(proposed)**.

#### 5.4.4 Telegram через Cloudflare (`/tgws`) — port of `renderTgws`, app.js:1036-1046
- Own card, shown independently of zapret (plan §2). Title «Telegram через Cloudflare» + tag «экспериментально».
- `absent` or `!installed` → **(proposed)** «Telegram-прокси на роутере не установлен.», toggle hidden. (The web hides the whole block.)
- Summary line: `!enabled` → «Выключен — Telegram идёт как обычно (через VPN)»; `enabled && running && listening && auto` → «Telegram на всех устройствах дома — **через Cloudflare, мимо VPN**, без настройки» + small «<redirected> подкл.»; `enabled && running && listening && !auto` → «Прокси работает, перехват ещё не включён (сторож включит в течение минуты)»; `enabled` otherwise → «Запускается… Пока прокси не работает, Telegram идёт через VPN».
- Toggle → `tgwsset {"on": !enabled}` → 428 **medium** (normal button). Not PW. After 200: re-read at +3 s and +8 s; if after +8 s `enabled` still differs → **(proposed)** «Роутер не переключил прокси Telegram — попробуй ещё раз.» (tgwsset failures are silent on the router).

#### 5.4.5 Сервисы напрямую (svcdirect) — port of app.js:276-281, 658-667
- Rows = `services()` (needs `status`); per row: service icon + name + host (caption) + `Toggle` (on = `svc_direct.contains(name)`).
- Caption per kind **(from app.js:662)**: web → «Домен <host> добавится в MyDirect.»; mc → «IP сервера добавится в MyDirect — игра пойдёт без VPN, пинг станет как «Напрямую».»
- Toggle → `svcdirect {"name": name, "on": !current}` → 428 high. Disabled offline, during PW lock-out, while an action runs.
- Client validation: `name.utf8.count` 1…40 and none of `\x00-\x1f \x7f ~ ! " < > & \ |`; a target list name that fails (set via the web editor) → disable its toggle with caption **(proposed)** «Это имя нельзя изменить из приложения.»
- Empty (`services()` empty) → «Список сервисов пустой — его можно задать в веб-панели.» **(proposed)**
- Errors: `400 no target` (stale list → re-read `/status`), `400 resolve` (mc), `500 no rule`.

#### 5.4.6 Сайты без VPN (MyDirect) — port of app.js:604-636
- Header «Сайты без VPN» + count «<domains.count> записей» (app.js:610; use `plural(n,"запись","записи","записей")`).
- **Добавленные** (`added`, from the panel or the app): row domain + «Убрать» button (no swipe). Empty: «Пока ничего — добавь сайт ниже.» (adapted from app.js:613).
- **Весь список** (`DisclosureGroup` «Весь список (N)»): read-only; search field «Найти домен…» (index.html:264): with a query → all `domains` containing it (case-insensitive); without → plain domains only (no `^[a-z]+:` prefix); show the first 60 + «…и ещё N. Уточни поиск.» (app.js:615-617); nothing → «Не найдено.». Rows that are also in `added` show the «добавлен» tag **(proposed)**; prefixed entries (`geosite:` …) are shown as is, never removable.
- **Add** («Добавить сайт»): text field placeholder «пример: gosuslugi.ru», `.keyboardType(.URL)`, no autocapitalization/autocorrection. Normalize (app.js:622): trim → lowercase → remove `^https?://` → remove `/.*$` → remove `^www\.`. Validate with the **server** regex (§3.2) and ≤ 100 bytes; else inline «Нужен домен вида site.ru». Already in `domains` → **(proposed)** «Этот сайт уже в списке.» without a request. Cyrillic domains (`.рф`) fail the regex → same «Нужен домен вида site.ru» (punycode is not supported).
  Then `diradd {"d": d}` → 428 high; 200 → clear the field, §3.7, re-read `/mydirect`.
- **Remove**: only for `added` items → `dirdel {"d": d}` → 428 high with **red** button. The server double-checks `added` (`400 bad_param` «Убрать можно только домены, добавленные из панели или приложения.», *observed*).
- Errors: `/mydirect` `500 no rule` → the card shows the message instead of the lists; add/remove disabled.

### 5.5 Журнал
Port of `events()` / `renderLog()` (app.js:397-414) with plan §2 additions.
- Header caption: «Время роутера (Самара, UTC+4)» (mock-up).
- Range segmented «24 ч» / «7 дн» / «30 дн» (own state, default `day`); source `data[range].events`.
- Level filter segmented «Все» / «Ошибки» / «Внимание» / «Действия» (index.html:309). Mapping (`LEVEL`, app.js:395, stage 3 §2.9): err = `offline, vpn_down`; warn = `auto, xraymem, reboot, newdev`; ok = `online, vpn_up`; info = everything else. Filter «Действия» shows **info and ok** (app.js:410 — successes are listed with actions).
- Search `.searchable` «Поиск в журнале» **(proposed)**: case-insensitive substring of the displayed text, or of the formatted time `when(ts)` (app.js:411).
- Text: replace `\b_direct\b` → «Напрямую (без VPN)» (already done by the watcher, keep the guard).
- **Grouping by Samara calendar day**: «Сегодня», «Вчера», else «12 октября» (`d MMMM`, `ru_RU`, Samara); add the year («12 октября 2025») when not the current year. Row time `HH:mm`.
- Row: level icon/dot + chip word (err «Ошибка», warn «Внимание», ok «Успех», info «Действие» — colour **and** word, stage 3 §4.10) + text (wraps, `.lineLimit(nil)`). Optional kind icons **(proposed)**: offline `wifi.slash`, online `wifi`, vpn_down `xmark.shield`, vpn_up `checkmark.shield`, auto `arrow.triangle.2.circlepath`, manual `hand.tap`, restart `arrow.counterclockwise`, update `arrow.down.circle`, reboot `power`, newdev `plus.circle`, xraymem `memorychip`, router `gearshape`.
- Optional MAC → name substitution for `router`/`newdev` texts **(proposed)**: for each `([0-9a-f]{2}:){5}[0-9a-f]{2}` (case-insensitive) with `names[mac]` set, append « (<name>)» after the MAC. Never replace the MAC.
- Count line (app.js:413): no filter → «N запись/записи/записей»; filtered → «найдено F из N». Web caps the list at 200; the server never sends more than 100, so no cap is needed.
- **Limit notice** (plan §2): when `events.count >= 100` → footer **(proposed)**: «Сервер отдаёт не больше 100 последних событий за период — более ранние сюда не попали.» For `month` always add **(proposed)**: «За 30 дней список может быть неполным.»
- Empty: no events → «Событий пока нет. Здесь появятся смены сервера, перезагрузки, сбои VPN и новые устройства.»; filtered empty → «Таких записей нет.» (app.js:407, 412).
- Works offline (server data). `status.log` is **not** used here (inventory §6: its lines reach `events.tsv` anyway).

### 5.6 Настройки (sheet; replaces stage 3 §7.9)
Sections in order (mock-up `Settings.dc.html` order):

#### 5.6.1 Защита
- «Face ID при открытии» (toggle) — stage 3.
- «Блокировать» — «Сразу» / «Через 1 минуту» / «Через 5 минут» — stage 3.
- «Face ID для опасных действий» (toggle, default on) — footer **(proposed)**: «Спрашивается перед «Напрямую, без VPN», перезагрузкой роутера и «Выйти везде».»
- **NEW** «Скрывать в переключателе приложений» (toggle, default **off**) — §1.3.
- The method name follows `BiometricGate.methodName` (Face ID / Touch ID / код-пароль), as stage 3.

#### 5.6.2 Этот телефон
Stage 3 (`/me`): name; «Вход до <dayMonth(expires)>»; «Не дольше <dayMonth(hard_expires)>»; 14-day warning.

#### 5.6.3 Доступ к роутеру (`/devices`)
- **Телефоны** (`apps`): row: `name` (or «Телефон»), caption joined by « · »: `model`, os (`osTxt`: if it starts with a digit → «iOS » + os, app.js:1089), «приложение <app>» if non-empty; meta: «был в сети <seenTxt(seen)>» (`seen` within 1 h → `ago`, else `when`, app.js:1088), «IP <last_ip>», «вход до <dayMonth(expires)>» (err if `expires − now < 7·86400`, app.js:1108). `current` → tag «этот телефон» and no «Отозвать».
  - «Отозвать» (destructive, small) → app dialog (texts from app.js:1119-1120): title «Отозвать доступ «<nm>»?», text «Приложение на этом телефоне сразу выйдет и больше не сможет управлять роутером. Вернуть доступ — войти в приложении заново: пароль и подтверждение в Telegram. Бот пришлёт сообщение об отзыве.», button «Отозвать» (red); no Face ID → `POST /devices/revoke {"id": id}`.
- **Браузеры** (`web`): row: browser/OS summary from `ua` **(proposed parser: «Chrome · Windows», «Safari · iPhone», fallback the first 40 chars)**, «IP <ip>», «был <seenTxt(seen)>», «вход <when(created)>». «Закрыть» → app dialog **(proposed)**: title «Закрыть сессию веб-панели?», text «Браузер с IP <ip> выйдет из панели. Если он запомнен, при следующем входе код из Telegram не спросят.» (sessions are closed, remembered browsers stay), button «Закрыть» (red) → `POST /devices/revoke {"web_ref": ref}`.
- Empty phones → «Приложение ещё ни на одном телефоне не входило.» (app.js:1114); empty web → «Открытых сессий веб-панели нет.» **(proposed)**

#### 5.6.4 Журнал входов
- Two lists (push screen «Журнал входов»):
  - «Входы в приложение» (`logins`): `when(ts)` · `name` · «IP <ip>» · result word **(proposed)**: `pending` «ждёт числа в боте», `approved` «одобрен, ключ ещё не забран», `issued` «вошёл», `expired` «время вышло», `denied` «неверное число», `notme` «нажато «Это не я»», `cancelled` «отменён в приложении»; levels: issued ok, denied/notme err, others faint.
  - «Все входы и выходы» (`auth_log`): `when(ts)` · word **(proposed)** · «IP <ip>»: `OK` «Вход в веб-панель» (ok), `FAIL` «Неверный пароль или код» (warn), `LOCKED` «Вход закрыт после ошибок» (err), `CODE` «Пароль верный, код отправлен в Telegram» (info), `CODEFAIL` «Код в Telegram не отправился» (warn), `LOGOUT` «Выход из веб-панели» (info), `LOGOUT_ALL` «Выход на всех устройствах» (info), `APP_LOGIN` «Приложение: пароль верный, ждёт числа в боте» (info), `APP_OK` «Вход в приложение» (ok), `APP_DENIED` «Приложение: вход отклонён в боте» (err), `APP_REVOKE` «Доступ приложения отозван» (info), `APP_BADTOKEN` «Приложение: неверный ключ» (warn), `APP_URLTOKEN` «Ключ попал в адрес запроса» (err); unknown → the raw code (info).
- Times in Samara (as everywhere).

#### 5.6.5 Выход
- «Выйти на этом iPhone» — stage 3 dialog (no Face ID).
- «Выйти везде — телефоны и браузеры» (destructive): a sheet with the toggle «Также закрыть все сессии веб-панели» (default off) and a «Продолжить» button → `POST /devices/revoke-all {"web": bool}` → 428 **critical** (red, Face ID) → resend → 200 → LOGOUT with the banner of §3.4.

#### 5.6.6 Тема, ссылки, о приложении
- Тема — stage 3 («Как в системе» / «Светлая» / «Тёмная»).
- Ссылки — stage 3 (web panel; LuCI from `site.luci` if `^https://[\w.-]+(:\d+)?/?$`; bot `https://t.me/<site.bot>` if `^[A-Za-z0-9_]{5,32}$`), open in Safari. Caption for LuCI: «откроется в Safari со своим входом» (plan §2).
- О приложении — stage 3 (version/build, build expiry line only for TestFlight builds) + «Время — роутера (Самара, UTC+4)».

---

## 6. Errors (new codes and stage 4 overrides)
Stage 3 §3 is normative (show the server `message` verbatim when present; LOGOUT only for the four `token_*` codes). Codes that become reachable in stage 4:

| HTTP | `error` | Where | Server `message` | Client behaviour |
|---|---|---|---|---|
| 400 | `bad node` (router) | pingone, switch | «Такого сервера нет — обнови список.» | show; re-read `/status` |
| 400 | `bad mac` (router) | block/unblock/direct/schedule | «Неверный адрес устройства (MAC).» | show (cannot happen with valid input) |
| 400 | `time` (router) | schedule | «Неверное время.» | show |
| 400 | `domain` (router) | diradd/dirdel | «Нужен домен вида site.ru.» | show |
| 400 | `no target` (router) | svcdirect | «Нет такого сервиса.» | show; re-read `/status` |
| 400 | `resolve` (router) | svcdirect (mc) | «Не удалось узнать IP сервера.» | show |
| 400 | `bad sub` (router) | subupdate | «Нет такой подписки — обнови список.» | show; re-read `/status` |
| 400 | `bad on` / `bad strategy` / `bad via` (router) | — | dictionary | cannot happen with valid input |
| 400 | `bad_param` with a **special message** | dirdel not in `added` | «Убрать можно только домены, добавленные из панели или приложения.» | show; re-read `/mydirect` |
| 400 | `too_long` | rename | «Слишком длинное значение.» | show under the field |
| 400 | `confirm_invalid` | any 428 resend | «Подтверждение не подошло — повтори действие.» | show; nothing happened |
| 404 | `not_found` | revoke | «Не найдено.» | toast «Этого входа уже нет — список обновлён.» **(proposed)**; re-read `/devices` |
| 409 | `busy` (server action lock) | any action | «Другое действие ещё выполняется — подожди немного.» | show, re-enable |
| 409 | `busy` (job lock) | speedtest/ping start | «Тест скорости или проверка уже идут — дождись результата.» (speedtest) / «Проверка или тест скорости уже идут — дождись результата.» (ping) | show |
| 409 | `busy`, `source:"router"` | **zapretset** | generic busy text | show **(proposed, inventory §9.1)** «zapret сейчас занят другим действием — повтори через несколько секунд.» |
| 409 | `busy`, `source:"router"` | **zapretcheck** | generic | treat as «проверка уже идёт»: start polling, no error |
| 409 | `busy`, `source:"router"` | **speedtest job** (`http:409` in the job) | generic | show «Тест скорости уже идёт — дождись результата.» **(proposed, app.js:111)** |
| 409 | `busy`, `source:"router"` | ledset | generic | stage 3 |
| 429 | `rate_limited` | any | «Слишком часто — подожди немного.» + `retry_after` | §3.6 |
| 500 | `nft` (router) | block/unblock | «Роутер не смог изменить правила.» | show |
| 500 | `no rule` (router) | mydirect/diradd/dirdel/svcdirect | «В PassWall нет правила MyDirect.» | show; on Bypass replace the MyDirect lists with the message **(and add «Проверь правило MyDirect в LuCI.» — proposed, inventory §9.1)** |
| 500 | `subscribe.lua not found` (router) | subupdate | «На роутере нет скрипта подписок PassWall.» | show |
| 503 | `not installed` (router) | zapretset/zapretstrat/zapretcheck/tgwsset | «Не установлено на роутере.» | show; re-read the state |
| 502/504 | `router_offline` / `router_timeout` | reads of zapret/tgws/mydirect | stage 3 | keep last data; **do not** enter offline mode (only `/status` does) |

All router error bodies carry `"source":"router"`; any other router code → server text «Роутер не смог выполнить действие.» (stage 3 §3.2).

---

## 7. Formatting (stage 4 additions; see §9 for the changed decimal rule)
| Function | Rule | Examples |
|---|---|---|
| `nodeDisplayName(name)` | trim spaces | «🇳🇱 Нидерланды» |
| `sortKeyName(name)` | drop leading `[^\p{L}\p{N}]+`, trim, lowercase | «🇳🇱 Нидерланды» → «нидерланды» |
| `flag(cc)` | `^[A-Z]{2}$` → regional indicators + space | «NL» → «🇳🇱 » |
| `signalText(dbm)` | `dbm != 0` → «−51 dBm» (U+2212) else «—» | |
| `bandText(band)` | `5g` «Wi-Fi 5 ГГц», `6g` «Wi-Fi 6 ГГц», `2g` «Wi-Fi 2,4 ГГц», `wired` «кабель» | |
| `schedText("2300-0700")` | «23:00–07:00» (en dash) | |
| `seenTxt(ts)` | `now − ts < 3600` → `ago(ts)`, else `when(ts)`; 0 → «—» | |
| `osTxt(os)` | starts with a digit → «iOS » + os | «18.1» → «iOS 18.1» |
| `dayLabel(ts)` | Samara: same day «Сегодня», previous «Вчера», else `d MMMM` (+ « yyyy» if another year) | «11 октября» |
| `msShort` in event texts | `(\d+)ms\b` → «$1 мс» (display only, proposed) | «41ms» → «41 мс» |
| `vdsMem(x)` | `round((mem_total−mem_avail)/mem_total·100)` + «% из » + `fixed1(mem_total/1048576)` + « ГБ» | «35% из 1,9 ГБ» |
| `count(n, …)` | `plural`: подписка/подписки/подписок, сервер/сервера/серверов, запись/записи/записей | |

---

## 8. Liquid Glass style (owner decision 2)
Goal: «плюс-минус в стиле Liquid Glass» on iOS 26, while the deployment target stays **iOS 17**. Every iOS 26 API below was checked in the Apple documentation JSON (introduced iOS 26.0 unless noted):

| API | Declaration |
|---|---|
| `glassEffect(_:in:)` | `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View` |
| `Glass` | `.regular`, `.clear`, `.identity`; `.tint(_ color: Color?)`, `.interactive(_ isEnabled: Bool = true)` |
| `GlassEffectContainer` | `init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)` |
| `glassEffectID(_:in:)` | `func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View` |
| `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` | `GlassButtonStyle` / `GlassProminentButtonStyle` |
| `tabBarMinimizeBehavior(_:)` | `.automatic`, `.never`, `.onScrollDown`, `.onScrollUp` |
| `scrollEdgeEffectStyle(_:for:)`, `backgroundExtensionEffect()`, `tabViewBottomAccessory(content:)` | available, optional |
| `Tab` (struct) | **iOS 18** — not used (target 17) |
| `tabItem(_:)` | iOS 13; `deprecatedAt: 27.2` → fine with SDK 26.5 |
| `UIDesignRequiresCompatibility` (Info.plist) | iOS 26; **must not be set to YES** (it would turn Liquid Glass off). `project.yml` does not set it — keep it that way |

Rules:
1. **One helper**, e.g. `View.glassCard(tint: Color? = nil, interactive: Bool = false, radius: CGFloat = 24)`:
   - `if #available(iOS 26.0, *)`: `.glassEffect(g, in: RoundedRectangle(cornerRadius: radius, style: .continuous))` where `g = tint.map { Glass.regular.tint($0.opacity(0.18)) } ?? Glass.regular`, plus `.interactive()` on `g` when the card is tappable;
   - else: `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))` + 0.5 pt stroke (`border` token at 60 % opacity);
   - `@Environment(\.accessibilityReduceTransparency)` on the fallback path → opaque `card` token instead of the material (iOS 26 glass adapts by itself).
2. **Navigation chrome is system glass:** `TabView` tab bar, `NavigationStack` large titles, toolbar buttons (the gear), `.searchable` fields, sheets with partial detents, `.confirmationDialog`/alerts. Do **not** paint opaque backgrounds on them (no `toolbarBackground(.visible)` with opaque colours, no `presentationBackground` on sheets). iOS 26: `.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView`.
3. **Backdrop:** each tab's scroll view sits on `Theme.bg` plus a soft, static gradient so glass has something to refract **(proposed)**: two blurred radial blobs — top-leading `acc` at 0.14 opacity (dark) / 0.10 (light), bottom-trailing `info` at 0.10 / 0.07. The verdict level may tint the top blob (err → `err` at 0.12). Static (no animation), `ignoresSafeArea()`.
4. **Cards** = one `glassCard` per section (radius 24). Rows inside a card are plain (no glass on glass); separators in the `line` token. Long lists (devices, journal, MyDirect) use `List`/`LazyVStack` sections where the section container is the glass card — **never** a glass effect per row (performance).
5. **Status tint:** the Summary verdict card and the offline banner use `glassCard(tint: level colour)`; the zapret/tgws summary lines use the level dot + text colour only.
6. **Buttons:** primary → `.buttonStyle(.glassProminent)` + `.tint(Theme.acc)`; secondary → `.buttonStyle(.glass)`; destructive → `.glassProminent` + `.tint(Theme.errFill)` (white label); all `.buttonBorderShape(.capsule)`, min height 44 pt. iOS 17–25: the stage 3 `ButtonStyles` (radius → capsule).
7. **Chips / segmented filters / «Лучший сервер» chips:** capsules with `.glassEffect(.regular.interactive(), in: Capsule())` inside a `GlassEffectContainer(spacing: 8)` (iOS 26); selected chip `Glass.regular.tint(acc.opacity(0.35))`. Standard `Picker(.segmented)` is fine where a system segmented control fits (ranges, filters).
8. **Shapes:** cards 24, tiles inside cards 16, chips and buttons capsule, sheets system. Replaces the stage 3 radii table (cards 14, tiles 10, buttons 8).
9. **Colours:** status/text tokens of stage 3 §6 stay (`text`, `dim`, `faint`, `acc`, `warn`, `err`, `info` and their `-soft`/`-bd`). `card`/`surface`/`raise` become fallback-only. Check contrast of `dim`/`faint` on glass in both themes (Light: use `dim` for captions, never `faint` for text that matters).
10. **Motion:** use `glassEffectID` + `@Namespace` only for the mode switch («Через VPN» / «Напрямую») morph (optional). Respect Reduce Motion (no morphs, no pulsing).
11. **Charts** sit inside glass cards; grid in `chart-grid`; no glass inside charts.
12. **App icon / launch:** unchanged.

---

## 9. Summary fixes (owner decision 4) — replaces stage 3 §5 «Numbers use a `.` decimal separator» and the font line of §6
1. **Monospaced digits only.** No `design: .monospaced` anywhere in the UI. Numbers use the system font with `.monospacedDigit()` (tabular digits, proportional letters):
   - replace every `.font(.system(<style>, design: .monospaced[, weight:]))` with `.font(.system(<style>, weight: <same>).monospacedDigit())` — current places: `Router/Views/Summary/VerdictCards.swift:162`, `RouterCards.swift:56,129,169,181,225`, `HistoryChartCard.swift:223`, `ServerCards.swift:41,89,126,129,160`, `Components/Card.swift:203`;
   - this fixes the wide gaps in «9 в сети», «64 мс», «осталось 17 дн.»;
   - IP and MAC also use `.monospacedDigit()` (no mono design).
2. **Russian decimal comma.** `Format.fixed1` returns `"9,2"` (comma), so: `speed` «18,7 Мбит/с», `mb`/`bytes` «9,2 ГБ», «3,4 МБ», «0,0 МБ», the subscription line «израсходовано 39,2 ГБ из 200,0 ГБ», `/vds` «1,9 ГБ». Integers, percents, times («14:20»), dates, IPs, versions are unchanged. `sys.load` (router string «0.21 0.17 0.15») is displayed with commas «0,21 0,17 0,15» **(proposed)**. Update `FormatTests`/`SummaryTests` expectations accordingly (stage 3 §5 examples and §8.1/§8.5 expected strings change only in the decimal separator).
3. **No line break between a number and its unit:** formatters put U+00A0 (NBSP) between the number and the unit («64 мс», «18,7 Мбит/с», «9,2 ГБ», «17 дн.», «9 в сети», «3 из 5»). Tests compare with `\u{00A0}`.
4. **«Проверка через VPN · Задержка» must not wrap awkwardly** (`ServerCards.swift:30`): the tile title becomes **«Проверка через VPN»** on one line (`.lineLimit(1)`, `.minimumScaleFactor(0.8)`, `.allowsTightening(true)`); the big value below («48 мс» / «VPN не проходит» / «—»); the caption below that: «Задержка — как пинг: ответ сайта через VPN по уже открытому соединению. Раз в 5 минут.» (stage 3 caption, prefixed with «Задержка — »). `LatencyTile.label` («Задержка») stays for VoiceOver: accessibility label «Проверка через VPN, задержка 48 мс».
5. Summary keeps all stage 3 rules otherwise; its card styling follows §8. The «Устройства в сети» tile on Summary links to the Devices tab (proposed).

---

## 10. Fixtures (in the repo: `ios/RouterCore/Sources/RouterCore/SampleJSON+Stage4.swift`; reference `now = 1791886560`)
MACs `00:00:5e:00:53:xx` (documentation range), `5a:…`/`ae:…` locally administered; IPs `192.168.1.x`, `203.0.113.x`, `198.51.100.x`; node ids invented.

### 10.1 `status_stage4.json`
```json
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":{"updated":1791886200,"current":"Kq7Lm2Xp","socks":true,"real":48,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":41,"group":"fspirat","own":true},{"id":"Rt5Vb8Nw","name":"fspiratDE","ms":0,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"},{"id":"Pz1Yc4Ue","name":" 🇳🇱 Нидерланды ","ms":63,"group":"nosok"},{"id":"Wm6Tj2Gk","name":"🇫🇮 Финляндия","ms":0,"group":"nosok"},{"id":"Bx2Kd7Lr","name":"🇸🇪 Швеция","ms":89,"group":"Reserve"},{"id":"Cy8Np3Vt","name":"🇵🇱 Польша","ms":0,"group":"Reserve"}]},"log":["13.10 13:20 вручную -> Kq7Lm2Xp","13.10 13:40 перезапуск VPN","13.10 13:55 MyDirect + gosuslugi.ru","13.10 14:02 мимо VPN: 00:00:5e:00:53:02"],"history":[[1791885900,52],[1791886200,48]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":112}]},"sub":{"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800,"title":"nosok"},"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14,"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800},{"id":"cfg7d8e9f","name":"Reserve","host":"r.example.org","hwid":false,"nodes":6}],"svc_direct":["Хайпиксель"],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/","mc|Хайпиксель|mc.example.net:25565"],"svc":{"Kq7Lm2Xp":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":112}]},"Hd3Fs9Qa":{"ts":1791884590,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":88},{"kind":"web","name":"Discord","host":"discord.com","vpn":95},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":102},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":140}]},"Pz1Yc4Ue":{"ts":1791884600,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":38},{"kind":"web","name":"Discord","host":"discord.com","vpn":71},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":97}]},"direct":{"ts":1791884410,"base":9,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":31}]}},"svc_running":false,"speed":{"vpn":{"via":"vpn","ts":1791880000,"down":91234567,"up":40123456,"latency":38,"ip":"203.0.113.77","country":"NL","server":"Hetzner (Германия)","streams":4,"up_limited":false},"direct":{"via":"direct","ts":1791879000,"down":286000000,"up":0,"latency":6,"ip":"198.51.100.20","country":"RU","server":"Selectel (Россия)","streams":4,"up_limited":true}},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-51,"rate":866,"up":120394882,"dn":2349872311},{"name":"","ip":"192.168.1.40","mac":"00:00:5e:00:53:02","online":true,"band":"wired","up":10392,"dn":88123,"direct":true},{"name":"tv-living","ip":"192.168.1.51","mac":"00:00:5e:00:53:03","online":true,"band":"2g","signal":-68,"rate":72,"up":0,"dn":0,"sched":"2300-0700"},{"name":"ipad","ip":"192.168.1.41","mac":"00:00:5e:00:53:05","online":true,"band":"5g","signal":-77,"rate":144,"up":1000,"dn":5000,"sblocked":true,"sched":"1300-1500"},{"name":"old-laptop","ip":"192.168.1.77","mac":"00:00:5e:00:53:04","online":false,"up":0,"dn":0,"blocked":true},{"name":"","ip":"192.168.1.90","mac":"ae:00:5e:00:53:06","online":false,"up":0,"dn":0}],"sys":{"cpu":7,"cores":2,"load":"0.21 0.17 0.15","mem_total":245632,"mem_avail":121840,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3460,"temp":null,"uptime":352812,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":61344,"net":{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}}}
```
**Expected VPN screen** (with `data_week.json` names):
- Mode «Через VPN»; «Подключён: fspiratNL» tag «свой».
- `services()` = YouTube, Discord, Telegram, Хайпиксель (from `targets`).
- Groups: «Свои серверы»: fspiratNL «41 мс» (current, «сейчас»; services YouTube 61 · Discord — · Telegram 74 · Хайпиксель 112), fspiratDE «—» dimmed (no services). «Подписка nosok»: 🇩🇪 Германия 57 (88 · 95 · 102 · 140), 🇳🇱 Нидерланды 63 (38 · 71 · — · 97). «Подписка Reserve»: 🇸🇪 Швеция 89 (· · · · — not measured). «Не отвечают: 2» (🇫🇮 Финляндия, 🇵🇱 Польша). «Напрямую» row: ping 9 мс; YouTube/Discord/Telegram «блок»; Хайпиксель 31 мс.
- Best per column (bold): ping 41 (fspiratNL); YouTube 38 (Нидерланды); Discord 71 (Нидерланды); Telegram 74 (fspiratNL); Хайпиксель 97 (Нидерланды).
- Chips: «YouTube: 🇳🇱 Нидерланды 38 мс» (tap → 428 «Подключить «🇳🇱 Нидерланды»?»), «Discord: 🇳🇱 Нидерланды 71 мс», «Telegram: fspiratNL 74 мс» (selected, disabled), «Хайпиксель: 🇳🇱 Нидерланды 97 мс».
- Sort by name asc inside nosok: «Германия» < «Нидерланды». Sort by Telegram asc inside nosok: Германия (102), then Нидерланды (0 → last).
- Subscriptions: «2 подписки». nosok: tag HWID; «sub.example.net · 14 серверов · обновлено 16 мин назад»; «осталось 17 дн.»; «израсходовано 39,2 ГБ из 200,0 ГБ»; bar 20 %; «до 31 октября». Reserve: «r.example.org · 6 серверов», no meta, no bar.
- Speed: VPN «91,2 Мбит/с» / «40,1 Мбит/с» / «38 мс», meta «Выход: 🇳🇱 203.0.113.77, проверено 2 ч назад · Hetzner (Германия), 4 потока». Direct «286 Мбит/с» / «позже» / «6 мс», meta «Выход: 🇷🇺 198.51.100.20, проверено 2 ч назад · Selectel (Россия), 4 потока · Cloudflare ограничил частые замеры отдачи, повтори через пару минут».

**Expected Devices** (names `{"5a:00:5e:00:53:01":"iPhone владельца"}`, traffic of 10.2):
- «4 в сети из 6». Filter «Ограничены» → 4 (ipad, Без имени/direct, tv-living, old-laptop).
- «Wi-Fi 5 ГГц» (2): «ipad» — label «по расписанию», no sched tag, signal level 1, «192.168.1.41 · 144 Мбит/с»; «iPhone владельца» — signal 4, «192.168.1.23 · 866 Мбит/с», «↓ 1,5 ГБ сегодня» (no «скрытый MAC» because it has a name).
- «Wi-Fi 2,4 ГГц» (1): «tv-living» — tag «23:00–07:00», signal 2.
- «По кабелю» (1): «Без имени» — «мимо VPN», «192.168.1.40», «↓ 10 МБ сегодня».
- «Не в сети: 2» collapsed: «old-laptop» «без интернета»; «Без имени» «192.168.1.90 · скрытый MAC».
- «Новые за неделю»: «Без имени · 11.10 10:26» → card of 00:00:5e:00:53:02.

**Expected Bypass services toggles:** YouTube off, Discord off, Telegram off, Хайпиксель **on**.

### 10.2 `data_week.json`
```json
{"now":1791886560,"range":"week","step":1800,"points":[[1791873900,52,0,0],[1791875700,49,1,0],[1791877500,0,2,0],[1791879300,-1,0,30],[1791881100,50,0,2],[1791882900,47,0,0],[1791884700,48,0,0],[1791886500,50,0,0]],"stats":{"avg":50,"min":38,"max":71,"fails":3,"offline_min":32},"events":[[1791886200,"manual","Сервер выбран вручную: fspiratNL"],[1791883800,"restart","Перезапуск VPN"],[1791857400,"auto","Автопереключение: fspiratDE -> fspiratNL 41ms"],[1791820000,"online","Роутер снова на связи (не было 6 мин)"],[1791819640,"offline","Роутер пропал со связи"],[1791700000,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5E:00:53:02)"],[1791600000,"reboot","Роутер перезагрузился"]],"offline_since":null,"last_ok":1791886530,"names":{"5a:00:5e:00:53:01":"iPhone владельца"},"tpoints":{"YouTube":[[1791882900,61],[1791884700,0],[1791886500,58]],"Discord":[[1791884700,0]]},"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[734003200,28991029248]},"00:00:5e:00:53:02":{"d":[1048576,10485760],"m":[20971520,209715200]}},"speed":[[1791879000,"direct",286000000,0,6],[1791880000,"vpn",91234567,40123456,38]],"mtg":null,"site":{"luci":"https://router.fspirat.xyz/","bot":"FSRouter_bot","mtg":"","panels":["fspirat.xyz"]},"newdevs":[{"ts":1791700000,"mac":"00:00:5e:00:53:02"}]}
```
**Expected chart («Связь», 7 дн):** line segments [52, 49] and [50, 47, 48, 50]; small fail bar at 1791875700 (fails 1); tall fail bar at 1791877500 (value 0); offline band at 1791879300 width 1800 s; stats «Средняя 50 мс · Лучшая 38 мс · Худшая 71 мс · Сбоев 3 · Без связи 32 мин»; tooltip at 1791879300 (mid = 12:15 Samara) → «сегодня 12:00–12:30 · роутер не на связи» (format of app.js:373: `when(mid − step/2)` + «–» + `HH:mm(mid + step/2)`).
**Expected Journal (7 дн, «Все», 7 записей):**
| Group | Time | Chip | Text |
|---|---|---|---|
| Сегодня | 14:10 | Действие | Сервер выбран вручную: fspiratNL |
| Сегодня | 13:30 | Действие | Перезапуск VPN |
| Сегодня | 06:10 | Внимание | Автопереключение: fspiratDE -> fspiratNL 41ms (display «→ … 41 мс» optional) |
| Вчера | 19:46 | Успех | Роутер снова на связи (не было 6 мин) |
| Вчера | 19:40 | Ошибка | Роутер пропал со связи |
| 11 октября | 10:26 | Внимание | Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5E:00:53:02) |
| 10 октября | 06:40 | Внимание | Роутер перезагрузился |
Filters: «Ошибки» 1 («найдено 1 из 7»); «Внимание» 3; «Действия» 3 (manual, restart, online). Search «vpn» → 1 (Перезапуск VPN). No limit notice (7 < 100).
**Expected VPN switch history (7 дн):** «Сервер выбран вручную: fspiratNL» (сегодня 14:10), «Автопереключение: fspiratDE → fspiratNL 41 мс» (сегодня 06:10).

### 10.3 `data_month.json` (points only; other keys as 10.2 with `"range":"month","step":7200`)
```json
{"now":1791886560,"range":"month","step":7200,"points":[[1791867600,51,0,0],[1791874800,49,3,0],[1791882000,0,5,0],[1791889200,50,0,0]],"stats":{"avg":50,"min":38,"max":71,"fails":8,"offline_min":0},"events":[],"offline_since":null,"last_ok":1791886530,"names":{},"tpoints":{},"traffic":{},"speed":[],"mtg":null,"site":{"luci":"","bot":"","mtg":"","panels":[]},"newdevs":[]}
```
Expected: the last point `mid = 1791889200 > now` → clipped to the x-domain (`now` is the right edge); bucket 1791874800 draws a small fail bar; 1791882000 a tall fail bar.

### 10.4 zapret
`zapret_on.json` = the observed body in §2.3 → summary «YouTube и Discord — напрямую, с IP провайдера · 18234 TCP · 5120 QUIC»; strategy 2 selected; results YouTube «412 мс», YouTube видео «530 мс», Discord API «610 мс», Discord CDN «нет»; caption «Проверено сегодня 14:06 · Discord видит IP провайдера».
```json
{"installed":true,"enabled":true,"strategy":3,"engine":false,"nft":true,"route_cfg":true,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":1,"version":"v72.5","busy":false,"checking":false,"check":null}
```
`zapret_partial.json` → «Включён, но работает не полностью»; error «Расхождение: режим включён, но служба не работает, маршрут PassWall не применён. Сторож попробует исправить в течение минуты.»
```json
{"installed":true,"enabled":true,"strategy":3,"engine":false,"nft":false,"route_cfg":false,"route_live":false,"fallback":true,"error":"nfqws не запускается — YouTube и Discord временно идут через VPN","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"v72.5","busy":false,"checking":false,"check":{"error":"xray"}}
```
`zapret_fallback.json` → error box shows `error` verbatim; check caption «Проверка не удалась: VPN (Xray) не был запущен.»
```json
{"installed":true,"enabled":false,"strategy":1,"engine":false,"nft":false,"route_cfg":false,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"v72.5","busy":true,"checking":false,"check":null}
```
`zapret_busy.json` → «Применяю… PassWall перезапускается»; toggle/strategy disabled; 3 s polling.
```json
{"installed":true,"enabled":false,"strategy":3,"engine":true,"nft":false,"route_cfg":false,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"","busy":false,"checking":true,"check":null}
```
`zapret_off_checking.json` → «YouTube и Discord — через VPN, как всё остальное»; error «Расхождение: режим выключен, но часть правил ещё активна. Сторож уберёт их в течение минуты.»; check button «Проверяю…».
```json
{"installed":false,"enabled":false,"strategy":3,"engine":false,"nft":false,"route_cfg":false,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"","busy":false,"checking":false,"check":null}
```
`zapret_not_installed.json` → error «zapret не установлен на роутере (нет nfqws, списков или модуля ядра).», controls disabled.
`zapret_absent.json` = `{"installed":false,"absent":true}` → «zapret на роутере не установлен.», no controls.

### 10.5 tgws
`tgws_on.json` = observed (§2.4) → «Telegram на всех устройствах дома — через Cloudflare, мимо VPN, без настройки · 3412 подкл.»
```json
{"installed":true,"auto":false,"redirected":0,"enabled":true,"running":true,"listening":false,"host":"192.168.1.1","port":1443,"version":"1.1.3"}
```
`tgws_starting.json` → «Запускается… Пока прокси не работает, Telegram идёт через VPN».
```json
{"installed":true,"auto":false,"redirected":0,"enabled":false,"running":false,"listening":false,"host":"192.168.1.1","port":1443,"version":"1.1.3"}
```
`tgws_off.json` → «Выключен — Telegram идёт как обычно (через VPN)». `tgws_absent.json` = `{"installed":false,"absent":true}`.

### 10.6 `mydirect.json`
```json
{"domains":["kinopoisk.ru","gosuslugi.ru","sberbank.ru","geosite:category-ru","mc.example.net"],"added":["kinopoisk.ru"]}
```
Expected: «5 записей»; «Добавленные»: kinopoisk.ru (Убрать); «Весь список (5)» without a query shows the 4 plain domains (kinopoisk.ru tagged «добавлен»), with query «geo» shows `geosite:category-ru` (not removable). Add input «https://www.Ozon.ru/catalog» → «ozon.ru» → 428 «Пускать ozon.ru напрямую?»; input «gosuslugi.ru» → «Этот сайт уже в списке.», no request; input «сайт.рф» → «Нужен домен вида site.ru».
`mydirect_norule.json` (500): `{"error":"no rule","message":"В PassWall нет правила MyDirect.","source":"router"}`.

### 10.7 `vds.json`
```json
{"ts":1791886440,"servers":[{"name":"Сервер панели","local":true,"stat":{"up":1209600,"cores":2,"mem_total":2014084,"mem_avail":1302500,"rx":918273645123,"tx":905172634512,"conns":14,"load":"0.08 0.05 0.01","disk":"37%","xray":"active"}},{"name":"DE","stat":null},{"name":"NL2","stat":{"up":86400,"cores":1,"mem_total":1000000,"mem_avail":200000,"rx":1048576,"tx":2097152,"conns":0,"load":"0.50 0.40 0.30","disk":"81%","xray":"inactive"}}]}
```
Expected: «Сервер панели» — «VPN (Xray) работает · соединений 14», «Нагрузка 0,08 0,05 0,01 на 2 ядр. · память 35% из 1,9 ГБ · диск 37%», «Без перезагрузки 14 д 0 ч · трафик с запуска ↓855,2 ГБ ↑843,0 ГБ», «Здесь же панель». «DE» — «не отвечает по SSH». «NL2» — «VPN (Xray): inactive · соединений 0», «… память 80% из 1,0 ГБ · диск 81%», «Без перезагрузки 1 д 0 ч · трафик с запуска ↓1,0 МБ ↑2,0 МБ». Footer «Данные 2 мин назад.»
`vds_empty.json` = `{"ts":null,"servers":[]}` → «Данных о серверах пока нет — они собираются раз в 5 минут.»

### 10.8 `devices_access.json`
```json
{"apps":[{"id":"49139e3a1db5a6ac","name":"iPhone владельца","model":"iPhone18,1","os":"iOS 26.0","app":"1.1 (20)","created":1791886000,"seen":1791886500,"last_ip":"203.0.113.50","expires":1799662500,"hard_expires":1823422000,"current":true},{"id":"8df5a0cb8a35a59a","name":"Второй iPhone","model":"iPhone16,1","os":"18.1","app":"1.0 (12)","created":1790000000,"seen":1791713760,"last_ip":"198.51.100.7","expires":1792400000,"hard_expires":1821536000,"current":false}],"web":[{"ref":"8207c706de3f72c7","created":1791880000,"seen":1791886300,"ip":"203.0.113.50","ua":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36","current":false}],"logins":[{"ts":1791886000,"name":"iPhone владельца","ip":"203.0.113.50","result":"issued"},{"ts":1791885000,"name":"iPhone","ip":"198.51.100.99","result":"denied"}],"auth_log":[{"ts":1791886000,"what":"APP_OK","ip":"203.0.113.50"},{"ts":1791885990,"what":"APP_LOGIN","ip":"203.0.113.50"},{"ts":1791885000,"what":"APP_DENIED","ip":"198.51.100.99"},{"ts":1791880000,"what":"OK","ip":"203.0.113.50"},{"ts":1791879900,"what":"CODE","ip":"203.0.113.50"},{"ts":1791870000,"what":"FAIL","ip":"203.0.113.51"}]}
```
Expected: phone 1 — tag «этот телефон», «iPhone18,1 · iOS 26.0 · приложение 1.1 (20)», «был в сети 1 мин назад · IP 203.0.113.50 · вход до 11 января» (dayMonth(1799662500)), no «Отозвать». Phone 2 — «iPhone16,1 · iOS 18.1 · приложение 1.0 (12)», «был в сети 11.10 14:16», «вход до 19 октября» in **err** (expires − now = 513 440 s < 7 days), «Отозвать». Web — «Chrome · Windows», «IP 203.0.113.50», «был 4 мин назад». Logins: «вошёл» (ok), «неверное число» (err).

### 10.9 Action responses (observed bodies)
```json
{"id":"Wm6Tj2Gk","ms":7,"ts":1791899279}
```
```json
{"ok":true}
```
```json
{"ok":true,"mac":"00:00:5e:00:53:03","blocked":true}
```
```json
{"ok":true,"mac":"00:00:5e:00:53:03","blocked":false}
```
```json
{"ok":true,"direct":true}
```
```json
{"ok":true,"same":true}
```
```json
{"ok":true,"names":{"00:00:5e:00:53:03":"Телевизор","00:00:5e:00:53:02":"Приставка"}}
```
```json
{"ok":true,"revoked":7}
```
```json
{"job":"34045d1894d672ac","poll_every":3}
```
```json
{"state":"done","action":"speedtest","http":200,"result":{"via":"vpn","ts":1791899279,"down":90000000,"up":40000000,"latency":12,"ip":"203.0.113.77","country":"DE","server":"Hetzner (Германия)","streams":4,"up_limited":false}}
```
```json
{"state":"error","action":"speedtest","http":409,"error":"busy","message":"Другое действие ещё выполняется — подожди немного.","source":"router"}
```

### 10.10 Error fixtures (observed)
```json
{"error":"bad node","message":"Такого сервера нет — обнови список.","source":"router"}
```
```json
{"error":"time","message":"Неверное время.","source":"router"}
```
```json
{"error":"no target","message":"Нет такого сервиса.","source":"router"}
```
```json
{"error":"nft","message":"Роутер не смог изменить правила.","source":"router"}
```
```json
{"error":"no rule","message":"В PassWall нет правила MyDirect.","source":"router"}
```
```json
{"error":"not installed","message":"Не установлено на роутере.","source":"router"}
```
```json
{"error":"busy","message":"Другое действие ещё выполняется — подожди немного.","source":"router"}
```
```json
{"error":"bad_param","message":"Убрать можно только домены, добавленные из панели или приложения."}
```
```json
{"error":"too_long","message":"Слишком длинное значение."}
```
```json
{"error":"rate_limited","message":"Слишком часто — подожди немного.","retry_after":30}
```
```json
{"error":"not_found","message":"Не найдено."}
```
```json
{"error":"confirm_invalid","message":"Подтверждение не подошло — повтори действие."}
```
All 428 bodies of §3.3 are fixtures too (`confirm_switch_node.json`, `confirm_switch_dead.json`, `confirm_switch_current.json`, `confirm_switch_unknown.json`, `confirm_switch_direct.json`, `confirm_subupdate_sid.json`, `confirm_subupdate_all.json`, `confirm_block_named.json`, `confirm_block_unnamed.json`, `confirm_direct_on.json`, `confirm_direct_off.json`, `confirm_schedule.json`, `confirm_diradd.json`, `confirm_dirdel.json`, `confirm_svcdirect_on.json`, `confirm_svcdirect_off.json`, `confirm_zapret_on.json`, `confirm_zapret_off.json`, `confirm_tgws_on.json`, `confirm_tgws_off.json`, `confirm_revokeall.json`, `confirm_revokeall_web.json`) — build them from the §3.3 table in the 428 body shape of stage 3 §2.11 (the raw run output was a temporary session file and is not kept).

### 10.11 Unit tests to add (RouterCore)
- decoding of every fixture above; 2- vs 4-element points;
- `services`, `svcOf`, `svcVal`, best-per-column, best chips, group building and order, dead list, direct row «блок» rule, sort (name/ping/service, bad-last, ties, direction);
- `subsList` fallback, subscription meta strings, `pct`;
- device grouping, filter «Ограничены», search, labels order, `hiddenMac`, `sigLevel`, newdevs dedupe;
- schedule window-active (incl. across midnight, `off > on`, boundaries `n == off` active, `n == on` inactive);
- zapret state machine (each fixture → summary + error text), strategy verification outcome;
- tgws summary per fixture;
- MyDirect normalize/validate (server regex, ≤100 bytes, prefixes not removable, `added` only);
- journal level mapping, filters (Действия = info + ok), search, Samara day grouping, limit notice;
- auth_log/login word maps; `osTxt`, `seenTxt`;
- formatter changes of §9 (comma, NBSP).

---

## 11. Where the code differs from the docs (code wins)
1. **Owner decision vs plan §3:** plan §3 «в переключателе приложений содержимое экрана скрыто» and stage 3 §7.8 are superseded: default **not hidden**, toggle in Settings (§1.3).
2. **Decimal separator:** stage 3 §5 used `.` like the web (`toFixed`); owner decision 4 → `,` (§9). The web keeps `.`.
3. **Plan §7 «Подписки … в приложении — только просмотр»** vs plan §2 «Кнопка «Обновить» — окно» and the code (`subupdate` is in `APP_ACTIONS`): «Обновить» is allowed; add/delete are not (`404 not_in_v1`).
4. **428 for `schedule`:** inventory §6 says «Текст окна выбирает приложение» (window active → high). The code sends one `medium` text for every case (it already mentions «Если сейчас как раз время …»). The app adds its own warning line and red button when the window is active (§3.3).
5. **Red buttons:** plan §2 wants red for «Выключить интернет» and removing a MyDirect site, but the server sends `danger: "high"` for `block` and `dirdel`. The app styles them red itself; Face ID stays only for `critical`.
6. **Mock-up `Device.dc.html`** shows «Подтвердите Face ID» for block and texts that differ from the server; the server texts and §3.3 rules win. Mock-up journal texts («Сервер сменён на Германию 1 · из приложения…», «Связь восстановлена») are invented: real texts come from fspirat-watch (stage 3 §2.9).
7. **`/devices` `web[].current`** exists in the code (inventory §7.6 lists `{ref, created, seen, ip, ua}` only); for the app it is always `false`.
8. **`/vds`** (inventory §6): `stat` can be `null` (host unreachable) — not in the inventory table; unknown keys are stripped; `ts` may be `null`.
9. **`/tgws`** has `host`, `port`, `version` (inventory §3.3 lists only auto/redirected/listening).
10. **Week/month `points` value 0** means «no ok minute and fewer than 3 offline minutes» — a bucket with only 1–2 offline minutes and no checks shows as a VPN failure. Inventory §3.2 describes `-1` only as «нет удачных и пропусков ≥ 3»; the 0 case is ambiguous. Treat 0 as «сбой VPN» like the web.
11. **`events` limit:** inventory says «до 100»; the code also only reads the last **300 lines** of events.tsv, so a 30-day list can be incomplete below 100 rows.
12. **Speedtest 409 from the router** reaches the job as the generic busy message, not «Тест скорости уже идёт» (inventory §7.8 «от CGI может прийти 409» without text). The app substitutes the web's text.
13. **`rename` works when the router is offline** (app.php:654 skips the «router silent» check) — not stated in plan/inventory; the app keeps «Переименовать» enabled offline.
14. **`confirm` mismatch consumes the confirm** (fsr_app_confirm_use deletes before comparing params). Inventory §7.9 says only «Не совпало → 400». The client must restart from a fresh 428.
15. **`schedule` clear with a `confirm` key** is accepted and ignored (200), although inventory implies `confirm` only for confirmable cases.
16. **`fsr_auth_log_tail` comment** says «Время в журнале — по Москве»; the returned `ts` is already correct Unix time (no client correction).
17. **zapret polling** inventory §9.1 «3 с при busy/checking, но не дольше 2 мин»; the web polls without a cap (app.js:1010). The app caps at 2 min per trigger.
18. **Journal «Действия» filter** in the web includes `ok` events (app.js:410); the plan lists only «ошибки, внимание, действия». Ported as the web.
19. **Plan §2 «Telegram через Cloudflare — переключатель виден, даже если zapret нет»**: the web hides tgws inside the zapret section (`index.html:156-161`); the app shows it as its own card. With tgws absent the app shows a disabled card (web hides).
20. **`switch` on the current node** is accepted by the server and restarts PassWall (inventory §5 п.9); the app does not offer it.
21. **`svcdirect` name limit** is 40 **bytes** on the server (inventory §7.8 says «1–40 байт»), but web names may be up to 40 bytes from settargets too; Cyrillic names ≈ 20 letters.
22. **Unit:** the web shows «ms»; the app «мс» (stage 3).
23. **inventory §9.1 timeouts** (15/20 s) are superseded by stage 3 §1.5 (30 s for status and actions).

---

## 12. Gotchas
- **Polling stops in the app switcher** even though the screen is now visible there (`scenePhase != .active`). That is intended: no network while not active.
- **«Сразу» lock with the toggle off** must engage on return, not on background, or the switcher shows the lock screen again (§1.3).
- **Never flip a toggle/segment before 200.** zapret, tgws, svcdirect, direct, mode: show a spinner, keep the server value until the action returns, then apply the local change and re-read.
- **PW pause is global (15 s for all phones).** A `429 rate_limited` right after another phone's action is normal; show the countdown.
- **One action at a time** across all app clients (`409 busy`); the web and the bot bypass this lock.
- **`svcOf(current)` uses `targets`, not `svc[current]`**; `svc` values are up to 30 min old; dead nodes never show service values.
- **`ping.nodes` misses Hysteria2 and «LTE/Россия/Обход» nodes** (unless current): the current node may be absent from `nodes` → `nodeName` falls back to the raw id.
- **`current == ""`** (Split missing): no current row; show the Split warning.
- **Week/month points have 4 ints; day points 2.** The last bucket mid can be after `now`; the first before the window.
- **`names` keys are lowercase MACs; `newdevs` MACs are lowercased by the server; event texts may contain uppercase MACs.**
- **Device counters (`up`/`dn` in status) reset on reboot** — use `data.traffic` for today/month, never `status.devices[].dn`.
- **`traffic` arrays are `[up, down]`** (upload first).
- **`schedule` times are Samara wall-clock `HHMM`**; the iPhone may be in another zone — always convert with `TimeZone(identifier: "Europe/Samara")`.
- **`unblock` during an active window leaves `sblocked`**; the device stays offline until the window ends.
- **`zapretstrat` can be silently lost** when the zapret lock is busy — always verify (§5.4.2).
- **`tgwsset` fails silently** — verify with the +8 s read.
- **`zapret.check.ms` is total request time**, not latency.
- **`/mydirect` `domains` contains `geosite:`-style entries and svcdirect hosts**; only `added` may be removed; the server re-checks.
- **`diradd` same domain** returns `{"ok":true,"same":true}` without restarting PassWall — no quiet window then.
- **`revoke-all` revokes this phone too** — LOGOUT right after 200.
- **Revoking our own `id` via `/devices/revoke`** = logout (`revoked_by=self`); hide the button for `current`.
- **`/devices` may list up to 10 phones**; at 10 a new login is refused (`too_many_devices`) — the access list is where the owner fixes it.
- **Glass on glass** (a glass row inside a glass card) looks muddy and costs GPU — one glass layer per card.
- **`Tab` struct is iOS 18+**; keep `.tabItem` for the iOS 17 target.
- **Do not add `UIDesignRequiresCompatibility`** to Info.plist.

# Stage 3 client contract: iOS app «Роутер» ↔ `/router/app/v1`

> **Справочный документ (этап 3, 13.10.2026).** Контракт клиента: вход, Keychain, Face ID, «Сводка», первые настройки.
> Выведен из кода сервера (`server/auth/*.php`), CGI роутера (`router/www/cgi-bin/fspirat`, `router/bin/*`) и веба (`web/app.js`).
> **При расхождении прав код** (прежде всего сервер). Этап 4 дополняет и местами заменяет этот документ: `docs/ios/contract-stage4.md`.
> Образцы ответов из §8 в репозитории лежат в `ios/RouterCore/Sources/RouterCore/SampleJSON.swift` (отдельной папки `Fixtures/` нет).
> Токен и `login_id` в образцах — заглушки, настоящих ключей и адресов здесь нет.
> Подписи в готовом приложении местами короче (например, «Блокировать»: «Сразу» / «1 мин» / «5 мин»); точные тексты — в коде `ios/`.
>
> *Reference (stage 3, 13.10.2026): the iOS client contract, derived from `server/auth/*.php`, the router CGI and `web/app.js`.
> The code wins on any disagreement. Extended by `docs/ios/contract-stage4.md`.*

This document was the single source of truth for the stage 3 iOS coding agents (now a reference; the code wins). Stage 3 covers login, Keychain, the Face ID lock, the «Сводка» screen with its actions, a minimal Settings sheet and the first TestFlight build.

**Sources.** Everything here was checked against the real code:
- `server/auth/app.php`, `app-lib.php`, `data-lib.php`, `lib.php`;
- `server/auth/nginx-apply.py` (the nginx block);
- `router/www/cgi-bin/fspirat`, `router/bin/fspirat-ping`, `fspirat-led`, `fspirat-sub`, `fspirat-subs`, `fspirat-targets`, `fspirat-svcping`;
- `server/bin/fspirat-watch`;
- `web/app.js`, `web/index.html`, `web/app.css`.

The API responses quoted as "observed" were produced by running the real `app.php` locally against the repo's test stubs (`server/auth/tests/router-stub.php`, `tg-stub.php`). Where the code and `docs/ios/inventory.md` disagree, **the code wins**; every such case is listed in §9.

**Conventions.**
- "int" means a JSON number without a fractional part. Decode it as Swift `Int`, which is 64-bit on iOS; some values are larger than 2³¹.
- "?" after a field name means the key may be absent.
- "|null" means the key is present and its value can be `null`.
- All timestamps are Unix seconds (int, UTC).
- All Russian UI strings are verbatim. Strings marked **(proposed)** are new app texts, not taken from the web or the server.

---

## 1. Transport

### 1.1 Base URL and routing
- **Base URL.** `https://fspirat.xyz/router/app/v1`. It comes from the `APP_BASE_URL` Info.plist key, which is not a secret. HTTPS only, with default ATS and no certificate pinning.
- **nginx.** `location ^~ /router/app/v1/` hands every request to `app.php` through FastCGI. Any other `/router/app/...` path (for example `/router/app/v2/`) gets nginx `404 {"error":"not_found"}` with no `message` key.
- **How `app.php` finds the route.** It does not use `PATH_INFO`. It reads `parse_url(REQUEST_URI, PHP_URL_PATH)` and removes the `/router/app/v1` prefix if the path starts with `/router/app/v1/`. What remains is compared **exactly**: case-sensitive, not URL-decoded, no trailing slash. So `/me/` → 404 and `/Me` → 404.
- **Routes used in stage 3:**

| Method | Path | Auth |
|---|---|---|
| POST | `/auth/login` | none |
| POST | `/auth/poll` | none |
| POST | `/auth/cancel` | none |
| POST | `/auth/logout` | Bearer |
| GET | `/me` | Bearer |
| GET | `/status` | Bearer |
| GET | `/net` | Bearer |
| GET | `/led` | Bearer |
| GET | `/data?range=day` | Bearer |
| POST | `/action/ping`, `/action/restart`, `/action/update`, `/action/reboot`, `/action/ledset` | Bearer |
| GET | `/jobs/{id}` | Bearer |

- **Other routes (stage 4, not used now).** `/devices`, `/devices/revoke`, `/devices/revoke-all`, `/zapret`, `/tgws`, `/mydirect`, `/vds`, and the other actions.
- **Unknown path with no or bad token.** The token is checked before the 404, so the answer is **401 token_missing** (or token_invalid), not 404. With a valid token an unknown path → `404 not_found`.
- **Action names.** `/action/<name>` matches `^[a-z]{1,20}$`. Known but not in v1 (`subadd`, `subdel`, `settargets`) → `404 not_in_v1`. Unknown name → `404 not_found`.

### 1.2 What the client must send
- **`Authorization: Bearer fsr1_<43 chars>`** on every route except the three `/auth/login|poll|cancel` routes.
  - The server regex is case-sensitive and exact: `^Bearer (fsr1_[A-Za-z0-9_-]{43})$`, applied after trimming the whole header.
  - The token regex is `^fsr1_[A-Za-z0-9_-]{43}$`, 48 characters in total.
  - Use the literal word `Bearer` with one space. `bearer …` → 401 token_invalid, which counts toward fail2ban.
- **POST with a body.** Send `Content-Type: application/json` (a `; charset=utf-8` suffix is fine; the server regex is `^application/json\s*(;|$)`, case-insensitive). The body must be a JSON **object**, so its first non-space character is `{`.
  - **Empty body.** An empty or whitespace-only body is accepted as `{}` with no Content-Type check. Recommended for actions without parameters: send no body, or send `{}` with the JSON content type. Both work.
  - **Size.** At most 4096 bytes. nginx also has `client_max_body_size 4k`.
  - **Nesting.** `json_decode` depth is 4, so at most 3 nested objects. Login uses 2 levels.
- **Unknown body fields → `400 bad_param`.** This applies everywhere:
  - login allows only `password` and `device`; `device` allows only `name`, `model`, `os`, `app`;
  - poll and cancel allow only `login_id`;
  - logout allows nothing;
  - actions allow only their own parameters plus `confirm`.
- **Query string.**
  - **Any** query parameter → `400 bad_param`, with one exception: `range` on `/data`.
  - The `range` value must be `day`, `week` or `month`. Anything else, or an array (`range[]=`), → 400.
  - A bare `?` (empty query) is fine.
- **Never put `fsr1_` anywhere in the URL.** Also never use query keys `access_token`, `token`, `bearer`, `authorization` or `auth`, in any case.
  - The server answers `400 token_in_url`.
  - If the URL contained a real token, the server **revokes it immediately** (`revoked_by=url_leak`) and alerts Telegram.
  - This check runs before authentication and also applies to `/auth/*`.
- **No browser headers.** Do **not** send `Origin` or `Sec-Fetch-Site`; either → `403 browser_request`. Plain URLSession does not send them.
- **No cookies.** nginx clears them anyway (`fastcgi_param HTTP_COOKIE ""`). Use `URLSessionConfiguration.ephemeral`, `httpShouldSetCookies = false`, `urlCache = nil`.
- **Methods.** Reads are GET and everything else is POST. A wrong method → `405 method` with an `Allow: GET` or `Allow: POST` header. OPTIONS and HEAD → 405.

### 1.3 Responses
- **Every `app.php` response** has these headers: `Content-Type: application/json; charset=utf-8`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`.
- **Error envelope:** `{"error":"<code>","message":"<Russian text>"[,"source":"router"][, extra fields]}`.
  - `error` is a string. It is usually snake_case, but router codes contain spaces, for example `"bad node"` or `"not installed"`.
  - `message` is a ready-to-show Russian sentence.
  - `"source":"router"` is present when the error code came from the router CGI.
  - Extra fields are `left` (int), `retry_after` (int) and the 428 fields (§2.11).
- **401** also sends `WWW-Authenticate: Bearer error="invalid_token"`.
- **429** sends `Retry-After: <seconds>` and the body field `retry_after` (int, ≥ 1). Prefer the body value and fall back to the header.
- **405** sends `Allow:`.
- **202 (job start)** also sends `Content-Length` and `Connection: close`.
- **Responses generated by nginx itself have no `message` key.** The client must use the fallback texts in §3.2 for them:
  - `429 {"error":"rate_limited","retry_after":2}` + `Retry-After: 2`. This is the nginx rate limit: 5 r/s per IP with burst 40, and 2 r/s per token with burst 20.
  - `413 {"error":"too_large"}`.
  - `502 {"error":"server_unavailable"}`. nginx returns this when php-fpm is down or the 30 s `fastcgi_read_timeout` expires.
  - `404 {"error":"not_found"}` for `/router/app/<not v1>/`.
- **app.php's own 502 and 504 reach the client unchanged.** The `error_page 502 504` rule does not apply to them because `fastcgi_intercept_errors` is off (the repo does not set it). So `router_offline` (502) and `router_timeout` (504) arrive with the app.php JSON body.
- **Bodies that may not be JSON.** A PHP fatal error, a proxy error page or a captive portal can return a non-JSON body. Handle it as described in §3.2.
- **Read success bodies** (`/status`, `/net`, `/led`, action results) are the router CGI's JSON passed through byte-for-byte. The only change: if the router sent broken JSON (a control character inside a string), the server repairs and re-encodes it once. If repair fails → `502 router_bad_reply`.

### 1.4 Order of checks on the server
Knowing this order explains which error you get.
1. The file `app_disabled` exists → `503 app_disabled`. This happens even for `/auth/*`.
2. `Origin` or `Sec-Fetch-Site` header present → `403 browser_request`.
3. Token in URL → `400 token_in_url`.
4. Public routes (`/auth/login|poll|cancel`): method must be POST → query must be empty → handler.
5. Token check, in this order:
   - no or empty header → `401 token_missing`;
   - wrong format or unknown hash → `401 token_invalid` (counted by fail2ban);
   - revoked → `401 token_revoked`;
   - `expires <= now` or `min(hard_expires, created+365d) <= now` → `401 token_expired`.
   
   A valid token is extended silently: `expires = min(now+90d, hard_expires)`, at most once per 5 minutes.
6. Route → method check → query check → handler. Unknown route → `404 not_found`.
7. Any uncaught exception → `500 server_error`.

### 1.5 Client timeouts (recommended)
`docs/ios/inventory.md` §9.1 says 15 s for normal requests and 20 s for status. The code is slower than that:
- the server waits up to 4 s for a free router slot;
- the CGI timeout for `/status` is 20 s;
- all router calls in one request share a 25 s budget;
- nginx gives up on php-fpm after 30 s.

A client timeout of 20 s would cut off valid replies. **Use these values:**

| Request | `timeoutInterval` |
|---|---|
| `/status`, every `/action/*` | 30 s |
| `/net`, `/led` | 15 s |
| `/data`, `/me`, `/auth/*`, `/jobs/*` | 15 s |

---

## 2. Endpoints

### 2.1 `POST /auth/login`
**Request**
```json
{"password":"<panel password>","device":{"name":"iPhone владельца","model":"iPhone15,2","os":"iOS 18.1","app":"1.0 (42)"}}
```

**Validation (each failure → 400):**
- **Keys.** Only the top-level keys `password` and `device` are allowed. `device` must be an object containing only `name`, `model`, `os`, `app`. Otherwise `bad_param`.
- **`device.name`** — string, required.
  - The server trims it first; the trimmed value must be non-empty and valid UTF-8, with no `\x00-\x1f` or `\x7f`. Otherwise `bad_param`.
  - More than **40 characters** (`mb_strlen`) → **`too_long`**.
  - **Client rule:** trim, strip control characters, limit input to 40 characters, disable «Войти» when the name is empty.
- **`device.model`, `device.os`, `device.app`** — optional (default `""`).
  - Each must be a string matching `^[\x20-\x7e]{0,32}$`: printable ASCII only, at most 32 characters. Non-ASCII → `bad_param`.
  - **Client values:**
    - `model` — the hardware identifier from `utsname.machine`, for example `iPhone15,2`;
    - `os` — `"iOS " + UIDevice.current.systemVersion`, for example `iOS 18.1`; the web displays it as is;
    - `app` — `CFBundleShortVersionString + " (" + CFBundleVersion + ")"`, for example `1.0 (42)`.
  - Clamp each value to 32 ASCII characters.
- **`password`** — a string of at most 200 **bytes**. It is required by default (`site.json app_password`, default on). If present it must be a string.
  - **Client rule: never submit an empty password.** `""` passes validation, but the server counts it as a wrong password: it is a real failed attempt and burns one of the 5 tries.

**Possible responses, in server order:**

| HTTP | `error` | Extra fields | Meaning, server `message` |
|---|---|---|---|
| 503 | `app_disabled` | | «Приложение выключено на сервере. Веб-панель работает.» |
| 400 | `bad_param` / `too_long` | | see validation above |
| 415 | `not_json` | | «Тело запроса должно быть JSON.» |
| 503 | `tg_unavailable` | | Bot not configured, or Telegram `sendMessage` failed: «Telegram-бот недоступен — войти в приложение сейчас нельзя.» |
| 429 | `rate_limited` | `retry_after` | More than 5 logins per hour from this IP, or more than 10 per hour in total: «Слишком часто — подожди немного.» |
| 429 | `busy` | `retry_after` | Two logins are already waiting: «Уже ждут подтверждения два входа — ответь в Telegram или подожди 2 минуты.» |
| 429 | `locked` | `retry_after` | Password login to the app is closed for everyone (after «Это не я» or a password spray): «Вход в приложение по паролю временно закрыт (отклонён вход или подбор пароля). Веб-панель работает.» |
| 429 | `locked` | `retry_after` | This IP is blocked for 15 min: «Слишком много неверных попыток. Вход с этого адреса закрыт ещё на N мин.» |
| 401 | `bad_password` | `left` (int 0–4) | `left>0`: «Неверный пароль. Осталось попыток: N.»; `left==0`: «Слишком много неверных попыток. Вход с этого адреса закрыт на 15 мин.» This is **not** a logout. |
| 409 | `too_many_devices` | | «Уже 10 телефонов с доступом — отзови старый в Настройках, в веб-панели или командой /apps в боте.» |
| 200 | — | | success, see below |

**200 body** (observed):
```json
{"login_id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","number":24,"expires_in":120,"poll_every":2}
```

| Field | Type | Notes |
|---|---|---|
| `login_id` | string | 64 lowercase hex. Secret: keep it in memory only, never log it. |
| `number` | int | 10–99; show it big. The bot shows three number buttons and «🚫 Это не я». |
| `expires_in` | int | Always 120: seconds the bot buttons stay valid. |
| `poll_every` | int | Always 2. |

**Timing.** Wrong passwords are delayed by 300–700 ms on the server. bcrypt plus Telegram can take 1–3 s, so show a spinner.

### 2.2 `POST /auth/poll`
**Request:** `{"login_id":"<64 hex>"}`. A wrong format → `400 bad_param`.

**Responses:**

| HTTP | Body | Client action |
|---|---|---|
| 200 | `{"state":"pending","expires_in":118}` | Keep polling every `poll_every` s. `expires_in` (int ≥ 0) is the seconds left on the server; use it to correct the countdown. |
| 200 | `{"state":"approved","token":"fsr1_…","device_id":"49139e3a1db5a6ac","expires":1799662560,"hard_expires":1823422560}` | Store and stop polling. The token is issued **once**; the next poll → 410. |
| 410 | `login_expired` — «Время на подтверждение вышло — начни вход заново.» | Covers 120 s passing, an unknown `login_id`, an already issued, cancelled or expired login, and an approved login not picked up within 180 s. |
| 410 | `login_denied` — «Вход отклонён в Telegram.» | A wrong number was tapped, «Это не я» was tapped, or the login was approved but password login was locked meanwhile. |
| 409 | `too_many_devices` | Ten devices already have access at the moment of issue. |
| 503 | `app_disabled` | |

**`approved` field types.**
- `token` — string, 48 characters.
- `device_id` — string, 16 hex.
- `expires` — int, created + 90 days.
- `hard_expires` — int, created + 365 days.

Observed `approved` body:
```json
{"state":"approved","token":"fsr1_TestTokenTestTokenTestTokenTestTokenTestTok","device_id":"49139e3a1db5a6ac","expires":1799662560,"hard_expires":1823422560}
```

### 2.3 `POST /auth/cancel`
**Request:** `{"login_id":"<64 hex>"}`.
- If the login was `pending` or `approved` → 200 `{"ok":true,"state":"cancelled"}`, and the bot message is edited to «↩️ Вход отменён в приложении.»
- Otherwise → 200 `{"ok":true,"state":"<current state>"}`. The state is one of `"issued"`, `"expired"`, `"denied"`, `"notme"`, `"cancelled"`. Observed: `{"ok":true,"state":"issued"}`.
- Unknown `login_id` → `410 login_expired`. Bad format → `400 bad_param`.

Always treat 200 as "login closed".

### 2.4 `POST /auth/logout`
- Bearer token required. Send no body or `{}`; any field → `400 bad_param`.
- 200 `{"ok":true}`. The server revokes this device (`revoked_by=self`) and notifies Telegram.
- **The client deletes the token from Keychain whatever happens:** 200, 401, a network error, anything.

### 2.5 `GET /me`
Observed:
```json
{"device":{"id":"4ef97d314dfc8030","name":"iPhone владельца","created":1791886560,"expires":1799662560,"hard_expires":1823422560},"now":1791886560}
```
- Types: `id` string (16 hex), `name` string; `created`, `expires`, `hard_expires`, `now` are ints.
- `expires` slides: 90 days from the last request, refreshed at most every 5 min, capped at `hard_expires`.
- Use `/me` on launch after unlock, to validate the token, and when opening Settings. Use `now` (server clock) for expiry maths.

### 2.6 `GET /status` (router CGI `status`, passed through)
- **Errors.**
  - `502 router_offline`: the tunnel is down, or the router stayed silent in the last 30 s, in which case the server answers immediately without calling it.
  - `504 router_timeout`: no reply within 20 s.
  - `502 router_bad_reply`: an empty or non-JSON body from the router.
  - `500 server_config` / `500 router_token`.
  - `429 busy` + `retry_after: 3`: the server's 2 router slots are taken. Message: «Роутер отвечает медленно: другие запросы к нему ещё ждут ответа. Повтори через несколько секунд.»
  - CGI errors with `source: "router"`.
- **Speed.** The CGI sleeps 1 s to sample CPU and network, so `/status` takes at least about 1.2 s.

**Schema.** These are exact types read from `cgi-bin/fspirat` `status_json()` and the files it reads.

```
{
  "running":      bool,     // pidof xray: ANY xray process, including svcping's temporary one
  "split_active": bool,     // passwall2 global node == Split; false → MyDirect does not work
  "current":      string,   // node id | "_direct" (no VPN) | "" (Split not found)
  "ping":         Ping|null,        // null after a reboot until the first fspirat-ping (≤5 min)
  "log":          [string],         // ≤8 lines "ДД.ММ ЧЧ:ММ текст", router time, may be []; NOT used in stage 3
  "history":      [[int,int]],      // [ts, ms] ≤288; [] after a reboot. Fallback chart only
  "targets":      Targets|null,     // service latency via the CURRENT server; null after a reboot
  "sub":          Sub|null,         // the subscription that expires first; null if unknown
  "subs":         [SubItem]|null,   // [] = no subscriptions; null = lua failed
  "svc_direct":   [string],         // service names sent "directly"
  "target_list":  [string],         // "kind|name|addr", e.g. "web|YouTube|https://www.youtube.com/generate_204"; may be []
  "svc":          {string: Targets},// key = node id or "direct"; ALWAYS a JSON object, may be {}
  "svc_running":  bool,
  "speed":        {"vpn": Speed|null, "direct": Speed|null},
  "devices":      [Device],
  "sys":          Sys
}
Ping = {
  "updated": int,           // when fspirat-ping finished
  "current": string,        // node that was current DURING that check (can differ from status.current)
  "socks":   bool,          // false = SOCKS 127.0.0.1:1070 unreachable (curl rc 7)
  "real":    int|null,      // VPN check "через VPN 204": ms > 0 = passed; 0 = FAILED; null = only when socks == false
  "nodes":   [{"id": string, "name": string, "ms": int /*0 = no answer*/, "group": string, "own"?: true}]
}
   // nodes: VLESS nodes of the subscription groups and own servers (group "fspirat" → own: true),
   //   minus names containing LTE|Россия|Обход, plus the current node. "_direct" is never in nodes.
   //   name has spaces trimmed but may start with a flag emoji.
Targets = {"ts": int, "base"?: int /*only in svc.direct: TCP to ya.ru, ms; 0 = no answer*/,
           "list": [{"kind": "web"|"mc", "name": string, "host": string, "vpn": int /*ms; 0 = no answer*/}]}
Sub     = {"ts": int, "up": int, "down": int, "total": int /*bytes; 0 = no limit*/, "expire": int /*unix; 0 = no expiry*/, "title": string}
SubItem = {"id": string, "name": string, "host": string, "hwid": bool, "nodes": int,
           "ts"?: int, "up"?: int, "down"?: int, "total"?: int, "expire"?: int}   // optional keys are absent after a reboot
Speed   = {"via": "vpn"|"direct", "ts": int, "down": int /*bit/s*/, "up": int /*bit/s*/, "latency": int /*ms*/,
           "ip": string, "country": string /*2 letters or ""*/, "server": string, "streams": int, "up_limited": bool}
Device  = {"name": string /*DHCP name, may be ""*/, "ip": string, "mac": string /*lowercase*/, "online": bool,
           "band"?: "2g"|"5g"|"6g"|"wired", "signal"?: int /*dBm, negative; 0 = unknown*/, "rate"?: int /*Mbit/s*/,
           "up": int, "dn": int /*bytes since the router's counter table was created; reset by reboot*/,
           "blocked"?: true, "sblocked"?: true, "direct"?: true, "sched"?: "HHMM-HHMM"}
           // band/signal/rate are present only for Wi-Fi clients in the assoclist; "wired" = online but not Wi-Fi.
           // Offline devices have no band.
Sys = {"cpu": int /*%, 0–100*/, "cores": int, "load": string /*"0.21 0.17 0.15", a STRING*/,
       "mem_total": int, "mem_avail": int, "disk_total": int, "disk_used": int /*overlay*/,
       "tmp_total": int, "tmp_used": int,                     // all memory and disk sizes in KiB
       "temp": int|null /*°C; null = no sensor*/, "uptime": int /*s*/, "model": string, "fw": string,
       "xray_rss": int /*KiB*/, "net": Net}
Net = {"dev": string, "rx": int /*bit/s, download*/, "tx": int /*bit/s, upload*/, "rx_total": int, "tx_total": int /*bytes since boot*/}
```

**Decoding rules.**
- Treat every optional key as optional and every `|null` as optional.
- Decode the int fields **leniently**: accept a JSON number with a fraction by rounding, and on any field failure fall back to the default instead of failing the whole document.
- A single bad device or node must not blank the Summary.

### 2.7 `GET /net`
- CGI `net`, about 1.1 s, server timeout 5 s.
- Body: `Net` from §2.6. Observed shape: `{"dev":"wan","rx":1000,"tx":2000,"rx_total":3,"tx_total":4}`.
- **Units.** `rx`/`tx` are **bits per second** (the CGI multiplies the byte delta by 8 over 1 s). `*_total` are **bytes**.

### 2.8 `GET /led`
- Body: `{"on": bool, "items": [{"name": string, "on": bool}]}`, or `{"absent": true}` when the router has no LED script. In the `absent` case `on` and `items` are missing.
- Hide the LED control when the body is absent, or before the first successful read.
- On AX3000T the item names are `blue:status`, `yellow:status`, `mt76-phy0`, `mt76-phy1`. Do not display them.

### 2.9 `GET /data?range=day`
- Built by PHP on the server from fspirat-watch files. **It works when the router is offline.**
- Stage 3 only needs `day`; omitting `range` also means day.

```
{
  "now": int, "range": "day", "step": 0,
  "points": [[int ts, int ms]],      // day: one point per minute from the server watcher. ms > 0 ok; 0 = VPN check failed; -1 = router offline
                                     // (week/month: [[mid_ts, avg|0|-1, fails, offline]], step 1800/7200; not stage 3)
  "stats": {"avg": int|null, "min": int|null, "max": int|null, "fails": int, "offline_min": int},
  "events": [[int ts, string kind, string text]],   // newest first, ≤100, within the range
  "offline_since": int|null,         // router silent since (server watcher); null when online
  "last_ok": int|null,               // last successful status read by the watcher
  "names": {mac: string},            // own device names; ALWAYS an object, may be {}
  "tpoints": {serviceName: [[int ts, int ms]]},     // object, may be {}; ms 0 = no answer
  "traffic": {mac: {"d": [int up, int down], "m": [int up, int down]}},   // bytes, today ("d") and this month ("m"); day = Europe/Samara; object, may be {}
  "speed": [[int ts, "vpn"|"direct", int down_bps, int up_bps, int latency_ms]],   // 90 days
  "mtg": object|null,                // stage 3: ignore
  "site": {"luci": string, "bot": string, "mtg": string, "panels": [string]},       // strings may be ""
  "newdevs": [{"ts": int, "mac": string /*lowercase*/}]   // app-only: newdev events of the last 7 days, newest first
}
```

**Event `kind` → level** (from `app.js` `LEVEL`):

| Level | Kinds |
|---|---|
| `err` | `offline`, `vpn_down` |
| `warn` | `auto`, `xraymem`, `reboot`, `newdev` |
| `ok` | `online`, `vpn_up` |
| `info` (anything else) | `manual`, `restart`, `update`, `router`, unknown |

**Event texts** come from `fspirat-watch`:
- «Роутер пропал со связи»
- «Роутер снова на связи (не было N мин)»
- «Новое устройство: <name> · <ip> · <band> (<mac>)»
- «Роутер перезагрузился»
- «VPN остановлен (Xray не запущен)»
- «VPN снова работает»
- «Xray занимает N МБ памяти»
- «Автопереключение: A -> B 85ms»
- «Сервер выбран вручную: <name>»
- «Перезапуск VPN»
- «Обновление подписки»
- other router lines as is

Before showing a text, replace the whole word `_direct` with «Напрямую (без VPN)» (regex `\b_direct\b`).

### 2.10 `POST /action/<name>`: common pipeline
The server runs these steps in order. Codes in brackets are what you get when a step fails.
1. Name check [404 `not_in_v1` / `not_found`].
2. Body parsed as JSON. `confirm` is taken out. The remaining keys must match the action's spec exactly, and `confirm` is only allowed on confirmable actions [400 `bad_param`].
3. **Rate limits** [429 `rate_limited` + `retry_after`]. This runs **before** the 428, so a limited action never shows the dialog.
4. The router stayed silent in the last 30 s [502 `router_offline`, no dialog].
5. **Only for confirmable actions sent with `confirm`:** take the global action lock [409 `busy`] and a router slot [429 `busy`, `retry_after: 3`]. Both happen **before** the confirm is checked, so a 409 or 429 here does **not** burn the confirm. The client may retry with the same `confirm` while `expires_in` lasts.
6. Confirm check (confirmable actions):
   - no `confirm` → **428** with the dialog (§2.11);
   - wrong, foreign or reused → 400 `confirm_invalid`;
   - older than 60 s → **428** again with a new confirm;
   - more than 20 confirms per minute → 429 `rate_limited`.
7. Jobs (`ping`): → **202** (§2.12). Other actions: take the action lock [409 `busy`], take a router slot [429 `busy`], call the router (POST, timeout ≤ 25 s).
8. The router body is passed through on 200. Router errors are mapped as follows:
   - `router_offline` 502, `router_timeout` 504, `server_config` 500, `router_token` 500;
   - CGI 400/409/500/503 with a code → same status + `"source":"router"`;
   - anything else → 502 `router_bad_reply`.
   
   If the router certainly did **not** run the action, it does not count toward the rate limits. A timeout does count, because the router may have run it.

**The five stage 3 actions:**

| Action | Body (exact) | Needs confirm (428) | Server `danger` | Face ID (app) | Server rate limits | 200 body |
|---|---|---|---|---|---|---|
| `ping` | none or `{}` | no (app pre-dialog, §7.4) | — | no | 1 per 30 s and 30 per hour per device; one long job at a time globally | **202** `{"job":"<16 hex>","poll_every":3}` |
| `restart` | `{}` then `{"confirm":"…"}` | yes | `high` | no | PW class: 1 per 15 s across **all** devices, 30 per hour per device | `{"ok":true}` |
| `update` | `{}` then `{"confirm":"…"}` | yes | `high` | no | PW class + 6 per hour per device | `{"ok":true}` |
| `reboot` | `{}` then `{"confirm":"…"}` | yes | `critical` | **yes** | 1 per 300 s and 3 per hour across **all** devices | `{"ok":true}` |
| `ledset` | `{"on": true\|false}` (a real bool; `1` or `0` → 400) | no | — | no | 10 per 60 s per device | `{"on":bool,"items":[…]}`, the new LED state |

- **PW class** (actions that restart PassWall): `switch`, `restart`, `update`, `subupdate`, `direct`, `diradd`, `dirdel`, `svcdirect`, `zapretset`. They share a 15 s pause across all devices. Observed: `restart` immediately followed by `update` → `429 rate_limited`, `retry_after: 15`.
- **ledset errors** come from the router: `503 {"error":"not installed","message":"Не установлено на роутере.","source":"router"}` or `409 busy` with `source: "router"`.
- **update errors:** `500 {"error":"subscribe.lua not found","message":"На роутере нет скрипта подписок PassWall.","source":"router"}`.

### 2.11 Confirm flow (428)
1. Send the action without `confirm`. The server answers:
```json
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"79217acbd9c66e9e1af7693324516b75","expires_in":60,"danger":"high","title":"Перезапустить VPN?","text":"Связь через VPN пропадёт на несколько секунд.","button":"Перезапустить"}
```
   Types:
   - `confirm` — 32 lowercase hex, single use;
   - `expires_in` — int, always 60;
   - `danger` — `"critical"`, `"high"` or `"medium"`;
   - `title`, `text`, `button` — strings to show **verbatim**. `text` may be `""` (generic fallback).
2. Show a modal with `title`, `text`, a cancel button «Отмена» and a confirm button labelled `button`.
   - **Style:** `danger == "critical"` → destructive (red, `err-fill`) confirm button. `high` and `medium` → normal accent button.
   - **Face ID:** when `danger == "critical"` and the setting «Face ID для опасных действий» is on (default on), run `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` **after** the user taps the button and before resending. If it fails → cancel silently.
3. Resend the **same body plus** `"confirm":"<hex>"` within `expires_in` seconds. For stage 3 the body is just `{"confirm":"…"}`.
   - If the dialog stayed open longer than ~55 s, do not resend. Start again from step 1 (a fresh 428).
   - If the resend gets **428 again** (expired), show the new dialog once more. Never auto-loop.
4. Outcomes of the resend:
   - 200 → success handling (§7.3);
   - 400 `confirm_invalid` → show the message, nothing happened;
   - 409 `busy` or 429 `busy` → show the message. The confirm is still valid until it expires; offer «Повторить».
   - 429 `rate_limited`, 502, 504, 500, 503 → show the message. On **504** add «Действие могло выполниться — проверь состояние через минуту.» **(proposed)**

**Exact 428 texts the server sends in stage 3** (`app_confirm_text`):

| Action | `danger` | `title` | `text` | `button` |
|---|---|---|---|---|
| restart | high | Перезапустить VPN? | Связь через VPN пропадёт на несколько секунд. | Перезапустить |
| update | high | Обновить подписки VPN? | Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. Если текущего сервера в подписке больше нет, роутер сам выберет другой. | Обновить |
| reboot | critical | Перезагрузить роутер? | Интернет дома пропадёт на 1–2 минуты, приложение на это время покажет «не на связи». Счётчики трафика устройств обнулятся. | Перезагрузить |

Observed reboot and update bodies:
```json
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"e9cd4613c347db5985111bd0d7e5e582","expires_in":60,"danger":"critical","title":"Перезагрузить роутер?","text":"Интернет дома пропадёт на 1–2 минуты, приложение на это время покажет «не на связи». Счётчики трафика устройств обнулятся.","button":"Перезагрузить"}
```
```json
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"578388c3d9636f559228b700ad625185","expires_in":60,"danger":"high","title":"Обновить подписки VPN?","text":"Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. Если текущего сервера в подписке больше нет, роутер сам выберет другой.","button":"Обновить"}
```

### 2.12 Jobs: `GET /jobs/{id}`
- `id` must be 16 hex and belong to **this device**; otherwise `404 not_found`. Jobs are deleted after 1 hour.
- Poll every `poll_every` (3) s after the 202.

| State | Body | Notes |
|---|---|---|
| running | `{"state":"running","action":"ping"}` | |
| done | `{"state":"done","action":"ping","http":200,"result":<raw router JSON>}` | For `ping`, `result` is a **full `/status` object** (§2.6): replace the stored status with it. |
| error | `{"state":"error","action":"ping","http":502,"error":"router_offline","message":"Роутер не на связи: туннель до сервера оборван или дома нет интернета."}` | Observed. May also carry `"source":"router"`. |
| error (stuck job) | `{"state":"error","action":"ping","http":500,"error":"server_error","message":"Ошибка на сервере — попробуй через минуту."}` | Returned when the job is still unfinished 150 s after creation. |

- **Start errors:** `409 busy` with the message «Проверка или тест скорости уже идут — дождись результата.»; `429 rate_limited`.
- **Duration.** The server calls the CGI with a 90 s timeout; fspirat-ping takes about 20 s. Client rule: stop polling after 160 s and show the job as an error.
- **Old data.** If the cron fspirat-ping is already running, the CGI returns the old data quickly. When `result.ping.updated < jobStartedAt - 5`, show «Показаны данные последней проверки» **(proposed, from inventory §7.10)**.
- **504 in a ping job** (`http: 504`, `router_timeout`) means the check is slow, not that the router is offline: «Проверка идёт дольше обычного — результат появится в Сводке через минуту.» **(proposed)**

### 2.13 Rate-limit summary (server, per device unless noted)
| Request | Limit |
|---|---|
| Login | 5 per hour per IP, 10 per hour in total, at most 2 pending at once. Password failures are shared with the web: 5 in 15 min → IP locked 15 min |
| ping | 1 per 30 s, 30 per hour |
| PW class | 1 per 15 s across all devices, 30 per hour |
| update | 6 per hour |
| reboot | 1 per 5 min and 3 per hour across all devices |
| ledset | 10 per 60 s |
| confirms issued | 20 per 60 s |
| nginx | 5 r/s per IP (burst 40) and 2 r/s per token (burst 20) |
| fail2ban | 10 × `token_invalid`, login_denied or token-in-URL within 10 min → IP banned 15 min |

**A fail2ban ban also cuts the home off from its own NL VPN server on port 443. Never generate `token_invalid`.**

---

## 3. Errors

### 3.1 Complete table
Columns: HTTP | `error` | where it comes from | client behaviour.

| HTTP | `error` | Where | Behaviour |
|---|---|---|---|
| 400 | `bad_param` | any | message; for actions also log it as a client bug |
| 400 | `too_long` | login (name > 40) | message |
| 400 | `token_in_url` | any | message; should never happen |
| 400 | `confirm_invalid` | action resend | message |
| 400 | router codes, e.g. `bad node` | actions | message (`source: "router"`) |
| 401 | `token_missing` | auth | **LOGOUT** |
| 401 | `token_invalid` | auth | **LOGOUT** |
| 401 | `token_expired` | auth | **LOGOUT** |
| 401 | `token_revoked` | auth | **LOGOUT** |
| 401 | `bad_password` | login only | stay on login, show message; `left` |
| 403 | `browser_request` | any | message (client bug) |
| 404 | `not_found` | unknown path, job, or `/router/app/` from nginx | message |
| 404 | `not_in_v1` | action | message |
| 405 | `method` | any | message (client bug) |
| 409 | `busy` | action lock, job lock, router CGI busy | message, re-enable the button |
| 409 | `too_many_devices` | login, poll | message on the login screen |
| 410 | `login_denied` | poll | back to the login form, message |
| 410 | `login_expired` | poll, cancel | back to the login form, message |
| 413 | `too_large` | app.php or nginx (no message) | fallback text |
| 415 | `not_json` | app.php | message |
| 428 | `confirm_required` | confirmable action | dialog, not an error |
| 429 | `rate_limited` | app.php or nginx (no message) | message + «Повтори через N с.», block the same request until `retry_after` |
| 429 | `locked` | login | message; disable «Войти» for `retry_after` with a countdown |
| 429 | `busy` | login (2 pending) or router slots | message; for reads just retry on the next tick |
| 500 | `server_error` | any | message |
| 500 | `server_config` | router call | message |
| 500 | `router_token` | router call | message |
| 500 | `no rule`, `subscribe.lua not found`, `nft` | router (`source: "router"`) | message |
| 502 | `router_offline` | router call | `/status`: offline mode (§7.5); actions: message |
| 502 | `router_bad_reply` | router call | reads: keep old data, retry on the next tick; show nothing unless it happens twice in a row; actions: message |
| 502 | `server_unavailable` | nginx (no message) | fallback text; **not** offline mode |
| 503 | `app_disabled` | any | full-screen state, keep the token, retry on pull-to-refresh |
| 503 | `tg_unavailable` | login | message on the login screen |
| 503 | `not installed` | router (`source: "router"`) | message |
| 504 | `router_timeout` | router call | `/status`: offline mode; actions: message + «Действие могло выполниться…»; ping job: «Проверка идёт дольше обычного…» |

**LOGOUT** means:
- stop all polling and jobs;
- delete the token, `device_id`, `expires` and `hard_expires` from Keychain;
- clear in-memory data;
- show the login screen with the server `message` as a banner.

Only these four `token_*` codes log out. Any other 401 or 403, or an unparsable 401, never logs out: show a generic error instead.

### 3.2 Final client message mapping
**Rule:** if the body is JSON with a non-empty string `message`, show `message` **verbatim**. Otherwise use this table, keyed by `error`, then by HTTP status.

| Key | Russian text |
|---|---|
| `bad_param` | Неверные данные запроса — обнови приложение. |
| `token_in_url` | Ключ нельзя передавать в адресе запроса. Если это был настоящий ключ, он уже отозван — войди заново. |
| `too_long` | Слишком длинное значение. |
| `confirm_invalid` | Подтверждение не подошло — повтори действие. |
| `confirm_required` | Нужно подтверждение. |
| `token_missing` | Нужно войти. |
| `token_invalid` | Ключ не подходит — войди заново. |
| `token_expired` | Срок входа истёк — войди заново. |
| `token_revoked` | Доступ этого телефона отозван — войди заново. |
| `bad_password` | Неверный пароль. |
| `browser_request` | Запросы из браузера сюда не принимаются. |
| `not_found` | Не найдено. |
| `not_in_v1` | Это действие пока есть только в веб-панели. |
| `method` | Неверный метод запроса — обнови приложение. |
| `busy` | Другое действие ещё выполняется — подожди немного. |
| `too_many_devices` | Уже 10 телефонов с доступом — отзови старый в Настройках, в веб-панели или командой /apps в боте. |
| `login_denied` | Вход отклонён в Telegram. |
| `login_expired` | Время на подтверждение вышло — начни вход заново. |
| `too_large` | Слишком большой запрос. |
| `not_json` | Тело запроса должно быть JSON. |
| `rate_limited` | Слишком часто — подожди немного. |
| `locked` | Вход временно закрыт после неверных попыток. |
| `server_error` | Ошибка на сервере — попробуй через минуту. |
| `server_config` | Сервер не настроен: нет ключа роутера (нужен Deploy server). |
| `router_token` | Роутер отклонил ключ сервера — нужен Deploy server. |
| `router_offline` | Роутер не на связи: туннель до сервера оборван или дома нет интернета. |
| `router_timeout` | Роутер не ответил вовремя. |
| `router_bad_reply` | Роутер ответил непонятно — попробуй ещё раз. |
| `app_disabled` | Приложение выключено на сервере. Веб-панель работает. |
| `tg_unavailable` | Telegram-бот недоступен — войти в приложение сейчас нельзя. |
| `server_unavailable` | Сервер панели не ответил — попробуй через минуту. **(proposed; nginx sends no message)** |
| `bad mac` | Неверный адрес устройства (MAC). |
| `bad node` | Такого сервера нет — обнови список. |
| `bad via` | Неизвестный вид теста. |
| `domain` | Нужен домен вида site.ru. |
| `time` | Неверное время. |
| `resolve` | Не удалось узнать IP сервера. |
| `no target` | Нет такого сервиса. |
| `no rule` | В PassWall нет правила MyDirect. |
| `bad sub` | Нет такой подписки — обнови список. |
| `bad on` | Неверный режим. |
| `bad strategy` | Нет такой стратегии. |
| `not installed` | Не установлено на роутере. |
| `nft` | Роутер не смог изменить правила. |
| `subscribe.lua not found` | На роутере нет скрипта подписок PassWall. |
| other code with `source: "router"` | Роутер не смог выполнить действие. |
| **no HTTP response** (URLError: offline, DNS, TLS, timeout) | Нет связи с сервером. Проверь интернет и попробуй ещё раз. **(proposed; web: «Нет связи с сайтом. Проверь интернет и попробуй ещё раз.»)** |
| non-JSON body, 5xx | Ошибка на сервере — попробуй через минуту. |
| non-JSON body, 4xx | Запрос не принят (код N). **(proposed)** |

**Additions to the message:**
- `429` with `retry_after`: append « Повтори через N с.» when N ≤ 90, or « Повтори через M мин.» with M = ceil(N/60) otherwise **(proposed)**.
- `401 bad_password`: the server message already includes «Осталось попыток: N.»

For reference, the web's own texts (`app.js` `api()`) are kept in §9 #9. The app does not use them.

---

## 4. «Сводка» (Summary): content and rules

All rules are ported from `web/app.js` `renderHero()` and its helpers. **Deviation** marks a deliberate stage 3 change.

### 4.1 Data sources
- **`status`** (`/status` or the `ping` job result): verdict, current server, VPN check, services, subscription, router stats, devices online.
- **`net`** (`/net`): «Интернет сейчас». Fallback: `status.sys.net`.
- **`data`** (`/data?range=day`): traffic today, mini chart, last events, offline banner. Fallback chart: `status.history`.
- **`led`** (`/led`): the LED toggle.

### 4.2 Verdict («итог»)
Build an ordered list of items `(name, level, text)` with `level` ∈ `ok`, `warn`, `err`, then add the optional `why` item.

**If offline mode is on, or no status has loaded yet after an error:**
- items = `[("Роутер", err, "не на связи")]`;
- hide the current-server block.

**Deviation:** before the **first** load attempt has finished, show the title «Проверяю…» with the neutral colour `faint` and no items. The web shows «не на связи» here, which is a known defect.

**Otherwise,** with `s = status`, `p = s.ping ?? {}`, `nodes = p.nodes ?? []`:
1. **Роутер.**
   - `ram = mem_total>0 ? 1 - mem_avail/mem_total : 0`; `disk = disk_total>0 ? disk_used/disk_total : 0`; `hot = temp != null && temp >= 85`.
   - level = `warn` if `ram > 0.9 || disk > 0.9 || hot`, else `ok`.
   - text = the first that applies: `"\(temp)°C"` (no space, when hot), «мало памяти», «флеш почти полон», otherwise «в сети».
2. **VPN.** First compute `vpnOk = s.running && (p.socks != true || (p.real ?? 0) > 0)`. In JS, `!p.socks` is true when `socks` is false **or absent**.
   - `s.current == "_direct"` → (`warn`, «выключен — всё напрямую»);
   - else `!s.running` → (`err`, «остановлен»);
   - else `!vpnOk` → (`err`, «не проходит»);
   - else `(p.real ?? 0) > 250` → (`warn`, «работает»);
   - else (`ok`, «работает»).
3. **Интернет.** `net = vpnOk || (s.svc["direct"]?.base ?? 0) > 0` → (`ok`, «есть») or (`err`, «нет»).
4. **Серверы.** `alive` = count of nodes with `ms > 0`.
   - level: `alive >= 2` → `ok`, `alive == 1` → `warn`, otherwise `err`;
   - text: `"\(alive) из \(nodes.count)"`.
   - **Deviation:** if `s.ping == null` (right after a reboot) → (`warn`, «ещё не проверены»). The web shows `err` «0 из 0».
5. **Сервисы** — only if `t = s.targets?.list ?? []` is non-empty. `bad` = items with `!(vpn > 0)`.
   - `bad` non-empty → (`warn`, «нет ответа: » + the names joined by «, »);
   - otherwise (`ok`, «отвечают»).
6. **Подписка.**
   - Pick `sub`: from `s.subs ?? []`, keep items whose `expire` is non-zero, sort by `expire` ascending, take the first; otherwise fall back to `s.sub`.
   - `left = sub?.expire > 0 ? floor((sub.expire - now)/86400) : nil`.
   - Add the item only if `left != nil && left <= 3`: (`err`, «закончилась») if `left < 1`, else (`warn`, «осталось N дн.»).
7. **why.** If `!s.split_active`, add an extra `warn` item with no name and the text «в PassWall выбран не Split». Also show the warning box: «В PassWall выбран не узел Split: правило прямых сайтов не работает, а смена сервера здесь ни на что не повлияет. Выбери Split в Basic Settings → Node.»

**Title and colour.**
- `worst` = `err` if any item is err; else `warn` if any item is warn or `why` is set; else `ok`.
- Title: `ok` → «Всё работает», `warn` → «Требует внимания», `err` → «Есть проблема».
- The lamp, the top accent line and the item dots use the level colours (§6).

**Item rendering.** A dot in the level colour, then the name in `dim`, then the text in **bold**. The bold text is `text` colour for ok, `warn` for warn and `err` for err. Example: «● VPN **работает**».

**Under the title:** «обновлено только что / N сек назад / N мин назад», counted from the last **successful `/status`** only (or the ping job result). Refresh the label every 5 s.

### 4.3 Current server
- The label «Подключён сервер» plus a name:
  - `current == "_direct"` → «Напрямую (без VPN)»;
  - otherwise the first `p.nodes` entry with `id == current` → `name` trimmed;
  - otherwise the raw id;
  - `current == ""` → «—».
- **Subtitle (proposed).**
  - If the node has `own == true` → tag «свой». These are the own servers `fspiratNL` / `fspiratDE`, group `fspirat`.
  - Else if `group` is non-empty → «Подписка \(group)».
  - For `_direct` → tag «без VPN».

### 4.4 VPN check («Задержка»; the "через VPN 204" check)
- Tile label «Задержка»; caption «Как пинг: ответ сайта через VPN по уже открытому соединению. Раз в 5 минут.»
- Value:
  - `p.socks == true && (p.real ?? 0) > 0` → `"\(real) мс"`, coloured by `msCls(real)`;
  - `p.socks == true && real == 0` → «VPN не проходит» in `err`. The web shows the short «нет»; the owner's plan wording is «VPN не проходит».
  - `socks` false or absent, or `ping == null` → «—» in `faint`.
- Footer: «Проверено \(ago(p.updated))», only if `p.updated` is present.

### 4.5 Service tiles (YouTube, Discord, Telegram, …)
- **List of services:**
  - if `s.targets?.list` is non-empty, use its items `(name, kind, host)`;
  - otherwise parse `s.target_list` strings `"kind|name|addr"` → `host = addr` without the `scheme://` prefix and without anything from the first `/` or `:` (JS: `replace(/^[a-z]+:\/\//i,'').replace(/[/:].*$/,'')`).
- **Value** for each service, from the current server: `r = s.targets` (for the current node, including `_direct`); otherwise `s.svc[current]`. The value is `r.list.first(name == service.name)?.vpn`.
  - `> 0` → `"\(v) мс"` coloured by `msCls`.
  - **Deviation:** `== 0` → «нет ответа» in `err`; missing (`nil`) → «—» in `faint`. The web shows a red «—» for both.
- **Icon** chosen by host (lowercased) or name (`app.js` `svcIcon`):
  - host ends in `youtube.com`, `youtu.be` or `googlevideo.com`, or name == «youtube» → YouTube (`play.rectangle`);
  - `discord.com`, `discord.gg`, `discordapp.com` / «discord» → `bubble.left.and.bubble.right`;
  - `telegram.org`, `t.me`, `telegram.me` / «telegram» → `paperplane`;
  - `instagram.com`, `cdninstagram.com` / «instagram» → `camera`;
  - else `kind == "mc"` → `cube`;
  - else `globe`.
  
  "Ends in" means the regex `(^|\.)domain$`.
- **Defaults** on a fresh router (`targets.default`): `web|YouTube|https://www.youtube.com/generate_204`, `web|Discord|https://discord.com/api/v10/gateway`, `web|Telegram|https://api.telegram.org/`.

### 4.6 Internet now («Интернет сейчас») and traffic today
- **Speed.**
  - «Загрузка» = `speed(net.rx)` with an `arrow.down` icon;
  - «Отдача» = `speed(net.tx)` with `arrow.up`;
  - both inputs are **bits/s**.
  - Under them, optionally: «С момента включения: \(bytes(rx_total))» and the same for `tx_total`.
- **Today.**
  - «Сегодня ↓» = `bytes(sum of traffic[*].d[1])`, shown only when the sum > 0;
  - optional «↑» = `bytes(sum of d[0])`;
  - caption «Все устройства дома, с полуночи».
  - The day boundary is midnight **Europe/Samara**.

### 4.7 Router block («Роутер»)
- **Meters** with a 6 px bar. The bar is `acc` normally, `warn` from 65 % and `err` from 85 %. Percent is an integer, clamped to 0–100.

| Meter | Percent | Caption |
|---|---|---|
| «Процессор» | `cpu` | «Средняя нагрузка \(load), ядер: \(cores)» |
| «Оперативная память» | `round((mem_total-mem_avail)/mem_total*100)` | `"\(mb(used)) из \(mb(mem_total))"` |
| «Флеш-память» | `disk_total>0 ? round(disk_used/disk_total*100) : 0` | `"\(mb(disk_used)) из \(mb(disk_total)): пакеты и настройки"` |

  «Временные файлы» (`tmp`) is optional on Summary.
- **Facts:**
  - «Температура» → `"\(temp) °C"` (with a space) or «нет датчика» when null;
  - «Работает без перезагрузки» → `upt(uptime)`.
- **Header:** `sys.model` (or «Роутер» when empty) and `sys.fw`.
- **LED toggle** (row «Подсветка», lightbulb icon `lightbulb` or `lightbulb.slash`) — §7.3.
- **Button «Перезагрузить роутер»** — destructive outline style.

### 4.8 Subscription line
Shown only if `sub?.expire > 0`, using `sub` and `left` from §4.2.

Template:
- `many` = `(s.subs ?? []).count > 1`;
- prefix: `many` → «"\(sub.name)" до », otherwise «Подписка до »;
- then: `{d MMMM}` · «осталось **\(left) дн.**»;
- `left <= 3` → that number in `err`;
- if `sub.down > 0`, append: « · израсходовано \(bytes(down + up))» + (`total > 0` ? « из \(bytes(total))» : «, без лимита»).

The date is formatted «d MMMM» in the `ru_RU` locale and Europe/Samara time zone, for example «31 октября». When the `s.sub` fallback is used, `name` is missing: use `title`, or «Подписка».

Example from the normal fixture: «Подписка до 31 октября · осталось 17 дн. · израсходовано 39.2 ГБ из 200.0 ГБ».

### 4.9 Mini history chart (24 h)
- **Source:** `data.points`. If `/data` failed and no data is loaded, fall back to `status.history` (`[ts, ms]`).
- **Window:** x from `now - 86400` to `now`. y from 0 to `max(150, max of ok ms) * 1.15`.
- **Marks:**
  - `ms > 0` → line in `acc`, width 1.75, with an area fill in the `area` token. Break the line at any point with `ms <= 0`, and at gaps longer than 750 s.
  - `ms == 0` (VPN check failed) → a short red bar at the bottom (`err`).
  - `ms < 0` (router offline) → a full-height band in the `offline` token, width = 300 s.
  - Grid lines in `chart-grid`.
- **Optional stats row** from `data.stats`:
  - «Средняя» `avg` мс, «Лучшая» `min`, «Худшая» `max` (each «—» when null);
  - «Сбоев» `fails`;
  - «Без связи» `minutes(offline_min)`, or «0 мин».
- **Empty state:** «данных за этот период пока нет».

### 4.10 Last events
- The first **5** entries of `data.events` (already newest first). The web mini list shows 6; the owner's plan says 5.
- Row: `when(ts)` · a level chip · the text.
- Chip label: `err` «Ошибка», `warn` «Внимание», `ok` «Успех», `info` «Действие».
- Chip colours: text in the level colour, background in its `-soft` token, border in its `-bd`/ring token (§6).
- Show colour **and** word, for VoiceOver.
- Empty state: «Событий пока нет. Здесь появятся смены сервера, перезагрузки, сбои VPN и новые устройства.»

### 4.11 Devices online
- `n = status.devices.filter(\.online).count` → «\(n) в сети».
- The full list is stage 4. Optionally show the top 4 online devices by today's ↓ traffic. Use `data.names[mac] ?? device.name`, or «Без имени» when both are empty.

### 4.12 Offline banner
Shown when offline mode is on (§7.5).
- **Heading:** «Роутер не на связи».
- **Line:** `since = data.offline_since ?? data.last_ok`.
  - If `since` is set: «Не на связи с \(whenShort(since)) · уже \(minutes(m))», where `m = max(1, round((now - since)/60))`.
    - Append « · последний ответ \(whenShort(last_ok))» if `last_ok` is set and differs from `since`.
    - Example: «Не на связи с 14:04 · уже 12 мин · последний ответ 14:03».
  - If neither is set: «Сервер не получает ответа от роутера».
- **Body (verbatim from the web):**
  - «Почему так бывает»: «дома пропал интернет или свет;» «роутер перезагружается (1–2 минуты);» «оборвался туннель от роутера до сервера.»
  - «Что сделать»: «подождать 2–3 минуты: туннель поднимается сам;» «проверить, есть ли дома интернет без VPN;» «если не помогло — выключить роутер из розетки на 10 секунд.»
  - Note: «Кнопки не работают, пока роутер не на связи. История и журнал — с сервера.»
- **What stays visible:** the chart, the events and today's traffic. They come from `/data`.

### 4.13 Buttons on Summary
| Label | SF Symbol | Action | Dialog |
|---|---|---|---|
| «Проверить» (primary) | `arrow.clockwise` | `ping` job; busy label «Проверяю, ~20 сек…» | app pre-dialog only when §7.4 applies |
| «Перезапустить VPN» | `arrow.counterclockwise` | `restart` | 428 dialog |
| «Обновить подписки» | `arrow.down` | `update` | 428 dialog |
| «Перезагрузить роутер» | `power` | `reboot` | 428 dialog + Face ID; destructive style |
| LED toggle | `lightbulb` / `lightbulb.slash` | `ledset` | none |

The LED toggle's accessibility label is «Подсветка роутера».

None of these may fire from a swipe, pull-to-refresh or an accidental tap. Pull-to-refresh only re-reads data.

---

## 5. Formatting
All functions are ported from `app.js`. Numbers use a `.` decimal separator, exactly as the web does (`toFixed`). Time is shown in **Europe/Samara** (router time).

| Function | Rule | Examples |
|---|---|---|
| `speed(bps)` (input bits/s) | `bps >= 1e6` → `(bps/1e6)` with 0 decimals if `bps >= 1e8`, else 1 decimal, + « Мбит/с»; else `round(bps/1e3)` + « кбит/с» | 18734216 → «18.7 Мбит/с»; 123456789 → «123 Мбит/с»; 1203448 → «1.2 Мбит/с»; 640000 → «640 кбит/с»; 0 → «0 кбит/с» |
| `mb(kib)` (input KiB) | `kib >= 1048576` → `(kib/1048576)` with 1 decimal + « ГБ»; `kib < 10240` → `(kib/1024)` with 1 decimal + « МБ»; else `round(kib/1024)` + « МБ» | 123792 → «121 МБ»; 245632 → «240 МБ»; 3460 → «3.4 МБ»; 2097152 → «2.0 ГБ» |
| `bytes(b)` (input bytes) | `mb(b/1024)` | 40802189312 → «38.0 ГБ»; 1621098496 → «1.5 ГБ»; 53477376 → «51 МБ»; 5000000 → «4.8 МБ»; 0 → «0.0 МБ» |
| `ms(v)` | `"\(v) мс"` — **deviation:** the web uses «ms», the owner's plan uses «мс» | 48 → «48 мс» |
| `msCls(v)` | `< 120` → ok (`acc-tx`); `< 250` → mid (`warn`); else slow (`err`) | 48 → ok, 180 → mid, 300 → slow |
| `pingLv(v)` (bars, 0–5) | `!(v > 0)` → 0; `< 60` → 5; `< 120` → 4; `< 250` → 3; `< 400` → 2; else 1 | |
| `ago(ts)` | `s = max(0, round(now - ts))`; `s < 60` → «только что»; `< 3600` → «\(round(s/60)) мин назад»; else «\(round(s/3600)) ч назад» | |
| `updatedLabel(sec)` | `< 5` → «обновлено только что»; `< 60` → «обновлено N сек назад»; else «обновлено \(round(sec/60)) мин назад» | |
| `upt(s)` | `d = s/86400`, `h = s%86400/3600`, `m = s%3600/60` (integer division); `d>0` → «d д h ч»; `h>0` → «h ч m мин»; else «m мин» | 352812 → «4 д 2 ч»; 3700 → «1 ч 1 мин»; 95 → «1 мин» |
| `minutes(m)` | `m < 60` → «m мин»; `m < 1440` → «\(m/60) ч» + (`m%60 > 0` ? « \(m%60) мин» : «»); else «\(m/1440) д \(m%1440/60) ч». Trim the result; the web leaves a trailing space. | 12 → «12 мин»; 75 → «1 ч 15 мин»; 120 → «2 ч»; 1500 → «1 д 1 ч» |
| `when(ts)` (journal) | same Samara day as now → «сегодня HH:mm»; the previous day → «вчера HH:mm»; else «dd.MM HH:mm» | «сегодня 14:20», «вчера 09:05», «12.10 14:20» |
| `whenShort(ts)` (offline banner) | same day → «HH:mm»; the previous day → «вчера HH:mm»; else «dd.MM HH:mm». The plan example is «Не на связи с 14:20». | |
| `dayMonth(ts)` | `DateFormatter`, locale `ru_RU`, format `d MMMM`, Europe/Samara | 1793404800 → «31 октября» |
| `plural(n, one, few, many)` | `n%10==1 && n%100!=11` → one; `n%10 ∈ 2…4 && n%100 ∉ 12…14` → few; else many | `plural(n,"запись","записи","записей")` |
| percent | an integer + «%» | «50%» |
| temperature | fact «\(t) °C» / «нет датчика»; verdict item «\(t)°C» | |

**Rounding.** JS `Math.round` rounds half up (toward +∞). `toFixed` rounds the decimal representation. Use `(x * 10).rounded(.toNearestOrAwayFromZero) / 10` for 1 decimal; this is good enough for positive values.

**Time zone.** Use `TimeZone(identifier: "Europe/Samara")` (+04, no DST) for every date and time shown, and say so once in Settings: «Время — роутера (Самара, UTC+4)» **(proposed)**. The web uses the browser's local zone (§9 #10).

---

## 6. Colours and style (from `web/app.css` `:root`)
Implement each token as `Color(light:dark:)`. The theme setting is «Как в системе / Светлая / Тёмная», stored with `@AppStorage("theme")` and applied with `.preferredColorScheme`.

| Token | Dark | Light | Used for |
|---|---|---|---|
| bg | #090B0F | #F6F8FB | screen background |
| surface | #11151B | #F1F5F9 | tiles, meter track |
| card | #161B22 | #FFFFFF | cards (panels) |
| raise | #1C222B | #FFFFFF | sheets, menus |
| hover | #1A2029 | #F4F7FA | pressed row |
| border | #252B35 | #E2E8F0 | card border (1 px) |
| border-2 | #313946 | #CBD5E1 | stronger border, inputs |
| line | #1F252E | #EDF1F5 | dividers inside cards |
| text | #F1F5F9 | #0F172A | primary text |
| dim | #94A3B8 | #64748B | secondary text, verdict item names |
| faint | #64748B | #94A3B8 | tertiary text, neutral or unknown state, «—» |
| acc / acc-fill | #34D399 | #059669 | ok dots, lamp ok, chart line, primary button fill, meter fill |
| acc-tx | #34D399 | #047857 | ok-coloured **text** (latency ok, «Успех» chip) |
| acc-hov | #4ADEA8 | #047857 | primary button pressed |
| on-acc | #052E1F | #FFFFFF | text on a primary button |
| acc-soft | rgba(52,211,153,.10) | rgba(5,150,105,.08) | ok soft background, lamp ok background |
| acc-ring | rgba(52,211,153,.32) | rgba(5,150,105,.30) | ok chip border |
| warn | #FBBF24 | #B45309 | warn dot, text and bar (≥ 65 %), latency mid |
| warn-soft | rgba(251,191,36,.10) | rgba(217,119,6,.09) | warn background |
| warn-bd | rgba(251,191,36,.30) | rgba(217,119,6,.30) | warn border |
| err | #F87171 | #DC2626 | err dot and text, bar ≥ 85 %, latency slow, chart fail bars |
| err-fill | #DC2626 | #DC2626 (pressed #B91C1C) | destructive button fill (white text) |
| err-soft | rgba(248,113,113,.10) | rgba(220,38,38,.06) | err background (offline banner gradient) |
| err-bd | rgba(248,113,113,.32) | rgba(220,38,38,.28) | err border (offline card, destructive outline button) |
| info | #60A5FA | #2563EB | «Действие» chip |
| info-soft | rgba(96,165,250,.10) | rgba(37,99,235,.07) | info background |
| info-bd | rgba(96,165,250,.30) | rgba(37,99,235,.25) | info border |
| chart-grid | rgba(148,163,184,.09) | rgba(100,116,139,.12) | chart grid |
| area | rgba(52,211,153,.10) | rgba(5,150,105,.10) | chart area fill |
| offline | rgba(148,163,184,.10) | rgba(100,116,139,.10) | chart "router offline" band |
| backdrop | rgba(3,5,8,.72) | rgba(15,23,42,.35) | modal backdrop |

**Fixed colours.**
- Ping bars: #10B981 for levels 5–4, #F59E0B for 3, #EF4444 for 2–1. Inactive bars #94A3B8 at 0.35 opacity. Level 0 shows a red cross.
- Logo gradient: 145°, #34D399 → #047857.

**Level → colour.**

| Level | Dot and bold text | Soft background | Border |
|---|---|---|---|
| ok | acc (dot) / acc-tx (text) | acc-soft | acc-ring |
| warn | warn | warn-soft | warn-bd |
| err | err | err-soft | err-bd |
| info | info | info-soft | info-bd |
| neutral («Проверяю…») | faint | surface | — |

The verdict lamp is 44×44 with radius 12, a `*-soft` fill and a 12 pt dot in the level colour. In `err` it pulses unless Reduce Motion is on.

**Shapes and type.**
- Corner radii: cards 14, tiles 10, buttons 8, modals 16, chips 999.
- Buttons are 36 pt tall (small ones 32). The meter bar is 6 pt.
- Fonts: Inter for UI text (base 14.5 pt); JetBrains Mono for numbers, ms, IP, MAC and times, with tabular digits. Use `Font.custom(…, relativeTo:)` with SF Pro and SF Mono as fallbacks; weight 650 → `.semibold`.
- Sizes: verdict title 20/650; server name 22/650; card heading 15/600; sub-heading 11.5/600 uppercase with .06em tracking; KPI mono 14/600; «Интернет сейчас» mono 26/600; chips 11/500; modal title 17/650.

---

## 7. Client behaviour (stage 3)

### 7.1 Polling
Rules from inventory §9.1 and `app.js` `every()`:
- One in-flight request per kind; skip a tick while the previous request of that kind is running.
- Polling runs only while `scenePhase == .active` and the Summary is visible.
- When the app returns to active, refresh `status`, `data` and `led` immediately. `/net` resumes on its own timer.
- There are no background tasks.

| Kind | Interval | Conditions |
|---|---|---|
| `/status` | 30 s | also on launch, on pull-to-refresh and after actions (§7.3) |
| `/net` | 3 s | only while the «Интернет сейчас» card is on screen; not in offline mode; not in a quiet window |
| `/data?range=day` | 60 s | also on launch and on pull-to-refresh; **keeps running in offline mode** |
| `/led` | 300 s | also on launch and on refresh; after `ledset`, use its response body |
| `/me` | on launch or unlock, and when Settings opens | |

Pull-to-refresh (`.refreshable`) re-reads `status`, `data`, `led` and `/me` in parallel. It never triggers actions.

**429 on a read:** honour `retry_after` for that kind and skip ticks until then.

### 7.2 Quiet windows and busy buttons
During a quiet window:
- errors from `/status` are suppressed: no toast, and offline mode does not switch on;
- `/net` is paused;
- a banner is shown;
- the listed buttons are disabled.

| Action (after 200) | Quiet window | Re-read `/status` at | Disabled during the window | Banner and toast |
|---|---|---|---|---|
| restart | 15 s | +15 s | Проверить, Перезапустить VPN, Обновить подписки, Перезагрузить роутер | banner «VPN перезапускается…»; toast «VPN перезапускается.» |
| update | none (0) | +60 s, then the normal 30 s cycle | Перезапустить VPN and Обновить подписки for 15 s (the server's PW pause) | toast «Подписки обновляются — список серверов обновится через 1–2 минуты, потом VPN перезапустится на несколько секунд.» **(proposed)**; web: «Подписка обновляется, список серверов обновится примерно через минуту.» |
| reboot | 150 s | +150 s | **all** router buttons, including the LED | banner «Роутер перезагружается…»; toast «Роутер перезагружается. Приложение само обновится, когда он вернётся.» (adapted from the web) |
| ping | none | the job result replaces status | «Проверить» while the job runs | done: toast «Проверка серверов завершена.» |
| ledset | none | — | the LED toggle while the request runs | «Подсветка роутера включена.» / «Подсветка роутера выключена.» |

Plan §2 says: «Пока VPN перезапускается, остальные такие кнопки отключены. Вместо ошибок видна плашка «VPN перезапускается…»». The table above implements this.

### 7.3 Action success handling
- Never retry a POST automatically. The only automatic follow-ups are polling `/jobs/{id}` and re-reading data.
- Use `.sensoryFeedback(.success)` on 200 and `.sensoryFeedback(.error)` on errors.

### 7.4 Ping pre-dialog
- **Condition:** `status.ping != nil && status.ping.socks == true && status.ping.real == 0`. `real` is int 0 here; `null` does not count.
- **Dialog (proposed, based on plan §2):**
  - title «VPN сейчас не проходит. Проверить?»
  - text «Если проверка снова не пройдёт, роутер сам переключит сервер, и VPN перезапустится на несколько секунд.»
  - buttons «Отмена» / «Проверить»
- No Face ID and no server confirm. The server does not require `confirm` for `ping`; sending one → 400.

### 7.5 Offline mode
- **On:** `/status` fails with `error ∈ {router_offline, router_timeout}` (502 or 504) **outside** a quiet window.
- **Off:** the next successful `/status`.
- **While offline:**
  - show the banner (§4.12);
  - the verdict is «Есть проблема» with «Роутер — не на связи»;
  - disable every button that reaches the router: Проверить, Перезапустить VPN, Обновить подписки, Перезагрузить роутер, LED;
  - stop `/net`;
  - keep polling `/status` (30 s) and `/data` (60 s), and keep showing the chart, events and traffic from `/data`.
- **Not offline:**
  - `router_bad_reply`: keep the last status;
  - `server_unavailable`, `server_error`, URL errors: show the error and keep the last data. The server itself is the problem.

### 7.6 Login flow
1. **Form fields:**
   - «Пароль панели» (secure field);
   - «Название телефона», default «iPhone», up to 40 characters, editable. `UIDevice.name` is generic on iOS 16+.
   
   Button «Войти», enabled only when the password is non-empty and the trimmed name is non-empty.
2. `POST /auth/login`. Errors are shown on the form (§2.1). On `429 locked` or `rate_limited`, disable «Войти» for `retry_after` seconds with a countdown.
3. **200 → number screen.**
   - Show the large `number`, the text «Нажми в Telegram-боте число N» **(proposed)**, and a countdown from `expires_in` (120).
   - Button «Отмена» → `POST /auth/cancel`, then return to the form. Ignore the result.
4. **Polling.** `POST /auth/poll` every `poll_every` (2) s. Update the countdown from `expires_in`. Keep polling through network errors until the countdown reaches 0, then poll once more.
   - `approved` → store the token (§7.7) → `GET /me` → offer Face ID: «Включить Face ID для входа в приложение?» **(proposed)** → Summary.
   - `410 login_denied` / `login_expired` / `409 too_many_devices` → back to the form with the message.
5. Never store `login_id` or the password anywhere. Never log them.

### 7.7 Token storage and lifetime
- **Keychain item:**
  - `kSecClassGenericPassword`, service `xyz.fspirat.router`, account `device-token`;
  - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; not synchronizable, so not in iCloud or backups.
  
  Store `device_id`, `expires` and `hard_expires` next to it (Keychain or UserDefaults; they are not secret).
- **Lifetime.**
  - `expires` = 90 days since the last use (the server extends it); `hard_expires` = login + 365 days. Refresh both from `/me`.
  - **Warn when `hard_expires - now < 14 days`** in Summary (an info banner) and in Settings:
    «Вход действует до \(dayMonth(hard_expires)). Потом нужно будет войти заново: пароль и число в Telegram.» **(proposed)**
- Any `token_*` 401 → LOGOUT (§3.1).

### 7.8 Face ID and app lock
- `LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)`. The passcode fallback is allowed.
- **On launch** and **after coming back from the background**, if the lock setting is on (default: on, after the user accepts the offer). Lock delay options: «Сразу», «Через 1 минуту», «Через 5 минут».
- **Before a `danger == "critical"` resend** (stage 3: reboot), if «Face ID для опасных действий» is on (default on).
- `localizedReason` strings **(proposed)**:
  - «Открыть приложение «Роутер»»
  - «Подтвердить: \(title)»
- `NSFaceIDUsageDescription` **(proposed)**: «Face ID защищает доступ к роутеру и опасные действия.»
- **App switcher privacy:** when `scenePhase != .active`, overlay an opaque cover (logo on `bg`). Keep no data on disk; everything stays in memory.

### 7.9 Minimal Settings sheet (gear icon)
- **Face ID:** «При открытии» (toggle); «Блокировать» (Сразу / Через 1 минуту / Через 5 минут); «Для опасных действий» (toggle).
- **Тема:** «Как в системе» / «Светлая» / «Тёмная».
- **Этот телефон** (from `/me`): name; «Вход до \(dayMonth(expires))»; «Не дольше \(dayMonth(hard_expires))»; plus the 14-day warning.
- **«Выйти на этом iPhone»** — a dialog only, no Face ID:
  - title «Выйти на этом iPhone?»
  - text «Приложение забудет ключ доступа. Войти снова — пароль панели и число в Telegram.»
  - button «Выйти»
  
  Then `POST /auth/logout` → LOGOUT (delete the token even if the request fails). **(proposed texts)**
- **Ссылки:**
  - веб-панель `https://fspirat.xyz/router/`;
  - LuCI = `data.site.luci`, only if it matches `^https://[\w.-]+(:\d+)?/?$`;
  - бот = `https://t.me/\(data.site.bot)`, only if `bot` matches `^[A-Za-z0-9_]{5,32}$`.
  
  Open them in Safari.
- **О приложении:** version, build, «Сборка действует до \(dayMonth(buildDate + 90 days))». Warn at ≤ 14 days left: «Сборка TestFlight скоро истечёт — установи обновление из TestFlight.» **(proposed)** The build date comes from an Info.plist key written at build time.
- Stage 4, not now: the device list, revoke, «Выйти везде», the login journal.

---

## 8. Fixtures (in the repo: `ios/RouterCore/Sources/RouterCore/SampleJSON.swift`)
- Reference time for every fixture: **`now = 1791886560`**, which is 2026-10-13 14:16:00 Europe/Samara.
- MACs use the documentation range `00:00:5e:00:53:xx`; `5a:…` is a locally administered "hidden" MAC.
- IPs are `192.168.1.x` (home) or `203.0.113.x` / `198.51.100.x` (documentation).
- Node ids are invented.

### 8.1 `status_normal.json`
```json
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":{"updated":1791886200,"current":"Kq7Lm2Xp","socks":true,"real":48,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":41,"group":"fspirat","own":true},{"id":"Rt5Vb8Nw","name":"fspiratDE","ms":0,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"},{"id":"Pz1Yc4Ue","name":"🇳🇱 Нидерланды","ms":63,"group":"nosok"},{"id":"Wm6Tj2Gk","name":"🇫🇮 Финляндия","ms":0,"group":"nosok"}]},"log":["13.10 13:20 вручную -> Kq7Lm2Xp","13.10 13:40 перезапуск VPN"],"history":[[1791885900,52],[1791886200,48]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74}]},"sub":{"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800,"title":"nosok"},"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14,"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800}],"svc_direct":[],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/"],"svc":{"Kq7Lm2Xp":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74}]},"Hd3Fs9Qa":{"ts":1791884590,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":88},{"kind":"web","name":"Discord","host":"discord.com","vpn":95},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":102}]},"direct":{"ts":1791884410,"base":9,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0}]}},"svc_running":false,"speed":{"vpn":{"via":"vpn","ts":1791880000,"down":91234567,"up":40123456,"latency":38,"ip":"203.0.113.77","country":"NL","server":"Hetzner (Германия)","streams":4,"up_limited":false},"direct":null},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-51,"rate":866,"up":120394882,"dn":2349872311},{"name":"","ip":"192.168.1.40","mac":"00:00:5e:00:53:02","online":true,"band":"wired","up":10392,"dn":88123,"direct":true},{"name":"tv-living","ip":"192.168.1.51","mac":"00:00:5e:00:53:03","online":true,"band":"2g","signal":-68,"rate":72,"up":0,"dn":0,"sched":"2300-0700"},{"name":"old-laptop","ip":"192.168.1.77","mac":"00:00:5e:00:53:04","online":false,"up":0,"dn":0,"blocked":true}],"sys":{"cpu":7,"cores":2,"load":"0.21 0.17 0.15","mem_total":245632,"mem_avail":121840,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3460,"temp":null,"uptime":352812,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":61344,"net":{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}}}
```

**Expected Summary** at `now = 1791886560`:
- Title «Требует внимания» (`warn`).
- Items:
  - Роутер `ok` «в сети»
  - VPN `ok` «работает»
  - Интернет `ok` «есть»
  - Серверы `ok` «3 из 5»
  - Сервисы `warn` «нет ответа: Discord»
- No Подписка item: `left` = 17.
- Current server «fspiratNL», tag «свой». Задержка «48 мс» (ok).
- Service tiles: YouTube «61 мс» (ok), Discord «нет ответа» (err), Telegram «74 мс» (ok).
- Subscription line «Подписка до 31 октября · осталось 17 дн. · израсходовано 39.2 ГБ из 200.0 ГБ».
- Footer «Проверено 6 мин назад»: 360 s → round(6).
- Meters:
  - CPU 7% «Средняя нагрузка 0.21 0.17 0.15, ядер: 2»;
  - RAM 50% «121 МБ из 240 МБ»;
  - Flash 35% «31 МБ из 87 МБ: пакеты и настройки».
- Температура «нет датчика». Uptime «4 д 2 ч». Devices: «3 в сети».
- Ping pre-dialog: not needed (`real` = 48).

### 8.2 `status_after_reboot.json`
```json
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":null,"log":[],"history":[],"targets":null,"sub":null,"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14}],"svc_direct":[],"target_list":[],"svc":{},"svc_running":false,"speed":{"vpn":null,"direct":null},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-55,"rate":780,"up":0,"dn":0}],"sys":{"cpu":38,"cores":2,"load":"1.10 0.40 0.15","mem_total":245632,"mem_avail":150212,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":812,"temp":null,"uptime":95,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":40120,"net":{"dev":"wan","rx":0,"tx":0,"rx_total":1048576,"tx_total":524288}}}
```

**Expected:**
- Title «Требует внимания».
- Items: Роутер ok «в сети»; VPN ok «работает» (`ping` is null, so `vpnOk = running`); Интернет ok «есть»; Серверы warn «ещё не проверены» (deviation). No Сервисы and no Подписка item.
- Задержка «—». No subscription line. Uptime «1 мин».
- Service list is empty (`targets` null, `target_list` empty) → hide the tiles.

### 8.3 `status_direct_mode.json`
Same as 8.1 with these changes:
- `"current":"_direct"`;
- `"ping"` with `"current":"_direct","socks":true,"real":45`;
- `"targets"` with `vpn` values `0`, `0`, `0`.

```json
{"running":true,"split_active":true,"current":"_direct","ping":{"updated":1791886200,"current":"_direct","socks":true,"real":45,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":41,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"}]},"log":["13.10 14:00 вручную -> _direct"],"history":[[1791886200,45]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0}]},"sub":null,"subs":[],"svc_direct":[],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/"],"svc":{"direct":{"ts":1791884410,"base":9,"list":[]}},"svc_running":false,"speed":{"vpn":null,"direct":null},"devices":[],"sys":{"cpu":3,"cores":2,"load":"0.05 0.08 0.10","mem_total":245632,"mem_avail":130000,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3000,"temp":51,"uptime":3700,"model":"","fw":"OpenWrt 25.12.5","xray_rss":50000,"net":{"dev":"wan","rx":640000,"tx":0,"rx_total":10,"tx_total":20}}}
```

**Expected:**
- VPN warn «выключен — всё напрямую».
- Сервисы warn «нет ответа: YouTube, Discord, Telegram».
- Серверы ok «2 из 2».
- Title «Требует внимания». Current server «Напрямую (без VPN)».
- Температура «51 °C». Uptime «1 ч 1 мин». Model header «Роутер».

### 8.4 `status_vpn_failing.json` (pre-dialog case)
Same as 8.1 with `"ping"` changed to:
```json
{"updated":1791886200,"current":"Kq7Lm2Xp","socks":true,"real":0,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":0,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"}]}
```

**Expected:**
- VPN err «не проходит».
- Интернет: if `svc.direct.base > 0` (9 in 8.1) → ok «есть».
- Серверы warn «1 из 2». Title «Есть проблема».
- Задержка «VPN не проходит». The ping pre-dialog is **required**.

Variant `"socks":false,"real":null` → VPN ok «работает» (unknown), Задержка «—», no pre-dialog.

### 8.5 `net.json`
```json
{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}
```
Expected: «18.7 Мбит/с» / «1.2 Мбит/с»; «С момента включения: 89.8 ГБ» / «6.8 ГБ».

### 8.6 `led_on.json`, `led_absent.json`, `ledset_off.json`
```json
{"on":true,"items":[{"name":"blue:status","on":true},{"name":"yellow:status","on":false},{"name":"mt76-phy0","on":true},{"name":"mt76-phy1","on":true}]}
```
```json
{"absent":true}
```
```json
{"on":false,"items":[{"name":"blue:status","on":false},{"name":"yellow:status","on":false},{"name":"mt76-phy0","on":false},{"name":"mt76-phy1","on":false}]}
```

### 8.7 `data_day.json`
```json
{"now":1791886560,"range":"day","step":0,"points":[[1791886320,47],[1791886380,0],[1791886440,-1],[1791886500,52]],"stats":{"avg":50,"min":47,"max":52,"fails":1,"offline_min":1},"events":[[1791886200,"manual","Сервер выбран вручную: fspiratNL"],[1791883800,"restart","Перезапуск VPN"],[1791880000,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5e:00:53:02)"],[1791871200,"online","Роутер снова на связи (не было 6 мин)"],[1791870840,"offline","Роутер пропал со связи"],[1791850000,"router","MyDirect + gosuslugi.ru"]],"offline_since":null,"last_ok":1791886530,"names":{"5a:00:5e:00:53:01":"iPhone владельца"},"tpoints":{"YouTube":[[1791886205,61]],"Discord":[[1791886205,0]],"Telegram":[[1791886205,74]]},"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[734003200,28991029248]},"00:00:5e:00:53:02":{"d":[1048576,10485760],"m":[20971520,209715200]}},"speed":[[1791879000,"direct",286000000,95000000,6],[1791880000,"vpn",91234567,40123456,38]],"mtg":null,"site":{"luci":"https://router.fspirat.xyz/","bot":"FSRouter_bot","mtg":"","panels":["fspirat.xyz"]},"newdevs":[{"ts":1791880000,"mac":"00:00:5e:00:53:02"}]}
```

**Expected:**
- «Сегодня ↓ 1.5 ГБ», «↑ 51 МБ».
- Events (5 shown):

| Time | Chip | Level | Text |
|---|---|---|---|
| «сегодня 14:10» | «Действие» | info | «Сервер выбран вручную: fspiratNL» |
| «сегодня 13:30» | «Действие» | info | «Перезапуск VPN» |
| «сегодня 12:26» | «Внимание» | warn | «Новое устройство: …» |
| «сегодня 10:00» | «Успех» | ok | «Роутер снова на связи (не было 6 мин)» |
| «сегодня 09:54» | «Ошибка» | err | «Роутер пропал со связи» |

- Chart: two line points (47 and 52), one fail bar, one offline band.

### 8.8 `data_day_offline.json`
Like 8.7 but `"offline_since":1791885840,"last_ok":1791885780`, and the last points are `[1791886440,-1],[1791886500,-1]`.

Expected banner: «Не на связи с 14:04 · уже 12 мин · последний ответ 14:03».

`data_day_empty.json`:
```json
{"now":1791886560,"range":"day","step":0,"points":[],"stats":{"avg":null,"min":null,"max":null,"fails":0,"offline_min":0},"events":[],"offline_since":null,"last_ok":null,"names":{},"tpoints":{},"traffic":{},"speed":[],"mtg":null,"site":{"luci":"","bot":"","mtg":"","panels":[]},"newdevs":[]}
```

### 8.9 Auth fixtures (observed shapes)
```json
{"login_id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","number":24,"expires_in":120,"poll_every":2}
```
```json
{"state":"pending","expires_in":118}
```
```json
{"state":"approved","token":"fsr1_TestTokenTestTokenTestTokenTestTokenTestTok","device_id":"49139e3a1db5a6ac","expires":1799662560,"hard_expires":1823422560}
```
```json
{"ok":true,"state":"cancelled"}
```
```json
{"device":{"id":"49139e3a1db5a6ac","name":"iPhone владельца","created":1791886560,"expires":1799662560,"hard_expires":1823422560},"now":1791886560}
```
`me_expiring.json` (the 14-day warning must show):
```json
{"device":{"id":"49139e3a1db5a6ac","name":"iPhone владельца","created":1761300000,"expires":1792836000,"hard_expires":1792836000},"now":1791886560}
```

### 8.10 Error fixtures (observed unless marked)
```json
{"error":"bad_password","message":"Неверный пароль. Осталось попыток: 4.","left":4}
```
```json
{"error":"bad_password","message":"Слишком много неверных попыток. Вход с этого адреса закрыт на 15 мин.","left":0}
```
```json
{"error":"locked","message":"Слишком много неверных попыток. Вход с этого адреса закрыт ещё на 15 мин.","retry_after":874}
```
```json
{"error":"login_denied","message":"Вход отклонён в Telegram."}
```
```json
{"error":"login_expired","message":"Время на подтверждение вышло — начни вход заново."}
```
```json
{"error":"token_missing","message":"Нужно войти."}
```
```json
{"error":"token_invalid","message":"Ключ не подходит — войди заново."}
```
```json
{"error":"token_revoked","message":"Доступ этого телефона отозван — войди заново."}
```
```json
{"error":"token_expired","message":"Срок входа истёк — войди заново."}
```
```json
{"error":"rate_limited","message":"Слишком часто — подожди немного.","retry_after":15}
```
```json
{"error":"rate_limited","retry_after":2}
```
```json
{"error":"busy","message":"Роутер отвечает медленно: другие запросы к нему ещё ждут ответа. Повтори через несколько секунд.","retry_after":3}
```
```json
{"error":"busy","message":"Другое действие ещё выполняется — подожди немного."}
```
```json
{"error":"busy","message":"Проверка или тест скорости уже идут — дождись результата."}
```
```json
{"error":"busy","message":"Другое действие ещё выполняется — подожди немного.","source":"router"}
```
```json
{"error":"router_offline","message":"Роутер не на связи: туннель до сервера оборван или дома нет интернета."}
```
```json
{"error":"router_timeout","message":"Роутер не ответил вовремя."}
```
```json
{"error":"router_bad_reply","message":"Роутер ответил непонятно — попробуй ещё раз."}
```
```json
{"error":"server_unavailable"}
```
```json
{"error":"not installed","message":"Не установлено на роутере.","source":"router"}
```
```json
{"error":"unknown action","message":"Роутер не смог выполнить действие.","source":"router"}
```
```json
{"error":"app_disabled","message":"Приложение выключено на сервере. Веб-панель работает."}
```
```json
{"error":"confirm_invalid","message":"Подтверждение не подошло — повтори действие."}
```
```json
{"error":"not_in_v1","message":"Это действие пока есть только в веб-панели."}
```
`job_*.json`:
```json
{"job":"fbe9f93b0caf8a91","poll_every":3}
```
```json
{"state":"running","action":"ping"}
```
```json
{"state":"error","action":"ping","http":502,"error":"router_offline","message":"Роутер не на связи: туннель до сервера оборван или дома нет интернета."}
```
```json
{"state":"error","action":"ping","http":500,"error":"server_error","message":"Ошибка на сервере — попробуй через минуту."}
```
`job_done.json` is `{"state":"done","action":"ping","http":200,"result":` + `status_normal.json` + `}`.

---

## 9. Where the code differs from `docs/ios/inventory.md`
1. **`/auth/poll` pending** returns `{"state":"pending","expires_in":N}`. Inventory §7.2 shows only `{state:"pending"}`.
2. **`/auth/cancel`** returns `{"ok":true,"state":"cancelled"}`, or the current state when the login was not pending or approved. Inventory §7.6 shows `{ok}`. Unknown `login_id` → 410 login_expired.
3. **Traffic day boundary** is **Europe/Samara** (`data-lib.php` `FSR_DAY_TZ`, and fspirat-watch writes keys by Samara time). Inventory §3.2 and §5 #30 describe Moscow or UTC; that is fixed now.
4. **The 428 texts are final in the code**, including `update`: «Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится…». Inventory §7.9 left `update` open. They also differ from the web's own dialogs. The app uses the server texts.
5. **Rate limits are checked before the confirm.** The 428 is never issued while limited. The confirm is not burned by 409 or 429 busy (lock and slot are taken first). It **is** burned by a router failure after the check.
6. **app.php's own 502 and 504 pass through nginx unchanged** (no `fastcgi_intercept_errors`). Only nginx-generated failures become `502 {"error":"server_unavailable"}`. nginx bodies (`rate_limited`, `too_large`, `server_unavailable`, `not_found`) have **no `message`**.
7. **Timeouts.** Inventory §9.1 says 15 s, and 20 s for status. Server-side waits reach 4 + 20 s (status) and a 25 s budget (actions), and nginx waits 30 s. Use 30 s for `/status` and actions.
8. **Unknown paths without a valid token give 401, not 404**, because auth runs first. Inventory §7.4 is consistent but does not say it.
9. **Web texts differ from the server's.** `app.js` `api()`:
   - 401 → «Вход истёк — открываю страницу входа.»
   - 502/504 → «Роутер временно недоступен. Попробуй ещё раз через несколько секунд.»
   - 409 → «Это действие уже выполняется.» (for speedtest «Тест скорости уже идёт, дождись результата.»)
   - 429 → «Слишком много запросов подряд. Подожди пару секунд.»
   - 400 → «Роутер не принял запрос: » + the ERR dictionary in lowercase
   - other → «Роутер не смог выполнить действие. Попробуй ещё раз через минуту.»
   
   The app uses the server `message` instead (§3.2).
10. **Web times are in the browser's local time zone.** The app uses Europe/Samara explicitly (inventory §9.1, §12 #11).
11. **Web `renderHero` shows «Роутер — не на связи»** before the first status even when the router is not down (inventory §4.3, last bullet). The app shows «Проверяю…» (§4.2).
12. **`ping.real == 0` vs null.** Inventory §3.1 is correct. Also, `vpnOk` is true when `socks` is false, so the verdict shows VPN «работает» when the check is impossible. Kept, same as the web.
13. **`/status` takes at least 1 s** because of the CPU and net sample, and `/net` about 1 s. Do not poll `/net` faster than 3 s.

---

## 10. Gotchas
- **`ping` is `null`** after a reboot and until the first fspirat-ping (≤ 5 min). `targets` and `sub` are null too. `history` and `log` are `[]`. `svc` is `{}`. `target_list` may be `[]`. `speed.vpn` and `speed.direct` are null until a speed test.
- **`ping.real` is `null` only when `socks == false`.** `0` means the VPN check **failed**. Do not treat 0 as missing.
- **`ping.current` can differ from `status.current`.** Always use `status.current` for the current server.
- **`current` can be `""`** (Split not found) or `"_direct"`. `_direct` is never in `ping.nodes`. Accept the action id `direct` only for switch (stage 4).
- **`sys.temp` is null** when there is no sensor. Show «нет датчика». The verdict's hot rule needs `temp != nil`.
- **`sys.load` is a string**, for example `"0.21 0.17 0.15"`. Every other `sys` number is an int. Memory and disk sizes are **KiB**. `net.rx`/`tx` are **bits/s**. `*_total` and traffic values are **bytes**. `sub.up`/`down`/`total` are **bytes** and can exceed 2³¹.
- **`subs` can be `null`** (lua failed) or `[]`. Its numeric keys are absent when `/tmp` was wiped. `sub.total == 0` means no limit; `expire == 0` means no expiry.
- **`svc`, `names`, `tpoints` and `traffic` are always JSON objects**, never arrays, even when empty. Decode them as dictionaries.
- **`events` rows are mixed arrays** `[Int, String, String]`, and day `points` are `[Int, Int]`. Use unkeyed decoding. Week and month points have 4 elements (not stage 3).
- **`devices[].name` may be `""`.** Optional keys (`band`, `signal`, `rate`, `blocked`, `sblocked`, `direct`, `sched`) are **absent**, not false. `signal` may be `0` when unknown. MACs are lowercase; lowercase them again when comparing with `data.names` and `data.traffic` keys.
- **Node names** may start with a flag emoji or contain stray spaces: trim them. A control character in a router name used to break JSON; the server now repairs it, otherwise you get `502 router_bad_reply`. Retry on the next tick.
- **`site.luci` and `site.bot` can be `""`.** Validate them before building links.
- **`login_id` and `token` are secrets.** Never log them, never put them in URLs, never persist `login_id`.
- **`retry_after`** is an int in the body for app.php 429s, plus the `Retry-After` header. The nginx 429 has `retry_after: 2` and no `message`.
- **`error` codes may contain spaces** (`"not installed"`, `"bad node"`, `"subscribe.lua not found"`). Do not make them Swift enum raw values that assume identifiers; map strings.
- **`bad_password` is a 401 that must not log out.** Only `token_missing`, `token_invalid`, `token_expired` and `token_revoked` log out.
- **`token_invalid` counts toward fail2ban** (10 in 10 min → 15 min IP ban, which also blocks the home's own VPN on port 443). Never resend a token after `token_invalid`, never send a malformed or lowercase-`bearer` header, and delete the token immediately.
- **Empty password is a real failed attempt.** Do not submit it.
- **`ledset` needs `on` as a JSON bool.** `1` → 400. `ping`, `restart`, `update` and `reboot` accept only an empty body, `{}` or `{"confirm":…}`; `ping` with `confirm` → 400.
- **The ping job result is a full status object:** replace the state with it. A 504 inside the job means slow, not offline.
- **After `reboot` the device counters (`up`/`dn`) reset**, and the router is unreachable for 1–2 min. The quiet window of 150 s suppresses offline mode. If the router is still offline after the window, offline mode switches on normally.
- **The server's 30 s "router silent" memory.** After one timeout, every request for the next 30 s gets an instant `502 router_offline`, including actions, which then get no dialog.
- **`/data` works without the router.** Never gate it on offline mode.
- **Clock.** Server timestamps are Unix UTC. Display in Europe/Samara. `data.now` and `me.now` give the server time if device clock skew matters.

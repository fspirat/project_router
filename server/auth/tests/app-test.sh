#!/usr/bin/env bash
# Тесты сервера для API приложения iPhone /router/app/v1 — docs/ios/inventory.md §10.1, T1–T29.
# Без сети и без настоящих секретов: всё во временной папке (FSR_DIR, журналы, данные fspirat-watch), только 127.0.0.1:
#   php -S — app.php, tgbot.php и веб (web-stub.php: check.php как auth_request nginx, data.php, logout.php, login.php);
#   заглушки Telegram (tg-stub.php) и CGI роутера (router-stub.php) пишут каждый вызов в журнал — по нему проверяется
#   «роутер не вызван» / «вызван ровно 1 раз» и что ушло в Telegram; db.php — SQL к временной базе (сдвинуть время строк).
# Сверх §10.1 (ревью 13.10.2026): параллельные неверные пароли (T11), «bearer» в другом регистре (T2), неудачный вызов
# роутера не в счёт лимитов (T16, T22), места для вызова роутера (T17), «роутер молчит» (T21), общий срок запроса (T19).
# Нужны: bash, php-cli 8.3+ с pdo_sqlite (php-sqlite3), curl, jq. Запускается в Checks у Deploy server (ubuntu-latest).
# Запуск: bash server/auth/tests/app-test.sh   KEEP=1 — оставить временную папку; ONLY="T5 T21" — только эти тесты.
# Каждая проверка — строка PASS/FAIL с номером теста; код выхода 1, если есть FAIL. Около 50 с.
# Здесь не проверить: лимиты nginx (fsr_app_ip/fsr_app_dev, 429 от nginx) и баны fail2ban вживую — это Verify выкладки (§10.2);
# PHP 8.5 — только на сервере (тут php-cli раннера, 8.3).
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AUTH=$(cd "$HERE/.." && pwd)
REPO=$(cd "$AUTH/../.." && pwd)
for c in php curl jq sha256sum; do command -v "$c" >/dev/null || { echo "нет $c — тесты не запустить"; exit 2; }; done
php -m | grep -qix pdo_sqlite || { echo "нет pdo_sqlite у php-cli (apt install php-sqlite3)"; exit 2; }
START=$(date +%s)

T=$(mktemp -d "${TMPDIR:-/tmp}/fsr-app-test.XXXXXX") || exit 2
mkdir -p "$T/www" "$T/auth" "$T/log" "$T/watch" "$T/stub"
cleanup() {
  pkill -TERM -f -- "$T/www" 2>/dev/null; sleep 0.3; pkill -KILL -f -- "$T/www" 2>/dev/null
  if [ -n "${KEEP:-}" ]; then echo "временная папка: $T"; else rm -rf "$T"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ---------- окружение (§10.1): временные файлы вместо /var/lib, /var/log, /etc/nginx ----------
export FSR_DIR=$T/auth FSR_LOG=$T/log/auth.log FSR_AUDIT=$T/log/audit.log FSR_WATCH=$T/watch FSR_HTPASSWD=$T/htpasswd
export FSR_ORIGIN=https://panel.example.test FSR_COOKIE_DOMAIN= STUB_DIR=$T/stub
rnd() { php -r 'echo bin2hex(random_bytes(32));' | cut -c "1-$1"; }
RTOK=r$(rnd 31)              # токен CGI роутера (тестовый)
RTOK2=s$(rnd 31)             # другой токен: «на сервере не тот, что на роутере» (T21)
PW=pw-$(rnd 14)              # пароль панели (тестовый)
TGTOK=123456:$(rnd 30)       # токен бота (тестовый)
TGSEC=$(rnd 32)              # секрет вебхука бота
CHAT=777000                  # чат владельца
printf '%s\n' "$RTOK" "$RTOK2" "$PW" "$TGTOK" "$TGSEC" > "$T/secrets"
printf '{"token":"%s","chat":%s}\n' "$TGTOK" "$CHAT" > "$FSR_DIR/telegram.json"
printf '{"secret":"%s"}\n' "$TGSEC" > "$FSR_DIR/tgbot.json"
printf '%s\n' "$RTOK" > "$FSR_DIR/router.token"
printf '%s\n' "$RTOK" > "$STUB_DIR/router.token"
printf '{"luci":"https://router.panel.example.test/","bot":"TestBot","mtg":"","panels":["panel.example.test"]}\n' > "$FSR_DIR/site.json"
php -r 'echo "bob:", password_hash($argv[1], PASSWORD_BCRYPT, ["cost" => 5]), "\n";' "$PW" > "$FSR_HTPASSWD"

NOW=$(date +%s)
{
  printf '%s\tnewdev\tНовое устройство: без имени · 192.168.1.5 (AA:BB:CC:DD:EE:01)\n' $((NOW - 3600))
  printf '%s\tmanual\tСервер выбран вручную: Германия\n' $((NOW - 60))
  printf '%s\tnewdev\tНовое устройство: старое (aa:bb:cc:dd:ee:02)\n' $((NOW - 9 * 86400))
} > "$FSR_WATCH/events.tsv"
printf '%s 50 nodeA1\n%s 0 nodeA1\n%s 42 nodeA1\n' $((NOW - 180)) $((NOW - 120)) $((NOW - 60)) > "$FSR_WATCH/history.tsv"
printf '{"last":{},"days":{"%s":{"aa:bb:cc:dd:ee:01":[10,20]}}}\n' "$(TZ=Europe/Samara date +%F)" > "$FSR_WATCH/traffic.json"
# vds.json: кроме разрешённых полей — адреса и «секреты», которых в ответе /vds быть не должно (T24)
cat > "$FSR_WATCH/vds.json" <<EOF
{"ts":$NOW,"servers":[{"name":"NL","local":true,"host":"203.0.113.10","ip":"203.0.113.10",
 "stat":{"up":100,"load":"0.10 0.20 0.30","cores":2,"mem_total":1000,"mem_avail":500,"disk":"40%","rx":1,"tx":2,"xray":"active","conns":3,
         "host":"203.0.113.10","ssh":"root@203.0.113.10","secret":"vds-secret-x"}},
 {"name":"DE","host":"198.51.100.20","key":"/root/.ssh/vds2_key","stat":null}]}
EOF

# ---------- серверы на свободных портах ----------
port() { php -r '$s = stream_socket_server("tcp://127.0.0.1:0"); $n = stream_socket_get_name($s, false); echo substr($n, strrpos($n, ":") + 1);'; }
PORTS=" "
newport() { local p; while :; do p=$(port); case "$PORTS" in *" $p "*) ;; *) PORTS="$PORTS$p "; echo "$p"; return;; esac; done; }
P_TG=$(newport); P_R=$(newport); P_APP=$(newport); P_OFF=$(newport); P_BOT=$(newport); P_BOFF=$(newport); P_WEB=$(newport); P_DEAD=$(newport)
PORTS="$PORTS$P_TG $P_R $P_APP $P_OFF $P_BOT $P_BOFF $P_WEB $P_DEAD "
P_BUD=$(newport); PORTS="$PORTS$P_BUD "
export FSR_TG_API=http://127.0.0.1:$P_TG FSR_ROUTER=http://127.0.0.1:$P_R/cgi-bin/fspirat
serve() {   # serve ИМЯ ПОРТ СКРИПТ [ПЕРЕМЕННАЯ=значение…] — php -S c несколькими воркерами (параллельные запросы, T17, T22)
  local name=$1 port=$2 script=$3; shift 3
  env PHP_CLI_SERVER_WORKERS=4 "$@" php -d display_errors=0 -d log_errors=1 -d error_reporting=-1 -d "error_log=$T/log/php-$name.err" \
    -S "127.0.0.1:$port" -t "$T/www" "$script" > "$T/log/srv-$name.log" 2>&1 &
}
serve tg "$P_TG" "$HERE/tg-stub.php" STUB_TG_TOKEN="$TGTOK"
serve router "$P_R" "$HERE/router-stub.php"
serve app "$P_APP" "$AUTH/app.php"
serve off "$P_OFF" "$AUTH/app.php" FSR_ROUTER="http://127.0.0.1:$P_DEAD/cgi-bin/fspirat"   # туннель оборван: порт никто не слушает
serve bud "$P_BUD" "$AUTH/app.php" FSR_APP_BUDGET=4          # общий срок вызовов роутера в запросе — 4 с вместо 25 (T19)
serve bot "$P_BOT" "$AUTH/tgbot.php"
serve botoff "$P_BOFF" "$AUTH/tgbot.php" FSR_ROUTER="http://127.0.0.1:$P_DEAD/cgi-bin/fspirat"            # бот при оборванном туннеле
serve web "$P_WEB" "$HERE/web-stub.php"
for p in "$P_TG" "$P_R" "$P_APP" "$P_OFF" "$P_BOT" "$P_BOFF" "$P_WEB" "$P_BUD"; do
  for i in $(seq 100); do (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && continue 2; sleep 0.05; done
  echo "не запустился php -S на порту $p:"; cat "$T"/log/srv-*.log; exit 2
done
APP=http://127.0.0.1:$P_APP/router/app/v1
OFF=http://127.0.0.1:$P_OFF/router/app/v1
BUD=http://127.0.0.1:$P_BUD/router/app/v1
BOT=http://127.0.0.1:$P_BOT/router/tg-hook
BOTOFF=http://127.0.0.1:$P_BOFF/router/tg-hook
WEB=http://127.0.0.1:$P_WEB

# ---------- запросы ----------
# req МЕТОД АДРЕС [ТЕЛО-JSON|-] [аргументы curl…] → CODE BODY HDRS
req() {
  local m=$1 u=$2 d=- f="$T/rq.$BASHPID"; shift 2
  if [ $# -gt 0 ]; then d=$1; shift; fi
  local a=(-s -m 40 -X "$m" -D "$f.h" -o "$f.b" -w '%{http_code}')
  [ "$d" = - ] || a+=(-H 'Content-Type: application/json' --data-binary "$d")
  rm -f "$f.h" "$f.b"
  CODE=$(curl "${a[@]}" "$@" "$u"); BODY=$(cat "$f.b" 2>/dev/null); HDRS=$(tr -d '\r' < "$f.h" 2>/dev/null)
}
# api КЛЮЧ|- МЕТОД ПУТЬ [ТЕЛО|-] [аргументы curl…] — API приложения с ключом устройства в Authorization («-» — без него)
api() {
  local k=$1 m=$2 p=$3 d=-; shift 3
  if [ $# -gt 0 ]; then d=$1; shift; fi
  if [ "$k" = - ]; then req "$m" "$APP$p" "$d" "$@"; else req "$m" "$APP$p" "$d" -H "Authorization: Bearer $k" "$@"; fi
}
hdr() { grep -i "^$1:" <<<"$HDRS" | tail -n 1 | cut -d: -f2- | sed 's/^ *//'; }
jf() { jq -r "$1 // empty" <<<"$BODY" 2>/dev/null; }
sha() { printf %s "$1" | sha256sum | cut -d' ' -f1; }
ms() { echo $(( $(date +%s%N) / 1000000 )); }

# ---------- проверки ----------
PASS=0; FAILS=(); NOTOK=0
ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAILS+=("$1"); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '       %s\n' "$2"; }
# is ID «что» КОД [условие jq] — последний ответ: код и условие по телу
is() {
  if [ "$CODE" = "$3" ] && { [ -z "${4:-}" ] || jq -e "$4" >/dev/null 2>&1 <<<"$BODY"; }; then ok "$1 $2"
  else bad "$1 $2" "ждали $3${4:+ и $4}; ответ $CODE: $(printf %s "$BODY" | head -c 400)"; fi
}
eq() { if [ "$3" = "$4" ]; then ok "$1 $2"; else bad "$1 $2" "ждали «$4», получили «$3»"; fi; }
chk() { if eval "$3" >/dev/null 2>&1; then ok "$1 $2"; else bad "$1 $2" "не выполнено: $3"; fi; }
that() { local _id=$1 _w=$2; shift 2; if "$@" >/dev/null 2>&1; then ok "$_id $_w"; else bad "$_id $_w"; fi; }   # that ID «что» команда…
jqe() { local _in=$1 _f=$2; shift 2; jq -e "$@" "$_f" >/dev/null 2>&1 <<<"$_in"; }                               # jqe ВХОД ФИЛЬТР [--arg …]
between() { [ -n "$1" ] && [ "$1" -ge "$2" ] 2>/dev/null && [ "$1" -le "$3" ]; }

# ---------- журналы заглушек и сервера: что появилось после mark ----------
cnt() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
mark() { M_CGI=$(cnt "$STUB_DIR/cgi.log"); M_TG=$(cnt "$STUB_DIR/tg.log"); M_LOG=$(cnt "$FSR_LOG"); M_AUD=$(cnt "$FSR_AUDIT"); }
since() { if [ -f "$1" ]; then tail -n "+$(($2 + 1))" "$1"; fi; }
cgi_new() { since "$STUB_DIR/cgi.log" "$M_CGI"; }
tg_new() { since "$STUB_DIR/tg.log" "$M_TG"; }
log_new() { since "$FSR_LOG" "$M_LOG"; }
aud_new() { since "$FSR_AUDIT" "$M_AUD"; }
n_cgi() { cgi_new | jq -s "[.[] | select(${1:-true})] | length"; }                     # вызовов CGI (с условием jq)
n_tg() { tg_new | jq -s "[.[] | select(${1:-true})] | length"; }                       # вызовов Telegram
tg_text() { n_tg ".m == \"sendMessage\" and ((.p.text // \"\") | contains($(jq -Rn --arg s "$1" '$s')))"; }   # сообщений с текстом
n_log() { log_new | grep -cF -- "$1"; }                                                 # строк журнала входов
n_aud() { aud_new | grep -cF -- "$1"; }                                                 # строк журнала действий

# ---------- база, устройства, сессии ----------
sql() { php "$HERE/db.php" sql "$1"; }
mint() {   # mint X «имя» → X_ID X_TOK: ключ устройства в обход входа (вход целиком — T9)
  local id tok; read -r id tok < <(php "$HERE/db.php" mint "$2")
  printf -v "$1_ID" %s "$id"; printf -v "$1_TOK" %s "$tok"; echo "$tok" >> "$T/secrets"
}
session() { local s; s=$(php "$HERE/db.php" session); echo "$s" >> "$T/secrets"; printf %s "$s"; }
# чистое состояние между тестами: лимиты, входы, подтверждения, задачи, ошибки входа, замки; прежние ключи отозваны; новые A и B
fresh() {
  sql "UPDATE app_devices SET revoked = $(date +%s), revoked_by = 'ops' WHERE revoked IS NULL;
       DELETE FROM app_actions; DELETE FROM app_confirms; DELETE FROM app_logins; DELETE FROM app_jobs; DELETE FROM fails"
  rm -f "$FSR_DIR/app_login_lock" "$FSR_DIR/app_urltoken_alert" "$FSR_DIR/router_token_alert" "$FSR_DIR/app_disabled" \
        "$FSR_DIR/app_router_down" "$STUB_DIR"/resp_* "$STUB_DIR"/sleep_* "$STUB_DIR/tg_down"
  mint A 'Тестовый iPhone'; mint B 'iPhone B'
  mark
}
# revoked ID «как» КЛЮЧ — следующий запрос с ключом → 401 token_revoked, и это не строка APP_BADTOKEN (fail2ban)
revoked() {
  local n0; n0=$(n_log ' APP_BADTOKEN ')
  api "$3" GET /me
  is "$1" "$2 → следующий запрос 401 token_revoked" 401 '.error == "token_revoked"'
  eq "$1" "$2: без APP_BADTOKEN" "$(n_log ' APP_BADTOKEN ')" "$n0"
}
# confirm428 КЛЮЧ ДЕЙСТВИЕ ТЕЛО → C (код подтверждения из 428)
confirm428() { api "$1" POST "/action/$2" "$3"; C=$(jf .confirm); }
withc() { jq -c --arg c "$2" '. + {confirm: $c}' <<<"$1"; }        # то же тело + confirm
wait_job() {   # wait_job КЛЮЧ JOB → последний ответ /jobs/JOB (не running), до 15 с
  local i; for i in $(seq 75); do
    api "$1" GET "/jobs/$2"; [ "$CODE" = 200 ] && [ "$(jf .state)" != running ] && { sleep 0.3; return 0; }; sleep 0.2
  done; return 1
}

# ---------- вход через бота ----------
login_body() { jq -nc --arg n "$1" --arg p "$2" '{password: $p, device: {name: $n, model: "iPhone15,2", os: "iOS 18.1", app: "1.0 (7)"}}'; }
# login_start ИМЯ [пароль] [аргументы curl…] → CODE BODY; LID NUM — экран приложения; LMSG MID KB — сообщение и кнопки в боте
login_start() {
  local k; k=$(cnt "$STUB_DIR/tg.log")
  req POST "$APP/auth/login" "$(login_body "$1" "${2-$PW}")" "${@:3}"
  LID=$(jf .login_id); NUM=$(jf .number); [ -z "$LID" ] || echo "$LID" >> "$T/secrets"
  LMSG=$(since "$STUB_DIR/tg.log" "$k" | jq -c 'select(.m == "sendMessage" and .p.reply_markup != null)' | tail -n 1)
  MID=$(jq -r '.mid // empty' <<<"$LMSG" 2>/dev/null); KB=$(jq -c '.p.reply_markup.inline_keyboard // []' <<<"$LMSG" 2>/dev/null)
}
btn() { jq -r --arg n "$1" '.[0][] | select(.text == $n) | .callback_data' <<<"$KB" 2>/dev/null; }                 # кнопка с этим числом
btn_wrong() { jq -r --arg n "$1" '[.[0][] | select(.text != $n)][0].callback_data' <<<"$KB" 2>/dev/null; }   # с другим
btn_notme() { jq -r '.[1][0].callback_data' <<<"$KB" 2>/dev/null; }                                          # «Это не я»
poll() { req POST "$APP/auth/poll" "{\"login_id\":\"${1:-$LID}\"}"; }
lcancel() { req POST "$APP/auth/cancel" "{\"login_id\":\"${1:-$LID}\"}"; }
login_state() { sql "SELECT state FROM app_logins WHERE hash = '$(sha "${1:-$LID}")'"; }
# Telegram → вебхук бота (с секретом). bot_cmd ТЕКСТ — команда владельца; press ДАННЫЕ MESSAGE_ID [from.id] — нажатие кнопки
bot() { curl -s -m 30 -o /dev/null -w '%{http_code}' -H "X-Telegram-Bot-Api-Secret-Token: $TGSEC" -H 'Content-Type: application/json' --data-binary "$1" "$BOT"; }
bot_cmd() { bot "$(jq -nc --arg t "$1" --argjson c "$CHAT" '{update_id: 1, message: {message_id: 5, date: 0, from: {id: $c}, chat: {id: $c, type: "private"}, text: $t}}')"; }
press() {
  bot "$(jq -nc --arg d "$1" --argjson mid "${2:-0}" --argjson f "${3:-$CHAT}" --argjson c "$CHAT" \
    '{update_id: 2, callback_query: {id: "cq1", from: {id: $f}, data: $d, message: {message_id: $mid, date: 0, chat: {id: $c, type: "private"}}}}')" >/dev/null
}
# веб: authq МЕТОД ИСХОДНЫЙ_АДРЕС [аргументы curl…] — check.php, как auth_request nginx перед /router/api и /router/data
authq() { local m=$1 u=$2; shift 2; req GET "$WEB/_fsr_auth" - -H "X-Orig-Method: $m" -H "X-Orig-Uri: $u" "$@"; }
csrf() { req GET "$WEB/router/data?csrf=1" - -H "Cookie: fsr_session=$1" -H 'X-FSR: 1'; jf .csrf; }
MAC1=aa:bb:cc:dd:ee:01

# ======================================================================================================================

t01() {   # Нет Authorization
  fresh
  api - GET /me
  is T1 "нет Authorization → 401 token_missing" 401 '.error == "token_missing" and (.message | type == "string")'
  eq T1 "401: WWW-Authenticate" "$(hdr WWW-Authenticate)" 'Bearer error="invalid_token"'
  eq T1 "ответ JSON (Content-Type)" "$(hdr Content-Type)" 'application/json; charset=utf-8'
  eq T1 "Cache-Control: no-store" "$(hdr Cache-Control)" no-store
  eq T1 "X-Content-Type-Options: nosniff" "$(hdr X-Content-Type-Options)" nosniff
  eq T1 "нет строки APP_BADTOKEN" "$(n_log ' APP_BADTOKEN ')" 0
  api "$A_TOK" GET /me
  is T1 "с ключом → 200 /me" 200 "(.device.id == \"$A_ID\") and (.device.name == \"Тестовый iPhone\") and (.now | type == \"number\")"
  api "$A_TOK" OPTIONS /me
  is T1 "OPTIONS (CORS нет) → 405 method" 405 '.error == "method"'
  eq T1 "405: заголовок Allow" "$(hdr Allow)" GET
  touch "$FSR_DIR/app_disabled"
  api "$A_TOK" GET /me
  is T1 "рубильник app_disabled → 503 app_disabled" 503 '.error == "app_disabled"'
  rm -f "$FSR_DIR/app_disabled"
}

t02() {   # Неверный ключ
  fresh
  local h r43; r43=$(php -r 'echo rtrim(strtr(base64_encode(random_bytes(32)), "+/", "-_"), "=");')
  for h in 'Bearer abc' 'Basic dXNlcjpwYXNzd29yZA==' "Bearer fsr1_$r43"; do
    req GET "$APP/me" - -H "Authorization: $h"
    is T2 "Authorization: ${h:0:12}… → 401 token_invalid" 401 '.error == "token_invalid"'
    eq T2 "  …WWW-Authenticate" "$(hdr WWW-Authenticate)" 'Bearer error="invalid_token"'
  done
  eq T2 "по строке APP_BADTOKEN ip=… на каждый (3)" "$(n_log ' APP_BADTOKEN ip=127.0.0.1 ')" 3
  # «Bearer» — с учётом регистра, как ключ лимита nginx на устройство (map в fsr-limits.conf): «bearer …» с настоящим
  # ключом обходил бы лимит fsr_app_dev, поэтому не принимается
  for h in bearer BEARER; do
    req GET "$APP/me" - -H "Authorization: $h $A_TOK"
    is T2 "Authorization: $h <настоящий ключ> → 401 token_invalid" 401 '.error == "token_invalid"'
  done
  eq T2 "  …ключ не отозван (это не утечка), строки APP_BADTOKEN (+2)" "$(sql "SELECT revoked IS NULL FROM app_devices WHERE id = '$A_ID'") $(n_log ' APP_BADTOKEN ip=127.0.0.1 ')" "1 5"
  api "$A_TOK" GET /me
  is T2 "  …«Bearer» с тем же ключом → 200" 200 ".device.id == \"$A_ID\""
}

t03() {   # Истёкший ключ
  fresh; mint X 'Истёк'; mint Y 'Старше года'
  local now; now=$(date +%s)
  sql "UPDATE app_devices SET expires = $((now - 1)) WHERE id = '$X_ID'"
  sql "UPDATE app_devices SET created = $((now - 366 * 86400)), seen = $((now - 60)), expires = $((now + 86400)), hard_expires = $((now + 86400)) WHERE id = '$Y_ID'"
  api "$X_TOK" GET /me
  is T3 "expires = now−1 → 401 token_expired" 401 '.error == "token_expired"'
  api "$Y_TOK" GET /me
  is T3 "created = now−366 дн (даже с будущими expires/hard_expires) → 401 token_expired" 401 '.error == "token_expired"'
  eq T3 "без APP_BADTOKEN" "$(n_log ' APP_BADTOKEN ')" 0
}

t04() {   # Скользящее продление
  fresh; mint X 'Продление'
  local now seen exp hard
  now=$(date +%s)
  sql "UPDATE app_devices SET seen = $((now - 400)), expires = $((now + 1000)) WHERE id = '$X_ID'"
  api "$X_TOK" GET /me
  IFS='|' read -r seen exp hard <<<"$(sql "SELECT seen, expires, hard_expires FROM app_devices WHERE id = '$X_ID'")"
  chk T4 "seen = now−400 с → expires = now + 90 дн" 'between "$exp" $((now + 90 * 86400)) $(($(date +%s) + 90 * 86400))'
  chk T4 "seen обновлён" 'between "$seen" $now $(date +%s)'
  eq T4 "/me отдаёт новый expires" "$(jf .device.expires)" "$exp"
  sql "UPDATE app_devices SET seen = $((now - 400)), expires = $((now + 1000)), hard_expires = $((now + 10 * 86400)) WHERE id = '$X_ID'"
  api "$X_TOK" GET /me
  IFS='|' read -r seen exp hard <<<"$(sql "SELECT seen, expires, hard_expires FROM app_devices WHERE id = '$X_ID'")"
  eq T4 "до годового срока 10 дн → expires = hard_expires" "$exp" "$((now + 10 * 86400))"
  sql "UPDATE app_devices SET seen = $((now - 100)), expires = $((now + 1000)), hard_expires = $((now + 300 * 86400)) WHERE id = '$X_ID'"
  api "$X_TOK" GET /me
  eq T4 "seen = now−100 с → не продлевается (не чаще раза в 300 с)" "$(sql "SELECT expires FROM app_devices WHERE id = '$X_ID'")" "$((now + 1000))"
}

t05() {   # Отзыв всеми способами
  fresh
  local S C REF msg cb mid
  # 1) /devices/revoke {id}
  mint X 'Отзыв из приложения'; mark
  api "$A_TOK" POST /devices/revoke "{\"id\":\"$X_ID\"}"
  is T5 "/devices/revoke {id} → 200 {ok}" 200 '.ok == true'
  revoked T5 "/devices/revoke" "$X_TOK"
  eq T5 "/devices/revoke: сообщение в Telegram" "$(tg_text 'Доступ приложения отозван')" 1
  eq T5 "/devices/revoke: revoked_by = app:<кто>" "$(sql "SELECT revoked_by FROM app_devices WHERE id = '$X_ID'")" "app:$A_ID"
  api "$A_TOK" POST /devices/revoke "{\"id\":\"$X_ID\"}"
  is T5 "/devices/revoke уже отозванного → 404" 404 '.error == "not_found"'
  # 2) /auth/logout
  mint X 'Выход на телефоне'; mark
  api "$X_TOK" POST /auth/logout
  is T5 "/auth/logout → 200 {ok}" 200 '.ok == true'
  revoked T5 "/auth/logout" "$X_TOK"
  eq T5 "/auth/logout: сообщение в Telegram" "$(tg_text 'Доступ приложения отозван')" 1
  eq T5 "/auth/logout: APP_REVOKE в журнале входов" "$(n_log ' APP_REVOKE ip=127.0.0.1 ')" 1
  # 3) /devices: список; /devices/revoke {web_ref} — закрыть сессию веба
  S=$(session)
  api "$A_TOK" GET /devices
  is T5 "/devices → apps (текущий отмечен), web, logins, auth_log" 200 \
    '(.apps | type == "array") and ([.apps[] | select(.current)] | length == 1) and (.web | type == "array") and (.logins | type == "array") and (.auth_log | type == "array")'
  REF=$(jq -r --arg r "$(sha "$S" | cut -c1-16)" '.web[] | select(.ref == $r) | .ref' <<<"$BODY")
  mark
  api "$A_TOK" POST /devices/revoke "{\"web_ref\":\"$REF\"}"
  is T5 "/devices/revoke {web_ref} → 200 {ok}" 200 '.ok == true'
  authq GET '/router/api?action=status' -H "Cookie: fsr_session=$S"
  eq T5 "{web_ref}: сессия веба закрыта (check.php → 401)" "$CODE" 401
  eq T5 "{web_ref}: сообщение в Telegram" "$(tg_text 'Сессия веб-панели закрыта')" 1
  # 4) /devices/revoke-all {web:true} — с подтверждением; заодно сессии веба и запомненные браузеры
  mint X 'Все телефоны'; S=$(session)
  sql "INSERT INTO devices(hash, created, seen, ip, ua) VALUES('$(sha "dev-$X_ID")', $(date +%s), $(date +%s), '127.0.0.1', 'app-test')"
  mark
  api "$A_TOK" POST /devices/revoke-all '{"web":true}'; C=$(jf .confirm)
  is T5 "/devices/revoke-all без confirm → 428 (critical)" 428 '.error == "confirm_required" and .danger == "critical"'
  eq T5 "revoke-all: до подтверждения не отозвано ничего" "$(sql 'SELECT COUNT(*) FROM app_devices WHERE revoked IS NULL')" 3
  api "$A_TOK" POST /devices/revoke-all "{\"web\":true,\"confirm\":\"$C\"}"
  is T5 "/devices/revoke-all с confirm → 200 {ok, revoked: 3}" 200 '.ok == true and .revoked == 3'
  revoked T5 "revoke-all (другой телефон)" "$X_TOK"
  revoked T5 "revoke-all (этот телефон)" "$A_TOK"
  eq T5 "revoke-all web:true: сессии веба закрыты" "$(sql 'SELECT COUNT(*) FROM sessions')" 0
  eq T5 "revoke-all web:true: запомненные браузеры забыты" "$(sql 'SELECT COUNT(*) FROM devices')" 0
  eq T5 "revoke-all: сообщение в Telegram" "$(tg_text 'Выход на всех устройствах')" 1
  # 5) кнопка ar в боте (/apps)
  fresh; mint X 'Отзыв из бота'; mark
  eq T5 "бот /apps → 200" "$(bot_cmd /apps)" 200
  msg=$(tg_new | jq -c 'select(.m == "sendMessage" and ((.p.text // "") | contains("Приложение на телефонах")))' | tail -n 1)
  cb=$(jq -r --arg id "$X_ID" '.p.reply_markup.inline_keyboard[][] | .callback_data | select(startswith("ar:" + $id + "|"))' <<<"$msg" 2>/dev/null)
  mid=$(jq -r '.mid // empty' <<<"$msg" 2>/dev/null)
  chk T5 "/apps: у телефона кнопка ar:<id>|время" '[ -n "$cb" ] && [ -n "$mid" ]'
  press "$cb" "$mid" 424242
  api "$X_TOK" GET /me
  is T5 "ar от чужого from.id — не отзывает" 200 ".device.id == \"$X_ID\""
  mark
  press "$cb" "$mid"
  revoked T5 "кнопка ar" "$X_TOK"
  eq T5 "ar: revoked_by = tg" "$(sql "SELECT revoked_by FROM app_devices WHERE id = '$X_ID'")" tg
  eq T5 "ar: бот ответил в Telegram «отозван»" "$(n_tg '.m == "editMessageText" and ((.p.text // "") | contains("отозван"))')" 1
  # 6) веб: POST /router/data?op=apprevoke (сначала check.php, как nginx)
  mint X 'Отзыв из веба'; S=$(session); C=$(csrf "$S"); mark
  authq POST '/router/data?op=apprevoke' -H "Cookie: fsr_session=$S" -H "X-FSR: $C" -H "Origin: $FSR_ORIGIN"
  eq T5 "веб op=apprevoke: check.php (CSRF и Origin в порядке) → 204" "$CODE" 204
  req POST "$WEB/router/data?op=apprevoke" - -H "Cookie: fsr_session=$S" -H "X-FSR: $C" -H "Origin: $FSR_ORIGIN" --data-urlencode "id=$X_ID"
  is T5 "веб op=apprevoke → 200 {ok}" 200 '.ok == true'
  revoked T5 "веб op=apprevoke" "$X_TOK"
  eq T5 "веб op=apprevoke: одно сообщение в Telegram — имя телефона, «Из панели»" \
    "$(n_tg '.m == "sendMessage"')$(tg_text 'Доступ приложения отозван: «Отзыв из веба»')$(tg_text 'Из панели, IP 127.0.0.1')" 111
  req POST "$WEB/router/data?op=apprevoke" - -H "Cookie: fsr_session=$S" -H "X-FSR: $C" -H "Origin: $FSR_ORIGIN" --data-urlencode "id=$X_ID"
  is T5 "веб op=apprevoke уже отозванного → 404" 404 '.error == "not_found"'
  # 7) веб: «Выйти на всех устройствах» (logout.php all=1)
  mint X 'Выход везде'; S=$(session)
  sql "INSERT INTO devices(hash, created, seen, ip, ua) VALUES('$(sha "dev2-$X_ID")', $(date +%s), $(date +%s), '127.0.0.1', 'app-test')"
  mark
  req POST "$WEB/router/logout" - -H "Cookie: fsr_session=$S" -H "Origin: $FSR_ORIGIN" --data-urlencode all=1
  eq T5 "веб logout all=1 → 303" "$CODE" 303
  revoked T5 "веб logout all=1" "$X_TOK"
  revoked T5 "веб logout all=1 (и остальные телефоны)" "$A_TOK"
  eq T5 "logout all=1: revoked_by = all у всех трёх" "$(sql "SELECT COUNT(*) FROM app_devices WHERE id IN ('$A_ID','$B_ID','$X_ID') AND revoked_by = 'all'")" 3
  eq T5 "logout all=1: сессии веба закрыты" "$(sql 'SELECT COUNT(*) FROM sessions')" 0
  eq T5 "logout all=1: запомненные браузеры забыты" "$(sql 'SELECT COUNT(*) FROM devices')" 0
  eq T5 "logout all=1: сообщение в Telegram «📵 … (3)»" "$(tg_text '📵 Доступ приложения отозван на всех телефонах (3)')" 1
  eq T5 "logout all=1: LOGOUT_ALL в журнале входов" "$(n_log ' LOGOUT_ALL ip=')" 1
  # 8) выход везде закрывает и входы: ждущий нажатия и одобренный, ключ которого ещё не забран (опрос до 3 мин)
  local l1 l2
  fresh; login_start 'T5 одобрен до выхода'; l1=$LID; press "$(btn "$NUM")" "$MID"
  login_start 'T5 ждёт до выхода'; l2=$LID
  S=$(session); mark
  req POST "$WEB/router/logout" - -H "Cookie: fsr_session=$S" -H "Origin: $FSR_ORIGIN" --data-urlencode all=1
  eq T5 "logout all=1 при одобренном и ждущем входе → 303" "$CODE" 303
  eq T5 "  …оба входа закрыты (expired)" "$(login_state "$l1") $(login_state "$l2")" "expired expired"
  poll "$l1"
  is T5 "  …опрос одобренного после выхода везде → 410, ключ не выдан" 410 '.error == "login_expired"'
  eq T5 "  …действующих ключей нет" "$(sql 'SELECT COUNT(*) FROM app_devices WHERE revoked IS NULL')" 0
  eq T5 "  …сообщения входов в боте поправлены (2)" "$(n_tg '.m == "editMessageText" and ((.p.text // "") | contains("отменён: выход на всех устройствах"))')" 2
  fresh; login_start 'T5 одобрен, revoke-all'; l1=$LID; press "$(btn "$NUM")" "$MID"
  api "$A_TOK" POST /devices/revoke-all '{"web":false}'; C=$(jf .confirm)
  api "$A_TOK" POST /devices/revoke-all "{\"web\":false,\"confirm\":\"$C\"}"
  is T5 "/devices/revoke-all при одобренном входе → 200, отозваны 2 (A и B)" 200 '.ok == true and .revoked == 2'
  poll "$l1"
  is T5 "  …опрос одобренного входа → 410, ключ не выдан" 410 '.error == "login_expired"'
  eq T5 "  …действующих ключей нет" "$(sql 'SELECT COUNT(*) FROM app_devices WHERE revoked IS NULL')" 0
}

t06() {   # Ключ в адресе
  fresh; mint X 'Ключ в ссылке 1'; mint Y 'Ключ в ссылке 2'; mark
  api - GET "/me?x=$X_TOK"
  is T6 "GET /me?x=fsr1_<настоящий> → 400 token_in_url" 400 '.error == "token_in_url"'
  req GET "$APP/me?access_token=$Y_TOK" - -H "Authorization: Bearer $Y_TOK"
  is T6 "GET /me?access_token=fsr1_<настоящий> (и он же в заголовке) → 400 token_in_url" 400 '.error == "token_in_url"'
  eq T6 "оба ключа отозваны (revoked_by = url_leak)" "$(sql "SELECT COUNT(*) FROM app_devices WHERE id IN ('$X_ID','$Y_ID') AND revoked_by = 'url_leak'")" 2
  revoked T6 "ключ из ?x=" "$X_TOK"
  revoked T6 "ключ из ?access_token=" "$Y_TOK"
  eq T6 "APP_URLTOKEN в журнале входов (на каждый)" "$(n_log ' APP_URLTOKEN ip=127.0.0.1 ')" 2
  eq T6 "Telegram: «ключ попал в адрес запроса… отозван» (на каждый)" "$(tg_text 'попал в адрес запроса')" 2
  # ненастоящий ключ (сканер, Verify выкладки): 400 и APP_URLTOKEN; сообщение в Telegram — не чаще раза в час
  mark
  api - GET '/me?token=x'
  is T6 "?token=x → 400 token_in_url" 400 '.error == "token_in_url"'
  api - GET '/me?Auth=1'
  is T6 "?Auth=1 (имя без учёта регистра) → 400 token_in_url" 400 '.error == "token_in_url"'
  eq T6 "ненастоящий ключ: APP_URLTOKEN на каждый" "$(n_log ' APP_URLTOKEN ip=127.0.0.1 ')" 2
  eq T6 "ненастоящий ключ: одно сообщение в Telegram на час" "$(tg_text 'Настоящих ключей в нём не было')" 1
  # из браузера (Origin): 403 browser_request раньше проверки адреса; настоящий ключ из ссылки всё равно отзывается,
  # но без строки для fail2ban (иначе чужая страница забанила бы домашний IP) — отклонение реализации, см. её заметки
  mint Z 'Ключ в ссылке из браузера'; mark
  req GET "$APP/me?token=$Z_TOK" - -H 'Origin: https://evil.example'
  is T6 "браузер (Origin) + настоящий ключ в адресе → 403 browser_request" 403 '.error == "browser_request"'
  eq T6 "  …ключ отозван (url_leak)" "$(sql "SELECT revoked_by FROM app_devices WHERE id = '$Z_ID'")" url_leak
  eq T6 "  …сообщение в Telegram" "$(tg_text 'попал в адрес запроса')" 1
  eq T6 "  …без APP_URLTOKEN" "$(n_log ' APP_URLTOKEN ')" 0
  req GET "$APP/me?token=x" - -H 'Sec-Fetch-Site: cross-site'
  is T6 "браузер (Sec-Fetch-Site) + ?token=x → 403 browser_request" 403 '.error == "browser_request"'
  eq T6 "  …без APP_URLTOKEN" "$(n_log ' APP_URLTOKEN ')" 0
}

t07() {   # Cookie вместо Bearer
  fresh
  local S; S=$(session)
  api - GET /me - -H "Cookie: fsr_session=$S"
  is T7 "cookie fsr_session вместо Bearer → 401 token_missing" 401 '.error == "token_missing"'
  api - GET /status - -H "Cookie: fsr_session=$S"
  is T7 "cookie на /status → 401 token_missing" 401 '.error == "token_missing"'
  eq T7 "роутер не вызван, без APP_BADTOKEN" "$(n_cgi)$(n_log ' APP_BADTOKEN ')" 00
}

t08() {   # Запрос из браузера
  fresh
  api "$A_TOK" GET /status - -H 'Origin: https://evil.example'
  is T8 "ключ + Origin: https://evil.example → 403 browser_request" 403 '.error == "browser_request"'
  api "$A_TOK" GET /status - -H 'Sec-Fetch-Site: cross-site'
  is T8 "ключ + Sec-Fetch-Site: cross-site → 403 browser_request" 403 '.error == "browser_request"'
  api "$A_TOK" POST /action/unblock "{\"mac\":\"$MAC1\"}" -H "Origin: $FSR_ORIGIN"
  is T8 "действие с Origin своей панели → тоже 403" 403 '.error == "browser_request"'
  eq T8 "роутер не вызван" "$(n_cgi)" 0
  eq T8 "в журнал входов не пишется" "$(log_new | grep -c .)" 0
}

t09() {   # Вход: пароль + число в боте
  fresh
  login_start 'Вход T9'
  is T9 "POST /auth/login → 200 {login_id, number, expires_in: 120, poll_every: 2}" 200 \
    '(.login_id | test("^[a-f0-9]{64}$")) and (.number | type == "number") and .expires_in == 120 and .poll_every == 2'
  chk T9 "в бот ушло сообщение с кнопками" '[ -n "$MID" ]'
  eq T9 "журнал входов: APP_LOGIN" "$(n_log ' APP_LOGIN ip=127.0.0.1 ')" 1
  that T9 "3 разных числа 10..99, ровно одно — с экрана; второй строкой «Это не я»" jqe "$KB" \
    '(.[0] | length) == 3 and ([.[0][].text | tonumber] | unique | length) == 3 and ([.[0][].text | tonumber | select(. >= 10 and . <= 99)] | length) == 3
     and ([.[0][] | select(.text == $n)] | length) == 1 and (.[1] | length) == 1 and (.[1][0].callback_data | startswith("an:"))' --arg n "$NUM"
  that T9 "кнопки al:<ref>:<число>|время и an:<ref>|время, не длиннее 30 байт" jqe "$KB" \
    '[.[][].callback_data] | length == 4 and all(test("^(al:[a-f0-9]{12}:[0-9]{2}|an:[a-f0-9]{12})[|][0-9]+$") and length <= 30)'
  eq T9 "сообщение без parse_mode (имя задаёт пользователь)" "$(jq -r '.p.parse_mode // "нет"' <<<"$LMSG")" нет
  that T9 "в тексте: устройство, модель, iOS, IP" jqe "$LMSG" '.p.text | contains("«Вход T9»") and contains("iPhone15,2") and contains("iOS 18.1") and contains("127.0.0.1")'
  poll
  is T9 "опрос до нажатия → pending" 200 '.state == "pending"'
  mark
  press "$(btn "$NUM")" "$MID"
  eq T9 "нажатие верного числа: бот поправил сообщение («разрешён»)" "$(n_tg '.m == "editMessageText" and ((.p.text // "") | contains("разрешён"))')" 1
  poll
  is T9 "опрос после нажатия → approved + ключ" 200 \
    '.state == "approved" and (.token | test("^fsr1_[A-Za-z0-9_-]{43}$")) and (.device_id | test("^[a-f0-9]{16}$")) and (.expires | type == "number") and (.hard_expires | type == "number")'
  local tok did; tok=$(jf .token); did=$(jf .device_id); echo "$tok" >> "$T/secrets"
  poll
  is T9 "повторный опрос → 410" 410 '.error == "login_expired"'
  api "$tok" GET /me
  is T9 "выданный ключ работает" 200 ".device.id == \"$did\" and .device.name == \"Вход T9\""
  eq T9 "в базе — sha256 ключа" "$(sql "SELECT token_hash FROM app_devices WHERE id = '$did'")" "$(sha "$tok")"
  eq T9 "в базе — sha256 login_id" "$(sql "SELECT COUNT(*) FROM app_logins WHERE hash = '$(sha "$LID")'")" 1
  chk T9 "самих ключа и login_id в файлах базы нет" '! grep -aqF -e "$tok" -e "$LID" "$FSR_DIR"/auth.sqlite*'
  eq T9 "журнал входов: APP_OK" "$(n_log ' APP_OK ip=127.0.0.1 ')" 1
  eq T9 "журнал действий: APP_OK id=<устройство>" "$(n_aud "APP_OK id=$did ip=127.0.0.1 s=a:$did ")" 1
  eq T9 "Telegram: «Вход в приложение: …» после выдачи ключа" "$(tg_text '📱 Вход в приложение: «Вход T9»')" 1
}

t10() {   # Вход: отказы
  local f0 now
  # неверное число → 410 login_denied, ошибка для IP входа, общего замка нет
  fresh; login_start 'T10 число'
  f0=$(sql "SELECT COUNT(*) FROM fails WHERE ip = '127.0.0.1'")
  press "$(btn_wrong "$NUM")" "$MID"; poll
  is T10 "неверное число → 410 login_denied" 410 '.error == "login_denied"'
  eq T10 "  …APP_DENIED в журнале входов (IP входа)" "$(n_log ' APP_DENIED ip=127.0.0.1 ')" 1
  eq T10 "  …ошибка входа (fails) для этого IP" "$(sql "SELECT COUNT(*) FROM fails WHERE ip = '127.0.0.1'")" $((f0 + 1))
  chk T10 "  …общего замка нет" '[ ! -e "$FSR_DIR/app_login_lock" ]'
  sql 'DELETE FROM app_logins'; login_start 'T10 снова'
  is T10 "  …вход сразу снова открыт" 200 '.login_id | length == 64'
  # «Это не я» → 410 login_denied + общий замок входа приложения на час + тревога в Telegram с советом сменить пароль
  fresh; login_start 'T10 не я'; mark
  press "$(btn_notme)" "$MID"; poll
  is T10 "«Это не я» → 410 login_denied" 410 '.error == "login_denied"'
  now=$(date +%s)
  chk T10 "  …общий замок на 1 ч (app_login_lock)" 'between "$(cat "$FSR_DIR/app_login_lock")" $((now + 3590)) $((now + 3600))'
  eq T10 "  …тревога в Telegram с советом сменить пароль" "$(tg_text 'смени его')" 1
  eq T10 "  …APP_DENIED и ошибка для IP входа" "$(n_log ' APP_DENIED ip=127.0.0.1 ')$(sql "SELECT COUNT(*) FROM fails WHERE ip = '127.0.0.1'")" 11
  sql 'DELETE FROM app_logins'; login_start 'T10 после не я'
  is T10 "  …новый вход → 429 locked на час" 429 '.error == "locked" and .retry_after > 3500'
  chk T10 "  …Retry-After" 'between "$(hdr Retry-After)" 3500 3600'
  # «Это не я» закрывает и другой вход, который ждёт (тот же посторонний): его верное число уже не впускает
  local l2 m2 n2 k2
  fresh; login_start 'T10 второй'; l2=$LID; m2=$MID; n2=$NUM; k2=$KB
  login_start 'T10 первый'; mark
  press "$(btn_notme)" "$MID"
  eq T10 "«Это не я» на одном входе — второй ждущий закрыт (expired)" "$(login_state "$l2")" expired
  eq T10 "  …его сообщение в боте поправлено («закрыт на час»)" \
    "$(n_tg ".m == \"editMessageText\" and .p.message_id == $m2 and ((.p.text // \"\") | contains(\"закрыт на час\"))")" 1
  KB=$k2; press "$(btn "$n2")" "$m2"; poll "$l2"
  is T10 "  …верное число на втором после «Это не я» → 410, ключ не выдан" 410 '.error == "login_expired"'
  # одобрен, ключ ещё не забран, а вход по паролю уже закрыт (подбор, «Это не я» на другом входе) — ключ не выдаётся
  fresh; login_start 'T10 одобрен под замком'; press "$(btn "$NUM")" "$MID"
  echo $(( $(date +%s) + 3600 )) > "$FSR_DIR/app_login_lock"; mark
  poll
  is T10 "одобрен, но вход по паролю закрыт (app_login_lock) → 410 login_denied" 410 '.error == "login_denied"'
  eq T10 "  …ключ не выдан, вход закрыт" "$(sql "SELECT COUNT(*) FROM app_devices WHERE name = 'T10 одобрен под замком'") $(login_state)" "0 expired"
  eq T10 "  …сообщение в боте поправлено" "$(n_tg '.m == "editMessageText" and ((.p.text // "") | contains("не выполнен: вход по паролю закрыт"))')" 1
  # 120 с → 410 login_expired; нажатие после — не впускает
  fresh; login_start 'T10 время'
  sql "UPDATE app_logins SET created = created - 121 WHERE hash = '$(sha "$LID")'"
  poll
  is T10 "прошло 120 с → 410 login_expired" 410 '.error == "login_expired"'
  press "$(btn "$NUM")" "$MID"; poll
  is T10 "  …верное число после срока — не впускает" 410 '.error == "login_expired"'
  # чужой message_id / from.id ≠ владелец — нажатие игнорируется
  fresh; login_start 'T10 кнопки'
  press "$(btn "$NUM")" "$((MID + 1))"; poll
  is T10 "чужой message_id → нажатие игнорируется (pending)" 200 '.state == "pending"'
  press "$(btn "$NUM")" "$MID" 424242; poll
  is T10 "from.id ≠ владелец → нажатие игнорируется (pending)" 200 '.state == "pending"'
  eq T10 "  …ни одной ошибки входа" "$(sql 'SELECT COUNT(*) FROM fails')" 0
  # cancel
  mark
  lcancel
  is T10 "POST /auth/cancel → {ok, state: cancelled}" 200 '.ok == true and .state == "cancelled"'
  eq T10 "  …сообщение в боте поправлено («отменён»)" "$(n_tg '.m == "editMessageText" and ((.p.text // "") | contains("отменён"))')" 1
  press "$(btn "$NUM")" "$MID"; poll
  is T10 "  …опрос после отмены (и нажатия) → 410, ключа нет" 410 '.error == "login_expired"'
  eq T10 "  …в базе cancelled" "$(login_state)" cancelled
}

t11() {   # 5 неверных паролей
  fresh
  local i
  for i in 1 2 3 4 5; do
    req POST "$APP/auth/login" "$(login_body 'T11' "wrong-$i")"
    is T11 "неверный пароль $i → 401 bad_password, left = $((5 - i))" 401 ".error == \"bad_password\" and .left == $((5 - i))"
  done
  login_start 'T11 верный'
  is T11 "6-я попытка (даже с верным паролем) → 429 locked" 429 '.error == "locked" and .retry_after > 0'
  chk T11 "  …Retry-After" 'between "$(hdr Retry-After)" 1 900'
  eq T11 "FAIL ×5 и LOCKED в журнале входов" "$(n_log ' FAIL ip=127.0.0.1 ')$(n_log ' LOCKED ip=127.0.0.1 ')" 51
  req POST "$WEB/router/login" - -H "Origin: $FSR_ORIGIN" --data-urlencode "password=$PW"
  chk T11 "login.php с того же IP тоже закрыт (верный пароль не пускает)" \
    'grep -q "Слишком много неверных попыток" <<<"$BODY" && ! grep -qiE "^set-cookie: fsr_session=[a-f0-9]{64}" <<<"$HDRS"'
  login_start 'T11 другой IP' "$PW" --interface 127.0.0.2
  is T11 "с другого IP (127.0.0.2) вход открыт" 200 '.login_id | length == 64'
  # пачка неверных паролей параллельно с одного IP: блокировка и запись попытки — одним шагом до bcrypt (fsr_attempt),
  # иначе каждый запрос пачки видит «0 ошибок» и проверяет пароль (больше 5 попыток, а ошибки — в общий замок «подбор»)
  local pids="" ip=127.0.0.3
  rm -f "$T"/burst.*; mark
  for i in $(seq 12); do ( req POST "$APP/auth/login" "$(login_body "T11 пачка $i" "wrong-p$i")" --interface $ip; echo "$CODE" > "$T/burst.$i" ) & pids+=" $!"; done
  wait $pids
  eq T11 "12 неверных паролей параллельно (приложение) → ровно 5 × 401, 7 × 429 locked" \
    "$(cat "$T"/burst.* | grep -c '^401$') $(cat "$T"/burst.* | grep -c '^429$')" "5 7"
  eq T11 "  …ошибок в fails для IP — 5, строк FAIL — 5" "$(sql "SELECT COUNT(*) FROM fails WHERE ip = '$ip'") $(n_log " FAIL ip=$ip ")" "5 5"
  ip=127.0.0.4; rm -f "$T"/burst.*; pids=""; mark
  for i in $(seq 12); do ( req POST "$WEB/router/login" - -H "Origin: $FSR_ORIGIN" --data-urlencode "password=wrong-w$i" --interface $ip; echo "$CODE" > "$T/burst.$i" ) & pids+=" $!"; done
  wait $pids
  eq T11 "12 неверных паролей параллельно (login.php) → ровно 5 FAIL, остальные LOCKED" \
    "$(sql "SELECT COUNT(*) FROM fails WHERE ip = '$ip'") $(n_log " FAIL ip=$ip ") $(n_log " LOCKED ip=$ip ")" "5 5 7"
  # верный пароль: запись попытки убрана (и в вебе, и в приложении)
  ip=127.0.0.5; mark
  req POST "$WEB/router/login" - -H "Origin: $FSR_ORIGIN" --data-urlencode "password=$PW" --interface $ip
  chk T11 "login.php, верный пароль с нового браузера → шаг кода из Telegram" 'grep -q "name=\"code\"" <<<"$BODY" && [ "$(tg_text "Код входа в панель")" = 1 ]'
  login_start 'T11 верный, новый IP' "$PW" --interface $ip
  is T11 "  …и вход в приложение с того же IP → 200" 200 '.login_id | length == 64'
  eq T11 "  …ошибок входа для IP нет (запись попытки убрана)" "$(sql "SELECT COUNT(*) FROM fails WHERE ip = '$ip'")" 0
}

t12() {   # Лимиты входа и Telegram
  local i now vals=""
  fresh
  login_start 'T12 1'; login_start 'T12 2'
  is T12 "2 входа ждут подтверждения → 2-й 200" 200 '.login_id | length == 64'
  login_start 'T12 3'
  is T12 "3-й одновременный вход → 429 busy" 429 '.error == "busy" and .retry_after > 0'
  fresh
  for i in 1 2 3 4 5; do login_start "T12 час $i"; lcancel; done
  login_start 'T12 час 6'
  is T12 "6-й вход за час с IP → 429 rate_limited" 429 '.error == "rate_limited" and .retry_after > 0'
  chk T12 "  …Retry-After" 'between "$(hdr Retry-After)" 1 3600'
  fresh; now=$(date +%s)
  for i in $(seq 10); do vals+="${vals:+,}('$(sha "t12-$i")', '$(printf '%012x' "$i")', 42, NULL, $((now - 60)), NULL, 'cancelled', NULL, 'x', '', '', '', '198.51.100.$i', '')"; done
  sql "INSERT INTO app_logins(hash, tg_ref, number, tg_msg, created, decided, state, device_id, name, model, os, app, ip, ua) VALUES $vals"
  login_start 'T12 всего 11'
  is T12 "11-й вход за час со всех IP → 429 rate_limited" 429 '.error == "rate_limited"'
  fresh; mv "$FSR_DIR/telegram.json" "$T/telegram.json.off"
  login_start 'T12 без Telegram'
  is T12 "нет telegram.json → 503 tg_unavailable" 503 '.error == "tg_unavailable"'
  mv "$T/telegram.json.off" "$FSR_DIR/telegram.json"; mv "$FSR_DIR/tgbot.json" "$T/tgbot.json.off"
  login_start 'T12 без вебхука'
  is T12 "нет tgbot.json → 503 tg_unavailable" 503 '.error == "tg_unavailable"'
  mv "$T/tgbot.json.off" "$FSR_DIR/tgbot.json"
  touch "$STUB_DIR/tg_down"
  login_start 'T12 Telegram лежит'
  is T12 "Telegram не принял сообщение → 503 tg_unavailable" 503 '.error == "tg_unavailable"'
  eq T12 "  …вход не остался в базе" "$(sql 'SELECT COUNT(*) FROM app_logins')" 0
  rm -f "$STUB_DIR/tg_down"
  # §7.2 п.8: больше 30 ошибок входа за час со всех IP → вход приложения по паролю закрыт на час, одно сообщение в Telegram
  fresh; now=$(date +%s); vals=""
  for i in $(seq 31); do vals+="${vals:+,}('198.51.100.$((i % 7 + 1))', $((now - 600)))"; done
  sql "INSERT INTO fails(ip, ts) VALUES $vals"
  login_start 'T12 подбор'
  is T12 "31 ошибка за час с разных IP → 429 locked" 429 '.error == "locked" and .retry_after > 3500'
  login_start 'T12 подбор 2'
  is T12 "  …и следующий вход → 429 locked" 429 '.error == "locked"'
  eq T12 "  …одно сообщение в Telegram о подборе с разных адресов" "$(tg_text 'с разных адресов')" 1
  # параллельная пачка входов с верным паролем: лимиты проверяются вместе с записью входа (BEGIN IMMEDIATE),
  # иначе каждый запрос, пока ждёт bcrypt, видит «0 входов» и проходит — ждущих больше двух
  fresh; rm -f "$T"/burst.*
  local pids=""
  for i in 1 2 3 4 5 6; do ( req POST "$APP/auth/login" "$(login_body "T12 пачка $i" "$PW")"; echo "$CODE" > "$T/burst.$i" ) & pids+=" $!"; done
  wait $pids
  eq T12 "6 входов параллельно → 2 × 200, 4 × 429" "$(cat "$T"/burst.* | grep -c '^200$') $(cat "$T"/burst.* | grep -c '^429$')" "2 4"
  eq T12 "  …ждут 2 входа, в бот — 2 сообщения с кнопками" \
    "$(sql "SELECT COUNT(*) FROM app_logins WHERE state = 'pending'") $(n_tg '.m == "sendMessage" and .p.reply_markup != null')" "2 2"
  # §7.2: устройств не больше 10
  fresh
  for i in $(seq 8); do mint X "Лишний $i"; done
  login_start 'T12 одиннадцатый'
  is T12 "уже 10 телефонов → 409 too_many_devices" 409 '.error == "too_many_devices"'
}

t13() {   # reboot без confirm, тексты окон
  fresh
  api "$A_TOK" POST /action/reboot '{}'
  is T13 "reboot без confirm → 428 {confirm, expires_in: 60, danger, title, text, button}" 428 \
    '.error == "confirm_required" and (.confirm | test("^[a-f0-9]{32}$")) and .expires_in == 60 and .danger == "critical" and (.title | length > 0) and (.text | length > 0) and (.button | length > 0)'
  eq T13 "роутер не вызван" "$(n_cgi)" 0
  eq T13 "в базе — sha256 кода подтверждения" "$(sql "SELECT COUNT(*) FROM app_confirms WHERE hash = '$(sha "$(jf .confirm)")'")" 1
  # тексты окон приходят с сервера (§7.9)
  api "$A_TOK" POST /action/switch '{"id":"direct"}'
  is T13 "окно switch direct: critical, «без VPN», автопереключение отключится" 428 '.danger == "critical" and (.title | contains("без VPN")) and (.text | contains("автопереключение"))'
  api "$A_TOK" POST /action/switch '{"id":"nodeB2"}'
  is T13 "окно switch на неживой узел: имя из status, «не отвечает»" 428 '.danger == "high" and (.title | contains("«Нидерланды»")) and (.text | contains("не отвечает"))'
  api "$A_TOK" POST /action/switch '{"id":"nodeA1"}'
  is T13 "окно switch на текущий узел: «уже подключён»" 428 '.text | contains("уже подключён")'
  api "$A_TOK" POST /action/block "{\"mac\":\"$MAC1\"}"
  is T13 "окно block: про этот iPhone в домашнем Wi-Fi" 428 '.danger == "high" and (.text | contains("iPhone в домашнем Wi-Fi"))'
  api "$A_TOK" POST /action/schedule "{\"mac\":\"$MAC1\",\"off\":\"2300\",\"on\":\"0700\"}"
  is T13 "окно schedule: medium, 23:00 → 07:00, про iPhone" 428 '.danger == "medium" and (.text | contains("23:00")) and (.text | contains("07:00")) and (.text | contains("iPhone"))'
  api "$A_TOK" POST /action/update '{}'
  is T13 "окно update: «VPN перезапустится» (§5 п.31)" 428 '.text | contains("VPN перезапустится")'
  api "$A_TOK" POST /action/subupdate '{"sid":"cfg1"}'
  is T13 "окно subupdate {sid}: имя подписки из status, «VPN перезапустится»" 428 '(.title | contains("«nosok»")) and (.text | contains("VPN перезапустится"))'
  api "$A_TOK" POST /action/tgwsset '{"on":true}'
  is T13 "окно tgwsset: medium" 428 '.danger == "medium"'
  eq T13 "окна: действия на роутере не вызваны (только status для текста)" "$(n_cgi '.a != "status"')" 0
  mark
  bot_cmd /update >/dev/null
  eq T13 "бот /update: «VPN перезапустится», без «не перезапускается»" "$(tg_text 'VPN перезапустится')$(tg_text 'не перезапускается')" 10
}

t14() {   # Неверный confirm
  fresh
  local c
  confirm428 "$A_TOK" block "{\"mac\":\"$MAC1\"}"; c=$C
  api "$A_TOK" POST /action/block "$(withc "{\"mac\":\"$MAC1\"}" "$c")"
  is T14 "block с confirm → 200 (подготовка)" 200 '.ok == true and .blocked == true'
  mark
  api "$A_TOK" POST /action/block "$(withc "{\"mac\":\"$MAC1\"}" "$c")"
  is T14 "повторный confirm → 400 confirm_invalid" 400 '.error == "confirm_invalid"'
  eq T14 "  …роутер не вызван" "$(n_cgi)" 0
  confirm428 "$A_TOK" reboot '{}'; c=$C; mark
  api "$B_TOK" POST /action/reboot "$(withc '{}' "$c")"
  is T14 "confirm с другого устройства → 400 confirm_invalid" 400 '.error == "confirm_invalid"'
  eq T14 "  …роутер не вызван" "$(n_cgi)" 0
  confirm428 "$A_TOK" switch '{"id":"nodeA1"}'; c=$C; mark
  api "$A_TOK" POST /action/switch "$(withc '{"id":"nodeB2"}' "$c")"
  is T14 "confirm к switch с другим id → 400 confirm_invalid" 400 '.error == "confirm_invalid"'
  eq T14 "  …роутер не вызван" "$(n_cgi)" 0
  confirm428 "$A_TOK" restart '{}'; c=$C; mark
  api "$A_TOK" POST /action/reboot "$(withc '{}' "$c")"
  is T14 "confirm от другого действия → 400 confirm_invalid" 400 '.error == "confirm_invalid"'
  eq T14 "  …роутер не вызван" "$(n_cgi)" 0
  confirm428 "$A_TOK" reboot '{}'; c=$C
  sql "UPDATE app_confirms SET created = created - 61 WHERE hash = '$(sha "$c")'"; mark
  api "$A_TOK" POST /action/reboot "$(withc '{}' "$c")"
  is T14 "confirm через 61 с → снова 428 (новый код)" 428 ".error == \"confirm_required\" and .confirm != \"$c\""
  eq T14 "  …роутер не вызван" "$(n_cgi)" 0
  mark
  api "$A_TOK" POST /action/reboot "$(withc '{}' 00000000000000000000000000000000)"
  is T14 "неизвестный код → 400 confirm_invalid" 400 '.error == "confirm_invalid"'
  api "$A_TOK" POST /action/reboot '{"confirm":"abc"}'
  is T14 "кривой код → 400 confirm_invalid" 400 '.error == "confirm_invalid"'
  api "$A_TOK" POST /action/reboot '{"confirm":123}'
  is T14 "confirm не строка → 400 bad_param" 400 '.error == "bad_param"'
  eq T14 "  …роутер не вызван" "$(n_cgi)" 0
  chk T14 "отказы — в журнале действий (APP_DENY reboot confirm)" '[ "$(n_aud "APP_DENY reboot confirm ip=127.0.0.1 s=a:$A_ID")" -ge 2 ]'
}

t15() {   # Правильный confirm
  fresh
  confirm428 "$A_TOK" reboot '{}'; mark
  api "$A_TOK" POST /action/reboot "$(withc '{}' "$C")"
  is T15 "reboot с правильным confirm → 200 (ответ роутера)" 200 '.ok == true'
  eq T15 "CGI вызван ровно 1 раз: POST action=reboot, Content-Length: 0, токен в cookie" \
    "$(n_cgi)$(n_cgi '.a == "reboot" and .m == "POST" and .q == "action=reboot" and .cl == "0" and .tok')" 11
  eq T15 "журнал действий: APP reboot → 200 … s=a:<id>" "$(n_aud "APP reboot → 200 ip=127.0.0.1 s=a:$A_ID ")" 1
  eq T15 "Telegram: «Перезагрузка роутера» из приложения «имя», IP" "$(tg_text $'🔄 Перезагрузка роутера\nИз приложения «Тестовый iPhone», IP 127.0.0.1')" 1
  api "$A_TOK" POST /action/reboot "$(withc '{}' "$C")"
  chk T15 "тот же код ещё раз — не выполняется (429 или 400)" '[ "$CODE" = 429 ] || [ "$CODE" = 400 ]'
  eq T15 "  …CGI по-прежнему 1 раз" "$(n_cgi)" 1
}

t16() {   # Лимиты действий
  local j now
  fresh
  api "$A_TOK" POST /action/ping '{}'; j=$(jf .job)
  is T16 "ping → 202" 202 '.job | length == 16'
  wait_job "$A_TOK" "$j"; mark
  api "$A_TOK" POST /action/ping '{}'
  is T16 "2-й ping за 30 с → 429 rate_limited" 429 '.error == "rate_limited" and .retry_after > 0'
  chk T16 "  …Retry-After 1..30" 'between "$(hdr Retry-After)" 1 30'
  eq T16 "  …роутер не вызван, APP_DENY ping rate" "$(n_cgi)$(n_aud 'APP_DENY ping rate')" 01
  fresh; now=$(date +%s)
  sql "INSERT INTO app_actions(device, action, ts) VALUES('$B_ID', 'reboot', $((now - 400))), ('$B_ID', 'reboot', $((now - 1200))), ('$A_ID', 'reboot', $((now - 2400)))"
  api "$A_TOK" POST /action/reboot '{}'
  is T16 "4-й reboot за час (на всех устройствах) → 429 rate_limited" 429 '.error == "rate_limited"'
  chk T16 "  …Retry-After ≈ до выхода старейшего из часа (1200 с)" 'between "$(hdr Retry-After)" 1190 1201'
  sql "DELETE FROM app_actions; INSERT INTO app_actions(device, action, ts) VALUES('$B_ID', 'reboot', $((now - 100)))"
  api "$A_TOK" POST /action/reboot '{}'
  is T16 "reboot через 100 с после другого → 429 (1 за 5 мин)" 429 '.error == "rate_limited"'
  chk T16 "  …Retry-After ≈ 200 с" 'between "$(hdr Retry-After)" 190 201'
  eq T16 "  …роутер не вызван" "$(n_cgi)" 0
  fresh
  confirm428 "$A_TOK" restart '{}'
  api "$A_TOK" POST /action/restart "$(withc '{}' "$C")"
  is T16 "restart с confirm → 200 (подготовка)" 200 '.ok == true'
  sql "UPDATE app_actions SET ts = ts - 5 WHERE action = 'restart'"; mark
  api "$B_TOK" POST /action/switch '{"id":"nodeB2"}'
  is T16 "switch с другого телефона через 5 с после restart → 429 (пауза PassWall 15 с)" 429 '.error == "rate_limited"'
  chk T16 "  …Retry-After 1..10" 'between "$(hdr Retry-After)" 1 10'
  eq T16 "  …роутер не вызван" "$(n_cgi)" 0
  # роутер действие точно не выполнил — попытка не в счёт лимитов и паузы PW: CGI отказал (устаревший id узла после
  # обновления подписки), туннель оборван (порт закрыт), роутер не принял ключ
  fresh
  printf '400\n{"error":"bad node"}' > "$STUB_DIR/resp_switch"
  confirm428 "$A_TOK" switch '{"id":"staleX1"}'
  api "$A_TOK" POST /action/switch "$(withc '{"id":"staleX1"}' "$C")"
  is T16 "switch на устаревший id: CGI 400 bad node → 400" 400 '.error == "bad node" and .source == "router"'
  eq T16 "  …в лимиты не записан" "$(sql "SELECT COUNT(*) FROM app_actions WHERE action = 'switch'")" 0
  rm -f "$STUB_DIR/resp_switch"
  api "$B_TOK" POST /action/restart '{}'
  is T16 "  …restart с другого телефона сразу → 428, а не 429 (паузы PassWall нет)" 428 '.error == "confirm_required"'
  confirm428 "$A_TOK" reboot '{}'
  req POST "$OFF/action/reboot" "$(withc '{}' "$C")" -H "Authorization: Bearer $A_TOK"
  is T16 "reboot с confirm, туннель оборван → 502 router_offline" 502 '.error == "router_offline"'
  eq T16 "  …в лимиты не записан" "$(sql "SELECT COUNT(*) FROM app_actions WHERE action = 'reboot'")" 0
  api "$B_TOK" POST /action/reboot '{}'
  is T16 "  …reboot с другого телефона → 428, а не 429 на 5 минут" 428 '.error == "confirm_required"'
  printf '%s\n' "$RTOK2" > "$FSR_DIR/router.token"
  api "$A_TOK" POST /action/unblock "{\"mac\":\"$MAC1\"}"
  is T16 "unblock, роутер не принял ключ сервера → 500 router_token" 500 '.error == "router_token"'
  printf '%s\n' "$RTOK" > "$FSR_DIR/router.token"; rm -f "$FSR_DIR/router_token_alert"
  NOTOK=$((NOTOK + 1))
  eq T16 "  …в лимиты не записан" "$(sql "SELECT COUNT(*) FROM app_actions WHERE action = 'unblock'")" 0
}

t17() {   # Действия по одному, одна долгая задача
  local t0 dt j
  fresh
  printf 3 > "$STUB_DIR/sleep_unblock"
  ( api "$A_TOK" POST /action/unblock "{\"mac\":\"$MAC1\"}"; printf '%s %s' "$CODE" "$BODY" > "$T/par1" ) &
  local p=$!
  sleep 0.8; t0=$(ms)
  api "$B_TOK" POST /action/ledset '{"on":true}'; dt=$(( $(ms) - t0 ))
  is T17 "второе действие, пока первое ждёт роутер (3 с) → 409 busy" 409 '.error == "busy"'
  chk T17 "  …сразу, не дожидаясь роутера (< 1,5 с)" '[ "$dt" -lt 1500 ]'
  wait "$p"
  chk T17 "первое действие → 200" 'grep -q "^200 " "$T/par1"'
  eq T17 "CGI: unblock 1 раз, ledset 0" "$(n_cgi '.a == "unblock"')$(n_cgi '.a == "ledset"')" 10
  rm -f "$STUB_DIR/sleep_unblock"
  # действие с confirm, пока идёт другое: 409 busy, но подтверждение не сгорает — повтор с тем же confirm проходит
  confirm428 "$A_TOK" block "{\"mac\":\"$MAC1\"}"
  printf 3 > "$STUB_DIR/sleep_pingone"
  ( api "$B_TOK" POST /action/pingone '{"id":"nodeA1"}'; printf %s "$CODE" > "$T/par2" ) &
  p=$!
  sleep 0.8; mark
  api "$A_TOK" POST /action/block "$(withc "{\"mac\":\"$MAC1\"}" "$C")"
  is T17 "block с confirm, пока идёт pingone с другого телефона → 409 busy" 409 '.error == "busy"'
  wait "$p"; rm -f "$STUB_DIR/sleep_pingone"
  api "$A_TOK" POST /action/block "$(withc "{\"mac\":\"$MAC1\"}" "$C")"
  is T17 "  …тот же confirm после — 200 (подтверждение не сгорело)" 200 '.ok == true and .blocked == true'
  eq T17 "  …CGI: pingone 200, block 1 раз" "$(cat "$T/par2") $(n_cgi '.a == "block"')" "200 1"
  printf 3 > "$STUB_DIR/sleep_speedtest"; mark
  api "$A_TOK" POST /action/speedtest '{"via":"vpn"}'; j=$(jf .job)
  is T17 "долгая задача speedtest → 202" 202 '.job | length == 16'
  api "$B_TOK" POST /action/ping '{}'
  is T17 "вторая долгая задача (ping с другого телефона) → 409 busy" 409 '.error == "busy"'
  wait_job "$A_TOK" "$j"
  is T17 "первая задача доработала → done" 200 '.state == "done"'
  eq T17 "CGI: speedtest 1 раз, ping 0" "$(n_cgi '.a == "speedtest"')$(n_cgi '.a == "ping"')" 10
  # места для вызова роутера (§11 п.3): роутер одновременно ждут не больше 2 запросов приложения (воркеры php-fpm общие
  # с вебом и ботом); третий ждёт место до 4 с, потом 429 busy — не дожидаясь роутера
  local p1 p2
  fresh; printf 2 > "$STUB_DIR/sleep_zapret"
  ( api "$A_TOK" GET /zapret; printf %s "$CODE" > "$T/sl1" ) & p1=$!
  ( api "$B_TOK" GET /zapret; printf %s "$CODE" > "$T/sl2" ) & p2=$!
  sleep 0.5; t0=$(ms)
  api "$A_TOK" GET /led; dt=$(( $(ms) - t0 ))
  is T17 "3-й запрос к роутеру, пока 2 ждут ответа (2 с) → ждёт место и проходит" 200 '.on == true'
  chk T17 "  …ждал, пока освободится место (1–3,5 с)" 'between "$dt" 1000 3500'
  wait "$p1" "$p2"
  eq T17 "  …первые два → 200" "$(cat "$T/sl1") $(cat "$T/sl2")" "200 200"
  printf 6 > "$STUB_DIR/sleep_zapret"; mark
  ( api "$A_TOK" GET /zapret; printf %s "$CODE" > "$T/sl1" ) & p1=$!
  ( api "$B_TOK" GET /zapret; printf %s "$CODE" > "$T/sl2" ) & p2=$!
  sleep 0.5; t0=$(ms)
  api "$A_TOK" GET /led; dt=$(( $(ms) - t0 ))
  is T17 "  …места не освободились за 4 с → 429 busy" 429 '.error == "busy" and .retry_after > 0'
  chk T17 "  …через ~4 с, не дожидаясь роутера" 'between "$dt" 3500 5500'
  eq T17 "  …роутер для 3-го не вызван" "$(n_cgi '.a == "led"')" 0
  wait "$p1" "$p2"; rm -f "$STUB_DIR/sleep_zapret"
  eq T17 "  …первые два → 200" "$(cat "$T/sl1") $(cat "$T/sl2")" "200 200"
}

t18() {   # Проверка параметров
  fresh
  p400() { api "$A_TOK" POST "/action/$1" "$2"; is T18 "$1 $2 → 400 bad_param" 400 '.error == "bad_param"'; }
  p400 block '{"mac":"AA:BB:CC:DD:EE:FF"}'
  p400 block '{"mac":"aa%3Abb%3Acc%3Add%3Aee%3Aff"}'
  p400 switch '{"id":"_direct"}'
  p400 pingone '{"id":"node;reboot"}'
  p400 subupdate '{"sid":"a/b"}'
  p400 subupdate '{}'
  p400 subupdate '{"all":false}'
  p400 unblock "{\"mac\":\"$MAC1\",\"foo\":1}"
  p400 direct "{\"mac\":\"$MAC1\"}"
  p400 direct "{\"mac\":\"$MAC1\",\"on\":\"1\"}"
  p400 schedule "{\"mac\":\"$MAC1\",\"off\":\"2300\",\"on\":\"2300\"}"
  p400 schedule "{\"mac\":\"$MAC1\",\"off\":\"2460\",\"on\":\"0700\"}"
  p400 diradd '{"d":"Example.COM"}'
  p400 diradd '{"d":"$(reboot).example"}'
  p400 svcdirect '{"name":"a&b","on":true}'
  p400 zapretstrat '{"n":4}'
  p400 zapretstrat '{"n":"1"}'
  p400 speedtest '{"via":"wifi"}'
  p400 unblock "{\"mac\":\"$MAC1\",\"confirm\":\"00000000000000000000000000000000\"}"
  api "$A_TOK" POST /action/rename "{\"mac\":\"$MAC1\",\"name\":\"$(printf 'я%.0s' $(seq 41))\"}"
  is T18 "rename: имя длиннее 40 символов → 400 too_long" 400 '.error == "too_long"'
  api "$A_TOK" GET '/status?foo=1'
  is T18 "GET /status?foo=1 → 400 bad_param" 400 '.error == "bad_param"'
  api "$A_TOK" POST '/action/unblock?foo=1' "{\"mac\":\"$MAC1\"}"
  is T18 "POST /action/unblock?foo=1 → 400 bad_param" 400 '.error == "bad_param"'
  api "$A_TOK" GET '/data?range=day&foo=1'
  is T18 "GET /data?range=day&foo=1 → 400 bad_param" 400 '.error == "bad_param"'
  req POST "$APP/action/unblock" - -H "Authorization: Bearer $A_TOK" -H 'Content-Type: application/x-www-form-urlencoded' --data-binary "mac=$MAC1"
  is T18 "тело не JSON → 415" 415 '.error | length > 0'
  api "$A_TOK" POST /action/unblock '{"mac":'
  is T18 "битый JSON → 415" 415
  api "$A_TOK" POST /action/unblock '[1]'
  is T18 "JSON не объект → 415" 415
  api "$A_TOK" POST /action/unblock "{\"mac\":\"$MAC1\",\"x\":\"$(printf 'a%.0s' $(seq 4200))\"}"
  is T18 "тело больше 4 КБ → 413 too_large" 413 '.error == "too_large"'
  api "$A_TOK" POST /action/foo '{}'
  is T18 "неизвестное действие → 404 not_found" 404 '.error == "not_found"'
  api "$A_TOK" GET /action/unblock
  is T18 "GET на действие → 405 method" 405 '.error == "method"'
  eq T18 "  …Allow: POST" "$(hdr Allow)" POST
  eq T18 "ни одного вызова CGI" "$(n_cgi)" 0
  chk T18 "отказы — в журнале действий (APP_DENY … param)" '[ "$(n_aud "APP_DENY block param ip=127.0.0.1 s=a:$A_ID")" = 2 ]'
  # верные параметры доходят до CGI, строка запроса — RFC 3986
  mark
  api "$A_TOK" POST /action/unblock '{"mac":"aa:bb:cc:dd:ee:0f"}'
  is T18 "unblock с верным mac → 200" 200 '.ok == true'
  eq T18 "  …CGI: POST action=unblock&mac=aa%3Abb…" "$(n_cgi '.m == "POST" and .q == "action=unblock&mac=aa%3Abb%3Acc%3Add%3Aee%3A0f"')" 1
  confirm428 "$A_TOK" svcdirect '{"name":"YouTube (видео)","on":true}'
  api "$A_TOK" POST /action/svcdirect "$(withc '{"name":"YouTube (видео)","on":true}' "$C")"
  is T18 "svcdirect {name: «YouTube (видео)», on} с confirm → 200" 200 '.ok == true'
  eq T18 "  …CGI: name=YouTube%20%28%D0%B2…%29&on=1" "$(n_cgi '.q == "action=svcdirect&name=YouTube%20%28%D0%B2%D0%B8%D0%B4%D0%B5%D0%BE%29&on=1"')" 1
  api "$A_TOK" POST /action/rename "{\"mac\":\"$MAC1\",\"name\":\" Телевизор \"}"
  is T18 "rename (PHP, без роутера) → 200, имя без пробелов по краям" 200 ".names[\"$MAC1\"] == \"Телевизор\""
}

t19() {   # dirdel только из added
  fresh
  api "$A_TOK" POST /action/dirdel '{"d":"luci-only.example"}'
  is T19 "dirdel домена не из added (есть в MyDirect из LuCI) → 400" 400 '.error == "bad_param"'
  api "$A_TOK" POST /action/dirdel '{"d":"zzz.example"}'
  is T19 "dirdel домена, которого нет вовсе → 400" 400 '.error == "bad_param"'
  eq T19 "  …CGI dirdel не вызван; список — GET mydirect" "$(n_cgi '.a == "dirdel"')$(n_cgi '.a == "mydirect" and .m == "GET"')" 02
  mark
  confirm428 "$A_TOK" dirdel '{"d":"a.example"}'
  is T19 "dirdel домена из added → 428 (подтверждение)" 428 '.title | contains("a.example")'
  api "$A_TOK" POST /action/dirdel "$(withc '{"d":"a.example"}' "$C")"
  is T19 "  …с confirm → 200" 200 '.ok == true'
  eq T19 "  …CGI dirdel ровно 1 раз: POST action=dirdel&d=a.example" "$(n_cgi '.a == "dirdel"')$(n_cgi '.a == "dirdel" and .m == "POST" and .q == "action=dirdel&d=a.example"')" 11
  eq T19 "  …журнал действий: APP dirdel d=a.example → 200" "$(n_aud "APP dirdel d=a.example → 200 ip=127.0.0.1 s=a:$A_ID")" 1
  # mydirect и dirdel — два вызова роутера в одном запросе: вместе укладываются в общий срок (nginx ждёт php-fpm 30 с,
  # дольше — 502 server_unavailable, хотя домен уже убран). У экземпляра BUD срок 4 с вместо 25 (FSR_APP_BUDGET)
  local t0 dt
  fresh; printf 2 > "$STUB_DIR/sleep_mydirect"
  confirm428 "$A_TOK" dirdel '{"d":"b.example"}'
  printf 6 > "$STUB_DIR/sleep_dirdel"; mark; t0=$(ms)
  req POST "$BUD/action/dirdel" "$(withc '{"d":"b.example"}' "$C")" -H "Authorization: Bearer $A_TOK"; dt=$(( $(ms) - t0 ))
  is T19 "dirdel: mydirect 2 с + dirdel 6 с при сроке запроса 4 с → 504 router_timeout от PHP" 504 '.error == "router_timeout"'
  chk T19 "  …в срок (< 4,8 с), а не через 8 с" '[ "$dt" -lt 4800 ]'
  eq T19 "  …dirdel ушёл на роутер — в лимитах остался (мог выполниться)" \
    "$(n_cgi '.a == "dirdel"') $(sql "SELECT COUNT(*) FROM app_actions WHERE action = 'dirdel'")" "1 1"
  rm -f "$STUB_DIR"/sleep_*
}

t20() {   # Не в v1
  fresh
  local a
  for a in subadd subdel settargets; do
    api "$A_TOK" POST "/action/$a" '{}'
    is T20 "$a → 404 not_in_v1" 404 '.error == "not_in_v1"'
  done
  api "$A_TOK" POST /action/subadd '{"name":"x","url":"https://sub.example/abc"}'
  is T20 "subadd с телом → 404 not_in_v1" 404 '.error == "not_in_v1"'
  eq T20 "роутер не вызван" "$(n_cgi)" 0
}

t21() {   # Роутер недоступен, ошибки роутера
  local t0 dt
  fresh
  api "$A_TOK" GET /status
  is T21 "обычный status → 200, {} остаётся объектом" 200 '.running == true and (.svc | type == "object")'
  # туннель оборван
  req GET "$OFF/status" - -H "Authorization: Bearer $A_TOK"
  is T21 "роутер выключен → 502 router_offline" 502 '.error == "router_offline"'
  req POST "$OFF/action/unblock" "{\"mac\":\"$MAC1\"}" -H "Authorization: Bearer $A_TOK"
  is T21 "действие при выключенном роутере → 502 router_offline" 502 '.error == "router_offline"'
  eq T21 "  …журнал действий: → 502:router_offline" "$(n_aud "APP unblock mac=$MAC1 → 502:router_offline")" 1
  eq T21 "  …в лимиты не записано (порт закрыт — запрос не ушёл)" "$(sql "SELECT COUNT(*) FROM app_actions WHERE action = 'unblock'")" 0
  req GET "$OFF/data?range=day" - -H "Authorization: Bearer $A_TOK"
  is T21 "  …/data → 200 (без роутера)" 200 '.range == "day" and (.points | length > 0)'
  # бот при оборванном туннеле: «Роутер не отвечает», а не пустой статус с нулями и «router_offline» на кнопках
  mark
  BOT=$BOTOFF bot_cmd /status >/dev/null; BOT=$BOTOFF bot_cmd /servers >/dev/null; BOT=$BOTOFF bot_cmd /devices >/dev/null
  eq T21 "бот /status, /servers, /devices при выключенном роутере → «Роутер не отвечает» ×3, без «VPN не проходит»" \
    "$(tg_text 'Роутер не отвечает') $(tg_text 'VPN не проходит') $(tg_text 'В сети')" "3 0 0"
  BOT=$BOTOFF press "restart|$(date +%s)" 77
  eq T21 "  …кнопка «перезапустить» → «Не получилось: роутер не отвечает»" \
    "$(n_tg '.m == "editMessageText" and ((.p.text // "") | contains("Не получилось: роутер не отвечает"))') $(n_tg '(.p.text // "") | contains("router_offline")')" "1 0"
  # дольше таймаута (/net — 5 с)
  printf 7 > "$STUB_DIR/sleep_net"; t0=$(ms)
  api "$A_TOK" GET /net; dt=$(( $(ms) - t0 ))
  is T21 "роутер молчит дольше таймаута → 504 router_timeout" 504 '.error == "router_timeout"'
  chk T21 "  …через ~5 с (таймаут /net)" 'between "$dt" 4000 6900'
  rm -f "$STUB_DIR/sleep_net"
  # роутер промолчал — следующие 30 с приложение его не зовёт (воркеры php-fpm общие с вебом и ботом), сразу 502
  chk T21 "  …отмечено «роутер молчит» (app_router_down)" '[ -e "$FSR_DIR/app_router_down" ]'
  mark; t0=$(ms)
  api "$A_TOK" GET /status; dt=$(( $(ms) - t0 ))
  is T21 "  …следующий /status → 502 router_offline" 502 '.error == "router_offline"'
  chk T21 "  …сразу (< 1 с)" '[ "$dt" -lt 1000 ]'
  api "$A_TOK" POST /action/reboot '{}'
  is T21 "  …действие → 502 router_offline, без окна подтверждения" 502 '.error == "router_offline"'
  eq T21 "  …роутер не вызван; в лимиты не записано" "$(n_cgi) $(sql 'SELECT COUNT(*) FROM app_actions')" "0 0"
  rm -f "$FSR_DIR/app_router_down"
  api "$A_TOK" GET /data
  is T21 "  …/data → 200" 200 '.range == "day"'
  # 403 forbidden: router.token на сервере не совпадает с токеном роутера
  printf '%s\n' "$RTOK2" > "$FSR_DIR/router.token"; mark
  api "$A_TOK" GET /status
  is T21 "роутер ответил 403 forbidden → 500 router_token" 500 '.error == "router_token"'
  api "$A_TOK" GET /zapret
  is T21 "  …и снова → 500 router_token" 500 '.error == "router_token"'
  eq T21 "  …одно сообщение в Telegram (не чаще раза в час)" "$(tg_text '403 forbidden')" 1
  NOTOK=$((NOTOK + $(n_cgi '.tok | not')))
  api "$A_TOK" GET /data
  is T21 "  …/data → 200" 200 '.range == "day"'
  printf '%s\n' "$RTOK" > "$FSR_DIR/router.token"
  mv "$FSR_DIR/router.token" "$T/router.token.off"
  api "$A_TOK" GET /status
  is T21 "нет router.token → 500 server_config" 500 '.error == "server_config"'
  mv "$T/router.token.off" "$FSR_DIR/router.token"
  # битый JSON status: сырой управляющий символ и TAB внутри строки (имя узла)
  printf '200\n{"running":true,"current":"nodeA1","ping":{"socks":true,"real":5,"nodes":[{"id":"nodeB2","name":"De\001ad\tx","ms":0}]},"svc":{}}' > "$STUB_DIR/resp_status"
  api "$A_TOK" GET /status
  if [ "$CODE" = 200 ]; then
    is T21 "status с управляющим символом и TAB в строке → исправлен (200, валидный JSON, {} — объект)" 200 '.ping.nodes[0].name == "De\u0001ad\tx" and (.svc | type == "object")'
  else
    is T21 "status с управляющим символом → 502 router_bad_reply" 502 '.error == "router_bad_reply"'
  fi
  printf '200\n' > "$STUB_DIR/resp_status"
  api "$A_TOK" GET /status
  is T21 "пустое тело → 502 router_bad_reply" 502 '.error == "router_bad_reply"'
  printf '200\n<html><body>Bad Gateway</body></html>' > "$STUB_DIR/resp_status"
  api "$A_TOK" GET /status
  is T21 "HTML вместо JSON → 502 router_bad_reply" 502 '.error == "router_bad_reply"'
  rm -f "$STUB_DIR/resp_status"
  api "$A_TOK" GET /data
  is T21 "  …/data → 200" 200 '.range == "day"'
  # ошибки CGI — как есть, с source: router
  printf '400\n{"error":"bad node"}' > "$STUB_DIR/resp_pingone"
  api "$A_TOK" POST /action/pingone '{"id":"nodeZZ"}'
  is T21 "CGI 400 bad node → 400, source: router, понятный текст" 400 '.error == "bad node" and .source == "router" and (.message | length > 0)'
  printf '409\n{"error":"busy"}' > "$STUB_DIR/resp_zapretcheck"
  api "$A_TOK" POST /action/zapretcheck '{}'
  is T21 "CGI 409 busy → 409, source: router" 409 '.error == "busy" and .source == "router"'
  printf '503\n{"error":"not installed"}' > "$STUB_DIR/resp_zapretstrat"
  api "$A_TOK" POST /action/zapretstrat '{"n":2}'
  is T21 "CGI 503 not installed → 503, source: router" 503 '.error == "not installed" and .source == "router"'
  rm -f "$STUB_DIR"/resp_*
}

t22() {   # Долгие задачи
  local j
  fresh
  printf 2 > "$STUB_DIR/sleep_ping"
  api "$A_TOK" POST /action/ping '{}'; j=$(jf .job)
  is T22 "ping → 202 {job, poll_every: 3}" 202 '(.job | test("^[a-f0-9]{16}$")) and .poll_every == 3'
  api "$A_TOK" GET "/jobs/$j"
  is T22 "сразу → running" 200 '.state == "running" and .action == "ping"'
  api "$B_TOK" GET "/jobs/$j"
  is T22 "задача другого устройства → 404" 404 '.error == "not_found"'
  wait_job "$A_TOK" "$j"
  is T22 "ping → done: http 200, result — ответ роутера ({} — объект)" 200 \
    '.state == "done" and .action == "ping" and .http == 200 and .result.running == true and (.result.svc | type == "object")'
  eq T22 "  …CGI ping 1 раз, POST" "$(n_cgi '.a == "ping"')$(n_cgi '.a == "ping" and .m == "POST"')" 11
  eq T22 "  …журнал действий: APP ping job=… → 200" "$(n_aud "APP ping job=$j → 200")" 1
  rm -f "$STUB_DIR/sleep_ping"; mark
  api "$A_TOK" POST /action/speedtest '{"via":"direct"}'; j=$(jf .job)
  is T22 "speedtest {via: direct} → 202" 202 '.job | length == 16'
  wait_job "$A_TOK" "$j"
  is T22 "speedtest → done, result.via = direct" 200 '.state == "done" and .action == "speedtest" and .result.via == "direct" and .result.down > 0'
  eq T22 "  …CGI: POST action=speedtest&via=direct" "$(n_cgi '.m == "POST" and .q == "action=speedtest&via=direct"')" 1
  printf '409\n{"error":"busy"}' > "$STUB_DIR/resp_speedtest"
  api "$B_TOK" POST /action/speedtest '{"via":"vpn"}'; j=$(jf .job)
  wait_job "$B_TOK" "$j"
  is T22 "CGI ответил 409 busy → задача error: busy, http 409, source router" 200 '.state == "error" and .error == "busy" and .http == 409 and .source == "router"'
  rm -f "$STUB_DIR/resp_speedtest"
  api "$B_TOK" POST /action/speedtest '{"via":"vpn"}'; j=$(jf .job)
  is T22 "  …роутер тест не начал — в лимит (1 за 2 мин) не записан: повтор → 202" 202 '.job | length == 16'
  wait_job "$B_TOK" "$j"
  api "$A_TOK" GET /jobs/zzz
  is T22 "/jobs/<не id> → 404" 404 '.error == "not_found"'
}

t23() {   # pingone
  fresh
  local i n=0
  for i in $(seq 20); do
    api "$A_TOK" POST /action/pingone '{"id":"nodeA1"}'
    [ "$CODE" = 200 ] && jq -e '.id == "nodeA1" and .ms == 7' >/dev/null 2>&1 <<<"$BODY" && n=$((n + 1))
  done
  eq T23 "pingone {id} → 200, ответ роутера (20 раз подряд)" "$n" 20
  eq T23 "  …CGI через GET: action=pingone&id=nodeA1 (20)" "$(n_cgi '.m == "GET" and .q == "action=pingone&id=nodeA1"')" 20
  mark
  api "$A_TOK" POST /action/pingone '{"id":"nodeA1"}'
  is T23 "21-й за минуту → 429 rate_limited" 429 '.error == "rate_limited"'
  chk T23 "  …Retry-After 1..60" 'between "$(hdr Retry-After)" 1 60'
  eq T23 "  …роутер не вызван" "$(n_cgi)" 0
  api "$B_TOK" POST /action/pingone '{"id":"nodeA1"}'
  is T23 "другой телефон — свой лимит → 200" 200 '.id == "nodeA1"'
}

t24() {   # /vds
  fresh
  api "$A_TOK" GET /vds
  is T24 "/vds → 200" 200 '(.ts | type == "number") and (.servers | length == 2)'
  is T24 "только ts и servers" 200 'keys == ["servers", "ts"]'
  is T24 "у серверов только name, local, stat" 200 '[.servers[] | keys[]] | unique - ["local", "name", "stat"] | length == 0'
  is T24 "в stat только разрешённые поля" 200 \
    '[.servers[] | (.stat // {}) | keys[]] | unique - ["conns", "cores", "disk", "load", "mem_avail", "mem_total", "rx", "tx", "up", "xray"] | length == 0'
  chk T24 "нет хостов, IP серверов, ключей и секретов" '! grep -qE "203[.]0[.]113|198[.]51[.]100|host|ssh|secret|vds2_key" <<<"$BODY"'
  is T24 "значения на месте" 200 '.servers[0].name == "NL" and .servers[0].local == true and .servers[0].stat.cores == 2 and .servers[0].stat.xray == "active" and .servers[1].stat == null'
}

t26() {   # Веб-CSRF не изменился (docs/audit-2026-10.md:98-100), check.php как auth_request
  fresh
  local S1 S2 C1 C2
  S1=$(session); S2=$(session); C1=$(csrf "$S1"); C2=$(csrf "$S2")
  chk T26 "data.php?csrf=1 → токен 48 hex для сессии" '[[ $C1 =~ ^[a-f0-9]{48}$ ]] && [ "$C1" != "$C2" ]'
  mark
  authq GET '/router/api?action=status' -H "Cookie: fsr_session=$S1"
  eq T26 "GET без токена → 204" "$CODE" 204
  authq POST '/router/api?action=net' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1" -H "Origin: $FSR_ORIGIN"
  eq T26 "POST с токеном и Origin → 204" "$CODE" 204
  authq POST '/router/api?action=reboot' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1" -H "Origin: $FSR_ORIGIN"
  eq T26 "POST reboot с токеном и Origin → 204" "$CODE" 204
  eq T26 "  …Telegram «Перезагрузка роутера … Из панели» (как раньше)" "$(tg_text $'🔄 Перезагрузка роутера\nИз панели, IP 127.0.0.1')" 1
  authq POST '/router/api?action=reboot' -H "Cookie: fsr_session=$S1" -H 'X-FSR: 1' -H "Origin: $FSR_ORIGIN"
  eq T26 "X-FSR: 1 → 403" "$CODE" 403
  authq POST '/router/api?action=reboot' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1" -H 'Origin: https://evil.example'
  eq T26 "чужой Origin → 403" "$CODE" 403
  authq POST '/router/api?action=reboot' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1"
  eq T26 "без Origin → 403" "$CODE" 403
  authq POST '/router/api?action=reboot' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C2" -H "Origin: $FSR_ORIGIN"
  eq T26 "токен другой сессии → 403" "$CODE" 403
  authq GET '/router/api?action=status'
  eq T26 "без сессии → 401" "$CODE" 401
  authq POST '/router/api?action=reboot' -H "X-FSR: $C1" -H "Origin: $FSR_ORIGIN"
  eq T26 "POST без сессии → 401" "$CODE" 401
  authq POST '/router/data?op=apprevoke' -H "Cookie: fsr_session=$S1" -H "Origin: $FSR_ORIGIN"
  eq T26 "op=apprevoke без токена → 403" "$CODE" 403
  authq POST '/router/data?op=apprevoke' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1" -H "Origin: $FSR_ORIGIN"
  eq T26 "op=apprevoke с токеном и Origin → 204" "$CODE" 204
  authq POST '/router/data' -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1" -H "Origin: $FSR_ORIGIN"
  eq T26 "rename (POST /router/data) с токеном → 204" "$CODE" 204
  req GET "$WEB/router/data?devices=1" - -H "Cookie: fsr_session=$S1" -H "X-FSR: $C1"
  is T26 "веб GET /router/data?devices=1 → то же, что /devices; своя сессия — current" 200 \
    "(.apps | length == 2) and (.web | type == \"array\") and ([.web[] | select(.current)] | length == 1) and (.logins | type == \"array\") and (.auth_log | type == \"array\")"
  authq GET '/router/api?action=net' -H "Authorization: Bearer $A_TOK" -H 'X-FSR: 1'
  eq T26 "ключ приложения (Bearer) веб-API не открывает → 401" "$CODE" 401
  eq T26 "журнал действий: ACTION net, reboot, apprevoke, rename" \
    "$(n_aud 'ACTION net ip=')$(n_aud 'ACTION reboot ip=')$(n_aud 'ACTION apprevoke ip=')$(n_aud 'ACTION rename ip=')" 1111
  eq T26 "журнал действий: DENY reboot csrf/origin ×4, DENY apprevoke ×1" "$(n_aud 'DENY reboot csrf/origin')$(n_aud 'DENY apprevoke csrf/origin')" 41
  eq T26 "Telegram только про reboot (apprevoke сообщает data.php, не check.php)" "$(n_tg '.m == "sendMessage"')" 1
}

t28() {   # Rotate router token: сухой прогон скрипта из workflow на заглушках
  local R=$T/rot OLD NEW rc
  mkdir -p "$R/bin" "$R/router" "$R/auth"
  php -r '$y = file_get_contents($argv[1]); if (!preg_match("~- name: Rotate\n.*?ssh vps \x27(.*?)\x27~s", $y, $m)) exit(1); echo $m[1], "\n";' \
    "$REPO/.github/workflows/rotate-router-token.yml" > "$R/rotate.sh"
  chk T28 "скрипт из rotate-router-token.yml найден, bash -n" '[ -s "$R/rotate.sh" ] && bash -n "$R/rotate.sh"'
  # заглушки: ssh на роутер (команда — локально, /etc/fspirat.token → папка «роутера»), curl к CGI (200 — токен роутера, иначе 403),
  # nginx -t / systemctl reload (NGINX_FAIL — не прошло), chown (CHOWN_FAIL — не прошло);
  # туннель: ROT_DROP — обрывается сразу после записи токена на роутер (дальше ssh — ошибка, curl — 000),
  # ROT_MV_LIES — откат (mv) на роутере выполнился, но ssh вернул ошибку (связь оборвалась после команды)
  cat > "$R/bin/ssh" <<'EOF'
#!/usr/bin/env bash
c=${*: -1}
[ -e "$ROT_ROUTER/../down" ] && exit 255
sh -c "${c//\/etc\/fspirat.token/$ROT_ROUTER/fspirat.token}"; rc=$?
[ -z "${ROT_DROP:-}" ] || touch "$ROT_ROUTER/../down"
case $c in *"mv "*) [ -z "${ROT_MV_LIES:-}" ] || exit 255;; esac
exit $rc
EOF
  # curl.log: на каждую проверку — «токен проверки | router.token в этот момент» (когда бот и приложение перешли на новый)
  cat > "$R/bin/curl" <<'EOF'
#!/usr/bin/env bash
[ -e "$ROT_ROUTER/../down" ] && { printf 000; exit 7; }
t=; while [ $# -gt 0 ]; do [ "$1" = -b ] && { t=${2#fspirat_token=}; shift; }; shift; done
echo "$t|$(cat "$FSR_DIR/router.token" 2>/dev/null)" >> "$ROT_ROUTER/../curl.log"
[ "$t" = "$(cat "$ROT_ROUTER/fspirat.token")" ] && printf 200 || printf 403
EOF
  printf '#!/bin/sh\n[ -z "${NGINX_FAIL:-}" ]\n' > "$R/bin/nginx"
  printf '#!/bin/sh\nexit 0\n' > "$R/bin/systemctl"
  printf '#!/bin/sh\necho "$*" >> "$ROT_ROUTER/../chown.log"\n[ -z "${CHOWN_FAIL:-}" ]\n' > "$R/bin/chown"
  chmod +x "$R"/bin/*
  OLD=old$(rnd 29)
  rot_setup() {
    rm -rf "$R/router" "$R/auth" "$R"/snippet.conf* "$R/chown.log" "$R/curl.log" "$R/down"; mkdir -p "$R/router" "$R/auth"
    printf '%s\n' "$OLD" > "$R/router/fspirat.token"
    printf 'location = /router/api {\n    proxy_set_header Cookie "fspirat_token=%s";\n}\n' "$OLD" > "$R/snippet.conf"
    printf '%s\n' "$OLD" > "$R/auth/router.token"; chmod 644 "$R/auth/router.token"
    touch "$R/auth/router_token_alert"            # тревога «роутер отклонил ключ» была в последний час
  }
  rot_run() { env PATH="$R/bin:$PATH" ROT_ROUTER="$R/router" FSR_SNIPPET="$R/snippet.conf" FSR_DIR="$R/auth" "$@" bash "$R/rotate.sh" > "$R/out" 2>&1; }
  rot_leftovers() { { ls -A "$R/router"; ls -A "$R/auth"; ls -A "$R"; } | grep -E '[.](bak|new)|bak-token'; }
  rot_tokens() { echo "$(cat "$R/router/fspirat.token") $(grep -o 'fspirat_token=[A-Za-z0-9]*' "$R/snippet.conf" | cut -d= -f2) $(cat "$R/auth/router.token")"; }
  rot_setup; rot_run; rc=$?
  NEW=$(cat "$R/router/fspirat.token"); echo "$NEW" >> "$T/secrets"
  eq T28 "успех: код 0" "$rc" 0
  chk T28 "  …роутер: новый токен (48 hex)" '[[ $NEW =~ ^[0-9a-f]{48}$ ]]'
  chk T28 "  …сниппет nginx: новый токен, старого нет" 'grep -qF "fspirat_token=$NEW" "$R/snippet.conf" && ! grep -qF "$OLD" "$R/snippet.conf"'
  eq T28 "  …router.token обновлён (бот и приложение)" "$(cat "$R/auth/router.token")" "$NEW"
  eq T28 "  …router.token: права 600, chown www-data:www-data" "$(stat -c %a "$R/auth/router.token") $(grep -c 'www-data:www-data' "$R/chown.log")" "600 1"
  chk T28 "  …без копий .bak и .new" '[ -z "$(rot_leftovers)" ]'
  chk T28 "  …токены в вывод не попали" '! grep -qF -e "$OLD" -e "$NEW" "$R/out" && ! grep -qE "[0-9a-f]{48}" "$R/out"'
  eq T28 "  …router.token переписан сразу за роутером: на проверке нового токена он уже новый" "$(grep -c "^$NEW|$NEW$" "$R/curl.log")" 1
  chk T28 "  …тревога router_token_alert убрана (не глушит следующую)" '[ ! -e "$R/auth/router_token_alert" ]'
  rot_setup; rot_run CHOWN_FAIL=1; rc=$?
  chk T28 "сбой при записи router.token: код ≠ 0" '[ "$rc" != 0 ]'
  eq T28 "  …откат: на роутере, в сниппете и в router.token — прежний токен" \
    "$(cat "$R/router/fspirat.token") $(grep -o 'fspirat_token=[A-Za-z0-9]*' "$R/snippet.conf" | cut -d= -f2) $(cat "$R/auth/router.token")" "$OLD $OLD $OLD"
  chk T28 "  …без копий .bak и .new" '[ -z "$(rot_leftovers)" ]'
  chk T28 "  …токены в вывод не попали" '! grep -qF "$OLD" "$R/out" && ! grep -qE "[0-9a-f]{48}" "$R/out"'
  rot_setup; rot_run NGINX_FAIL=1; rc=$?
  chk T28 "nginx -t не прошёл: код ≠ 0" '[ "$rc" != 0 ]'
  eq T28 "  …откат: прежний токен везде" \
    "$(cat "$R/router/fspirat.token") $(grep -o 'fspirat_token=[A-Za-z0-9]*' "$R/snippet.conf" | cut -d= -f2) $(cat "$R/auth/router.token")" "$OLD $OLD $OLD"
  rot_setup; rm -f "$R/auth/router.token"; rot_run NGINX_FAIL=1; rc=$?
  chk T28 "router.token не было, nginx -t не прошёл: код ≠ 0, router.token так и нет (не остался новый)" '[ "$rc" != 0 ] && [ ! -e "$R/auth/router.token" ]'
  chk T28 "  …без копий .bak и .new" '[ -z "$(rot_leftovers)" ]'
  # туннель оборвался сразу после записи токена на роутер: откат на роутере не прошёл — сервер остаётся на НОВОМ (как роутер)
  rot_setup; rot_run ROT_DROP=1; rc=$?
  NEW=$(cat "$R/router/fspirat.token"); echo "$NEW" >> "$T/secrets"
  chk T28 "туннель оборвался после записи: код ≠ 0, на роутере новый токен" '[ "$rc" != 0 ] && [[ $NEW =~ ^[0-9a-f]{48}$ ]]'
  eq T28 "  …сниппет и router.token — тоже новый (панель, бот и приложение заработают, когда роутер вернётся)" "$(rot_tokens)" "$NEW $NEW $NEW"
  chk T28 "  …на сервере без копий .bak-token и .new; в выводе — предупреждение" \
    '! ls -A "$R" "$R/auth" | grep -qE "bak-token|[.]new" && grep -q "НОВЫЙ" "$R/out"'
  chk T28 "  …токены в вывод не попали" '! grep -qF -e "$OLD" -e "$NEW" "$R/out" && ! grep -qE "[0-9a-f]{48}" "$R/out"'
  # откат на роутере выполнился, но ssh вернул ошибку: по ответу роутера на старый токен — сервер тоже на старом
  rot_setup; rot_run NGINX_FAIL=1 ROT_MV_LIES=1; rc=$?
  chk T28 "откат выполнился, ssh вернул ошибку: код ≠ 0" '[ "$rc" != 0 ]'
  eq T28 "  …прежний токен везде" "$(rot_tokens)" "$OLD $OLD $OLD"
  chk T28 "  …без копий .bak и .new" '[ -z "$(rot_leftovers)" ]'
}

t29() {   # Чистка раз в 100 запросов
  fresh
  local now i; now=$(date +%s)
  mint R 'Отозван давно'; mint E 'Истёк недавно'; mint G 'Срок + 30 дн прошёл'
  sql "UPDATE app_devices SET created = $((now - 200 * 86400)), seen = $((now - 100 * 86400)), expires = $((now - 10 * 86400)), hard_expires = $((now + 165 * 86400)), revoked = $((now - 90 * 86400)), revoked_by = 'web' WHERE id = '$R_ID';
       UPDATE app_devices SET created = $((now - 375 * 86400)), seen = $((now - 100 * 86400)), expires = $((now - 10 * 86400)), hard_expires = $((now - 10 * 86400)) WHERE id = '$E_ID';
       UPDATE app_devices SET created = $((now - 400 * 86400)), seen = $((now - 100 * 86400)), expires = $((now - 35 * 86400)), hard_expires = $((now - 35 * 86400)), revoked = $((now - 90 * 86400)), revoked_by = 'web' WHERE id = '$G_ID';
       INSERT INTO app_actions(device, action, ts) VALUES('$A_ID', 'ping', $((now - 3 * 86400)))"
  printf 0 > "$FSR_DIR/app_gc"; mark
  for i in $(seq 100); do curl -s -o /dev/null -m 10 "$APP/me"; done
  eq T29 "100 запросов — счётчик чистки 100" "$(cat "$FSR_DIR/app_gc")" 100
  eq T29 "чистка прошла: строка старше hard_expires + 30 дн удалена, действия старше 2 суток тоже" \
    "$(sql "SELECT COUNT(*) FROM app_devices WHERE id = '$G_ID'") $(sql "SELECT COUNT(*) FROM app_actions WHERE ts < $((now - 2 * 86400))")" "0 0"
  eq T29 "отозванный и истёкший ключи: строки остались" "$(sql "SELECT COUNT(*) FROM app_devices WHERE id IN ('$R_ID','$E_ID')")" 2
  api "$R_TOK" GET /me
  is T29 "отозванный → 401 token_revoked (не token_invalid)" 401 '.error == "token_revoked"'
  api "$E_TOK" GET /me
  is T29 "истёкший → 401 token_expired" 401 '.error == "token_expired"'
  api "$G_TOK" GET /me
  is T29 "удалённый чисткой (старше срока + 30 дн) → 401 token_invalid" 401 '.error == "token_invalid"'
  eq T29 "APP_BADTOKEN только у удалённого (1)" "$(n_log ' APP_BADTOKEN ')" 1
}

t25() {   # Секреты в журналах (после всех тестов)
  grep -v '^$' "$T/secrets" | sort -u > "$T/secrets.all"
  grep -v '^fsr1_' "$T/secrets.all" > "$T/secrets.core"   # токен роутера, пароль, токен бота, секрет вебхука, сессии веба, login_id
  chk T25 "журнал входов: нет fsr1_, login_id, токенов, пароля" '[ -s "$FSR_LOG" ] && ! grep -qF -e fsr1_ -f "$T/secrets.all" "$FSR_LOG"'
  chk T25 "журнал действий: нет fsr1_, login_id, токенов, пароля" '[ -s "$FSR_AUDIT" ] && ! grep -qF -e fsr1_ -f "$T/secrets.all" "$FSR_AUDIT"'
  chk T25 "сообщения в Telegram: нет ключей, login_id, токенов, пароля" '! grep -qF -e fsr1_ -f "$T/secrets.all" "$STUB_DIR/tg.log"'
  chk T25 "вызовы CGI: токен роутера не в адресе" '! grep -qF -f "$T/secrets.core" "$STUB_DIR/cgi.log"'
  eq T25 "вызовы CGI: верный токен роутера в cookie — у всех, кроме проверки 403 в T21 ($NOTOK)" "$(jq -s '[.[] | select(.tok | not)] | length' "$STUB_DIR/cgi.log")" "$NOTOK"
  chk T25 "ошибки php и журналы серверов (кроме Telegram-заглушки): нет токена роутера, пароля, токена бота, секрета, сессий" \
    '! grep -qF -f "$T/secrets.core" "$T"/log/php-*.err "$T"/log/srv-app.log "$T"/log/srv-off.log "$T"/log/srv-bud.log "$T"/log/srv-bot.log "$T"/log/srv-botoff.log "$T"/log/srv-web.log "$T"/log/srv-router.log'
}

t27() {   # Строки APP_* в журнале входов: сторож и fail2ban
  local L=$T/app-lines.log k
  grep -E '^[0-9-]+ [0-9:]+ APP_[A-Z]+ ip=' "$FSR_LOG" > "$L"
  for k in APP_LOGIN APP_OK APP_DENIED APP_BADTOKEN APP_URLTOKEN APP_REVOKE; do
    chk T27 "в журнале есть $k" 'grep -q " $k ip=" "$L"'
  done
  chk T27 "каждая строка журнала входов — «ДАТА ВРЕМЯ ЧТО ip=… ua=\"…\"»" \
    '! grep -vE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Z_]+ ip=[0-9a-fA-F.:]* ua=\"[^\"]*\"$" "$FSR_LOG"'
  watch_parse() { local d t what ipkv rest; while read -r d t what ipkv rest; do
    [[ $d =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $t =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ && $what =~ ^APP_[A-Z]+$ && $ipkv =~ ^ip=[0-9a-fA-F.:]+$ ]] || return 1
  done < "$1"; }
  that T27 "read -r d t what ipkv (fspirat-watch:38) разбирает строки APP_*: дата, время, ЧТО, ip=" watch_parse "$L"
  # блок разбора журнала входов из fspirat-watch — как есть, send() пишет в файл
  awk '/^AUTHLOG=/{f=1} /^# Сайты, Telegram-прокси/{f=0} f' "$REPO/server/bin/fspirat-watch" | sed 's#^AUTHLOG=.*#AUTHLOG=$WATCH_INPUT#' > "$T/watch-auth.sh"
  chk T27 "блок разбора журнала входов найден в fspirat-watch" 'grep -q "while read -r d t what ipkv" "$T/watch-auth.sh"'
  watch_run() { ( S=$T/wstate; mkdir -p "$S"; WATCH_INPUT=$1
    send() { printf '%s\n' "$1" >> "$T/watch-sent"; }; get() { cat "$S/$1" 2>/dev/null; }; put() { echo "$2" > "$S/$1"; }
    . "$T/watch-auth.sh" ); }
  rm -rf "$T/wstate" "$T/watch-sent"
  watch_run "$L"
  eq T27 "сторож на строках APP_* ($(grep -c . "$L") шт.) — без сообщений" "$(cnt "$T/watch-sent")" 0
  printf '%s OK ip=203.0.113.5 ua="x"\n' "$(date '+%F %T')" >> "$L"
  watch_run "$L"
  eq T27 "  …проверка заглушки: строка OK → одно сообщение «Вход в панель»" "$(grep -c 'Вход в панель роутера: 203.0.113.5' "$T/watch-sent" 2>/dev/null)" 1
  # фильтры fail2ban: строка целиком и без даты (fail2ban вырезает дату перед сравнением)
  f2b() {   # f2b ФИЛЬТР ФАЙЛ → «целая без_даты ЧТО» по строкам (1 — совпало)
    php -r '$c = file_get_contents($argv[1]); preg_match("/^failregex\s*=\s*(.+)$/m", $c, $m);
      $re = "/" . str_replace(["/", "<HOST>"], ["\\/", "(?<host>[0-9A-Fa-f.:]+)"], trim($m[1])) . "/";
      foreach (file($argv[2], FILE_IGNORE_NEW_LINES) as $l) {
        $s = preg_replace("/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d/", "", $l);
        preg_match("/ ([A-Z_]+) ip=/", $l, $w);
        echo (int)preg_match($re, $l), " ", (int)preg_match($re, $s), " ", $w[1] ?? "?", "\n";
      }' "$REPO/server/fail2ban/filter.d/$1.conf" "$2"
  }
  eq T27 "фильтр fspirat-router-auth строки APP_* не ловит (целиком и без даты)" "$(f2b fspirat-router-auth "$L" | grep -cE '^1 |^[01] 1 ')" 0
  grep -E ' (FAIL|LOCKED) ip=' "$FSR_LOG" > "$T/fail-lines.log"
  chk T27 "  …строки FAIL и LOCKED он ловит — целиком и без даты (так их видит fail2ban)" \
    '[ -s "$T/fail-lines.log" ] && grep -q " LOCKED ip=" "$T/fail-lines.log" && ! f2b fspirat-router-auth "$T/fail-lines.log" | grep -qv "^1 1 "'
  chk T27 "фильтр fspirat-router-app: APP_BADTOKEN, APP_DENIED, APP_URLTOKEN — да (целиком и без даты)" \
    '! f2b fspirat-router-app "$L" | grep -E " APP_(BADTOKEN|DENIED|URLTOKEN)$" | grep -qv "^1 1 "'
  chk T27 "  …APP_LOGIN, APP_OK, APP_REVOKE, OK — нет" '! f2b fspirat-router-app "$L" | grep -vE " APP_(BADTOKEN|DENIED|URLTOKEN)$" | grep -qv "^0 0 "'
}

x01() {   # Нет предупреждений PHP (8.3 здесь; на сервере 8.5)
  chk X1 "в журналах ошибок php нет Warning/Notice/Deprecated/Fatal" '! grep -hE "PHP (Warning|Notice|Deprecated|Fatal|Parse|Strict)" "$T"/log/php-*.err'
  chk X1 "нет неожиданных исключений (fspirat-router-app/auth: …)" \
    '! grep -hE "fspirat-router-(app|auth)" "$T"/log/php-*.err | grep -v "sendMessage для входа не прошёл"'
  if grep -qhE "PHP |fspirat-router-" "$T"/log/php-*.err 2>/dev/null; then grep -hE "PHP |fspirat-router-" "$T"/log/php-*.err | grep -v 'sendMessage для входа' | head -n 20 | sed 's/^/       /'; fi
}

# ======================================================================================================================
run() { if [ -n "${ONLY:-}" ] && ! grep -qw -- "$1" <<<"$ONLY"; then return; fi; echo "== $1 $3"; "$2"; }
run T1 t01 "нет Authorization"
run T2 t02 "неверный ключ"
run T3 t03 "истёкший ключ"
run T4 t04 "скользящее продление"
run T5 t05 "отзыв: приложение, бот, веб"
run T6 t06 "ключ в адресе"
run T7 t07 "cookie вместо Bearer"
run T8 t08 "запрос из браузера"
run T9 t09 "вход: пароль + число в боте"
run T10 t10 "вход: отказы"
run T11 t11 "5 неверных паролей"
run T12 t12 "лимиты входа, Telegram"
run T13 t13 "подтверждение: 428 и тексты окон"
run T14 t14 "неверный confirm"
run T15 t15 "правильный confirm"
run T16 t16 "лимиты действий"
run T17 t17 "по одному"
run T18 t18 "проверка параметров"
run T19 t19 "dirdel только из added"
run T20 t20 "не в v1"
run T21 t21 "роутер недоступен, ошибки роутера"
run T22 t22 "долгие задачи"
run T23 t23 "pingone"
run T24 t24 "/vds"
run T26 t26 "веб-CSRF не изменился"
run T28 t28 "rotate router token (сухой прогон)"
run T29 t29 "чистка"
run T25 t25 "секреты в журналах"
run T27 t27 "строки APP_* и сторож, fail2ban"
run X1 x01 "предупреждения PHP"

echo
echo "Итог: PASS $PASS, FAIL ${#FAILS[@]} ($(( $(date +%s) - START )) с)"
if [ ${#FAILS[@]} -gt 0 ]; then printf '  FAIL %s\n' "${FAILS[@]}"; exit 1; fi
exit 0

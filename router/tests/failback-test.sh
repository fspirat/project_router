#!/bin/sh
# Офлайн-тест выбора сервера в router/bin/fspirat-ping: порядок при сбое (свои серверы первыми) и возврат на свой.
# Роутер не нужен: uci, tcping, curl, logger, netstat, date, sleep, lua, xray и /etc/init.d/passwall2 — заглушки,
# пути /tmp/fspirat, /etc/fspirat, /usr/bin, /proc/meminfo в копии скрипта заменены на временную папку.
# Запуск (из корня репозитория): sh router/tests/failback-test.sh   (оболочка для fspirat-ping: dash, если есть)
#   BB=1 sh router/tests/failback-test.sh — как на роутере: busybox sh и утилиты busybox (grep, sed, awk, tr, cut…)
# Нужны: dash или busybox, GNU date, setsid, awk, sed, grep.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PING_SRC=$HERE/../bin/fspirat-ping
CGI_SRC=$HERE/../www/cgi-bin/fspirat
if [ -z "${SH:-}" ]; then
  if command -v dash >/dev/null; then SH=dash; elif command -v busybox >/dev/null; then SH="busybox sh"; else SH=sh; fi
fi
REALDATE=$(command -v date); REALSLEEP=$(command -v sleep)
PASS=0; FAILN=0
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fsfb.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
BBP=""
if [ "${BB:-0}" = 1 ]; then
  command -v busybox >/dev/null || { echo "нет busybox"; exit 2; }
  SH="busybox sh"; BBP=$ROOT/bb/; mkdir -p $BBP
  for a in grep sed awk tr cut head tail basename cat mv rm mkdir sort wc kill setsid printf; do ln -s "$(command -v busybox)" $BBP$a; done
  BBP=$ROOT/bb:
fi

ok()   { PASS=$((PASS+1)); }
bad()  { FAILN=$((FAILN+1)); echo "  FAIL: $*"; }
is()   { [ "$2" = "$3" ] && ok || bad "$1: ждали «$3», получили «$2»"; }
has()  { grep -qF -- "$3" "$2" 2>/dev/null && ok || bad "$1: в $(basename "$2") нет «$3»"; }
hasnt(){ grep -qF -- "$3" "$2" 2>/dev/null && bad "$1: в $(basename "$2") есть «$3»" || ok; }

# ---------- окружение одного сценария ----------
setup() {   # $1 — название
  echo "• $1"
  FT=$ROOT/$(echo "$1" | tr -c 'A-Za-z0-9' _); export FT
  mkdir -p $FT/bin $FT/tmp/fspirat $FT/etc/fspirat $FT/world
  : > $FT/pw.log; : > $FT/logger.log; : > $FT/curl.log
  echo 1760000000 > $FT/now
  echo 'MemAvailable:   55000 kB' > $FT/meminfo
  echo 'TUNNEL_HOST=example.invalid' > $FT/etc/fspirat/config
  echo 0123456789abcdef > $FT/etc/fspirat.token
  # PassWall: Split, свои DE/NL (группа fspirat), подписка nosok: Эстония, Швеция, исключённый «Россия LTE», RU-узел (не пингуется)
  cat > $FT/uci.db <<'EOF'
passwall2.@global[0].node='9DxG2j8l'
passwall2.9DxG2j8l=nodes
passwall2.9DxG2j8l.protocol='_shunt'
passwall2.9DxG2j8l.default_node='fspiratDE'
passwall2.fspiratDE=nodes
passwall2.fspiratDE.remarks='🇩🇪 Германия (fspirat)'
passwall2.fspiratDE.group='fspirat'
passwall2.fspiratDE.protocol='vless'
passwall2.fspiratDE.address='fspiratDE.test'
passwall2.fspiratDE.port='443'
passwall2.fspiratNL=nodes
passwall2.fspiratNL.remarks='🇳🇱 Нидерланды (fspirat)'
passwall2.fspiratNL.group='fspirat'
passwall2.fspiratNL.protocol='vless'
passwall2.fspiratNL.address='fspiratNL.test'
passwall2.fspiratNL.port='443'
passwall2.y7DiVlJN=nodes
passwall2.y7DiVlJN.remarks='🇪🇪 Эстония'
passwall2.y7DiVlJN.group='nosok'
passwall2.y7DiVlJN.protocol='vless'
passwall2.y7DiVlJN.address='y7DiVlJN.test'
passwall2.y7DiVlJN.port='443'
passwall2.SwEdEn01=nodes
passwall2.SwEdEn01.remarks='🇸🇪 Швеция'
passwall2.SwEdEn01.group='nosok'
passwall2.SwEdEn01.protocol='vless'
passwall2.SwEdEn01.address='SwEdEn01.test'
passwall2.SwEdEn01.port='443'
passwall2.LtEru001=nodes
passwall2.LtEru001.remarks='Россия LTE'
passwall2.LtEru001.group='nosok'
passwall2.LtEru001.protocol='vless'
passwall2.LtEru001.address='LtEru001.test'
passwall2.LtEru001.port='443'
EOF
  # «мир»: TCP-пинг (0 — не отвечает) и пропускает ли VPN через узел (1/0)
  world fspiratDE 58 1; world fspiratNL 156 1; world y7DiVlJN 42 1; world SwEdEn01 41 1; world LtEru001 10 1
  mocks
  # копии скриптов с путями во временной папке
  sed -e "s|/etc/init.d/passwall2|$FT/bin/passwall2-init|g" -e "s|/tmp/fspirat|$FT/tmp/fspirat|g" \
      -e "s|/etc/fspirat|$FT/etc/fspirat|g" -e "s|/usr/bin/|$FT/bin/|g" -e "s|/proc/meminfo|$FT/meminfo|g" \
      "$PING_SRC" > $FT/fspirat-ping
  sed -e "s|/etc/init.d/passwall2|$FT/bin/passwall2-init|g" -e "s|/tmp/fspirat|$FT/tmp/fspirat|g" \
      -e "s|/etc/fspirat|$FT/etc/fspirat|g" -e "s|/usr/bin/|$FT/bin/|g" -e "s|^export PATH=.*|:|" \
      "$CGI_SRC" > $FT/cgi
}
world() { echo "$2" > $FT/world/$1.tcp; echo "$3" > $FT/world/$1.vpn; }
node()  { $FT/bin/uci -q get passwall2.9DxG2j8l.default_node; }
set_cur() { $FT/bin/uci set passwall2.9DxG2j8l.default_node=$1; }
logline() { echo "$($REALDATE -d "@$(cat $FT/now)" '+%d.%m %H:%M') $*" >> $FT/tmp/fspirat/switch.log; }
restarts() { grep -c restart $FT/pw.log; }
advance() { echo $(( $(cat $FT/now) + ${1:-300} )) > $FT/now; }
run() {     # $1 — сколько запусков (cron раз в 5 минут)
  i=0; while [ $i -lt ${1:-1} ]; do
    advance 300
    PATH=$FT/bin:$BBP$PATH $SH $FT/fspirat-ping >>$FT/run.out 2>&1
    i=$((i+1))
  done
}
manual() {  # ручной выбор через CGI switch (как страница, бот и приложение)
  PATH=$FT/bin:$BBP$PATH HTTP_COOKIE="fspirat_token=0123456789abcdef" REQUEST_METHOD=POST CONTENT_LENGTH=0 \
    QUERY_STRING="action=switch&id=$1" $SH $FT/cgi > $FT/cgi.out 2>&1
  $REALSLEEP 0.3    # CGI перезапускает PassWall в фоне
}

mocks() {
  B=$FT/bin
  cat > $B/uci <<'EOF'
#!/bin/sh
DB=$FT/uci.db
[ "$1" = -q ] && shift
case "$1" in
  get)  awk -v k="$2=" 'index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^'\''|'\''$/, "", v); print v; f = 1; exit } END { exit !f }' $DB ;;
  set)  k=${2%%=*}; v=${2#*=}; grep -vF "$k=" $DB > $DB.tmp; mv $DB.tmp $DB; echo "$k='$v'" >> $DB; echo "set $k=$v" >> $FT/uci.log ;;
  commit) echo commit >> $FT/uci.log ;;
  show) grep "^$2\." $DB ;;
esac
EOF
  cat > $B/tcping <<'EOF'
#!/bin/sh
for a; do h=$a; done
id=${h%.test}; ms=$(cat $FT/world/$id.tcp 2>/dev/null || echo 0)
[ "$ms" -gt 0 ] && echo "Probing $h:443/tcp - Port is open - time=${ms}.123ms" || echo "Probing $h:443/tcp - No response"
EOF
  cat > $B/curl <<'EOF'
#!/bin/sh
# заглушка: -x socks5h://127.0.0.1:1070 — текущий узел Split; :10802 — узел временного Xray (fb-xray.json)
px=""; fmt=""; nurl=0; prev=""
for a; do
  case "$prev" in -x) px=$a ;; -w) fmt=$a ;; esac
  case "$a" in http://*|https://*) nurl=$((nurl+1)) ;; esac
  prev=$a
done
case "$px" in
  *:1070) [ -f $FT/pw_down ] && { echo "1070 down" >> $FT/curl.log; exit 7; }
          id=$($FT/bin/uci -q get passwall2.9DxG2j8l.default_node) ;;
  *:10802) id=$(sed -n 's/.*"node":"\([^"]*\)".*/\1/p' $FT/tmp/fspirat/fb-xray.json 2>/dev/null) ;;
  *) id=direct ;;
esac
v=1; [ "$id" = _direct ] || [ "$id" = direct ] || v=$(cat $FT/world/$id.vpn 2>/dev/null || echo 0)
echo "${px##*:} $id $v" >> $FT/curl.log
case "$fmt" in
  *time_starttransfer*) i=0; while [ $i -lt $nurl ]; do [ "$v" = 1 ] && echo "204 0.070 0.010" || echo "000 0.000 0.000"; i=$((i+1)); done ;;
  *) [ "$v" = 1 ] && printf 204 || printf 000 ;;
esac
[ "$v" = 1 ] && exit 0 || exit 28
EOF
  cat > $B/date <<EOF
#!/bin/sh
exec $REALDATE -d "@\$(cat \$FT/now)" "\$@"
EOF
  cat > $B/xray <<EOF
#!/bin/sh
echo started >> \$FT/xray.log
exec $REALSLEEP 30
EOF
  cat > $B/fspirat-subs <<'EOF'
#!/bin/sh
[ "$1" = groups ] && printf 'nosok\nfspirat\n'
EOF
  printf '#!/bin/sh\necho "$*" >> $FT/logger.log\n' > $B/logger
  printf '#!/bin/sh\necho "restart $(cat $FT/now)" >> $FT/pw.log; rm -f $FT/pw_down\n' > $B/passwall2-init
  printf '#!/bin/sh\necho "tcp 0 0 0.0.0.0:1070 0.0.0.0:* LISTEN"\necho "tcp 0 0 127.0.0.1:10802 0.0.0.0:* LISTEN"\n' > $B/netstat
  printf '#!/bin/sh\n[ "$2" = gen_config ] && printf "{\\"node\\":\\"%%s\\"}\\n" "$(echo "$3" | sed -n "s/.*\\"node\\":\\"\\([^\\"]*\\)\\".*/\\1/p")"\n' > $B/lua
  printf '#!/bin/sh\nexit 0\n' > $B/sleep
  for f in fspirat-fw fspirat-sub fspirat-targets fspirat-svcping; do printf '#!/bin/sh\nexit 0\n' > $B/$f; done
  chmod +x $B/*
}

echo "Оболочка: $SH"

# ---------- 1. DE перестал работать → уходим на свой NL, а не на Эстонию (у неё пинг меньше) ----------
setup "DE не работает -> свой NL"
world fspiratDE 58 0
run 1; is "после 1 сбоя ещё на DE" "$(node)" fspiratDE
run 1; is "после 2 сбоев" "$(node)" fspiratNL
has "журнал" $FT/tmp/fspirat/switch.log "авто fspiratDE -> fspiratNL 156ms"
is "last_switch" "$(cat $FT/etc/fspirat/last_switch)" "auto fspiratNL"
[ -s $FT/tmp/fspirat/fb_away_fspiratDE ] && ok || bad "нет fb_away_fspiratDE"
is "перезапусков PassWall" "$(restarts)" 1

# ---------- 2. Оба своих молчат → как раньше, наименьший пинг (Швеция 41), исключённый «Россия LTE» (10) не берём ----------
setup "свои молчат -> наименьший пинг"
world fspiratDE 0 0; world fspiratNL 0 0
run 2; is "сервер" "$(node)" SwEdEn01
has "журнал" $FT/tmp/fspirat/switch.log "авто fspiratDE -> SwEdEn01 41ms"

# ---------- 3. Автоматически ушли на Эстонию, DE снова отвечает → через 3 проверки возврат ----------
setup "авто на Эстонию -> возврат на DE"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
echo "$(( $(cat $FT/now) - 3600 ))" > $FT/tmp/fspirat/fb_away_fspiratDE
run 2; is "2 проверки — ещё ждём" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" 0
run 1; is "3-я проверка — возврат" "$(node)" fspiratDE
has "журнал" $FT/tmp/fspirat/switch.log "авто-возврат y7DiVlJN -> fspiratDE 58ms"
is "last_switch" "$(cat $FT/etc/fspirat/last_switch)" "auto fspiratDE"
is "перезапусков" "$(restarts)" 1
is "fb_gap" "$(cat $FT/tmp/fspirat/fb_gap)" 60
has "logger" $FT/logger.log "failback y7DiVlJN -> fspiratDE"
hasnt "временный Xray не запускали (мало памяти)" $FT/curl.log "10802"
run 5; is "дальше стоим на DE" "$(node)" fspiratDE; is "лишних перезапусков нет" "$(restarts)" 1

# ---------- 4. Эстония выбрана вручную (страница / бот / приложение) → не возвращаемся, и после перезагрузки тоже ----------
setup "вручную Эстония -> без возврата"
manual y7DiVlJN
is "CGI переключил" "$(node)" y7DiVlJN
has "журнал CGI" $FT/tmp/fspirat/switch.log "вручную -> y7DiVlJN"
is "last_switch" "$(cat $FT/etc/fspirat/last_switch)" "manual y7DiVlJN"
r0=$(restarts)
run 6; is "через 30 минут" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" "$r0"
logline "MyDirect: + example.org"; logline "перезапуск VPN"
run 3; is "строки другого вида не мешают" "$(node)" y7DiVlJN
rm -f $FT/tmp/fspirat/switch.log $FT/tmp/fspirat/fb_*      # «перезагрузка»: /tmp пуст
run 4; is "после перезагрузки" "$(node)" y7DiVlJN

# ---------- 5. Режим «Напрямую» → ничего не делаем ----------
setup "_direct -> ничего"
manual direct
is "CGI" "$(node)" _direct
r0=$(restarts)
run 6; is "сервер" "$(node)" _direct; is "без перезапусков" "$(restarts)" "$r0"
logline "авто fspiratDE -> _direct 1ms"              # даже если в журнале «авто» — режим «Напрямую» не трогаем
run 4; is "сервер (авто-строка)" "$(node)" _direct

# ---------- 6. Качели: DE упал и сразу поднялся → не раньше FB_HOLD (20 мин) после ухода ----------
setup "FB_HOLD 20 минут"
world fspiratDE 58 0
run 2; is "ушли на NL" "$(node)" fspiratNL
away=$(cat $FT/tmp/fspirat/fb_away_fspiratDE)
world fspiratDE 58 1
run 3; is "через 15 мин ещё на NL (пинг DE шёл всё время, но держим 20 мин)" "$(node)" fspiratNL
run 1; is "через 20 мин — возврат" "$(node)" fspiratDE
is "возврат не раньше 20 мин" "$(( $(cat $FT/tmp/fspirat/fb_last) - away >= 1200 ))" 1
has "журнал" $FT/tmp/fspirat/switch.log "авто-возврат fspiratNL -> fspiratDE"

# ---------- 7. DE отвечает на пинг, но VPN через него не идёт → авто-откат, паузы 120, 240 мин ----------
setup "неудачный возврат -> откат и пауза"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
world fspiratDE 58 0
run 3; is "откатились на Эстонию" "$(node)" y7DiVlJN
has "журнал: попытка" $FT/tmp/fspirat/switch.log "авто-возврат y7DiVlJN -> fspiratDE"
has "журнал: откат" $FT/tmp/fspirat/switch.log "авто-откат fspiratDE -> y7DiVlJN"
is "два перезапуска (туда и обратно)" "$(restarts)" 2
is "пауза удвоилась" "$(cat $FT/tmp/fspirat/fb_gap)" 120
is "last_switch" "$(cat $FT/etc/fspirat/last_switch)" "auto y7DiVlJN"
run 23; is "через 115 мин новой попытки нет" "$(restarts)" 2
run 1;  is "через 120 мин — вторая попытка" "$(restarts)" 4
is "пауза 240" "$(cat $FT/tmp/fspirat/fb_gap)" 240
world fspiratDE 58 1
run 47; is "до 240 мин ждём" "$(node)" y7DiVlJN
run 1;  is "через 240 мин — возврат удался" "$(node)" fspiratDE
is "пауза пока 240" "$(cat $FT/tmp/fspirat/fb_gap)" 240
run 12; is "свой держится час — пауза снова 60" "$(cat $FT/tmp/fspirat/fb_gap)" 60

# ---------- 8. Памяти хватает → сначала проверка через временный Xray; не прошла — без перезапуска ----------
setup "предварительная проверка"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
echo 'MemAvailable:   80000 kB' > $FT/meminfo
world fspiratDE 58 0
run 3; is "остались на Эстонии" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" 0
has "проверяли через 10802" $FT/curl.log "10802 fspiratDE 0"
has "logger" $FT/logger.log "precheck via fspiratDE failed"
is "счётчик DE сброшен" "$(cat $FT/tmp/fspirat/fb_ok_fspiratDE)" 0
[ -f $FT/tmp/fspirat/fb-xray.json ] && bad "fb-xray.json не удалён" || ok
world fspiratDE 58 1
run 3; is "проверка прошла — возврат" "$(node)" fspiratDE; is "один перезапуск" "$(restarts)" 1
has "проверяли через 10802" $FT/curl.log "10802 fspiratDE 1"
: > $FT/curl.log; set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"; echo 0 > $FT/tmp/fspirat/fb_last
mkdir -p $FT/tmp/fspirat/svc; echo $$ > $FT/tmp/fspirat/svc/lock     # «идёт fspirat-svcping» (живой PID)
run 1; hasnt "пока идёт svcping, временный Xray не запускаем" $FT/curl.log "10802"
is "но возврат всё равно (проверка после)" "$(node)" fspiratDE

# ---------- 9. Текущего узла нет (подписка обновилась) → сразу на свой DE ----------
setup "текущий узел пропал"
set_cur GoNe0001; logline "авто fspiratDE -> GoNe0001 30ms"
run 1; is "сервер" "$(node)" fspiratDE
has "журнал" $FT/tmp/fspirat/switch.log "авто GoNe0001 -> fspiratDE 58ms"
ls $FT/tmp/fspirat/fb_away_* >/dev/null 2>&1 && bad "fb_away записан для чужого узла" || ok

# ---------- 10. После перезагрузки (switch.log пуст) возврат по /etc/fspirat/last_switch ----------
setup "после перезагрузки"
set_cur y7DiVlJN; echo "auto y7DiVlJN" > $FT/etc/fspirat/last_switch
run 3; is "возврат" "$(node)" fspiratDE
setup "после перезагрузки, last_switch о другом узле"
set_cur y7DiVlJN; echo "auto SwEdEn01" > $FT/etc/fspirat/last_switch
run 4; is "неизвестно кто выбрал — не трогаем" "$(node)" y7DiVlJN
setup "после перезагрузки, ничего не известно"
set_cur y7DiVlJN
run 4; is "не трогаем" "$(node)" y7DiVlJN

# ---------- 11. Настройки в /etc/fspirat/config ----------
setup "PREFER_RETURN=0"
echo 'PREFER_RETURN=0' >> $FT/etc/fspirat/config
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
run 6; is "без возврата" "$(node)" y7DiVlJN
world y7DiVlJN 42 0
run 2; is "но при сбое — свой первым" "$(node)" fspiratDE

setup "PREFER=fspiratDE (NL не в приоритете)"
echo 'PREFER="fspiratDE"' >> $FT/etc/fspirat/config
world fspiratDE 58 0
run 2; is "при сбое DE — наименьший пинг" "$(node)" SwEdEn01

setup "авто на NL -> возврат на DE"
set_cur fspiratNL; logline "авто fspiratDE -> fspiratNL 156ms"
run 3; is "возврат на DE" "$(node)" fspiratDE

setup "DE мёртв, авто на Эстонии, NL жив -> на NL, потом на DE"
world fspiratDE 0 0
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
run 3; is "сначала NL" "$(node)" fspiratNL
world fspiratDE 58 1
run 3; is "через 15 мин ещё NL (пауза 60 мин между попытками)" "$(node)" fspiratNL
run 9; is "через час — DE" "$(node)" fspiratDE

setup "DE только что ожил, NL давно жив -> ждём DE, на NL не уходим"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
world fspiratDE 0 0
run 2; world fspiratDE 58 1
run 2; is "DE отвечает 2 проверки — ещё Эстония" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" 0
run 1; is "3-я — сразу DE" "$(node)" fspiratDE; is "один перезапуск" "$(restarts)" 1

setup "текущий DE падает только один раз"
world fspiratDE 58 0; run 1; world fspiratDE 58 1; run 3
is "остались на DE" "$(node)" fspiratDE; is "без перезапусков" "$(restarts)" 0

setup "ручной выбор во время проверки возврата не откатываем"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
world fspiratDE 58 0; world SwEdEn01 41 0
# пока fspirat-ping проверяет DE, пользователь выбирает Швецию (имитация: passwall2-init в момент перезапуска меняет узел)
printf '#!/bin/sh\necho "restart" >> $FT/pw.log\n[ "$($FT/bin/uci -q get passwall2.9DxG2j8l.default_node)" = fspiratDE ] && $FT/bin/uci set passwall2.9DxG2j8l.default_node=SwEdEn01\nexit 0\n' > $FT/bin/passwall2-init
run 3; is "осталась Швеция" "$(node)" SwEdEn01
hasnt "отката не было" $FT/tmp/fspirat/switch.log "авто-откат"

setup "ручной выбор того же DE во время проверки — тоже не откатываем"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
world fspiratDE 58 0
printf '#!/bin/sh\necho "restart" >> $FT/pw.log\n[ "$($FT/bin/uci -q get passwall2.9DxG2j8l.default_node)" = fspiratDE ] && echo "$($REALDATE -d @$(cat $FT/now) "+%%d.%%m %%H:%%M") вручную -> fspiratDE" >> $FT/tmp/fspirat/switch.log\nexit 0\n' > $FT/bin/passwall2-init
sed -i "s|\$REALDATE|$REALDATE|" $FT/bin/passwall2-init
run 3; is "остался DE (выбран вручную)" "$(node)" fspiratDE
hasnt "отката не было" $FT/tmp/fspirat/switch.log "авто-откат"

setup "кнопка «Пинг всех» (fspirat-ping all) не возвращает и не ускоряет счёт"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
i=0; while [ $i -lt 5 ]; do advance 60; PATH=$FT/bin:$BBP$PATH $SH $FT/fspirat-ping all >>$FT/run.out 2>&1; i=$((i+1)); done
is "по кнопке — без возврата" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" 0
is "счётчик DE не рос" "$(cat $FT/tmp/fspirat/fb_ok_fspiratDE 2>/dev/null || echo 0)" 0
run 3; is "по cron — возврат" "$(node)" fspiratDE

setup "SOCKS не отвечает (PassWall перезапускается) — возврат ждёт"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
run 2; touch $FT/pw_down; run 1
is "SOCKS лежит — без возврата" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" 0
rm -f $FT/pw_down; run 1; is "SOCKS снова есть — возврат" "$(node)" fspiratDE

setup "DE снова ломается вскоре после возврата — пауза вдвое"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
run 3; is "вернулись" "$(node)" fspiratDE; is "fb_gap" "$(cat $FT/tmp/fspirat/fb_gap)" 60
world fspiratDE 58 0; world fspiratNL 0 0
run 2; is "ушли на подписку (Швеция 41)" "$(node)" SwEdEn01; is "пауза 120 (возврат не удержался)" "$(cat $FT/tmp/fspirat/fb_gap)" 120
world fspiratDE 58 1
run 21; is "через 115 мин после попытки — ещё Швеция" "$(node)" SwEdEn01
run 1; is "через 120 мин — снова DE" "$(node)" fspiratDE
world fspiratDE 58 0
run 2; is "и снова сломался" "$(node)" SwEdEn01; is "пауза 240 (качели не сбрасывают её)" "$(cat $FT/tmp/fspirat/fb_gap)" 240

setup "оба своих сломаны, но порт 443 отвечает — без качелей DE <-> NL, дальше подписка"
world fspiratDE 58 0; world fspiratNL 156 0
run 2; is "сначала NL" "$(node)" fspiratNL
run 2; is "потом подписка, а не снова DE" "$(node)" SwEdEn01
r0=$(restarts)
run 12; is "через час — попытка возврата не удалась, остались на подписке" "$(node)" SwEdEn01
has "откат" $FT/tmp/fspirat/switch.log "авто-откат fspiratDE -> SwEdEn01"
hasnt "на NL второй раз не ходили" $FT/tmp/fspirat/switch.log "SwEdEn01 -> fspiratNL"

setup "живы только свои, с которых недавно ушли — всё равно лучше, чем ничего"
world fspiratDE 58 0; world fspiratNL 156 0; world y7DiVlJN 0 0; world SwEdEn01 0 0; world LtEru001 0 0
run 2; is "NL" "$(node)" fspiratNL
run 2; is "снова DE (больше никого)" "$(node)" fspiratDE

setup "PassWall сейчас перезапускается (CGI restart) — возврат ждёт"
set_cur y7DiVlJN; logline "авто fspiratDE -> y7DiVlJN 37ms"
printf '#!/bin/sh\necho "  PID USER COMMAND"\necho " 4242 root /bin/sh /etc/init.d/passwall2 restart"\n' > $FT/bin/ps; chmod +x $FT/bin/ps
run 4; is "идёт перезапуск — без возврата" "$(node)" y7DiVlJN; is "без перезапусков" "$(restarts)" 0
printf '#!/bin/sh\necho "  PID USER COMMAND"\n' > $FT/bin/ps
run 1; is "перезапуск закончился — возврат" "$(node)" fspiratDE

# fspirat-ping ничего не должен печатать (ошибки оболочки — «Illegal number», «not found» и т.п.)
for f in $ROOT/*/run.out; do [ -s "$f" ] && { bad "вывод fspirat-ping в $(basename "$(dirname "$f")"):"; sed 's/^/    /' "$f" | head -5; }; done
echo
echo "Итог: пройдено $PASS, ошибок $FAILN"
[ $FAILN -eq 0 ]

#!/bin/bash
# Панель роутера на новом домене, параллельно со старым (переезд fspirat.online → fspirat.xyz, docs/domain-migration.md).
#   NEW/router/      — include snippets/fspirat-router.conf вместо заглушки «location ^~ /router/ { return 404; }»
#                      в /etc/nginx/sites-available/NEW (этот server-блок и его сертификат создаёт сессия homeserver);
#   router.NEW       — LuCI за входом, копия router.OLD; свой сертификат (certbot webroot, обновляется сам);
#   deploy.conf      — PANEL_ALIASES+=NEW: вход на NEW ставит cookie на NEW (server/auth/lib.php fsr_panel).
# Старые адреса не меняются. Копии — /root/fspirat-backups/domain-<время>/; nginx -t не прошёл — всё возвращается.
# Запуск (root, NL, из файла — откат вызывает сам себя): bash panel-new-domain.sh fspirat.online fspirat.xyz      Откат: bash panel-new-domain.sh --rollback <папка копий>
set -euo pipefail
A=/etc/nginx/sites-available; E=/etc/nginx/sites-enabled
if [ "${1:-}" = --rollback ]; then
  B=$2; [ -d "$B" ] || { echo "нет $B"; exit 1; }
  for f in "$B"/*; do n=$(basename "$f"); case $n in *.absent) rm -f "$A/${n%.absent}" "$E/${n%.absent}";; deploy.conf) cp "$f" /etc/fspirat-router/deploy.conf;; *) cp "$f" "$A/$n";; esac; done
  nginx -t -q && systemctl reload nginx && echo "откат из $B: готово"; exit 0
fi
OLD=$1; NEW=$2; R=router.$NEW; W=/var/www/$OLD
for d in "$OLD" "$NEW"; do [[ $d =~ ^[a-z0-9.-]+$ ]] || { echo "неверный домен $d"; exit 1; }; done
IP=$(dig +short $OLD A @1.1.1.1 | tail -1)   # старый домен — уже на этом сервере
for h in $NEW $R; do [ "$(dig +short $h A @1.1.1.1 | tail -1)" = "$IP" ] || { echo "❌ DNS: $h не указывает на этот сервер"; exit 1; }; done
[ -f $A/$NEW ] && [ -f /etc/letsencrypt/live/$NEW/fullchain.pem ] || { echo "❌ нет сайта $NEW или его сертификата (создаёт homeserver)"; exit 1; }
[ -f $A/router.$OLD ] || { echo "❌ нет $A/router.$OLD (образец)"; exit 1; }

B=/root/fspirat-backups/domain-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
cp $A/$NEW "$B/"; if [ -f $A/$R ]; then cp $A/$R "$B/"; else touch "$B/$R.absent"; fi
[ -f /etc/fspirat-router/deploy.conf ] && cp /etc/fspirat-router/deploy.conf "$B/deploy.conf"
echo "копии: $B"
restore() { echo "❌ $1 — возвращаю как было"; bash "$0" --rollback "$B" || true; exit 1; }

# 1. NEW/router/ — подключить сниппет панели вместо заглушки
python3 - "$A/$NEW" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
if 'include snippets/fspirat-router.conf;' in s:
    print(f'{p}: /router/ уже подключён'); sys.exit()
s, n = re.subn(r'[ \t]*location \^~ /router/ \{\s*return 404;\s*\}\n', '    include snippets/fspirat-router.conf;\n', s, count=1)
if n != 1: sys.exit(f'{p}: не нашёл заглушку location ^~ /router/ {{ return 404; }}')
open(p, 'w').write(s); print(f'{p}: /router/ подключён')
PY

# 2. router.NEW — сначала порт 80 (ACME), сертификат, потом сайт как router.OLD
if [ ! -f /etc/letsencrypt/live/$R/fullchain.pem ]; then
  cat > $A/$R <<N
server { listen 80; listen [::]:80; server_name $R;
    location /.well-known/acme-challenge/ { root $W; }
    location / { return 301 https://\$host\$request_uri; } }
N
  ln -sf $A/$R $E/$R
  nginx -t -q || restore "nginx -t (порт 80 для $R)"; systemctl reload nginx
  certbot certonly --webroot -w $W -d $R --non-interactive --agree-tos --register-unsafely-without-email -q || restore "certbot $R"
fi
echo "сертификат $R: $(openssl x509 -in /etc/letsencrypt/live/$R/fullchain.pem -noout -enddate)"
H=/etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
[ -n "$(ls /etc/letsencrypt/renewal-hooks/deploy/)" ] || { printf '#!/bin/sh\nsystemctl reload nginx\n' > $H; chmod 755 $H; }
python3 - "$A/router.$OLD" "$A/$R" "$OLD" "$NEW" "$W" <<'PY'
import re, sys
src, dst, old, new, web = sys.argv[1:]
s = open(src).read()
m = re.search(r'server \{(?:(?!\nserver \{).)*?listen 127\.0\.0\.1:10443[^\n]*\n.*?\n\}', s, re.S)
if not m: sys.exit('образец: не нашёл server-блок с listen 127.0.0.1:10443')
b = m.group(0)
b = b.replace(f'https://{old}/router/login?next=https://router.{old}', f'https://{new}/router/login?next=https://router.{new}')
b = b.replace(f'router.{old}', f'router.{new}')
if old in b: sys.exit('образец: остался старый домен — не понимаю структуру')
if 'auth_request /_fsr_auth' not in b: sys.exit('образец: нет auth_request — без входа не выкладываю')
b = re.sub(r'\s*# managed by Certbot', '', b)
head = (f'# /etc/nginx/sites-available/router.{new} — LuCI роутера за входом панели (копия router.{old}, server/domain/panel-new-domain.sh)\n'
        f'server {{ listen 80; listen [::]:80; server_name router.{new};\n'
        f'    location /.well-known/acme-challenge/ {{ root {web}; }}\n'
        f'    location / {{ return 301 https://$host$request_uri; }} }}\n')
open(dst, 'w').write(head + b + '\n'); print(f'{dst}: записан')
PY
ln -sf $A/$R $E/$R

# 3. deploy.conf: панель работает и на NEW (Deploy server запишет это в site.json)
C=/etc/fspirat-router/deploy.conf
cur=$(. $C; echo "${PANEL_ALIASES:-}")
case " $cur " in *" $NEW "*) ;; *)
  sed -i '/^PANEL_ALIASES=/d' $C; echo "PANEL_ALIASES=\"$(echo $cur $NEW)\"" >> $C ;;
esac
echo "deploy.conf: $(grep '^PANEL_ALIASES=' $C)"

nginx -t -q 2>/tmp/ngt || { cat /tmp/ngt; restore "nginx -t"; }
systemctl reload nginx; sleep 1; echo "nginx: перезагружен"

# 4. проверка: новые адреса и старые (старые — как были)
c() { curl -s -o /dev/null -m 10 -w '%{http_code} %{redirect_url}' "$@" || echo "ошибка curl"; }
echo "-- новые:"
echo "  https://$NEW/router/login       $(c https://$NEW/router/login)"
echo "  https://$NEW/router/            $(c https://$NEW/router/)"
echo "  https://$NEW/router/api (без X-FSR)  $(c "https://$NEW/router/api?action=net")"
echo "  https://$NEW/router/api (X-FSR, без входа) $(c -H 'X-FSR: 1' "https://$NEW/router/api?action=net")"
echo "  https://$NEW/router/manifest.webmanifest $(c https://$NEW/router/manifest.webmanifest)"
echo "  https://$R/                     $(c https://$R/)"
echo "-- старые:"
echo "  https://$OLD/router/            $(c https://$OLD/router/)"
echo "  https://$OLD/router/login       $(c https://$OLD/router/login)"
echo "  https://router.$OLD/            $(c https://router.$OLD/)"
echo "  https://$OLD/                   $(c https://$OLD/)"
echo "  https://$NEW/                   $(c https://$NEW/)"
echo "откат: bash panel-new-domain.sh --rollback $B"

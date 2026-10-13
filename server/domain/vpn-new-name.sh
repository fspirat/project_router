#!/bin/bash
# VPN (Xray Reality «сам у себя») под новым именем, параллельно со старым: nl.fspirat.online → + nl.fspirat.xyz (NL),
# de.fspirat.online → + de.fspirat.xyz (DE). Ключи, UUID и shortId не меняются; старое имя продолжает работать.
#   prep — сертификат и сайт-обложка для нового имени (как у старого). VPN не трогается.
#   xray — новое имя в realitySettings.serverNames (+ строка в карте SNI на 443, если она есть) и перезапуск xray:
#          связь через этот сервер прерывается на 1–2 секунды. Конфиг проверяется (xray -test), при ошибке — откат.
# Запуск (root, на самом сервере, из файла): bash vpn-new-name.sh prep|xray НОВОЕ_ИМЯ СТАРОЕ_ИМЯ
# Откат: bash vpn-new-name.sh --rollback <папка копий>
set -euo pipefail
X=/usr/local/etc/xray/config.json; S=/etc/nginx/stream.d/sni-443.conf; A=/etc/nginx/sites-available; E=/etc/nginx/sites-enabled
if [ "${1:-}" = --rollback ]; then
  B=$2
  [ -f "$B/config.json" ] && { cp "$B/config.json" $X; systemctl restart xray; }
  [ -f "$B/sni-443.conf" ] && cp "$B/sni-443.conf" $S
  for f in "$B"/*.absent; do [ -e "$f" ] || continue; n=$(basename "$f" .absent); rm -f "$A/$n" "$E/$n"; done
  nginx -t -q && systemctl reload nginx; echo "откат из $B: xray $(systemctl is-active xray)"; exit 0
fi
MODE=$1; NEW=$2; OLD=$3
for d in "$NEW" "$OLD"; do [[ $d =~ ^[a-z0-9.-]+$ ]] || { echo "неверное имя $d"; exit 1; }; done
if [ -f $S ]; then LAY=nl; W=/var/www/nl; else LAY=de; W=/var/www/de; fi
B=/root/fspirat-backups/vpn-$MODE-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"; echo "копии: $B (схема $LAY)"
restore() { echo "❌ $1 — возвращаю как было"; bash "$0" --rollback "$B" || true; exit 1; }

if [ "$MODE" = prep ]; then
  MY=$(dig +short "$OLD" A @1.1.1.1 | tail -1)
  [ "$(dig +short "$NEW" A @1.1.1.1 | tail -1)" = "$MY" ] || { echo "❌ DNS: $NEW не указывает на этот сервер (как $OLD)"; exit 1; }
  [ -f $A/$NEW ] && cp $A/$NEW "$B/" || touch "$B/$NEW.absent"
  mkdir -p $W/.well-known/acme-challenge
  if [ ! -f /etc/letsencrypt/live/$NEW/fullchain.pem ]; then
    echo "server { listen 80; listen [::]:80; server_name $NEW; location /.well-known/acme-challenge/ { root $W; } location / { return 404; } }" > $A/$NEW
    ln -sf $A/$NEW $E/$NEW
    nginx -t -q || restore "nginx -t (порт 80)"; systemctl reload nginx
    certbot certonly --webroot -w $W -d $NEW --non-interactive --agree-tos --register-unsafely-without-email -q || restore "certbot $NEW"
  fi
  echo "сертификат $NEW: $(openssl x509 -in /etc/letsencrypt/live/$NEW/fullchain.pem -noout -enddate)"
  C=/etc/letsencrypt/live/$NEW
  if [ $LAY = nl ]; then
    cat > $A/$NEW <<N
# $NEW — сайт-обложка VPN (Reality отдаёт сюда всех, кто пришёл без ключа); копия $OLD (server/domain/vpn-new-name.sh)
server { listen 80; listen [::]:80; server_name $NEW;
  location /.well-known/acme-challenge/ { root $W; } location / { return 301 https://fspirat.xyz/; } }
server { listen 127.0.0.1:10443 ssl proxy_protocol; server_name $NEW;
  ssl_certificate $C/fullchain.pem; ssl_certificate_key $C/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf; ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
  root $W; index index.html; }
N
  else
    cat > $A/$NEW <<N
# $NEW — сайт-обложка VPN (Reality отдаёт сюда всех, кто пришёл без ключа); копия $OLD (server/domain/vpn-new-name.sh)
server { listen 80; listen [::]:80; server_name $NEW;
  location /.well-known/acme-challenge/ { root $W; }
  location / { return 301 https://$NEW\$request_uri; } }
server { listen 127.0.0.1:8443 ssl http2; server_name $NEW;
  ssl_certificate $C/fullchain.pem; ssl_certificate_key $C/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3; root $W; index index.html; }
N
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
  fi
  ln -sf $A/$NEW $E/$NEW
  nginx -t -q 2>/tmp/ngt || { cat /tmp/ngt; restore "nginx -t"; }
  systemctl reload nginx; sleep 1
  if [ $LAY = nl ]; then r="127.0.0.1"; p=443; else r="127.0.0.1"; p=8443; fi
  echo "обложка $NEW (TLS, проверка сертификата): $(curl -s -o /dev/null -m 8 -w '%{http_code}' --resolve $NEW:$p:$r https://$NEW:$p/ || echo ошибка)"
  echo "обложка $OLD (как была): $(curl -s -o /dev/null -m 8 -w '%{http_code}' --resolve $OLD:$p:$r https://$OLD:$p/ || echo ошибка)"
  echo "откат: bash vpn-new-name.sh --rollback $B"; exit 0
fi

[ "$MODE" = xray ] || { echo "режим: prep или xray"; exit 1; }
[ -f /etc/letsencrypt/live/$NEW/fullchain.pem ] || { echo "❌ сначала prep (нет сертификата $NEW)"; exit 1; }
XN=${X%.json}.new.json
cp $X "$B/config.json"; [ -f $S ] && cp $S "$B/"
jq -e --arg o "$OLD" 'any(.inbounds[]; (.streamSettings.realitySettings.serverNames // []) | index($o))' $X >/dev/null || { echo "❌ в xray нет inbound с $OLD"; exit 1; }
( umask 077; jq --arg o "$OLD" --arg n "$NEW" '(.inbounds[] | select((.streamSettings.realitySettings.serverNames // []) | index($o)) | .streamSettings.realitySettings.serverNames) |= (. + [$n] | unique)' $X > $XN )
/usr/local/bin/xray run -test -config $XN >/tmp/xt 2>&1 || { rm -f $XN; grep -iE "fail|error|invalid" /tmp/xt | tail -3 | cut -c1-200; echo "❌ xray -test не прошёл — ничего не меняю"; exit 1; }
cat $XN > $X; rm -f $XN
systemctl restart xray; sleep 2; systemctl is-active --quiet xray || { journalctl -u xray -n 5 --no-pager | cut -c1-200; restore "xray не запустился"; }
echo "xray: $(systemctl is-active xray), имена: $(jq -c '[.inbounds[].streamSettings.realitySettings.serverNames // empty] | add' $X)"
if [ -f $S ] && ! grep -qE "^\s*${NEW//./\\.}\s" $S; then
  sed -i -E "s|^(\s*)${OLD//./\\.}(\s+)(127\.0\.0\.1:[0-9]+;)|&\n\1$NEW\2\3|" $S
  grep -qE "^\s*${NEW//./\\.}\s" $S || restore "не смог добавить $NEW в $S"
  nginx -t -q || restore "nginx -t (карта SNI)"; systemctl reload nginx; echo "443: $NEW → xray"
fi
echo "откат: bash vpn-new-name.sh --rollback $B"

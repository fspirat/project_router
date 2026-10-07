#!/bin/bash
# Reality «сам у себя»: маскировка под свой домен de.fspirat.online, который указывает на этот же VDS
# (как у серверов nosok) — DPI видит обычный сайт с настоящим сертификатом на своём IP.
# nginx: 80 — ACME и редирект, 127.0.0.1:8443 — сайт с сертификатом Let's Encrypt (сюда Reality отдаёт чужие подключения).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
D=de.fspirat.online
[ "$(getent ahostsv4 $D | awk 'NR==1{print $1}')" = 64.188.83.100 ] || { echo "DNS $D ещё не указывает на 64.188.83.100"; exit 1; }
apt-get -y -qq install nginx certbot >/dev/null
mkdir -p /var/www/de/.well-known/acme-challenge
cat > /var/www/de/index.html <<'H'
<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>FSPIRAT</title></head><body style="font-family:sans-serif;background:#050605;color:#9be052;text-align:center;padding-top:20vh"><h1>FSPIRAT</h1><p>de.fspirat.online</p></body></html>
H
cat > /etc/nginx/sites-available/de <<N
server { listen 80; listen [::]:80; server_name $D;
  location /.well-known/acme-challenge/ { root /var/www/de; }
  location / { return 301 https://$D\$request_uri; } }
N
ln -sf /etc/nginx/sites-available/de /etc/nginx/sites-enabled/de; rm -f /etc/nginx/sites-enabled/default
ufw allow 80/tcp >/dev/null
nginx -t -q; systemctl reload nginx
[ -f /etc/letsencrypt/live/$D/fullchain.pem ] || certbot certonly -q --webroot -w /var/www/de -d $D --agree-tos --register-unsafely-without-email --non-interactive
echo "сертификат: $(openssl x509 -in /etc/letsencrypt/live/$D/fullchain.pem -noout -enddate)"
cat >> /etc/nginx/sites-available/de <<N
server { listen 127.0.0.1:8443 ssl http2; server_name $D;
  ssl_certificate /etc/letsencrypt/live/$D/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$D/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3; root /var/www/de; index index.html; }
N
nginx -t -q; systemctl reload nginx
printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/nginx.sh; chmod 755 /etc/letsencrypt/renewal-hooks/deploy/nginx.sh
sed -i "s/^SNI=.*/SNI=$D/" /usr/local/etc/xray/fspirat.env
jq --arg d "$D" '.inbounds[0].streamSettings.realitySettings.dest = "127.0.0.1:8443" | .inbounds[0].streamSettings.realitySettings.serverNames = [$d]' /usr/local/etc/xray/config.json > /tmp/c.json && cat /tmp/c.json > /usr/local/etc/xray/config.json && rm /tmp/c.json
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null && systemctl restart xray && echo "xray: маскировка $D, $(systemctl is-active xray)"
echo "сайт через 443 (как видит DPI): $(curl -s -m 8 -o /dev/null -w '%{http_code}' --resolve $D:443:127.0.0.1 https://$D/)"

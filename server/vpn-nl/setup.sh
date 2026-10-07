#!/bin/bash
# VPN на сервере сайта (Нидерланды): Xray VLESS + Reality «сам у себя» под nl.fspirat.online.
# Порт 443 уже делит nginx stream по SNI (stream.d/sni-443.conf): nl.fspirat.online → Xray 127.0.0.1:10445,
# остальное — как было (сайты 10443, Telegram-прокси 10444). Reality отдаёт чужих на сайт-обложку nl.fspirat.online
# (nginx 127.0.0.1:10443, настоящий сертификат). Перед правкой — копия nginx; если сайты не отвечают — откат.
# Ключи Xray — /usr/local/etc/xray/fspirat.env (только root), не печатаются. Повторный запуск безопасен.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
D=nl.fspirat.online
IP4=$(curl -s -4 -m 8 ifconfig.me)
STAMP=$(date +%Y%m%d-%H%M%S)
dns=$(dig +short "$D" A @1.1.1.1 | tail -1)
[ "$dns" = "$IP4" ] || { echo "❌ DNS: $D → '${dns:-нет записи}', нужно $IP4 (Cloudflare, серое облако)"; exit 1; }
echo "✅ DNS $D → $dns"

tar -czf /root/nginx-backup-$STAMP.tgz -C /etc nginx; echo "копия nginx: /root/nginx-backup-$STAMP.tgz"
restore() { echo "❌ $1 — возвращаю nginx как было"; rm -rf /etc/nginx; tar -xzf /root/nginx-backup-$STAMP.tgz -C /etc; nginx -t -q && systemctl restart nginx; exit 1; }

# 1. сертификат для обложки
mkdir -p /var/www/nl
printf '<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>FSPIRAT</title></head><body style="font-family:sans-serif;background:#050605;color:#9be052;text-align:center;padding-top:20vh"><h1>FSPIRAT</h1></body></html>\n' > /var/www/nl/index.html
if [ ! -f /etc/letsencrypt/live/$D/fullchain.pem ]; then
  echo "server { listen 80; listen [::]:80; server_name $D; location /.well-known/acme-challenge/ { root /var/www/nl; } location / { return 404; } }" > /etc/nginx/sites-available/$D
  ln -sf /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/$D
  nginx -t -q || restore "nginx -t (порт 80)"; systemctl reload nginx
  certbot certonly --webroot -w /var/www/nl -d $D --non-interactive --agree-tos --register-unsafely-without-email -q
fi
echo "✅ сертификат: $(openssl x509 -in /etc/letsencrypt/live/$D/fullchain.pem -noout -enddate)"
cat > /etc/nginx/sites-available/$D <<N
# $D — сайт-обложка для VPN (Reality отдаёт сюда всех, кто пришёл без ключа)
server { listen 80; listen [::]:80; server_name $D;
  location /.well-known/acme-challenge/ { root /var/www/nl; } location / { return 301 https://fspirat.online/; } }
server { listen 127.0.0.1:10443 ssl proxy_protocol; server_name $D;
  ssl_certificate /etc/letsencrypt/live/$D/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$D/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf; ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
  root /var/www/nl; index index.html; }
N
ln -sf /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/$D

# 2. Xray
[ -x /usr/local/bin/xray ] || bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
E=/usr/local/etc/xray/fspirat.env
if [ ! -s $E ]; then
  K=$(/usr/local/bin/xray x25519)
  ( umask 077; printf 'UUID=%s\nPRIV=%s\nPUBK=%s\nSID=%s\nSNI=%s\n' "$(/usr/local/bin/xray uuid)" "$(echo "$K" | grep -i private | awk '{print $NF}')" \
    "$(echo "$K" | grep -iE 'public|password' | head -1 | awk '{print $NF}')" "$(openssl rand -hex 8)" "$D" > $E )
  echo "✅ ключи xray: созданы"
fi
. $E
( umask 077; jq -n --arg id "$UUID" --arg pk "$PRIV" --arg sid "$SID" --arg sni "$D" '{
  log: {loglevel: "warning"},
  inbounds: [{listen: "127.0.0.1", port: 10445, protocol: "vless",
    settings: {clients: [{id: $id, flow: "xtls-rprx-vision", email: "router"}], decryption: "none"},
    streamSettings: {network: "raw", security: "reality", sockopt: {acceptProxyProtocol: true},
      realitySettings: {dest: "127.0.0.1:10443", xver: 1, serverNames: [$sni], privateKey: $pk, shortIds: [$sid]}},
    sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}}],
  outbounds: [{protocol: "freedom", tag: "direct", settings: {domainStrategy: "UseIPv4"}}, {protocol: "blackhole", tag: "block"}],
  routing: {rules: [{type: "field", ip: ["geoip:private"], outboundTag: "block"}, {type: "field", protocol: ["bittorrent"], outboundTag: "block"}]}
}' > /usr/local/etc/xray/config.json )
chgrp nogroup /usr/local/etc/xray/config.json; chmod 640 /usr/local/etc/xray/config.json
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null && echo "✅ конфиг xray: проверен"
systemctl enable -q xray; systemctl restart xray; sleep 1; systemctl is-active --quiet xray || { journalctl -u xray -n 10 --no-pager; exit 1; }

# 3. маршрут по SNI на 443
F=/etc/nginx/stream.d/sni-443.conf
grep -q "$D" $F || sed -i "s|^\(\s*\)tg.fspirat.online\(\s*\)127.0.0.1:10444;|&\n\1$D  127.0.0.1:10445;|" $F
grep -q "$D" $F || restore "не смог добавить $D в $F"
nginx -t -q || restore "nginx -t"
systemctl reload nginx || restore "nginx reload"
sleep 2
ok=1
for u in https://fspirat.online/ https://fspirat.ru/ https://fspirat.online/router/login https://router.fspirat.online/ https://$D/; do
  c=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" || true); echo "  $u → $c"
  case $c in 200|301|302) ;; *) ok=0 ;; esac
done
systemctl is-active --quiet mtg && echo "  mtg: работает" || { ok=0; echo "  mtg: НЕ работает"; }
[ $ok = 1 ] || { systemctl stop xray; restore "сайты не отвечают после переключения"; }
echo "✅ готово: $D → Xray, сайты и Telegram-прокси на месте"

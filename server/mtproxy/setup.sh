#!/bin/bash
# MTProto-прокси mtg на 443 через nginx stream (SNI). Запуск на сервере от root.
# Повторный запуск безопасен. Перед правкой nginx — копия /etc/nginx в /root/nginx-backup-*.tgz;
# если nginx -t не проходит или сайты не отвечают — всё возвращается как было.
# Секрет прокси в лог не печатается: ссылка уходит в Telegram-бота (@FSRouter_bot).
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
DOMAIN=tg.fspirat.online
IP4=193.39.143.202
MTG_VER=2.2.8
STAMP=$(date +%Y%m%d-%H%M%S)

# 0. DNS: без записи A tg.fspirat.online → сервер сертификат не выпустить
dns=$(dig +short "$DOMAIN" A @1.1.1.1 | tail -1)
[ "$dns" = "$IP4" ] || { echo "❌ DNS: $DOMAIN → '${dns:-нет записи}', нужно $IP4 (Cloudflare, серое облако)"; exit 1; }
echo "✅ DNS $DOMAIN → $dns"

# 1. модуль stream для nginx
dpkg -s libnginx-mod-stream >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -q libnginx-mod-stream >/dev/null
echo "✅ libnginx-mod-stream"

# 2. сертификат для сайта-обложки (порт 80 работает как раньше)
install -d -m 755 /var/www/tg
if [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
  cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server { listen 80; listen [::]:80; server_name $DOMAIN; location /.well-known/acme-challenge/ { root /var/www/tg; } location / { return 404; } }
EOF
  ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
  nginx -t -q && systemctl reload nginx
  certbot certonly --webroot -w /var/www/tg -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email -q
fi
install -d /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
echo "✅ сертификат $DOMAIN"

# 3. mtg
if ! /usr/local/bin/mtg --version 2>/dev/null | grep -q "$MTG_VER"; then
  t=$(mktemp -d)
  curl -fsSL -o "$t/mtg.tgz" "https://github.com/9seconds/mtg/releases/download/v$MTG_VER/mtg-$MTG_VER-linux-amd64.tar.gz"
  tar -xzf "$t/mtg.tgz" -C "$t"
  install -m 755 "$(find "$t" -type f -name mtg | head -1)" /usr/local/bin/mtg
  rm -rf "$t"
fi
id mtg >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin mtg
if [ ! -f /etc/mtg.toml ]; then
  secret=$(/usr/local/bin/mtg generate-secret --hex $DOMAIN)
  ( umask 027; cat > /etc/mtg.toml <<EOF
# MTProto-прокси (mtg $MTG_VER). Секрет = доступ, в git не класть. Новый: mtg generate-secret --hex $DOMAIN
secret = "$secret"
bind-to = "127.0.0.1:10444"
proxy-protocol-listener = true      # соединения приходят от nginx stream с настоящим IP клиента
public-ipv4 = "$IP4"
prefer-ip = "prefer-ipv4"

[domain-fronting]                   # кто пришёл без секрета — на сайт-обложку (nginx 127.0.0.1:10443)
host = "127.0.0.1"
ip = "127.0.0.1"                    # mtg 2.2.x понимает только ip (host — в новых версиях)
port = 10443
proxy-protocol = true
EOF
  )
  chgrp mtg /etc/mtg.toml; chmod 640 /etc/mtg.toml
fi
# исправление первой установки: mtg 2.2.x не знает «host» и шёл на внешний IP:10443
grep -q '^ip = "127.0.0.1"' /etc/mtg.toml || sed -i '/^host = "127.0.0.1"/a ip = "127.0.0.1"                    # mtg 2.2.x понимает только ip' /etc/mtg.toml
install -m 644 "$D/mtg.service" /etc/systemd/system/mtg.service
systemctl daemon-reload
echo "✅ mtg: $(/usr/local/bin/mtg --version | head -1)"

# 4. nginx: сайты 443 → 127.0.0.1:10443 (proxy_protocol), на 443 — stream по SNI
tar -czf /root/nginx-backup-$STAMP.tgz -C /etc nginx
echo "копия nginx: /root/nginx-backup-$STAMP.tgz"
restore() {
  echo "❌ $1 — возвращаю nginx как было"
  systemctl stop mtg 2>/dev/null || true
  rm -rf /etc/nginx; tar -xzf /root/nginx-backup-$STAMP.tgz -C /etc
  nginx -t -q && systemctl restart nginx
  exit 1
}
python3 - <<'PY'
import re
for f in ['/etc/nginx/sites-available/fspirat.online', '/etc/nginx/sites-available/fspirat.ru',
          '/etc/nginx/sites-available/router.fspirat.online']:
    s = open(f).read()
    if '127.0.0.1:10443' in s:
        print(f, 'уже переведён'); continue
    s = re.sub(r'^[ \t]*listen \[::\]:443[^;]*;[^\n]*\n', '', s, flags=re.M)        # IPv6 теперь принимает stream
    s, n = re.subn(r'^([ \t]*)listen 443 ssl;', r'\1listen 127.0.0.1:10443 ssl proxy_protocol;', s, flags=re.M)
    if n < 1:
        raise SystemExit(f + ': не нашёл "listen 443 ssl;"')
    open(f, 'w').write(s); print(f, '→ 127.0.0.1:10443')
PY
install -m 644 "$D/realip-proxy-protocol.conf" /etc/nginx/conf.d/realip-proxy-protocol.conf
install -m 644 "$D/no-port-in-redirect.conf" /etc/nginx/conf.d/no-port-in-redirect.conf
install -d /etc/nginx/stream.d
install -m 644 "$D/sni-443.conf" /etc/nginx/stream.d/sni-443.conf
grep -q 'stream.d/\*.conf' /etc/nginx/nginx.conf || \
  sed -i '/^include \/etc\/nginx\/modules-enabled\/\*.conf;/a include /etc/nginx/stream.d/*.conf;' /etc/nginx/nginx.conf
install -m 644 "$D/tg.fspirat.online.site" /etc/nginx/sites-available/$DOMAIN
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
nginx -t 2>&1 | tail -2
nginx -t -q || restore "nginx -t не прошёл"
systemctl restart nginx || restore "nginx не перезапустился"     # restart: порт 443 переходит от http к stream
systemctl enable mtg >/dev/null 2>&1; systemctl restart mtg
sleep 3

# 5. проверка
ok=1
for u in https://fspirat.online/ https://fspirat.ru/ https://fspirat.online/router/login https://router.fspirat.online/; do
  c=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" || true); echo "  $u → $c"
  case $c in 200|301|302) ;; *) ok=0 ;; esac
done
# перенаправления — без внутреннего порта
for u in https://fspirat.online/fstweak https://fspirat.online/router/ https://fspirat.ru/fstweak; do
  r=$(curl -s -o /dev/null -m 10 -w '%{redirect_url}' "$u" || true); echo "  $u → $r"
  case $r in *:10443*) ok=0 ;; esac
done
f=$(curl -s -o /dev/null -m 10 -w '%{http_code} %{redirect_url}' https://$DOMAIN/ || true)
echo "  https://$DOMAIN/ без секрета (как сканер) → $f"
case $f in 301*fspirat.online*) ;; *) echo "  ⚠️ сайт-обложка не отвечает (прокси работает, но маскировка слабее)"; journalctl -u mtg -n 5 --no-pager | cut -c1-200 ;; esac
if systemctl is-active --quiet mtg; then echo "  mtg: работает"; else ok=0; echo "  mtg: НЕ работает"; journalctl -u mtg -n 15 --no-pager; fi
[ $ok = 1 ] || restore "что-то не отвечает после переключения"
echo "  IP в логе сайтов (должны быть настоящие, не 127.0.0.1): $(tail -n 5 /var/log/nginx/access.log | awk '{print $1}' | sort -u | tr '\n' ' ')"

# 6. ссылка — в Telegram-бота (не в лог)
if [ ! -f /var/lib/fspirat/mtg_link_sent ]; then
  . /etc/fspirat-watch.conf
  sec=$(grep -oP '^secret = "\K[^"]+' /etc/mtg.toml)
  link="https://t.me/proxy?server=$DOMAIN&port=443&secret=$sec"
  curl -s -m 15 "https://api.telegram.org/bot$TG_TOKEN/sendMessage" --data-urlencode "chat_id=$TG_CHAT" \
    --data-urlencode "text=📨 Свой Telegram-прокси готов. Нажми, чтобы подключить:
$link

Ссылка = доступ. Давай только тем, кому доверяешь." >/dev/null && touch /var/lib/fspirat/mtg_link_sent && echo "✅ ссылка отправлена в Telegram-бота"
fi
echo "✅ готово"

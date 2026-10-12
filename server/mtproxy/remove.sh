#!/bin/bash
# Выключить свой Telegram-прокси (mtg) — 12.10.2026 владелец решил, что он не нужен.
#   служба mtg — остановлена и убрана из автозапуска; файл службы — в копии (fspirat-watch по нему решает, следить ли за mtg);
#   stream.d/sni-443.conf — без строки tg.<домен> (такие подключения уходят на сайты, как любые другие);
#   deploy.conf — MTG_DOMAIN пустой: Deploy server уберёт блок прокси из панели и команду /tgproxy из бота.
# Конфиг с секретом /etc/mtg.toml и сайт-обложка tg.<домен> остаются — для возврата.
# Запуск (root, NL, из файла): bash remove.sh            Откат: bash remove.sh --rollback <папка копий>
set -euo pipefail
S=/etc/nginx/stream.d/sni-443.conf; U=/etc/systemd/system/mtg.service; C=/etc/fspirat-router/deploy.conf
if [ "${1:-}" = --rollback ]; then
  B=$2; cp "$B/sni-443.conf" $S; cp "$B/deploy.conf" $C; cp "$B/mtg.service" $U
  systemctl daemon-reload; systemctl enable -q --now mtg; nginx -t -q && systemctl reload nginx
  echo "откат: mtg $(systemctl is-active mtg), строка tg вернулась в $S"; exit 0
fi
B=/root/fspirat-backups/mtg-off-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
cp $S $C "$B/"; [ -f $U ] && cp $U "$B/"
echo "копии: $B"
D=$(. $C; echo "${MTG_DOMAIN:-}")
# 1. 443: убрать строку прокси из карты SNI
if [ -n "$D" ] && grep -qE "^\s*$(echo "$D" | sed 's/\./\\./g')\s+127\.0\.0\.1:10444;" $S; then
  sed -i -E "/^\s*$(echo "$D" | sed 's/\./\\./g')\s+127\.0\.0\.1:10444;/d" $S
fi
sed -i 's/^#   tg\.[^ ]* → MTProto-прокси mtg (127\.0\.0\.1:10444), /#   /' $S
if ! nginx -t -q 2>/tmp/ngt; then cat /tmp/ngt; cp "$B/sni-443.conf" $S; echo "❌ nginx -t — карта возвращена, ничего не выключено"; exit 1; fi
systemctl reload nginx; echo "443: строки $D больше нет"
# 2. служба mtg
if [ -f $U ]; then systemctl disable -q --now mtg || true; rm -f $U; systemctl daemon-reload; fi
echo "mtg: $(systemctl is-active mtg 2>/dev/null || true), автозапуск: $(systemctl is-enabled mtg 2>/dev/null || echo нет)"
# 3. deploy.conf
sed -i 's/^MTG_DOMAIN=.*/MTG_DOMAIN=                # Telegram-прокси выключен 12.10.2026 (server\/mtproxy\/remove.sh)/' $C
rm -f /var/lib/fspirat/mtg.json
echo "deploy.conf: $(grep '^MTG_DOMAIN' $C)"
echo "проверка: 443 слушает — $(ss -ltn 'sport = :443' | grep -c LISTEN), 10444 — $(ss -ltn 'sport = :10444' | grep -c LISTEN) (должно быть 0)"
for u in https://fspirat.online/ https://fspirat.xyz/ https://fspirat.online/router/login https://router.fspirat.online/; do
  echo "  $u $(curl -s -o /dev/null -m 10 -w '%{http_code}' $u)"; done
echo "откат: bash remove.sh --rollback $B"

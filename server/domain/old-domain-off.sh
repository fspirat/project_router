#!/bin/bash
# Выключить старый домен (fspirat.online) после переезда на новый (fspirat.xyz) — 12.10.2026 по решению владельца.
# NL: панель (/router/ на старом сайте → 404, router.OLD выключен), VPN nl.OLD (из Reality serverNames и карты SNI),
#     обложки router./nl./tg.OLD выключены; deploy.conf: PANEL_DOMAIN=NEW, LUCI_DOMAIN=router.NEW, без PANEL_ALIASES.
# DE: VPN de.OLD (из serverNames) и его обложка.
# Сертификаты старых имён не удаляются — их renewal-конфиги уходят в копии (certbot больше не продлевает).
# Сам сайт OLD (главная страница) — не трогается: это сессия homeserver.
# Запуск (root, из файла): bash old-domain-off.sh OLD NEW          Откат: bash old-domain-off.sh --rollback <папка копий>
set -euo pipefail
X=/usr/local/etc/xray/config.json; S=/etc/nginx/stream.d/sni-443.conf; A=/etc/nginx/sites-available; E=/etc/nginx/sites-enabled
C=/etc/fspirat-router/deploy.conf; L=/etc/letsencrypt/renewal
if [ "${1:-}" = --rollback ]; then
  B=$2
  [ -f "$B/config.json" ] && cp "$B/config.json" $X
  [ -f "$B/sni-443.conf" ] && cp "$B/sni-443.conf" $S
  [ -f "$B/deploy.conf" ] && cp "$B/deploy.conf" $C
  for f in "$B"/site.*; do [ -e "$f" ] || continue; n=${f##*/site.}; cp "$f" $A/$n; done
  for f in "$B"/enabled.*; do [ -e "$f" ] || continue; n=${f##*/enabled.}; ln -sf $A/$n $E/$n; done
  for f in "$B"/renewal.*; do [ -e "$f" ] || continue; cp "$f" $L/${f##*/renewal.}; done
  nginx -t -q && systemctl reload nginx; systemctl restart xray; echo "откат из $B: готово (Deploy server — чтобы вернуть бота на старый домен)"; exit 0
fi
OLD=$1; NEW=$2
for d in "$OLD" "$NEW"; do [[ $d =~ ^[a-z0-9.-]+$ ]] || { echo "неверный домен $d"; exit 1; }; done
if [ -f $S ]; then LAY=nl; else LAY=de; fi
B=/root/fspirat-backups/old-domain-off-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"; echo "копии: $B (схема $LAY)"
cp $X "$B/config.json"; [ -f $S ] && cp $S "$B/"; [ -f $C ] && cp $C "$B/"
restore() { echo "❌ $1 — возвращаю как было"; bash "$0" --rollback "$B" || true; exit 1; }

# сайты старых имён: выключить (копия + запоминаем, что был включён)
off_site() { # имя_файла
  [ -f $A/$1 ] && cp $A/$1 "$B/site.$1"
  if [ -e $E/$1 ]; then touch "$B/enabled.$1"; rm -f $E/$1; echo "сайт $1: выключен"; fi
}
if [ $LAY = nl ]; then
  VPN=nl.$OLD
  for s in router.$OLD nl.$OLD tg.$OLD; do off_site $s; done
  # /router/ на старом сайте → 404
  cp $A/$OLD "$B/site.$OLD"
  python3 - $A/$OLD <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'include snippets/fspirat-router.conf;'
if old in s:
    s = s.replace(old, 'location ^~ /router/ { return 404; }   # панель переехала на новый домен (server/domain/old-domain-off.sh)', 1)
    open(p, 'w').write(s); print(f'{p}: /router/ → 404')
else:
    print(f'{p}: сниппета панели нет — не трогаю')
PY
  # deploy.conf: основной домен — новый
  sed -i "s/^PANEL_DOMAIN=.*/PANEL_DOMAIN=$NEW/; s/^LUCI_DOMAIN=.*/LUCI_DOMAIN=router.$NEW/; /^PANEL_ALIASES=/d" $C
  echo "deploy.conf: $(grep -E '^(PANEL_DOMAIN|LUCI_DOMAIN)=' $C | tr '\n' ' ')"
  # 443: убрать строку старого имени VPN
  sed -i -E "/^\s*${VPN//./\\.}\s+127\.0\.0\.1:[0-9]+;/d" $S
  CERTS="router.$OLD nl.$OLD tg.$OLD"
else
  VPN=de.$OLD
  off_site de
  CERTS="de.$OLD"
fi
# Reality: убрать старое имя (новое уже есть — проверяем, чтобы не остаться без имён)
jq -e --arg o "$VPN" --arg n "${VPN%%.*}.$NEW" 'any(.inbounds[]; (.streamSettings.realitySettings.serverNames // []) | (index($o) != null and index($n) != null))' $X >/dev/null \
  || restore "в xray нет пары $VPN + новое имя — старое не убираю"
XN=${X%.json}.new.json
( umask 077; jq --arg o "$VPN" '(.inbounds[].streamSettings.realitySettings.serverNames | select(. != null)) |= map(select(. != $o))' $X > $XN )
/usr/local/bin/xray run -test -config $XN >/tmp/xt 2>&1 || { rm -f $XN; grep -iE "fail|error" /tmp/xt | tail -2 | cut -c1-200; restore "xray -test"; }
cat $XN > $X; rm -f $XN
nginx -t -q 2>/tmp/ngt || { cat /tmp/ngt; restore "nginx -t"; }
systemctl reload nginx; systemctl restart xray; sleep 2
systemctl is-active --quiet xray || restore "xray не запустился"
echo "xray: $(systemctl is-active xray), имена: $(jq -c '[.inbounds[].streamSettings.realitySettings.serverNames // empty] | add' $X)"
for c in $CERTS; do [ -f $L/$c.conf ] && { cp $L/$c.conf "$B/renewal.$c.conf"; rm -f $L/$c.conf; echo "certbot: $c больше не продлевается"; }; done
echo "откат: bash old-domain-off.sh --rollback $B"

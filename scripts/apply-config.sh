#!/bin/sh
# Подставить свои значения в копии файлов перед выкладкой: [DEPLOY_LOCAL=файл] apply-config.sh ФАЙЛ|ПАПКА …
# Значения: deploy.conf из репозитория, поверх — DEPLOY_LOCAL (копия /etc/fspirat-router/deploy.conf с сервера).
# В исходниках стоят нейтральные example.org, luci.example.org, YourRouterBot — здесь они меняются на свои.
set -e
cd "$(dirname "$0")/.."
. ./deploy.conf
[ -n "$DEPLOY_LOCAL" ] && [ -s "$DEPLOY_LOCAL" ] && . "$DEPLOY_LOCAL"
ok() { printf '%s' "$2" | grep -qE "$1" || { echo "deploy.conf: неверное значение «$2»" >&2; exit 1; }; }
D='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
ok "$D" "$PANEL_DOMAIN"; ok "$D" "$LUCI_DOMAIN"; ok '^[A-Za-z0-9_]{3,40}$' "$TG_BOT"
e() { printf '%s' "$1" | sed 's/[.]/\\./g'; }
files=$(for p in "$@"; do if [ -d "$p" ]; then find "$p" -type f \( -name '*.html' -o -name '*.js' -o -name '*.php' -o -name '*.py' -o -name '*.json' -o -name '*.conf' -o -name 'fspirat-*' \); else echo "$p"; fi; done)
[ -n "$files" ] || exit 0
# сначала поддомен (в нём есть example.org), потом сам домен
echo "$files" | while read -r f; do
  sed -i -e "s/luci\.example\.org/@@LUCI@@/g; s/example\.org/@@PANEL@@/g; s/YourRouterBot/@@BOT@@/g" \
    -e "s/@@LUCI@@/$(e "$LUCI_DOMAIN")/g; s/@@PANEL@@/$(e "$PANEL_DOMAIN")/g; s/@@BOT@@/$TG_BOT/g" "$f"
done
echo "настройки: $PANEL_DOMAIN, $LUCI_DOMAIN, @$TG_BOT"

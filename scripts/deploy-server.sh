#!/usr/bin/env bash
# Выкладка серверных файлов на NL-сервер. Секреты (токены) этот скрипт НЕ трогает.
# Запуск: bash scripts/deploy-server.sh
set -euo pipefail
S="${SERVER:-root@193.39.143.202}"
cd "$(dirname "$0")/.."

bash -n server/bin/fspirat-watch
tr -d '\r' < server/bin/fspirat-watch | ssh "$S" "cat > /usr/local/bin/fspirat-watch && chmod 755 /usr/local/bin/fspirat-watch"
tr -d '\r' < server/cron.d/fspirat-watch | ssh "$S" "cat > /etc/cron.d/fspirat-watch"
tr -d '\r' < server/fail2ban/fspirat.local | ssh "$S" "cat > /etc/fail2ban/jail.d/fspirat.local && systemctl restart fail2ban"
echo "Готово: fspirat-watch, cron, fail2ban обновлены."

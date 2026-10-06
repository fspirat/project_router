#!/usr/bin/env bash
# Выкладка скриптов на роутер с компьютера (дома, в той же сети).
# Запуск: bash scripts/deploy-router.sh          (из корня репозитория)
# Без пароля, если ключ компьютера добавлен в /etc/dropbear/authorized_keys роутера.
set -euo pipefail
R="${ROUTER:-root@192.168.7.1}"
cd "$(dirname "$0")/.."

for f in router/bin/fspirat-ping router/www/cgi-bin/fspirat router/etc/init.d/fstunnel; do
  sh -n "$f"                                   # проверка синтаксиса до отправки
done

push() { # локальный_файл путь_на_роутере
  tr -d '\r' < "$1" | ssh "$R" "cat > '$2' && chmod 755 '$2'"
  echo "  -> $2"
}

echo "Выкладываю на $R"
push router/bin/fspirat-ping   /usr/bin/fspirat-ping
push router/www/cgi-bin/fspirat /www/cgi-bin/fspirat
push router/etc/init.d/fstunnel /etc/init.d/fstunnel

ssh "$R" "grep -q fspirat-ping /etc/crontabs/root || echo '*/5 * * * * /usr/bin/fspirat-ping' >> /etc/crontabs/root; /etc/init.d/cron restart"
echo "Готово. Туннель не перезапускаю: если менялся fstunnel, выполни на роутере /etc/init.d/fstunnel restart"

#!/bin/bash
# Вход на VDS только по ключу (запускается после проверки входа по ключу с сервера панели)
set -euo pipefail
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-fspirat.conf
sshd -t && systemctl reload ssh && echo "ssh: вход по паролю выключен, только ключ"
sshd -T | grep -E '^(passwordauthentication|permitrootlogin)'

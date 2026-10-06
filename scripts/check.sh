#!/usr/bin/env bash
# Быстрая проверка, что всё живо. Запуск: bash scripts/check.sh
R="${ROUTER:-root@192.168.7.1}"; S="${SERVER:-root@193.39.143.202}"
echo "== Роутер =="
ssh "$R" 'pidof xray >/dev/null && echo "xray: работает" || echo "xray: НЕ работает";
  /etc/init.d/fstunnel status;
  echo "global node: $(uci get passwall2.@global[0].node)  (должен быть 9DxG2j8l = Split)";
  echo "Split default: $(uci get passwall2.9DxG2j8l.default_node)";
  head -c 160 /tmp/fspirat/ping.json; echo'
echo "== Сервер =="
ssh "$S" 'curl -s -o /dev/null -w "туннель -> LuCI: %{http_code}\n" http://127.0.0.1:8081;
  fail2ban-client status | tail -n 1'

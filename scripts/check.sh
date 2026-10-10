#!/usr/bin/env bash
# Быстрая проверка, что всё живо. Запуск: bash scripts/check.sh
R="${ROUTER:-root@192.168.1.1}"; S="${SERVER:?укажи сервер: SERVER=root@адрес bash scripts/check.sh}"
echo "== Роутер =="
ssh "$R" 'pidof xray >/dev/null && echo "xray: работает" || echo "xray: НЕ работает";
  /etc/init.d/fstunnel status;
  echo "global node: $(uci get passwall2.@global[0].node)  (должен быть узел Split, protocol=_shunt: $(uci -q get passwall2.$(uci get passwall2.@global[0].node).protocol))";
  echo "Split default: $(uci get passwall2.$(uci get passwall2.@global[0].node).default_node)";
  head -c 160 /tmp/fspirat/ping.json; echo'
echo "== Сервер =="
ssh "$S" 'curl -s -o /dev/null -w "туннель -> LuCI: %{http_code}\n" http://127.0.0.1:8081;
  fail2ban-client status | tail -n 1'

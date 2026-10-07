#!/bin/bash
# Новый VDS (Германия, 64.188.83.100): ключ сервера панели, обновления, firewall, fail2ban, Xray VLESS + Reality на 443.
# Повторный запуск безопасен: ключи Xray создаются один раз (/usr/local/etc/xray/fspirat.env, только root). Секреты не печатает.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEhv9FFFN2NZHl6XD/VJFzcoSTntZTvMe9dVFLT9GTLL fspirat-ops-vds2'
SNI=dl.google.com   # www.microsoft.com с этого VDS по IPv6 не открывается — Reality не может завершить рукопожатие

install -d -m 700 /root/.ssh
grep -qF "$PUB" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUB" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "ключ сервера панели: добавлен"

apt-get update -qq
apt-get -y -qq -o Dpkg::Options::=--force-confold upgrade >/dev/null
apt-get -y -qq install curl ufw fail2ban unattended-upgrades jq openssl >/dev/null
echo "пакеты: обновлены, установлены ufw fail2ban unattended-upgrades"

[ -x /usr/local/bin/xray ] || bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
echo "xray: $(/usr/local/bin/xray version | head -1)"

E=/usr/local/etc/xray/fspirat.env
if [ ! -s $E ]; then
  K=$(/usr/local/bin/xray x25519)
  PRIV=$(echo "$K" | grep -i 'private' | awk '{print $NF}')
  PUBK=$(echo "$K" | grep -iE 'public|password' | head -1 | awk '{print $NF}')
  ( umask 077; printf 'UUID=%s\nPRIV=%s\nPUBK=%s\nSID=%s\nSNI=%s\n' "$(/usr/local/bin/xray uuid)" "$PRIV" "$PUBK" "$(openssl rand -hex 8)" "$SNI" > $E )
  echo "ключи xray: созданы"
fi
. $E
[ -n "$UUID" ] && [ -n "$PRIV" ] && [ -n "$PUBK" ] || { echo "ключи xray не получились"; exit 1; }
( umask 077; jq -n --arg id "$UUID" --arg pk "$PRIV" --arg sid "$SID" --arg sni "$SNI" '{
  log: {loglevel: "warning"},
  inbounds: [{listen: "0.0.0.0", port: 443, protocol: "vless",
    settings: {clients: [{id: $id, flow: "xtls-rprx-vision", email: "router"}], decryption: "none"},
    streamSettings: {network: "raw", security: "reality",
      realitySettings: {dest: ($sni + ":443"), serverNames: [$sni], privateKey: $pk, shortIds: [$sid]}},
    sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}}],
  outbounds: [{protocol: "freedom", tag: "direct", settings: {domainStrategy: "UseIPv4"}}, {protocol: "blackhole", tag: "block"}],
  routing: {rules: [{type: "field", ip: ["geoip:private"], outboundTag: "block"}, {type: "field", protocol: ["bittorrent"], outboundTag: "block"}]}
}' > /usr/local/etc/xray/config.json )
chown nobody:nogroup /usr/local/etc/xray/config.json 2>/dev/null || true; chmod 640 /usr/local/etc/xray/config.json; chgrp nogroup /usr/local/etc/xray/config.json 2>/dev/null || true
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null && echo "конфиг xray: проверен"
systemctl enable -q xray && systemctl restart xray && sleep 2 && systemctl is-active xray

ufw allow 22/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ufw --force enable >/dev/null; echo "firewall: открыты 22 и 443"
systemctl enable -q --now fail2ban; echo "fail2ban: $(systemctl is-active fail2ban)"
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades; echo "автообновления безопасности: включены"
ss -ltnp | grep -q ':443 ' && echo "порт 443: слушает xray"

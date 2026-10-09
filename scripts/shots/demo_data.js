// Демо-данные для скриншотов README: всё выдуманное. Адреса — из документационных диапазонов (RFC 5737),
// MAC — локально администрируемые 02:00:00:…, имена устройств и серверов — общие.
const now = Math.floor(Date.now() / 1000);
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;   // повторяемый «шум»
const T = ['YouTube', 'Discord', 'Telegram', 'Hypixel'], K = ['web', 'web', 'web', 'mc'];
const HOST = ['www.youtube.com', 'discord.com', 'web.telegram.org', 'mc.hypixel.net'];
const lst = v => ({ts: now - 540, list: v.map((x, i) => ({kind: K[i], name: T[i], host: HOST[i], vpn: x}))});
const SUB = [['demo0001', '🇫🇮 Финляндия', 52, [61, 66, 58, 104]], ['demo0002', '🇸🇪 Швеция', 57, [70, 72, 69, 112]],
  ['demo0003', '🇵🇱 Польша', 49, [58, 63, 60, 97]], ['demo0004', '🇱🇻 Латвия', 44, [55, 59, 52, 95]],
  ['demo0005', '🇫🇷 Франция', 63, [76, 81, 74, 88]], ['demo0006', '🇺🇸 США', 128, [140, 152, 147, 121]],
  ['demo0007', '🇹🇷 Турция', 0, [0, 0, 0, 0]]];
const nodes = [{id: 'fspiratDE', name: '🇩🇪 Германия', ms: 38, own: true}, {id: 'fspiratNL', name: '🇳🇱 Нидерланды', ms: 45, own: true},
  ...SUB.map(([id, name, ms]) => ({id, name, ms}))];
const svc = {direct: {...lst([0, 0, 0, 0]), base: 8}, fspiratDE: lst([42, 47, 44, 92]), fspiratNL: lst([49, 55, 51, 90])};
SUB.forEach(([id,,, v]) => svc[id] = lst(v));
const rh = []; for(let t = now - 86400; t <= now; t += 300) rh.push([t, (t % 14400 < 300) ? 0 : 150 + Math.round(18 * Math.sin(t / 9000) + 35 * rnd() * rnd())]);
const status = {running: true, split_active: true, current: 'fspiratDE', ping: {updated: now - 95, socks: true, real: 171, nodes}, log: [], history: rh,
  targets: {...lst([45, 49, 46, 94]), ts: now - 95}, target_list: T.map((n, i) => `${K[i]}|${n}|${K[i] === 'mc' ? HOST[i] + ':25565' : 'https://' + HOST[i] + '/'}`),
  svc, svc_running: false, svc_direct: ['Telegram'],
  sub: {ts: now - 3000, up: 3.1e9, down: 41.7e9, total: 0, expire: now + 23 * 86400 + 3600, title: 'Демо-подписка'},
  speed: {vpn: {via: 'vpn', ts: now - 1800, down: 268e6, up: 91e6, latency: 47, ip: '203.0.113.24', country: 'DE', server: 'Тестовый сервер', streams: 4},
          direct: {via: 'direct', ts: now - 1750, down: 402e6, up: 287e6, latency: 6, ip: '198.51.100.7', country: 'RU', server: 'Тестовый сервер', streams: 4}},
  devices: [
    {name: 'Компьютер', ip: '192.168.1.20', mac: '02:00:00:00:00:01', online: true, band: 'wired', up: 1, dn: 1},
    {name: 'iPhone', ip: '192.168.1.31', mac: '02:00:00:00:00:02', online: true, band: '5g', signal: -51, rate: 1201, up: 1, dn: 1},
    {name: 'MacBook', ip: '192.168.1.32', mac: '02:00:00:00:00:03', online: true, band: '5g', signal: -58, rate: 866, up: 1, dn: 1},
    {name: 'PlayStation', ip: '192.168.1.40', mac: '02:00:00:00:00:04', online: true, direct: true, band: 'wired', up: 1, dn: 1},
    {name: 'Телевизор', ip: '192.168.1.41', mac: '02:00:00:00:00:05', online: true, sched: '2300-0800', band: '5g', signal: -63, rate: 433, up: 1, dn: 1},
    {name: 'Умная колонка', ip: '192.168.1.50', mac: '02:00:00:00:00:06', online: true, band: '2g', signal: -60, rate: 72, up: 1, dn: 1},
    {name: 'Умная розетка', ip: '192.168.1.51', mac: '02:00:00:00:00:07', online: true, blocked: true, band: '2g', signal: -70, rate: 65, up: 0, dn: 0},
    {name: 'Ноутбук', ip: '192.168.1.33', mac: '02:00:00:00:00:08', online: false}],
  sys: {cpu: 9, cores: 2, load: '0.18 0.22 0.20', mem_total: 252000, mem_avail: 141000, disk_total: 92000, disk_used: 46000,
        tmp_total: 126000, tmp_used: 7400, temp: 54, uptime: 9 * 86400 + 5 * 3600, model: 'Xiaomi AX3000T', fw: 'OpenWrt 25.12.5',
        net: {dev: 'wan', rx: 38e6, tx: 4.2e6, rx_total: 1.9e11, tx_total: 2.6e10}}};
const SPEED = []; for(let i = 14; i >= 0; i--){ SPEED.push([now - i * 86400 - 1800, 'vpn', 250e6 + Math.round(30e6 * Math.sin(i)), 90e6, 48]); if(i % 2 === 0) SPEED.push([now - i * 86400 - 1750, 'direct', 395e6 + Math.round(15e6 * Math.cos(i)), 285e6, 6]); }
const MD = {domains: ['sberbank.ru', 'tbank.ru', 'gosuslugi.ru', 'nalog.gov.ru', 'ozon.ru', 'wildberries.ru', 'avito.ru', 'yandex.ru', 'vk.com', 'mail.ru', 'kinopoisk.ru', '2gis.ru'], added: ['example.ru', 'shop.example.ru']};
function data(range){
  const span = {day: 86400, week: 7 * 86400, month: 30 * 86400}[range], step = {day: 0, week: 1800, month: 7200}[range], st = step || 300, pts = [];
  for(let t = now - span; t <= now; t += st){ let v = 150 + Math.round(18 * Math.sin(t / (step ? 40000 : 9000)) + 35 * rnd() * rnd()); if(t % (step ? 86400 : 14400) < st) v = 0; pts.push(step ? [t, v, v === 0 ? 1 : 0, 0] : [t, v]); }
  const tp = {}; T.forEach((n, k) => { tp[n] = []; for(let t = now - span; t <= now; t += st) tp[n].push([t, [45, 49, 46, 94][k] + Math.round(4 * Math.sin(t / (step ? 30000 : 9000) + k) + 14 * rnd() * rnd())]); });
  return {now, range, step, points: pts, stats: {avg: 163, min: 121, max: 214, fails: range === 'day' ? 6 : 31, offline_min: 0}, tpoints: tp,
    events: [[now - 900, 'manual', 'Сервер выбран вручную: 🇩🇪 Германия'], [now - 3 * 3600, 'auto', 'Автопереключение: 🇹🇷 Турция -> 🇩🇪 Германия 38ms'],
      [now - 8 * 3600, 'update', 'Обновление подписки'], [now - 26 * 3600, 'online', 'Роутер снова на связи (не было 4 мин)'], [now - 26 * 3600 - 240, 'offline', 'Роутер пропал со связи']],
    offline_since: null, last_ok: now - 40, mtg: {active: true, conns: 2, since: now - 5 * 86400, ts: now - 30},
    names: {}, speed: SPEED, traffic: {'02:00:00:00:00:01': {d: [0.4e9, 7.8e9], m: [9e9, 164e9]}, '02:00:00:00:00:02': {d: [0.1e9, 1.9e9], m: [2.2e9, 41e9]}, '02:00:00:00:00:04': {d: [0.05e9, 12.4e9], m: [1.1e9, 96e9]}}};
}
// «YouTube и Discord через zapret» (CGI zapret): ZAP_STATE=ok|fallback|off
const ZAP = {
  ok: {installed: true, enabled: true, strategy: 3, engine: true, nft: true, route_cfg: true, route_live: true, fallback: false, error: '',
       pkts_tcp: 1842, pkts_udp: 637, vpn_excluded: 1, version: 'v72.13', busy: false, checking: false,
       check: {ts: now - 120, via: 'isp', list: [{name: 'YouTube', ok: true, code: '204', ms: 182, queued: 6}, {name: 'YouTube видео', ok: true, code: '200', ms: 241, queued: 6},
                                              {name: 'Discord API', ok: true, code: '200', ms: 214, queued: 5}, {name: 'Discord CDN', ok: true, code: '404', ms: 196, queued: 5}]}},
  fallback: {installed: true, enabled: true, strategy: 2, engine: false, nft: false, route_cfg: false, route_live: false, fallback: true,
       error: 'nfqws не запускается — YouTube и Discord временно идут через VPN', pkts_tcp: 0, pkts_udp: 0, vpn_excluded: 0, version: 'v72.13', busy: false, checking: false, check: null},
  off: {installed: true, enabled: false, strategy: 1, engine: false, nft: false, route_cfg: false, route_live: false, fallback: false, error: '',
       pkts_tcp: 0, pkts_udp: 0, vpn_excluded: 0, version: 'v72.13', busy: false, checking: false, check: null},
};
const TGWS = {installed: true, enabled: true, running: true, listening: true, host: '192.168.1.1', port: 1443, version: '1.11.1'};
module.exports = {status, data, now, MD, ZAP, TGWS};

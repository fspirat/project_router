/* FSPIRAT Router — логика страницы (подключает index.html; CSP: script-src 'self') */
const API = '/router/api';
// Свой заголовок в каждом запросе: nginx без него отвечает 403. Чужой сайт или ссылка его подставить не могут,
// поэтому «?action=reboot» по ссылке из другого места не сработает (защита от CSRF).
const H = {'X-FSR': '1'};
let state = null, hist = null, names = {}, range = 'day', toastTimer, quietUntil = 0, editing = null;
const $ = s => document.querySelector(s);
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

/* ---------- помощники ---------- */
function level(ms){ if(!ms) return 0; if(ms<60) return 5; if(ms<100) return 4; if(ms<160) return 3; if(ms<250) return 2; return 1; }
function bars(ms){
  const l = level(ms);
  if(!l) return '<svg class="bars off" viewBox="0 0 20 16" aria-hidden="true"><path d="M4 3 16 13M16 3 4 13"/></svg>';
  let r = '';
  for(let i=0;i<5;i++){ const h = 4+i*3; r += `<rect x="${i*4}" y="${16-h}" width="3" height="${h}" class="${i<l?'on':''}"/>`; }
  return `<svg class="bars" viewBox="0 0 20 16" aria-hidden="true">${r}</svg>`;
}
const pingHtml = ms => bars(ms) + (ms ? `<b>${ms}</b> ms` : 'нет ответа');
const mb = kb => kb >= 1048576 ? (kb/1048576).toFixed(1)+' ГБ' : kb < 10240 ? (kb/1024).toFixed(1)+' МБ' : Math.round(kb/1024)+' МБ';
const bytes = b => mb(b/1024);
function speed(bps){
  if(bps >= 1e6) return (bps/1e6).toFixed(bps >= 1e8 ? 0 : 1) + ' Мбит/с';
  return Math.round(bps/1e3) + ' кбит/с';
}
function ago(ts){
  const s = Math.max(0, Math.round(Date.now()/1000 - ts));
  if(s < 60) return 'только что';
  if(s < 3600) return Math.round(s/60) + ' мин назад';
  return Math.round(s/3600) + ' ч назад';
}
function upt(s){
  const d = Math.floor(s/86400), h = Math.floor(s%86400/3600), m = Math.floor(s%3600/60);
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
}
function toast(msg, err){
  let t = $('.toast');
  if(!t){ t = document.createElement('div'); t.className = 'toast'; t.setAttribute('role','status'); document.body.append(t); }
  t.textContent = msg; t.classList.toggle('err', !!err); t.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.hidden = true, err ? 9000 : 6000);
}

async function api(action, extra=''){
  let r;
  try { r = await fetch(`${API}?action=${action}${extra}`, {cache:'no-store', headers: H}); }
  catch { throw new Error('Нет связи с сайтом. Проверь интернет.'); }
  if(r.status === 401){ location.href = '/router/login?next=' + encodeURIComponent(location.pathname); throw new Error('Вход истёк — открываю страницу входа.'); }
  if(r.status === 502 || r.status === 504){ const e = new Error('Роутер не на связи: туннель до сервера не поднят.'); e.down = true; throw e; }
  if(r.status === 409) throw new Error('Тест скорости уже идёт, дождись результата.');
  if(r.status === 403){
    let m = ''; try { m = (await r.clone().json()).error || ''; } catch {}
    throw new Error(m === 'csrf' ? 'Запрос отклонён: обнови страницу (Ctrl+F5).' : 'Роутер отклонил запрос: токен в nginx не совпадает с /etc/fspirat.token.');
  }
  if(!r.ok){ let m = ''; try { m = (await r.json()).error || ''; } catch {} throw new Error(`Ошибка ${r.status} при запросе к роутеру. ${m}`); }
  return r.json();
}

/* ---------- блоки ---------- */
function renderStatus(s){
  const nodes = (s.ping && s.ping.nodes) || [];
  const cur = nodes.find(n => n.id === s.current);
  $('#vpn').className = 'status vpn ' + (s.running ? 'up' : 'down');
  $('#vpn-text').textContent = s.running ? 'VPN работает' : 'VPN остановлен';
  $('#cur-name').textContent = cur ? cur.name : (s.current || '—');
  $('#cur-ping').innerHTML = cur ? pingHtml(cur.ms) : '';
  const real = $('#real');
  if(!s.ping || !s.ping.socks){ real.className = ''; real.textContent = 'Проверка через VPN не настроена: нужен SOCKS на порту 1080.'; }
  else if(s.ping.real > 0){ real.className = ''; real.innerHTML = `Задержка через VPN: <b>${s.ping.real}</b> ms`; }
  else { real.className = 'bad'; real.innerHTML = 'Задержка через VPN: <b>не проходит</b>'; }
  real.title = 'Как пинг: ответ сайта gstatic.com через VPN по уже открытому соединению. Раз в 5 минут.';
  $('#updated').textContent = s.ping ? 'Проверено ' + ago(s.ping.updated) + ', автопроверка раз в 5 минут' : 'Проверок ещё не было.';
  $('#warn').hidden = s.split_active;
  renderTargets(s.targets);
  $('#cur-svc').innerHTML = cur && cur.ms ? svcLine(cur) : '';      // YouTube · Discord · серверы Minecraft через текущий
}

const RANGES = {day: [86400, '24 часа', '24 ч назад'], week: [7*86400, '7 дней', '7 дней назад'], month: [30*86400, '30 дней', '30 дней назад']};
const minutes = m => m < 60 ? m + ' мин' : m < 1440 ? Math.floor(m/60) + ' ч ' + (m%60 ? m%60 + ' мин' : '') : Math.floor(m/1440) + ' д ' + Math.floor(m%1440/60) + ' ч';

/* Точки: [время, отклик] (0 — сбой VPN, -1 — роутер не на связи). Берём с сервера; если его нет — из роутера (24 ч). */
/* Задержка до сервисов через текущий сервер: легенда с последним замером + график за выбранный период
   (история — с сервера, targets.tsv; если её нет — только последние цифры). Список правится кнопкой «✎ Список». */
const TCOL = ['#9be052', '#e3b542', '#5ec8e0', '#e07ad0', '#f09a4a', '#d9e7cd', '#8f9cff', '#e0563c'];
function tColor(name){
  const names = ((state && state.targets && state.targets.list) || []).map(x => x.name);
  Object.keys((hist && hist.tpoints) || {}).forEach(n => names.includes(n) || names.push(n));
  return TCOL[Math.max(0, names.indexOf(name)) % TCOL.length];
}
function renderTargets(t){
  t = t || (state && state.targets);
  const list = (t && t.list) || [];
  $('#tg-list').innerHTML = list.map(x => `<li title="${esc(x.host)}"><i style="background:${tColor(x.name)}"></i>${svcIcon(x)}${esc(x.name)} ${x.vpn ? `<b>${x.vpn}</b> ms` : '<b style="color:var(--red)">нет ответа</b>'}</li>`).join('')
    || '<li>Замеров ещё не было.</li>';
  if(t && t.ts) $('#tg-refresh').title = 'Перемерить (последний замер ' + ago(t.ts) + ')';
  renderTChart();
}
function renderTChart(){
  const [span, title, fromTxt] = RANGES[range];
  $('#tchart-title').textContent = 'Сервисы через VPN за ' + title;
  $('#tchart-from').textContent = fromTxt;
  const svg = $('#tchart'), W = 600, H = 150, now = Date.now()/1000, from = now - span;
  const tp = hist && hist.range === range && hist.tpoints ? hist.tpoints : {};
  const all = Object.values(tp).flat().filter(p => p[0] >= from && p[1] > 0).map(p => p[1]);
  const max = Math.max(150, ...all) * 1.15;
  const x = t => ((t - from) / span) * W, y = v => H - (v / max) * (H - 8);
  let g = '';
  for(let i=1;i<4;i++) g += `<line class="grid" x1="0" x2="${W}" y1="${H*i/4}" y2="${H*i/4}"/>`;
  const cols = range === 'week' ? 7 : 6;
  for(let i=1;i<cols;i++) g += `<line class="grid" y1="0" y2="${H}" x1="${W*i/cols}" x2="${W*i/cols}"/>`;
  const gap = (hist && hist.step ? hist.step : 300) * 2.5;      // дыра в данных — линия рвётся
  let lines = '';
  for(const [name, pts] of Object.entries(tp)){
    let seg = [], prev = 0;
    const flush = () => { if(seg.length > 1) lines += `<polyline class="tl" stroke="${tColor(name)}" points="${seg.join(' ')}"/>`; seg = []; };
    pts.filter(p => p[0] >= from).forEach(p => {
      if(p[1] <= 0 || (prev && p[0] - prev > gap)) flush();
      if(p[1] > 0) seg.push(`${x(p[0]).toFixed(1)},${y(p[1]).toFixed(1)}`);
      prev = p[0];
    });
    flush();
  }
  svg.innerHTML = g + lines;
  $('#tchart-max').textContent = all.length ? `шкала до ${Math.round(max)} ms` : 'истории пока нет — она копится на сервере';
}

/* Свой список сервисов */
const hostOf = a => String(a).replace(/^[a-z]+:\/\//i, '').replace(/[/:].*$/, '');
function tgRow(k = 'web', name = '', addr = ''){
  return `<div class="tg-row"><span class="ico">${svcIcon({kind: k, name, host: hostOf(addr)})}</span><select aria-label="Вид"><option value="web"${k === 'web' ? ' selected' : ''}>Сайт</option><option value="mc"${k === 'mc' ? ' selected' : ''}>Minecraft</option></select>
    <input class="nm" maxlength="20" placeholder="Имя" value="${esc(name)}" aria-label="Имя">
    <input class="addr" maxlength="200" placeholder="${k === 'mc' ? 'mc.server.net:25565' : 'https://…'}" value="${esc(addr)}" aria-label="Адрес">
    <button type="button" class="ed" data-del title="Убрать" aria-label="Убрать">✕</button></div>`;
}
$('#tg-edit').addEventListener('click', () => {
  const f = $('#tg-form');
  if(!f.hidden){ f.hidden = true; return; }
  const list = ((state && state.target_list) || []).map(l => l.split('|'));
  $('#tg-rows').innerHTML = list.map(([k, n, a]) => tgRow(k, n, k === 'mc' ? a.replace(/:25565$/, '') : a)).join('') || tgRow();
  f.hidden = false;
});
$('#tg-add').addEventListener('click', () => { if($('#tg-rows').children.length < 8) $('#tg-rows').insertAdjacentHTML('beforeend', tgRow()); });
$('#tg-cancel').addEventListener('click', () => $('#tg-form').hidden = true);
$('#tg-rows').addEventListener('click', e => { if(e.target.closest('[data-del]')) e.target.closest('.tg-row').remove(); });
$('#tg-rows').addEventListener('change', e => {
  if(e.target.tagName === 'SELECT') e.target.closest('.tg-row').querySelector('.addr').placeholder = e.target.value === 'mc' ? 'mc.server.net:25565' : 'https://…';
});
$('#tg-rows').addEventListener('input', e => {        // значок меняется вместе с видом, именем и адресом
  const r = e.target.closest('.tg-row'); if(!r) return;
  r.querySelector('.ico').innerHTML = svcIcon({kind: r.querySelector('select').value, name: r.querySelector('.nm').value, host: hostOf(r.querySelector('.addr').value)});
});
$('#tg-form').addEventListener('submit', async e => {
  e.preventDefault();
  const rows = [...$('#tg-rows').children].map(r => [r.querySelector('select').value, r.querySelector('.nm').value.trim(), r.querySelector('.addr').value.trim()])
    .filter(r => r[1] || r[2]);
  for(const [k, n, a] of rows){
    if(!n || !a) return toast('У каждой строки нужны имя и адрес.', true);
    if(/[|~!"<>&\\]/.test(n)) return toast(`Имя «${n}»: без символов | ~ ! " < > & \\`, true);
    if(k === 'web' && !/^https?:\/\/[\w.-]+[\w\-./?=]*$/.test(a)) return toast(`«${n}»: нужна ссылка вида https://сайт/путь`, true);
    if(k === 'mc' && !/^[\w.-]+(:\d{1,5})?$/.test(a)) return toast(`«${n}»: нужен адрес сервера, например mc.server.net или mc.server.net:25565`, true);
  }
  const b = e.submitter; b.disabled = true;
  try {
    await api('settargets', '&list=' + encodeURIComponent(rows.map(r => r.join('~')).join('!')));
    state.target_list = rows.map(([k, n, a]) => [k, n, k === 'mc' && !a.includes(':') ? a + ':25565' : a].join('|'));
    $('#tg-form').hidden = true;
    toast('Список сохранён. Роутер перемеряет через пару минут.');
    setTimeout(load, 20000);
  } catch(err){
    const m = {name: 'недопустимое имя', url: 'неверная ссылка', host: 'неверный адрес сервера', many: 'не больше 8 строк'}[(err.message.match(/(name|url|host|many)\s*$/) || [])[1]];
    toast(m ? 'Роутер не принял список: ' + m : err.message, true);
  }
  finally { b.disabled = false; }
});
$('#tg-refresh').addEventListener('click', async e => {
  const b = e.currentTarget; b.disabled = true;
  try { const t = await api('targets'); if(state) state.targets = t; renderTargets(t); renderServers(state); toast('Задержка до сервисов обновлена.'); }
  catch(err){ toast(err.message, true); }
  finally { b.disabled = false; }
});

function renderChart(){
  const [span, title, fromTxt] = RANGES[range];
  $('#chart-title').textContent = 'Связь за ' + title;
  $('#chart-from').textContent = fromTxt;
  const svg = $('#chart'), W = 600, H = 150, now = Date.now()/1000, from = now - span;
  const src = hist && hist.range === range ? hist.points : (range === 'day' && state ? state.history || [] : []);
  const pts = src.filter(p => p[0] >= from);
  const ok = pts.filter(p => p[1] > 0).map(p => p[1]);
  const max = Math.max(200, ...ok) * 1.15;
  const x = t => ((t - from) / span) * W, y = v => H - (v / max) * (H - 8);
  const slot = hist && hist.step ? hist.step / span * W : 300 / span * W;   // ширина одной точки
  let g = '';
  for(let i=1;i<4;i++) g += `<line class="grid" x1="0" x2="${W}" y1="${H*i/4}" y2="${H*i/4}"/>`;
  const cols = range === 'week' ? 7 : 6;
  for(let i=1;i<cols;i++) g += `<line class="grid" y1="0" y2="${H}" x1="${W*i/cols}" x2="${W*i/cols}"/>`;
  // линии рвутся на сбоях и на «нет связи»
  let seg = [], lines = '', areas = '', fails = '', off = '';
  const flush = () => {
    if(seg.length > 1){
      const d = seg.map(p => `${x(p[0]).toFixed(1)},${y(p[1]).toFixed(1)}`).join(' ');
      lines += `<polyline class="line" points="${d}"/>`;
      areas += `<polygon class="area" points="${x(seg[0][0]).toFixed(1)},${H} ${d} ${x(seg[seg.length-1][0]).toFixed(1)},${H}"/>`;
    } else if(seg.length === 1){
      lines += `<rect x="${x(seg[0][0])-1}" y="${y(seg[0][1])-1}" width="3" height="3" fill="var(--lime)"/>`;
    }
    seg = [];
  };
  pts.forEach(p => {
    if(p[1] > 0){ seg.push(p); if(p[2]) fails += `<rect class="fail" x="${x(p[0])-1.5}" y="${H-8}" width="3" height="8"/>`; return; }
    flush();
    if(p[1] < 0) off += `<rect class="offline" x="${(x(p[0]) - Math.max(slot, 2)/2).toFixed(1)}" y="0" width="${Math.max(slot, 2).toFixed(1)}" height="${H}"/>`;
    else fails += `<rect class="fail" x="${x(p[0])-1.5}" y="${H-14}" width="3" height="14"/>`;
  });
  flush();
  svg.innerHTML = g + off + areas + lines + fails;
  $('#chart-max').textContent = pts.length ? `шкала до ${Math.round(max)} ms` : 'данных за этот период пока нет';
  const st = hist && hist.range === range ? hist.stats : {
    avg: ok.length ? Math.round(ok.reduce((a,b) => a+b, 0) / ok.length) : null,
    min: ok.length ? Math.min(...ok) : null, max: ok.length ? Math.max(...ok) : null,
    fails: pts.filter(p => p[1] === 0).length, offline_min: null};
  $('#st-avg').textContent = st.avg ? st.avg + ' ms' : '—';
  $('#st-min').textContent = st.min ? st.min + ' ms' : '—';
  $('#st-max').textContent = st.max ? st.max + ' ms' : '—';
  $('#st-fail').textContent = st.fails;
  $('#st-off').textContent = st.offline_min == null ? '—' : st.offline_min ? minutes(st.offline_min) : 'ни разу';
}

function renderNet(n){
  if(!n) return;
  $('#sp-rx').textContent = speed(n.rx);
  $('#sp-tx').textContent = speed(n.tx);
  $('#tot-rx').textContent = 'С момента включения: ' + bytes(n.rx_total);
  $('#tot-tx').textContent = 'С момента включения: ' + bytes(n.tx_total);
}

function setMeter(key, pct, sub){
  pct = Math.min(100, Math.max(0, pct || 0));
  $('#x-'+key).style.width = pct + '%';
  $('#x-'+key).parentElement.className = 'xp' + (pct >= 85 ? ' crit' : pct >= 65 ? ' warn' : '');
  $('#m-'+key).textContent = pct + '%';
  $('#s-'+key).textContent = sub;
}
function renderSys(y){
  if(!y) return;
  $('#sys-model').textContent = y.model || 'Роутер';
  $('#sys-fw').textContent = y.fw || '';
  setMeter('cpu', y.cpu, `Средняя нагрузка ${y.load}, ядер: ${y.cores}`);
  const used = y.mem_total - y.mem_avail;
  setMeter('ram', Math.round(used / y.mem_total * 100), `${mb(used)} из ${mb(y.mem_total)}`);
  setMeter('disk', y.disk_total ? Math.round(y.disk_used / y.disk_total * 100) : 0, `${mb(y.disk_used)} из ${mb(y.disk_total)}: пакеты и настройки`);
  setMeter('tmp', y.tmp_total ? Math.round(y.tmp_used / y.tmp_total * 100) : 0, `${mb(y.tmp_used)} из ${mb(y.tmp_total)}: логи, кэш, данные в RAM`);
  $('#f-temp').textContent = y.temp != null ? y.temp + '°C' : 'нет датчика';
  $('#f-up').textContent = upt(y.uptime);
  renderNet(y.net);
}

const isPc = d => !!(state && state.pc && state.pc.mac === (d.mac || '').toLowerCase());
const BANDS = {'5g': ['g5', '5 ГГц'], '2g': ['g2', '2,4 ГГц'], wired: ['', 'кабель']};
function renderDevices(list){
  if(editing) return;                      // не мешать, пока пользователь вводит имя
  const nm = d => names[(d.mac || '').toLowerCase()] || d.name || '';
  list = (list || []).slice().sort((a,b) => (b.online - a.online) || (nm(a) || 'я').localeCompare(nm(b) || 'я'));
  const row = (d, tag) => {
    const own = names[(d.mac || '').toLowerCase()];
    const band = BANDS[d.band];
    const info = [d.signal ? d.signal + ' dBm' : '', d.rate ? d.rate + ' Мбит/с' : ''].filter(Boolean).join(' · ');
    const t = hist && hist.traffic && hist.traffic[(d.mac || '').toLowerCase()];
    const traf = t && (t.m[0] + t.m[1]) > 0 ? `сегодня ↓${bytes(t.d[1])} ↑${bytes(t.d[0])} · месяц ↓${bytes(t.m[1])} ↑${bytes(t.m[0])}` : '';
    return `<li class="dev${d.blocked ? ' is-blocked' : ''}">
      <span class="dot${d.online ? ' on' : ''}" title="${d.online ? 'в сети' : 'не в сети'}"></span>
      <span class="dev-name" data-mac="${esc(d.mac)}">
        <span>${esc(nm(d) || 'Без имени')}</span>
        ${tag && band ? `<span class="band ${band[0]}">${band[1]}</span>` : ''}
        <button class="ed" data-edit="${esc(d.mac)}" title="Переименовать" aria-label="Переименовать">✎</button>
        ${own && d.name ? `<small>в сети называется ${esc(d.name)}</small>` : ''}
        ${d.blocked ? '<span class="band cut">без интернета</span>' : ''}
        ${isPc(d) && d.online ? `<button class="blk wk" data-sleep="${esc(d.mac)}" title="${state.pc.agent ? 'Отправить компьютер в сон' : 'Скрипт на ПК не отвечает — см. блок «Компьютер» выше'}">☾ Усыпить</button>` : ''}
        ${!d.online || isPc(d) ? `<button class="blk wk" data-wake="${esc(d.mac)}" title="Wake-on-LAN: разбудить компьютер из сна">⏻ Разбудить</button>` : ''}
        <button class="blk" data-block="${esc(d.mac)}" title="${d.blocked ? 'Вернуть интернет' : 'Выключить интернет этому устройству'}">${d.blocked ? 'Включить интернет' : 'Выкл. интернет'}</button>
        ${info ? `<small class="band-info">${esc(info)}</small>` : ''}
        ${traf ? `<small class="dev-traf">${traf}</small>` : ''}
      </span>
      <span class="dev-ip">${esc(d.ip)}<small>${esc(d.mac)}</small></span>
    </li>`;
  };
  const g5 = list.filter(d => d.online && (d.band === '5g' || d.band === '6g'));
  const g2 = list.filter(d => d.online && d.band === '2g');
  const wired = list.filter(d => d.online && d.band === 'wired');
  const other = list.filter(d => d.online && !['5g', '6g', '2g', 'wired'].includes(d.band));
  const off = list.filter(d => !d.online);
  const col = (cls, title, arr) => `<div class="bcol ${cls}"><h3>${title}<small>${arr.length}</small></h3>
      ${arr.length ? `<ul class="list">${arr.map(d => row(d, false)).join('')}</ul>` : '<p class="empty">Никого</p>'}</div>`;
  let html = `<div class="bands">${col('g5', 'Wi-Fi 5 ГГц', g5)}${col('g2', 'Wi-Fi 2,4 ГГц', g2)}</div>`;
  if(wired.length || other.length)
    html += `<div class="bwide"><h3>По кабелю${other.length ? ' и прочие' : ''}<small>${wired.length + other.length}</small></h3>
      <ul class="list">${wired.concat(other).map(d => row(d, d.band !== 'wired')).join('')}</ul></div>`;
  if(off.length)
    html += `<details><summary>Не в сети: ${off.length}</summary><ul class="list">${off.map(d => row(d, true)).join('')}</ul></details>`;
  $('#devices').innerHTML = list.length ? html : '<p class="empty">Нет устройств с выданным адресом.</p>';
}

/* Под сервером — тонкая строка задержки до сервисов через него (fspirat-svcping, раз в 30 мин). */
/* Значки сервисов (по адресу): YouTube, Discord, прочие сайты — кружок; Minecraft — пиксельный блок травы */
const ICONS = {
  mc: '<svg class="si sq" viewBox="0 0 8 8" shape-rendering="crispEdges" aria-hidden="true"><rect x="0" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="1" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="2" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="3" y="0" width="1" height="1" fill="#86c43c"/><rect x="4" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="5" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="6" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="7" y="0" width="1" height="1" fill="#86c43c"/><rect x="0" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="1" y="1" width="1" height="1" fill="#86c43c"/><rect x="2" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="3" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="4" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="5" y="1" width="1" height="1" fill="#86c43c"/><rect x="6" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="7" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="0" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="1" y="2" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="3" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="4" y="2" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="6" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="7" y="2" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="3" width="1" height="1" fill="#a5733f"/><rect x="2" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="3" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="3" width="1" height="1" fill="#6b4423"/><rect x="6" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="7" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="4" width="1" height="1" fill="#6b4423"/><rect x="3" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="4" width="1" height="1" fill="#a5733f"/><rect x="5" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="7" y="4" width="1" height="1" fill="#6b4423"/><rect x="0" y="5" width="1" height="1" fill="#6b4423"/><rect x="1" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="3" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="5" width="1" height="1" fill="#a5733f"/><rect x="7" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="6" width="1" height="1" fill="#a5733f"/><rect x="3" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="6" width="1" height="1" fill="#6b4423"/><rect x="5" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="7" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="7" width="1" height="1" fill="#6b4423"/><rect x="2" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="3" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="7" width="1" height="1" fill="#6b4423"/><rect x="7" y="7" width="1" height="1" fill="#8b5a2b"/></svg>',
  web: '<svg class="si sq" viewBox="0 0 8 8" shape-rendering="crispEdges" aria-hidden="true"><path fill="#7f8e74" d="M2 0h4v1h1v1h1v4h-1v1h-1v1h-4v-1h-1v-1h-1v-4h1v-1h1z"/><path fill="#0a0f08" d="M3 1h2v6h-2zM1 3h6v2h-6z" opacity=".55"/></svg>',
  youtube: '<svg class="si" viewBox="0 0 16 12" aria-hidden="true"><rect width="16" height="12" rx="3" fill="#ff0033"/><path d="M6.2 3.3v5.4L10.9 6z" fill="#fff"/></svg>',
  discord: '<svg class="si" viewBox="0 0 127.14 96.36" aria-hidden="true"><path fill="#5865f2" d="M107.7 8.07A105.15 105.15 0 0 0 81.47 0a72.06 72.06 0 0 0-3.36 6.83 97.68 97.68 0 0 0-29.11 0A72.37 72.37 0 0 0 45.64 0a105.89 105.89 0 0 0-26.25 8.09C2.79 32.65-1.71 56.6.54 80.21a105.73 105.73 0 0 0 32.17 16.15 77.7 77.7 0 0 0 6.89-11.11 68.42 68.42 0 0 1-10.85-5.18c.91-.66 1.8-1.34 2.66-2a75.57 75.57 0 0 0 64.32 0c.87.71 1.76 1.39 2.66 2a68.68 68.68 0 0 1-10.87 5.19 77 77 0 0 0 6.89 11.1 105.25 105.25 0 0 0 32.19-16.14c2.64-27.38-4.51-51.11-18.9-72.15ZM42.45 65.69C36.18 65.69 31 60 31 53s5-12.74 11.43-12.74S54 46 53.89 53s-5.05 12.69-11.44 12.69Zm42.24 0C78.41 65.69 73.25 60 73.25 53s5-12.74 11.44-12.74S96.23 46 96.12 53s-5.04 12.69-11.43 12.69Z"/></svg>',
};
function svcIcon(x){
  const h = (x.host || '').toLowerCase(), n = (x.name || '').toLowerCase();
  if(/(^|\.)(youtube\.com|youtu\.be|googlevideo\.com)$/.test(h) || n === 'youtube') return ICONS.youtube;
  if(/(^|\.)(discord\.com|discord\.gg|discordapp\.com)$/.test(h) || n === 'discord') return ICONS.discord;
  return x.kind === 'mc' ? ICONS.mc : ICONS.web;
}
const svcMs = ms => ms > 0 ? `<b class="${ms < 120 ? 'ok' : ms < 250 ? 'mid' : 'slow'}">${ms}</b>` : '<b class="slow">—</b>';
function svcLine(n){
  const r = state && (n.id === state.current && state.targets ? state.targets : state.svc && state.svc[n.id]);
  if(!n.ms) return '';
  if(!r || !r.list) return state && state.svc_running ? '<small class="svc">измеряю…</small>' : '';
  return `<small class="svc" title="Задержка через этот сервер · ${esc(ago(r.ts))}">${r.list.map(x =>
    `<span>${svcIcon(x)}${esc(x.name)} ${svcMs(x.vpn)}</span>`).join('')}</small>`;
}
function srvRow(n, cur){
  return `<li class="srv${n.id === cur ? ' is-cur' : ''}${n.ms ? '' : ' is-off'}">
    <span class="srv-name">${esc(n.name)}</span>${svcLine(n)}
    <span class="ping">${pingHtml(n.ms)}</span>
    <button class="rp" data-ping="${esc(n.id)}" title="Пингануть этот сервер" aria-label="Пингануть ${esc(n.name)}">↻</button>
    ${n.id === cur ? '<span class="tag">Сейчас</span>'
      : `<button class="btn small" data-id="${esc(n.id)}"${n.ms ? '' : ' disabled'}>Подключить</button>`}
  </li>`;
}
function directRow(s){
  const r = s.svc && s.svc.direct;
  if(!r) return '';
  return `<li class="srv is-direct" title="Без VPN: так открываются сайты из списка MyDirect (Россия). Пинг — TCP до ya.ru">
    <span class="srv-name">🇷🇺 Напрямую (MyDirect)</span>${svcLine({id: 'direct', ms: 1})}
    <span class="ping">${pingHtml(r.base)}</span><span class="tag dim">без VPN</span>
  </li>`;
}
function renderServers(s){
  const nodes = (s.ping && s.ping.nodes) || [];
  const alive = nodes.filter(n => n.ms > 0).sort((a,b) => a.ms - b.ms);
  const dead = nodes.filter(n => !n.ms);
  $('#list').innerHTML = (alive.map(n => srvRow(n, s.current)).join('') || '<li class="empty">Ни один сервер не ответил. Нажми «Проверить серверы».</li>') + directRow(s);
  $('#dead-box').hidden = !dead.length;
  $('#dead-sum').textContent = `Не отвечают: ${dead.length}`;
  $('#dead').innerHTML = dead.map(n => srvRow(n, s.current)).join('');
}

const two = n => String(n).padStart(2, '0');
function when(ts){
  const d = new Date(ts * 1000), t = new Date();
  const hm = two(d.getHours()) + ':' + two(d.getMinutes());
  if(d.toDateString() === t.toDateString()) return 'сегодня ' + hm;
  t.setDate(t.getDate() - 1);
  if(d.toDateString() === t.toDateString()) return 'вчера ' + hm;
  return two(d.getDate()) + '.' + two(d.getMonth() + 1) + ' ' + hm;
}
function renderLog(s){
  if(hist && hist.events && hist.events.length){
    $('#log').innerHTML = hist.events.slice(0, 40).map(e =>
      `<li class="k-${esc(e[1])}"><time>${when(e[0])}</time><span>${esc(e[2])}</span></li>`).join('');
    return;
  }
  const nodes = ((s && s.ping && s.ping.nodes) || []);
  const byId = Object.fromEntries(nodes.map(n => [n.id, n.name]));
  const log = ((s && s.log) || []).slice().reverse().map(l => `<li><span>${esc(l.replace(/\b[A-Za-z0-9]{8}\b/g, id => byId[id] || id))}</span></li>`);
  $('#log').innerHTML = log.join('') || '<li><span>Пока пусто.</span></li>';
}

const flag = cc => /^[A-Z]{2}$/.test(cc || '') ? String.fromCodePoint(...[...cc].map(c => 0x1F1A5 + c.charCodeAt(0))) + ' ' : '';
function renderSpeedCard(via, r){
  const box = $('#st-' + via);
  if(!r) return;
  box.querySelector('.st-down').textContent = speed(r.down);
  box.querySelector('.st-up').textContent = r.up ? speed(r.up) : (r.up_limited ? 'позже' : '—');
  box.querySelector('.st-lat').textContent = r.latency ? r.latency + ' ms' : '—';
  box.querySelector('.st-meta').textContent = (r.ip ? `Выход: ${flag(r.country)}${r.ip}, ` : '') + 'проверено ' + ago(r.ts)
    + (r.server ? ` · сервер ${r.server}, ${r.streams || 1} потока` : '')
    + (!r.up && r.up_limited ? ' · Cloudflare ограничил частые замеры отдачи, повтори через пару минут' : '');
}
function renderSpeedtest(sp){ if(!sp) return; renderSpeedCard('vpn', sp.vpn); renderSpeedCard('direct', sp.direct); }

function render(){
  renderPc(state);
  renderStatus(state); renderChart(); renderSys(state.sys); renderSpeedtest(state.speed);
  renderDevices(state.devices); renderServers(state); renderLog(state);
}

/* ---------- вкладки ---------- */
const currentTab = () => location.hash === '#net' ? 'net' : 'vpn';
function showTab(){
  const t = currentTab();
  document.querySelectorAll('[data-page]').forEach(p => p.hidden = p.dataset.page !== t);
  document.querySelectorAll('.tab').forEach(a => a.setAttribute('aria-selected', a.dataset.tab === t));
  if(t === 'net') loadNet();
}
window.addEventListener('hashchange', showTab);

/* ---------- загрузка ---------- */
async function load(){
  try { state = await api('status'); showDown(false); render(); }
  catch(e){
    if(Date.now() < quietUntil) return;
    $('#vpn-text').textContent = 'Роутер не отвечает'; $('#vpn').className = 'status vpn down';
    if(e.down) showDown(true); else toast(e.message, true);
  }
}

/* История, журнал и имена устройств — с сервера: есть даже когда роутер не на связи */
async function loadData(){
  try {
    const r = await fetch('/router/data?range=' + range, {cache: 'no-store', headers: H});
    if(r.status === 401){ location.href = '/router/login?next=' + encodeURIComponent(location.pathname); return; }
    if(!r.ok) return;
    hist = await r.json(); names = hist.names || {};
    renderMtg(hist.mtg);
    renderChart(); renderTChart(); renderLog(state);
    if(state) renderDevices(state.devices);
    if(!$('#down').hidden) showDown(true);
  } catch {}
}

function renderMtg(m){
  $('#mtg-box').hidden = !m;
  if(!m) return;
  const stale = Date.now()/1000 - m.ts > 300;          // наблюдатель давно не писал — состояние неизвестно
  const up = m.active && !stale;
  const box = $('#mtg-box').querySelector('.mtg');
  box.className = 'mtg ' + (up ? 'up' : 'down');
  $('#mtg-dot').className = 'dot' + (up ? ' on' : '');
  $('#mtg-state').textContent = stale ? 'нет данных' : m.active ? 'работает' : 'не работает';
  const sum = $('#mtg-sum');
  sum.textContent = $('#mtg-state').textContent + (up ? ` · подключений: ${m.conns}` : '');
  sum.className = up ? 'up' : 'down';
  if(!up) $('#mtg-fold').open = true;                  // упал — раскрыть, чтобы было видно
  const n = m.conns, word = n % 10 === 1 && n % 100 !== 11 ? 'подключение' : [2,3,4].includes(n % 10) && ![12,13,14].includes(n % 100) ? 'подключения' : 'подключений';
  $('#mtg-info').textContent = up ? `сейчас ${n} ${word}` + (m.since ? ` · без перезапуска ${minutes(Math.round((Date.now()/1000 - m.since) / 60))}` : '')
    : stale ? `последние данные ${when(m.ts)}` : 'служба mtg остановлена — бот уже прислал сообщение';
}

function showDown(on){
  $('#down').hidden = !on;
  document.body.classList.toggle('is-down', on);
  document.body.classList.toggle('no-state', !state);
  if(!on) return;
  const since = hist && (hist.offline_since || hist.last_ok);
  const sm = $('#down-since small');
  if(since){
    const m = Math.max(1, Math.round((Date.now()/1000 - since) / 60));
    $('#down-since').firstChild.textContent = `Не на связи с ${when(since)}`;
    sm.textContent = `уже ${minutes(m)}` + (hist.last_ok ? ` · последний ответ ${when(hist.last_ok)}` : '');
  } else {
    $('#down-since').firstChild.textContent = 'Сервер не получает ответа от роутера';
    sm.textContent = '';
  }
}

$('#range').addEventListener('click', e => {
  const b = e.target.closest('button[data-range]'); if(!b) return;
  range = b.dataset.range;
  document.querySelectorAll('#range button').forEach(x => x.setAttribute('aria-pressed', x === b));
  renderChart(); renderTChart(); loadData();
});

/* Компьютер: какой — выбрать, команда установки скрипта (скрипт для ПК встроен выше как #pc-agent), усыпить */
function renderPc(s){
  const pc = s.pc, sel = $('#pc-dev');
  const nm = d => names[(d.mac || '').toLowerCase()] || d.name || d.mac;
  if(document.activeElement !== sel){
    const devs = (s.devices || []).slice().sort((a, b) => nm(a).localeCompare(nm(b)));
    const want = pc ? pc.mac : ((devs.find(d => /shvrf|desktop|pc/i.test(d.name || '')) || {}).mac || '');
    sel.innerHTML = '<option value="">— не выбран —</option>' + devs.map(d => `<option value="${esc(d.mac)}"${d.mac === want ? ' selected' : ''}>${esc(nm(d))} · ${esc(d.ip)}</option>`).join('');
  }
  const sum = $('#pc-sum');
  if(!pc){ sum.textContent = 'не настроено'; sum.className = ''; return; }
  const d = (s.devices || []).find(x => x.mac === pc.mac) || {mac: pc.mac};
  sum.textContent = `${nm(d)} · ` + (pc.agent ? 'скрипт отвечает' : d.online ? 'скрипт не отвечает' : 'не в сети');
  sum.className = pc.agent ? 'up' : d.online ? 'down' : '';
}
function pcInstall(tok){
  const agent = $('#pc-agent').textContent.trim();
  return [
    '$d = Join-Path $env:ProgramData "FSPIRAT"',
    'New-Item -ItemType Directory -Force $d | Out-Null',
    "icacls $d /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null",
    `Set-Content (Join-Path $d 'token.txt') '${tok}' -Encoding ASCII`,
    "Set-Content (Join-Path $d 'fsp-sleep.ps1') -Encoding UTF8 -Value @'", agent, "'@",
    "$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + (Join-Path $d 'fsp-sleep.ps1') + '\"')",
    '$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)',
    "Stop-ScheduledTask -TaskName 'FSPIRAT sleep' -ErrorAction SilentlyContinue",
    "Register-ScheduledTask -TaskName 'FSPIRAT sleep' -Action $a -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings $s -User 'SYSTEM' -RunLevel Highest -Force | Out-Null",
    "Remove-NetFirewallRule -DisplayName 'FSPIRAT sleep' -ErrorAction SilentlyContinue",
    "New-NetFirewallRule -DisplayName 'FSPIRAT sleep' -Direction Inbound -Protocol TCP -LocalPort 47321 -RemoteAddress 192.168.7.1 -Action Allow -Profile Any | Out-Null",
    "Start-ScheduledTask -TaskName 'FSPIRAT sleep'",
    "Write-Host 'Готово' -ForegroundColor Green", ''].join('\r\n');
}
$('#pc-save').addEventListener('click', async e => {
  const b = e.currentTarget, mac = $('#pc-dev').value; b.disabled = true;
  try { await api('pcset', '&mac=' + encodeURIComponent(mac)); state.pc = mac ? {mac, agent: false} : null; render(); toast(mac ? 'Компьютер выбран. Теперь установи на него скрипт.' : 'Компьютер больше не выбран.'); setTimeout(load, 3000); }
  catch(err){ toast(err.message, true); }
  finally { b.disabled = false; }
});
$('#pc-show').addEventListener('click', async e => {
  const b = e.currentTarget; b.disabled = true;
  try {
    const r = await api('pcinfo');
    $('#pc-code').textContent = pcInstall(r.token); $('#pc-code').hidden = false; $('#pc-copy').hidden = false;
  } catch(err){ toast(err.message, true); }
  finally { b.disabled = false; }
});
$('#pc-copy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText($('#pc-code').textContent); toast('Команда скопирована. Вставь её в PowerShell от имени администратора.'); }
  catch { const r = document.createRange(); r.selectNodeContents($('#pc-code')); getSelection().removeAllRanges(); getSelection().addRange(r); toast('Выделил команду — нажми Ctrl+C.'); }
});
document.addEventListener('click', async e => {
  const b = e.target.closest('button[data-sleep]'); if(!b) return;
  const mac = b.dataset.sleep, d = (state.devices || []).find(x => x.mac === mac) || {};
  const nm = names[mac.toLowerCase()] || d.name || mac;
  if(!confirm(`Отправить «${nm}» в сон?`)) return;
  b.disabled = true;
  try { await api('sleep', '&mac=' + encodeURIComponent(mac)); toast(`«${nm}» засыпает. Разбудить — кнопкой «⏻ Разбудить».`); setTimeout(load, 15000); }
  catch(err){
    const m = /NOAGENT|NOREPLY/.test(err.message) ? 'Скрипт на ПК не отвечает: он не установлен, или ПК уже спит.'
      : /DENY/.test(err.message) ? 'Ключ не совпал — установи скрипт заново командой из блока «Компьютер».' : err.message;
    toast(m, true);
  }
  finally { setTimeout(() => b.disabled = false, 5000); }
});

/* Разбудить компьютер (Wake-on-LAN). По Wi-Fi — только из сна и если адаптер умеет. */
document.addEventListener('click', async e => {
  const b = e.target.closest('button[data-wake]'); if(!b) return;
  const mac = b.dataset.wake, d = (state.devices || []).find(x => x.mac === mac) || {};
  const nm = names[mac.toLowerCase()] || d.name || mac;
  b.disabled = true;
  try {
    await api('wake', '&mac=' + encodeURIComponent(mac));
    toast(`Сигнал «проснись» отправлен на «${nm}». Если компьютер умеет просыпаться по сети, он появится в сети через 10–30 секунд.`);
    setTimeout(load, 20000); setTimeout(load, 45000);
  } catch(err){ toast(err.message, true); }
  finally { setTimeout(() => b.disabled = false, 5000); }
});

/* Выключить / включить интернет устройству (fspirat-fw на роутере: MAC в наборе block) */
document.addEventListener('click', async e => {
  const b = e.target.closest('button[data-block]'); if(!b) return;
  const mac = b.dataset.block, d = (state.devices || []).find(x => x.mac === mac) || {};
  const nm = names[mac.toLowerCase()] || d.name || mac;
  if(!d.blocked && !confirm(`Выключить интернет устройству «${nm}»?\n\nОно останется в Wi-Fi, но сайты и приложения перестанут открываться — пока не нажмёшь «Включить интернет». Если это устройство, с которого ты сейчас смотришь, страница тоже станет недоступна с него.`)) return;
  b.disabled = true;
  try {
    const r = await api(d.blocked ? 'unblock' : 'block', '&mac=' + encodeURIComponent(mac));
    d.blocked = r.blocked; renderDevices(state.devices);
    toast(r.blocked ? `Интернет для «${nm}» выключен.` : `Интернет для «${nm}» снова включён.`);
  } catch(err){ toast(err.message, true); b.disabled = false; }
});

/* Свои имена устройств (хранятся на сервере, по MAC) */
document.addEventListener('click', e => {
  const b = e.target.closest('button[data-edit]'); if(!b) return;
  const mac = b.dataset.edit, box = b.closest('.dev-name');
  const d = (state.devices || []).find(x => x.mac === mac) || {};
  editing = mac;
  box.innerHTML = `<input maxlength="40" value="${esc(names[mac.toLowerCase()] || d.name || '')}" placeholder="${esc(d.name || 'Имя устройства')}" aria-label="Имя устройства">
    <small>Enter — сохранить, Esc — отмена. Пустое имя — как называет себя устройство.</small>`;
  const inp = box.querySelector('input'); inp.focus(); inp.select();
  const done = async save => {
    if(editing !== mac) return;
    editing = null;
    if(save){
      try {
        const r = await fetch('/router/data', {method: 'POST', headers: H, body: new URLSearchParams({mac, name: inp.value})});
        if(!r.ok) throw new Error();
        names = (await r.json()).names || {};
      } catch { toast('Не удалось сохранить имя.', true); }
    }
    renderDevices(state.devices);
  };
  inp.addEventListener('keydown', ev => { if(ev.key === 'Enter') done(true); if(ev.key === 'Escape') done(false); });
  inp.addEventListener('blur', () => done(true));
});
async function loadNet(){
  if(document.hidden || currentTab() !== 'net' || Date.now() < quietUntil) return;
  try { renderNet(await api('net')); } catch {}
}

/* ---------- действия ---------- */
async function pingAll(){
  const bs = [$('#ping-btn'), $('#ping-all')], txt = bs.map(b => b.textContent);
  bs.forEach(b => { b.disabled = true; b.textContent = 'Проверяю, ~20 сек…'; });
  try { state = await api('ping'); render(); toast('Проверка серверов завершена.'); }
  catch(err){ toast(err.message, true); }
  finally { bs.forEach((b, i) => { b.disabled = false; b.textContent = txt[i]; }); }
}
$('#ping-btn').addEventListener('click', pingAll);
$('#ping-all').addEventListener('click', pingAll);

/* Пинг одного сервера: ↻ в строке */
document.addEventListener('click', async e => {
  const b = e.target.closest('button[data-ping]'); if(!b) return;
  b.disabled = true;
  try {
    const r = await api('pingone', '&id=' + encodeURIComponent(b.dataset.ping));
    const n = state.ping.nodes.find(x => x.id === r.id);
    if(n){ n.ms = r.ms; renderServers(state); renderStatus(state); }
    toast(`${n ? n.name : r.id}: ${r.ms ? r.ms + ' ms' : 'не отвечает'}`, !r.ms);
  } catch(err){ toast(err.message, true); b.disabled = false; }
});

document.querySelectorAll('[data-speed]').forEach(btn => btn.addEventListener('click', async () => {
  const via = btn.dataset.speed, all = document.querySelectorAll('[data-speed]');
  all.forEach(x => x.disabled = true); btn.textContent = 'Идёт тест, ~35 сек…';
  $('#st-' + via).querySelector('.st-meta').textContent = 'Измеряю загрузку, потом отдачу…';
  try {
    const r = await api('speedtest', '&via=' + via);
    if(state){ state.speed = state.speed || {}; state.speed[via] = r; }
    renderSpeedCard(via, r);
    toast(`Тест ${via === 'vpn' ? 'через VPN' : 'напрямую'}: ${speed(r.down)} загрузка, ${speed(r.up)} отдача.`);
  } catch(err){ toast(err.message, true); }
  finally { all.forEach(x => x.disabled = false); btn.textContent = 'Запустить'; }
}));

document.addEventListener('click', async e => {
  const b = e.target.closest('button[data-id]'); if(!b) return;
  const n = state.ping.nodes.find(x => x.id === b.dataset.id);
  if(!confirm(`Подключить «${n.name}»? Связь пропадёт на несколько секунд.`)) return;
  b.disabled = true; b.textContent = 'Подключаю…';
  try {
    await api('switch', '&id=' + encodeURIComponent(n.id));
    state.current = n.id; render(); quietUntil = Date.now() + 15000;
    toast(`Подключаю «${n.name}». VPN перезапускается, статус обновится через 10 секунд.`);
    setTimeout(load, 10000);
  } catch(err){ toast(err.message, true); b.disabled = false; b.textContent = 'Подключить'; }
});

const ACTIONS = {
  restart: { ask: 'Перезапустить VPN? Связь пропадёт на несколько секунд.', done: 'VPN перезапускается.', quiet: 15000 },
  update:  { ask: 'Обновить подписку nosok? Список серверов скачается заново, это займёт до минуты.', done: 'Подписка обновляется, список серверов обновится примерно через минуту.', quiet: 0 },
  reboot:  { ask: 'Перезагрузить роутер? Интернет дома пропадёт на 1–2 минуты.', done: 'Роутер перезагружается. Страница сама обновится, когда он вернётся.', quiet: 150000 },
};
document.querySelector('.controls').addEventListener('click', async e => {
  const b = e.target.closest('button[data-act]'); if(!b) return;
  const a = ACTIONS[b.dataset.act];
  if(!confirm(a.ask)) return;
  b.disabled = true;
  try {
    await api(b.dataset.act);
    toast(a.done); quietUntil = Date.now() + a.quiet;
    setTimeout(load, b.dataset.act === 'update' ? 60000 : Math.max(10000, a.quiet));
  } catch(err){ toast(err.message, true); }
  finally { setTimeout(() => b.disabled = false, 5000); }
});

showTab();
load();
loadData();
setInterval(load, 30000);
setInterval(loadData, 60000);
setInterval(loadNet, 3000);

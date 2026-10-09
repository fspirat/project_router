/* FSPIRAT Router — логика страницы (подключает index.html; CSP: script-src 'self') */
const API = '/router/api';
// Чтение (status, net, pingone) — GET. Всё остальное меняет что-то на роутере — только POST с CSRF-токеном сессии
// в заголовке X-FSR: сервер (check.php) без верного токена и нашего Origin отвечает 403, роутер на GET — 405.
// Токен — из /router/data?csrf=1 (ответ чужому сайту не прочитать), меняется с каждой новой сессией.
const READ = new Set(['status', 'net', 'pingone', 'mydirect', 'zapret', 'tgws']);
let csrf = '';
let state = null, hist = null, names = {}, range = 'day', series = 'link', logLv = 'all', toastTimer, quietUntil = 0, editing = null, lastOk = 0, md = null;
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
const num = v => Number.isFinite(+v) ? Math.round(+v) : 0;     // числа с роутера — только числа (в HTML без экранирования)
const pingHtml = ms => { ms = num(ms); return bars(ms) + (ms ? `<b>${ms}</b> ms` : 'нет ответа'); };
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
  return d ? `${d} д ${h} ч` : h ? `${h} ч ${m} мин` : `${m} мин`;
}
function toast(msg, err){
  let t = $('.toast');
  if(!t){ t = document.createElement('div'); t.className = 'toast'; t.setAttribute('role', 'status'); t.setAttribute('aria-live', 'polite'); document.body.append(t); }
  t.textContent = (err ? '' : '✓ ') + msg; t.classList.toggle('err', !!err); t.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.hidden = true, err ? 9000 : 6000);
}
const toLogin = () => { location.href = '/router/login?next=' + encodeURIComponent(location.pathname); };

/* Окно подтверждения вместо confirm(): <dialog> (фокус внутри, Esc — отмена). ask(...) → true / false */
function ask({title, text, ok = 'Да', danger = false}){
  const d = $('#dlg');
  $('#dlg-title').textContent = title; $('#dlg-text').textContent = text || '';
  const okb = $('#dlg-ok'); okb.textContent = ok; okb.className = 'btn ' + (danger ? 'danger' : 'primary');
  return new Promise(res => {
    const close = v => { d.close(); res(v); };
    okb.onclick = () => close(true); $('#dlg-cancel').onclick = () => close(false);
    d.oncancel = e => { e.preventDefault(); close(false); };
    d.showModal(); $('#dlg-cancel').focus();
  });
}

/* Кнопка «занята»: надпись и disabled на время операции; вернуть — вызвать результат */
function busy(b, text){
  const old = b.textContent; b.disabled = true; b.setAttribute('aria-busy', 'true'); if(text) b.textContent = text;
  return (later = 0) => setTimeout(() => { b.disabled = false; b.removeAttribute('aria-busy'); if(text) b.textContent = old; }, later);
}

async function csrfToken(fresh){
  if(csrf && !fresh) return csrf;
  const r = await fetch('/router/data?csrf=1', {cache: 'no-store', headers: {'X-FSR': '1'}});
  if(r.status === 401){ toLogin(); throw new Error('Вход истёк — открываю страницу входа.'); }
  csrf = (await r.json()).csrf || '';
  return csrf;
}
// Понятные слова вместо кодов; код и ответ роутера — в консоли (F12) для разбора
const ERR = {
  'bad mac': 'неверный адрес устройства (MAC)', 'bad node': 'такого сервера нет — обнови список', 'bad via': 'неизвестный вид теста',
  name: 'недопустимое имя', url: 'нужна ссылка вида https://сайт/путь', host: 'неверный адрес сервера', many: 'не больше 8 строк',
  inner: 'адрес ведёт внутрь домашней сети или на сам роутер — так нельзя', long: 'слишком длинный список',
  domain: 'нужен домен вида site.ru', time: 'неверное время', resolve: 'не удалось узнать IP сервера', 'no target': 'нет такого сервиса',
  'no rule': 'в PassWall нет правила MyDirect',
  'bad on': 'неверный режим', 'bad strategy': 'нет такой стратегии', 'not installed': 'zapret не установлен на роутере',
};
async function api(action, extra = ''){
  const post = !READ.has(action), url = `${API}?action=${action}${extra}`;
  const send = async fresh => fetch(url, {method: post ? 'POST' : 'GET', cache: 'no-store',
    headers: {'X-FSR': post ? await csrfToken(fresh) : (csrf || '1')}});
  let r;
  try {
    r = await send(false);
    if(post && r.status === 403) r = await send(true);      // токен устарел (новая сессия) — взять свежий и повторить один раз
  } catch(e){ if(e.message.startsWith('Вход')) throw e; throw new Error('Нет связи с сайтом. Проверь интернет и попробуй ещё раз.'); }
  if(r.ok){ lastOk = Date.now(); return r.json(); }
  let m = ''; try { m = (await r.clone().json()).error || ''; } catch {}
  console.warn('router api', action, r.status, m);
  if(r.status === 401){ toLogin(); throw new Error('Вход истёк — открываю страницу входа.'); }
  if(r.status === 502 || r.status === 504){ const e = new Error('Роутер временно недоступен. Попробуй ещё раз через несколько секунд.'); e.down = true; throw e; }
  if(r.status === 409) throw new Error(action === 'speedtest' ? 'Тест скорости уже идёт, дождись результата.' : 'Это действие уже выполняется.');
  if(r.status === 429) throw new Error('Слишком много запросов подряд. Подожди пару секунд.');
  if(r.status === 405) throw new Error('Страница устарела — обнови её (Ctrl+F5).');
  if(r.status === 403) throw new Error(m === 'forbidden' ? 'Роутер отклонил запрос: ключ сервера не совпадает с роутером.' : 'Запрос отклонён. Обнови страницу (Ctrl+F5).');
  if(r.status === 400) throw new Error('Роутер не принял запрос: ' + (ERR[m] || m || 'неверные данные') + '.');
  throw new Error('Роутер не смог выполнить действие. Попробуй ещё раз через минуту.');
}

/* Значки сервисов (по адресу): YouTube, Discord, прочие сайты — глобус; Minecraft — пиксельный блок травы */
const ICONS = {
  mc: '<svg class="si sq" viewBox="0 0 8 8" shape-rendering="crispEdges" aria-hidden="true"><rect x="0" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="1" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="2" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="3" y="0" width="1" height="1" fill="#86c43c"/><rect x="4" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="5" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="6" y="0" width="1" height="1" fill="#6aaa2c"/><rect x="7" y="0" width="1" height="1" fill="#86c43c"/><rect x="0" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="1" y="1" width="1" height="1" fill="#86c43c"/><rect x="2" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="3" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="4" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="5" y="1" width="1" height="1" fill="#86c43c"/><rect x="6" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="7" y="1" width="1" height="1" fill="#6aaa2c"/><rect x="0" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="1" y="2" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="3" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="4" y="2" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="6" y="2" width="1" height="1" fill="#6aaa2c"/><rect x="7" y="2" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="3" width="1" height="1" fill="#a5733f"/><rect x="2" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="3" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="3" width="1" height="1" fill="#6b4423"/><rect x="6" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="7" y="3" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="4" width="1" height="1" fill="#6b4423"/><rect x="3" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="4" width="1" height="1" fill="#a5733f"/><rect x="5" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="4" width="1" height="1" fill="#8b5a2b"/><rect x="7" y="4" width="1" height="1" fill="#6b4423"/><rect x="0" y="5" width="1" height="1" fill="#6b4423"/><rect x="1" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="3" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="5" width="1" height="1" fill="#a5733f"/><rect x="7" y="5" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="2" y="6" width="1" height="1" fill="#a5733f"/><rect x="3" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="6" width="1" height="1" fill="#6b4423"/><rect x="5" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="7" y="6" width="1" height="1" fill="#8b5a2b"/><rect x="0" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="1" y="7" width="1" height="1" fill="#6b4423"/><rect x="2" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="3" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="4" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="5" y="7" width="1" height="1" fill="#8b5a2b"/><rect x="6" y="7" width="1" height="1" fill="#6b4423"/><rect x="7" y="7" width="1" height="1" fill="#8b5a2b"/></svg>',
  web: '<svg class="si sq" viewBox="0 0 8 8" shape-rendering="crispEdges" aria-hidden="true"><path fill="#7f8e74" d="M2 0h4v1h1v1h1v4h-1v1h-1v1h-4v-1h-1v-1h-1v-4h1v-1h1z"/><path fill="#0a0f08" d="M3 1h2v6h-2zM1 3h6v2h-6z" opacity=".55"/></svg>',
  youtube: '<svg class="si" viewBox="0 0 16 12" aria-hidden="true"><rect width="16" height="12" rx="3" fill="#ff0033"/><path d="M6.2 3.3v5.4L10.9 6z" fill="#fff"/></svg>',
  discord: '<svg class="si" viewBox="0 0 127.14 96.36" aria-hidden="true"><path fill="#5865f2" d="M107.7 8.07A105.15 105.15 0 0 0 81.47 0a72.06 72.06 0 0 0-3.36 6.83 97.68 97.68 0 0 0-29.11 0A72.37 72.37 0 0 0 45.64 0a105.89 105.89 0 0 0-26.25 8.09C2.79 32.65-1.71 56.6.54 80.21a105.73 105.73 0 0 0 32.17 16.15 77.7 77.7 0 0 0 6.89-11.11 68.42 68.42 0 0 1-10.85-5.18c.91-.66 1.8-1.34 2.66-2a75.57 75.57 0 0 0 64.32 0c.87.71 1.76 1.39 2.66 2a68.68 68.68 0 0 1-10.87 5.19 77 77 0 0 0 6.89 11.1 105.25 105.25 0 0 0 32.19-16.14c2.64-27.38-4.51-51.11-18.9-72.15ZM42.45 65.69C36.18 65.69 31 60 31 53s5-12.74 11.43-12.74S54 46 53.89 53s-5.05 12.69-11.44 12.69Zm42.24 0C78.41 65.69 73.25 60 73.25 53s5-12.74 11.44-12.74S96.23 46 96.12 53s-5.04 12.69-11.43 12.69Z"/></svg>',
};

/* ---------- сервисы: значки, список, значения через сервер ---------- */
function svcIcon(x){
  const h = (x.host || '').toLowerCase(), n = (x.name || '').toLowerCase();
  if(/(^|\.)(youtube\.com|youtu\.be|googlevideo\.com)$/.test(h) || n === 'youtube') return ICONS.youtube;
  if(/(^|\.)(discord\.com|discord\.gg|discordapp\.com)$/.test(h) || n === 'discord') return ICONS.discord;
  return x.kind === 'mc' ? ICONS.mc : ICONS.web;
}
const msCls = ms => ms < 120 ? 'ok' : ms < 250 ? 'mid' : 'slow';
// Значок «палочки пинга» (img/ping-0…5.svg): 5 — до 60 ms, 4 — до 120, 3 — до 250, 2 — до 400, 1 — дольше, 0 — нет ответа
const pingLv = ms => !(ms > 0) ? 0 : ms < 60 ? 5 : ms < 120 ? 4 : ms < 250 ? 3 : ms < 400 ? 2 : 1;
const pingIcon = (ms, cls = 'pi') => `<img class="${cls}" src="img/ping-${pingLv(ms)}.svg" width="20" height="16" alt="">`;
// Список сервисов (что мерим): из последнего замера, иначе из списка на роутере
function services(){
  const t = state && state.targets && state.targets.list;
  if(t && t.length) return t.map(x => ({name: x.name, kind: x.kind, host: x.host}));
  return ((state && state.target_list) || []).map(l => { const [kind, name, a] = l.split('|'); return {name, kind, host: hostOf(a)}; });
}
// Замер сервисов через сервер: текущий — свежий (раз в 5 минут), остальные — fspirat-svcping (раз в 30 минут)
function svcOf(id){
  if(!state) return null;
  if(id === 'direct') id = '_direct';
  const r = id === state.current && state.targets ? state.targets : state.svc && state.svc[id === '_direct' ? 'direct' : id];
  return r && r.list ? r : null;
}
const svcVal = (r, name) => { const x = r && r.list.find(v => v.name === name); return x ? num(x.vpn) : null; };
const hostOf = a => String(a).replace(/^[a-z]+:\/\//i, '').replace(/[/:].*$/, '');
const DIRECT_NAME = 'Напрямую (без VPN)';
const nodeName = id => { if(id === '_direct' || id === 'direct') return DIRECT_NAME; const n = ((state && state.ping && state.ping.nodes) || []).find(x => x.id === id); return n ? n.name.trim() : id; };

/* ---------- главная карточка ---------- */
function renderHero(){
  const box = $('#hero'), s = state, down = !$('#down').hidden;
  const items = [];                 // [название, уровень ok|warn|err, подпись]
  let why = '';
  if(down || !s){
    items.push(['Роутер', 'err', 'не на связи']);
    $('#cur-name').textContent = s ? nodeName(s.current) : '—';
  } else {
    const p = s.ping || {}, nodes = p.nodes || [], alive = nodes.filter(n => n.ms > 0).length;
    const y = s.sys || {}, ram = y.mem_total ? 1 - y.mem_avail / y.mem_total : 0, disk = y.disk_total ? y.disk_used / y.disk_total : 0;
    const hot = y.temp != null && y.temp >= 85;
    items.push(['Роутер', ram > .9 || disk > .9 || hot ? 'warn' : 'ok', hot ? `${y.temp}°C` : ram > .9 ? 'мало памяти' : disk > .9 ? 'флеш почти полон' : 'в сети']);
    const vpnOk = s.running && (!p.socks || p.real > 0);
    if(s.current === '_direct') items.push(['VPN', 'warn', 'выключен — всё напрямую']);
    else items.push(['VPN', !s.running || !vpnOk ? 'err' : p.real > 250 ? 'warn' : 'ok', !s.running ? 'остановлен' : !vpnOk ? 'не проходит' : 'работает']);
    const dir = s.svc && s.svc.direct;
    const net = vpnOk || (dir && dir.base > 0);
    items.push(['Интернет', net ? 'ok' : 'err', net ? 'есть' : 'нет']);
    items.push(['Серверы', alive >= 2 ? 'ok' : alive ? 'warn' : 'err', `${alive} из ${nodes.length}`]);
    const t = (s.targets && s.targets.list) || [], bad = t.filter(x => !(x.vpn > 0));
    if(t.length) items.push(['Сервисы', bad.length ? 'warn' : 'ok', bad.length ? 'нет ответа: ' + bad.map(x => x.name).join(', ') : 'отвечают']);
    const sub = s.sub, left = sub && sub.expire ? Math.floor((sub.expire - Date.now() / 1000) / 86400) : null;
    if(left != null && left <= 3) items.push(['Подписка', left < 1 ? 'err' : 'warn', left < 1 ? 'закончилась' : `осталось ${left} дн.`]);
    if(!s.split_active) why = 'в PassWall выбран не Split';
    // текущий сервер и показатели
    $('#cur-name').textContent = nodeName(s.current);
    const r = svcOf(s.current), today = Object.values((hist && hist.traffic) || {}).reduce((a, v) => a + v.d[1], 0);
    const kp = [[`${pingIcon(p.socks ? p.real : 0)}Задержка`, p.socks ? (p.real > 0 ? `<i class="${msCls(p.real)}">${num(p.real)} ms</i>` : '<i class="slow">нет</i>') : '—',
                 'Как пинг: ответ сайта через VPN по уже открытому соединению. Раз в 5 минут.']];
    services().forEach(x => { const v = svcVal(r, x.name);
      kp.push([`${svcIcon(x)}${esc(x.name)}`, v ? `<i class="${msCls(v)}">${v} ms</i>` : '<i class="slow">—</i>', x.host]); });
    if(today) kp.push(['Сегодня ↓', `<i>${bytes(today)}</i>`, 'Все устройства дома, с полуночи']);
    $('#kpis').innerHTML = kp.map(([k, v, t]) => `<div title="${esc(t || '')}"><span>${k}</span>${v}</div>`).join('');
    $('#updated').textContent = p.updated ? 'Проверено ' + ago(p.updated) : '';
    // подписка
    $('#sub-line').innerHTML = sub && sub.expire
      ? `Подписка до <b>${new Date(sub.expire * 1000).toLocaleDateString('ru-RU', {day: 'numeric', month: 'long'})}</b> · осталось <b class="${left <= 3 ? 'slow' : ''}">${left} дн.</b>`
        + (sub.down ? ` · израсходовано ${bytes(sub.down + (sub.up || 0))}` + (sub.total ? ` из ${bytes(sub.total)}` : ', без лимита') : '')
      : '';
    $('#warn').hidden = s.split_active;
  }
  document.querySelector('.hero-cur').hidden = down || !s;     // роутер не на связи — нечего показывать про сервер
  const worst = items.some(i => i[1] === 'err') ? 'err' : items.some(i => i[1] === 'warn') || why ? 'warn' : 'ok';
  box.className = 'panel hero ' + worst;
  $('#ov-title').textContent = {ok: 'ВСЁ РАБОТАЕТ', warn: 'ТРЕБУЕТ ВНИМАНИЯ', err: 'ЕСТЬ ПРОБЛЕМА'}[worst];
  $('#ov-items').innerHTML = items.map(([n, lv, t]) => `<li class="${lv}"><i aria-hidden="true"></i>${esc(n)} <b>${esc(t)}</b></li>`).join('')
    + (why ? `<li class="warn"><i aria-hidden="true"></i><b>${esc(why)}</b></li>` : '');
  tickUpdated();
}
function tickUpdated(){
  const el = $('#ov-upd'); if(!el) return;
  if(!lastOk){ el.textContent = ''; return; }
  const sec = Math.round((Date.now() - lastOk) / 1000);
  el.textContent = 'обновлено ' + (sec < 5 ? 'только что' : sec < 60 ? sec + ' сек назад' : Math.round(sec / 60) + ' мин назад');
}

/* ---------- серверы: таблица (строка — сервер, столбцы — пинг и сервисы; лучшее в столбце обведено) ---------- */
function renderServers(s){
  const nodes = (s.ping && s.ping.nodes) || [];
  const alive = nodes.filter(n => n.ms > 0).sort((a, b) => a.ms - b.ms), dead = nodes.filter(n => !n.ms);
  const sv = services();
  const cell = (v, best, web) => v == null ? '<td class="na" title="ещё не мерили">·</td>' : v ? `<td class="${msCls(v)}${best ? ' best' : ''}"><b>${v}</b></td>`
    : web ? '<td class="blk" title="Без VPN этот сайт в России не открывается">блок</td>' : '<td class="slow"><b>—</b></td>';
  const pcell = (v, best) => v > 0 ? `<td class="${msCls(v)}${best ? ' best' : ''} pcol"><b>${pingIcon(v)}${v}</b></td>` : `<td class="slow pcol"><b>${pingIcon(0)}—</b></td>`;
  // лучшее значение в каждом столбце (только среди VPN-серверов)
  const best = {ping: Math.min(...alive.map(n => n.ms))};
  sv.forEach(x => { const v = alive.map(n => svcVal(svcOf(n.id), x.name)).filter(v => v > 0); best[x.name] = v.length ? Math.min(...v) : 0; });
  const head = `<tr><th>Сервер</th><th title="Пинг до самого сервера"><img class="pi" src="img/ping-5.svg" width="20" height="16" alt=""><span>Пинг</span></th>${sv.map(x => `<th title="${esc(x.name)} · ${esc(x.host || '')}">${svcIcon(x)}<span>${esc(x.name)}</span></th>`).join('')}<th class="act"></th></tr>`;
  const row = n => { const r = svcOf(n.id), cur = n.id === s.current;
    return `<tr class="${cur ? 'cur' : ''}" data-node="${esc(n.id)}" ${cur ? '' : 'tabindex="0"'} title="${cur ? 'Подключён сейчас' : 'Нажми, чтобы подключить'}">
      <th scope="row">${esc(n.name.trim())}${n.own ? ' <span class="tag own">свой</span>' : ''}</th>${pcell(n.ms, n.ms === best.ping)}${sv.map(x => cell(r ? svcVal(r, x.name) : null, r && svcVal(r, x.name) === best[x.name] && best[x.name] > 0)).join('')}
      <td class="act">${cur ? '<span class="now">сейчас</span>' : '<span class="go">подключить</span>'}</td></tr>`; };
  const dir = s.svc && s.svc.direct;
  const dcur = s.current === '_direct';
  const drow = dir || dcur ? `<tr class="direct${dcur ? ' cur' : ''}" data-node="direct" ${dcur ? '' : 'tabindex="0"'} title="${dcur ? 'Подключено: весь трафик без VPN' : 'Без VPN: так открываются сайты из списка MyDirect. Нажми, чтобы пустить весь трафик напрямую. Пинг — до ya.ru'}">
      <th scope="row">🇷🇺 Напрямую <span class="tag">без VPN</span></th>${pcell(num(dir && dir.base))}${sv.map(x => cell(dir ? svcVal(dcur && state.targets ? state.targets : dir, x.name) : null, false, x.kind === 'web' && !dcur)).join('')}<td class="act">${dcur ? '<span class="now">сейчас</span>' : '<span class="go">подключить</span>'}</td></tr>` : '';
  // свои серверы (ярлык fspirat в PassWall) — отдельным разделом сверху, подписка — ниже
  const own = alive.filter(n => n.own), sub = alive.filter(n => !n.own);
  const grp = t => `<tr class="grp"><th colspan="${sv.length + 3}">${t}</th></tr>`;
  const body = own.length ? grp('Свои серверы') + own.map(row).join('') + (sub.length ? grp('Подписка nosok') + sub.map(row).join('') : '') : sub.map(row).join('');
  $('#srv').innerHTML = `<thead>${head}</thead><tbody>${body || `<tr><td class="empty" colspan="${sv.length + 3}">Ни один сервер не ответил. Нажми «↻ Пинг всех».</td></tr>`}${drow}</tbody>`;
  // «лучший для …» — с кнопкой подключить
  const chips = sv.map(x => {
    const b = alive.filter(n => svcVal(svcOf(n.id), x.name) > 0).sort((a, c) => svcVal(svcOf(a.id), x.name) - svcVal(svcOf(c.id), x.name))[0];
    if(!b) return '';
    const cur = b.id === s.current;
    return `<button class="chip${cur ? ' on' : ''}" ${cur ? 'disabled' : `data-best="${esc(b.id)}"`} title="${cur ? 'Уже подключён' : 'Подключить ' + esc(b.name.trim())}">${svcIcon(x)}${esc(x.name)}: <b>${esc(b.name.trim())}</b> ${svcVal(svcOf(b.id), x.name)} ms${cur ? ' ✓' : ' →'}</button>`;
  }).join('');
  $('#best').innerHTML = chips ? '<span class="muted">Лучший сервер для:</span>' + chips : '';
  // сервисы напрямую (мимо VPN)
  const sd = s.svc_direct || [];
  $('#svcdir').innerHTML = sv.length ? `<span class="muted">Пускать напрямую, без VPN:</span>` + sv.map(x => {
    const on = sd.includes(x.name);
    return `<button class="chip tgl${on ? ' on' : ''}" data-svcdir="${esc(x.name)}" aria-pressed="${on}" title="${on ? 'Сейчас напрямую — нажми, чтобы снова через VPN' : 'Пустить мимо VPN'}">${svcIcon(x)}${esc(x.name)}${on ? ' ✓' : ''}</button>`;
  }).join('') : '';
  $('#dead-box').hidden = !dead.length;
  $('#dead-sum').textContent = `Не отвечают: ${dead.length}`;
  $('#dead').innerHTML = dead.map(n => `<li>${pingIcon(0)} ${esc(n.name.trim())}</li>`).join('');
  renderSeries();
}

/* ---------- один график: «Связь» или выбранный сервис ---------- */
const RANGES = {day: [86400, '24 часа', '24 ч назад'], week: [7*86400, '7 дней', '7 дней назад'], month: [30*86400, '30 дней', '30 дней назад']};
const minutes = m => m < 60 ? m + ' мин' : m < 1440 ? Math.floor(m/60) + ' ч ' + (m%60 ? m%60 + ' мин' : '') : Math.floor(m/1440) + ' д ' + Math.floor(m%1440/60) + ' ч';
function renderSeries(){
  const sv = services();
  if(series !== 'link' && !sv.some(x => x.name === series)) series = 'link';
  $('#series').innerHTML = `<button data-series="link" aria-pressed="${series === 'link'}">Связь</button>`
    + sv.map(x => `<button data-series="${esc(x.name)}" aria-pressed="${series === x.name}">${svcIcon(x)}${esc(x.name)}</button>`).join('');
}
const grid = (W, H) => { let g = ''; for(let i=1;i<4;i++) g += `<line class="grid" x1="0" x2="${W}" y1="${H*i/4}" y2="${H*i/4}"/>`;
  const cols = range === 'week' ? 7 : 6; for(let i=1;i<cols;i++) g += `<line class="grid" y1="0" y2="${H}" x1="${W*i/cols}" x2="${W*i/cols}"/>`; return g; };
const fact = (k, v) => `<div class="fact"><span>${k}</span><b>${v}</b></div>`;
function renderChart(){
  const [span, title, fromTxt] = RANGES[range];
  $('#chart-from').textContent = fromTxt;
  const svg = $('#chart'), W = 600, H = 150, now = Date.now()/1000, from = now - span;
  if(series !== 'link'){                   // сервис: одна линия из истории замеров через текущий сервер
    $('#chart-title').textContent = `${series} за ${title}`;
    const pts = ((hist && hist.range === range && hist.tpoints && hist.tpoints[series]) || []).filter(p => p[0] >= from);
    const ok = pts.filter(p => p[1] > 0).map(p => p[1]);
    const max = Math.max(150, ...ok) * 1.15, x = t => ((t - from) / span) * W, y = v => H - (v / max) * (H - 8);
    const gap = (hist && hist.step ? hist.step : 300) * 2.5;
    let seg = [], lines = '', fails = '', prev = 0;
    const flush = () => { if(seg.length > 1){ const d = seg.join(' '); lines += `<polyline class="line" points="${d}"/>`; } seg = []; };
    pts.forEach(p => { if(p[1] <= 0 || (prev && p[0] - prev > gap)) flush();
      if(p[1] > 0) seg.push(`${x(p[0]).toFixed(1)},${y(p[1]).toFixed(1)}`); else fails += `<rect class="fail" x="${x(p[0])-1.5}" y="${H-14}" width="3" height="14"/>`; prev = p[0]; });
    flush();
    svg.innerHTML = grid(W, H) + lines + fails;
    chartView = {from, span, max, H, pts, step: hist && hist.range === range ? hist.step : 0, kind: 'svc'}; hideTip();
    $('#chart-max').textContent = ok.length ? `шкала до ${Math.round(max)} ms` : 'истории пока нет — она копится на сервере';
    $('#stats').innerHTML = fact('Средняя', ok.length ? Math.round(ok.reduce((a, b) => a + b, 0) / ok.length) + ' ms' : '—')
      + fact('Лучшая', ok.length ? Math.min(...ok) + ' ms' : '—') + fact('Худшая', ok.length ? Math.max(...ok) + ' ms' : '—')
      + fact('Не ответил', pts.filter(p => p[1] <= 0).length + ' раз');
    return;
  }
  $('#chart-title').textContent = 'Связь за ' + title;
  const src = hist && hist.range === range ? hist.points : (range === 'day' && state ? state.history || [] : []);
  const pts = src.filter(p => p[0] >= from);
  const ok = pts.filter(p => p[1] > 0).map(p => p[1]);
  const max = Math.max(150, ...ok) * 1.15;
  const x = t => ((t - from) / span) * W, y = v => H - (v / max) * (H - 8);
  const slot = hist && hist.step ? hist.step / span * W : 300 / span * W;
  let seg = [], lines = '', areas = '', fails = '', off = '';
  const flush = () => {
    if(seg.length > 1){
      const d = seg.map(p => `${x(p[0]).toFixed(1)},${y(p[1]).toFixed(1)}`).join(' ');
      lines += `<polyline class="line" points="${d}"/>`;
      areas += `<polygon class="area" points="${x(seg[0][0]).toFixed(1)},${H} ${d} ${x(seg[seg.length-1][0]).toFixed(1)},${H}"/>`;
    } else if(seg.length === 1) lines += `<rect x="${x(seg[0][0])-1}" y="${y(seg[0][1])-1}" width="3" height="3" fill="var(--lime)"/>`;
    seg = [];
  };
  pts.forEach(p => {
    if(p[1] > 0){ seg.push(p); if(p[2]) fails += `<rect class="fail" x="${x(p[0])-1.5}" y="${H-8}" width="3" height="8"/>`; return; }
    flush();
    if(p[1] < 0) off += `<rect class="offline" x="${(x(p[0]) - Math.max(slot, 2)/2).toFixed(1)}" y="0" width="${Math.max(slot, 2).toFixed(1)}" height="${H}"/>`;
    else fails += `<rect class="fail" x="${x(p[0])-1.5}" y="${H-14}" width="3" height="14"/>`;
  });
  flush();
  svg.innerHTML = grid(W, H) + off + areas + lines + fails;
  chartView = {from, span, max, H, pts, step: hist && hist.range === range ? hist.step : 0, kind: 'link'}; hideTip();
  $('#chart-max').textContent = pts.length ? `шкала до ${Math.round(max)} ms` : 'данных за этот период пока нет';
  const st = hist && hist.range === range ? hist.stats : {avg: ok.length ? Math.round(ok.reduce((a,b) => a+b, 0) / ok.length) : null,
    min: ok.length ? Math.min(...ok) : null, max: ok.length ? Math.max(...ok) : null, fails: pts.filter(p => p[1] === 0).length, offline_min: null};
  $('#stats').innerHTML = fact('Средняя', st.avg ? st.avg + ' ms' : '—') + fact('Лучшая', st.min ? st.min + ' ms' : '—')
    + fact('Худшая', st.max ? st.max + ' ms' : '—') + fact('Сбоев', st.fails)
    + fact('Без связи', st.offline_min == null ? '—' : st.offline_min ? minutes(st.offline_min) : '0 мин');
}

/* Подсказка на графике: время и задержка в точке под курсором (на телефоне — нажать или вести пальцем).
   За 7 и 30 дней точка — среднее за 30 минут / 2 часа, поэтому показывается промежуток. */
let chartView = null;
const hm = ts => { const d = new Date(ts * 1000); return two(d.getHours()) + ':' + two(d.getMinutes()); };
function hideTip(){ ['#ctip', '#cline', '#cdot'].forEach(s => $(s).hidden = true); }
function chartTip(e){
  const v = chartView, svg = $('#chart');
  if(!v || !v.pts.length) return hideTip();
  const r = svg.getBoundingClientRect(), w = svg.clientWidth, h = svg.clientHeight;
  const t = v.from + Math.min(Math.max(e.clientX - r.left - svg.clientLeft, 0), w) / w * v.span;
  let p = null, d = Infinity;
  for(const q of v.pts){ const k = Math.abs(q[0] - t); if(k < d){ d = k; p = q; } }
  if(!p || d > Math.max(v.step, 300) * 1.5) return hideTip();          // в дыре между данными — ничего не показывать
  const x = svg.clientLeft + (p[0] - v.from) / v.span * w, ms = p[1];
  const val = ms > 0 ? `<b>${ms} ms</b>${v.step ? ' в среднем' : ''}${v.kind === 'link' && p[2] ? ` · сбоев VPN: ${p[2]}` : ''}`
    : ms < 0 ? '<b class="bad">роутер не на связи</b>' : `<b class="bad">${v.kind === 'link' ? 'сбой VPN' : 'нет ответа'}</b>`;
  const tip = $('#ctip');
  tip.innerHTML = `<span>${v.step ? `${when(p[0] - v.step / 2)}–${hm(p[0] + v.step / 2)}` : when(p[0])}</span>${val}`;
  tip.hidden = false;
  tip.style.left = Math.min(Math.max(x - tip.offsetWidth / 2, 0), r.width - tip.offsetWidth) + 'px';
  const line = $('#cline'); line.hidden = false; line.style.left = x + 'px';
  const dot = $('#cdot'); dot.hidden = !(ms > 0);
  if(ms > 0){ dot.style.left = x + 'px'; dot.style.top = svg.clientTop + (v.H - ms / v.max * (v.H - 8)) / v.H * h + 'px'; }
}
$('#chart-box').addEventListener('pointermove', chartTip);
$('#chart-box').addEventListener('pointerdown', chartTip);
$('#chart-box').addEventListener('pointerleave', e => { if(e.pointerType === 'mouse') hideTip(); });

/* ---------- журнал ---------- */
const two = n => String(n).padStart(2, '0');
function when(ts){
  const d = new Date(ts * 1000), t = new Date();
  const hm = two(d.getHours()) + ':' + two(d.getMinutes());
  if(d.toDateString() === t.toDateString()) return 'сегодня ' + hm;
  t.setDate(t.getDate() - 1);
  if(d.toDateString() === t.toDateString()) return 'вчера ' + hm;
  return two(d.getDate()) + '.' + two(d.getMonth() + 1) + ' ' + hm;
}
const LEVEL = {offline: 'err', vpn_down: 'err', auto: 'warn', reboot: 'warn', newdev: 'warn', online: 'ok', vpn_up: 'ok'};
const LEVEL_TXT = {err: 'ОШИБКА', warn: 'ВНИМАНИЕ', ok: 'УСПЕХ', info: 'ДЕЙСТВИЕ'};
function events(){
  if(hist && hist.events && hist.events.length) return hist.events.map(e => ({ts: e[0], kind: e[1], text: String(e[2]).replace(/\b_direct\b/g, DIRECT_NAME)}));
  const byId = Object.fromEntries(((state && state.ping && state.ping.nodes) || []).map(n => [n.id, n.name]));
  return ((state && state.log) || []).slice().reverse().map(l => ({ts: 0, kind: 'router', text: l.replace(/\b[A-Za-z0-9]{8}\b/g, id => byId[id] || id).replace(/\b_direct\b/g, DIRECT_NAME)}));
}
function logItem(e){
  const lv = LEVEL[e.kind] || 'info';
  return `<li class="lv-${lv}">${e.ts ? `<time>${when(e.ts)}</time>` : '<time></time>'}<i class="lv">${LEVEL_TXT[lv]}</i><span>${esc(e.text)}</span></li>`;
}
function renderLog(){
  const ev = events(), empty = '<li class="empty"><span>Событий пока нет. Здесь появятся смены сервера, перезагрузки, сбои VPN и новые устройства.</span></li>';
  $('#log-mini').innerHTML = ev.slice(0, 6).map(logItem).join('') || empty;
  const f = ev.filter(e => logLv === 'all' || (LEVEL[e.kind] || 'info') === logLv || (logLv === 'info' && (LEVEL[e.kind] || 'info') === 'ok'));
  $('#log').innerHTML = f.slice(0, 200).map(logItem).join('') || (ev.length ? '<li class="empty"><span>Таких записей нет.</span></li>' : empty);
}

/* ---------- устройства: компактные строки, действия — в меню «⋯» ---------- */
const BANDS = {'5g': ['g5', '5 ГГц'], '6g': ['g5', '6 ГГц'], '2g': ['g2', '2,4 ГГц'], wired: ['', 'кабель']};
const devName = d => names[(d.mac || '').toLowerCase()] || d.name || '';
const hiddenMac = m => /^.[26ae]/i.test(m || '');                 // «локальный» MAC: телефон сам его выдумал для приватности
const sig = dbm => { const l = !dbm ? 0 : dbm > -55 ? 4 : dbm > -65 ? 3 : dbm > -75 ? 2 : 1;
  return `<span class="sig" title="${dbm ? dbm + ' dBm' : ''}">${[4, 7, 10, 13].map((h, i) => `<i class="${i < l ? 'on' : ''}" style="height:${h}px"></i>`).join('')}</span>`; };
function devRow(d, mini){
  const mac = (d.mac || '').toLowerCase(), t = hist && hist.traffic && hist.traffic[mac], b = BANDS[d.band];
  const tags = [b && d.online ? `<span class="band ${b[0]}">${b[1]}</span>` : '',
    d.blocked ? '<span class="tag cut">без интернета</span>' : d.sblocked ? '<span class="tag cut">по расписанию</span>' : '',
    d.direct ? '<span class="tag dir">мимо VPN</span>' : '', d.sched && !d.sblocked ? `<span class="tag">⏱ ${d.sched.replace(/(\d\d)(\d\d)/g, '$1:$2').replace('-', '–')}</span>` : ''].join('');
  const sub = [d.ip, hiddenMac(mac) && !devName(d) ? 'скрытый MAC' : '', !mini && d.rate ? d.rate + '\u00a0Мбит/с' : ''].filter(Boolean).join(' · ');
  return `<li class="dev${d.online ? '' : ' off'}${d.blocked || d.sblocked ? ' is-blocked' : ''}" data-mac="${esc(mac)}">
    <i class="dot${d.online ? ' on' : ''}" title="${d.online ? 'в сети' : 'не в сети'}"></i>
    <div class="dev-main"><b class="dev-nm">${esc(devName(d) || 'Без имени')}</b>${tags}<small>${esc(sub)}</small></div>
    ${d.band && d.band !== 'wired' && d.online ? sig(d.signal) : '<span></span>'}
    <div class="tr">${t ? `↓${bytes(t.d[1])}<small>${mini ? 'сегодня' : `месяц ↓${bytes(t.m[1])}`}</small>` : ''}</div>
    ${mini ? '' : `<button class="more" data-menu="${esc(mac)}" aria-label="Действия: ${esc(devName(d) || mac)}" aria-haspopup="menu">⋯</button>`}
  </li>`;
}
function renderDevices(list){
  if(editing) return;                      // не мешать, пока вводится имя
  list = (list || []).slice();
  const traf = d => { const t = hist && hist.traffic && hist.traffic[(d.mac || '').toLowerCase()]; return t ? t.d[1] : 0; };
  const byName = (a, b) => (devName(a) || 'я').localeCompare(devName(b) || 'я');
  const on = list.filter(d => d.online);
  $('#dev-sum').textContent = `${on.length} в сети из ${list.length}`;
  $('#dev-mini-sum').textContent = `${on.length} в сети · все →`;
  $('#dev-mini').innerHTML = on.slice().sort((a, b) => traf(b) - traf(a)).slice(0, 4).map(d => devRow(d, true)).join('') || '<li class="empty">Никого нет в сети.</li>';
  const groups = [['Wi-Fi 5 ГГц', on.filter(d => d.band === '5g' || d.band === '6g')], ['Wi-Fi 2,4 ГГц', on.filter(d => d.band === '2g')],
    ['По кабелю', on.filter(d => !['5g', '6g', '2g'].includes(d.band))]];
  let html = groups.filter(g => g[1].length).map(([t, a]) => `<h3>${t}<small>${a.length}</small></h3><ul class="dev-list">${a.sort(byName).map(d => devRow(d)).join('')}</ul>`).join('');
  const off = list.filter(d => !d.online);
  if(off.length) html += `<details><summary>Не в сети: ${off.length}</summary><ul class="dev-list">${off.sort(byName).map(d => devRow(d)).join('')}</ul></details>`;
  $('#devices').innerHTML = list.length ? html : '<p class="empty">Устройства не найдены: роутер пока никому не выдал адрес.</p>';
}

/* Меню «⋯» устройства */
const devBy = mac => ((state && state.devices) || []).find(x => (x.mac || '').toLowerCase() === mac) || {mac};
function openMenu(btn){
  const mac = btn.dataset.menu, d = devBy(mac), m = $('#devmenu'), t = hist && hist.traffic && hist.traffic[mac];
  m.innerHTML = `<div class="menu-head"><b>${esc(devName(d) || 'Без имени')}</b><small>${esc(d.ip || '')} · ${esc(mac)}${t ? ` · месяц ↓${bytes(t.m[1])} ↑${bytes(t.m[0])}` : ''}</small></div>
    <button role="menuitem" data-do="rename">✎ Переименовать</button>
    <button role="menuitem" data-do="${d.blocked ? 'unblock' : 'block'}" class="${d.blocked ? 'ok' : 'danger'}">${d.blocked ? '✓ Включить интернет' : '⛔ Выключить интернет'}</button>
    <button role="menuitem" data-do="direct">${d.direct ? '↺ Снова через VPN' : '⇢ Пускать мимо VPN'}</button>
    <button role="menuitem" data-do="sched">⏱ Расписание${d.sched ? ': ' + d.sched.replace(/(\d\d)(\d\d)/g, '$1:$2').replace('-', '–') : '…'}</button>`;
  m.dataset.mac = mac; m.hidden = false;
  const r = btn.getBoundingClientRect(), w = m.offsetWidth;
  m.style.top = Math.min(window.scrollY + r.bottom + 4, window.scrollY + innerHeight - m.offsetHeight - 70) + 'px';
  m.style.left = Math.max(8, Math.min(r.right - w, innerWidth - w - 8)) + 'px';
  m.querySelector('button').focus();
}
const closeMenu = () => { $('#devmenu').hidden = true; };
document.addEventListener('click', e => {
  const b = e.target.closest('[data-menu]');
  if(b){ e.stopPropagation(); $('#devmenu').hidden || $('#devmenu').dataset.mac !== b.dataset.menu ? openMenu(b) : closeMenu(); return; }
  if(!e.target.closest('#devmenu')) closeMenu();
});
document.addEventListener('keydown', e => { if(e.key === 'Escape') closeMenu(); });
$('#devmenu').addEventListener('click', async e => {
  const b = e.target.closest('[data-do]'); if(!b) return;
  const mac = $('#devmenu').dataset.mac, d = devBy(mac), nm = devName(d) || mac, act = b.dataset.do;
  closeMenu();
  if(act === 'rename') return rename(mac);
  if(act === 'sched') return schedule(mac);
  if(act === 'block' && !await ask({title: `Выключить интернет «${nm}»?`, danger: true, ok: 'Выключить',
    text: 'Устройство останется в Wi-Fi, но сайты и приложения перестанут открываться, пока не включишь обратно. Если ты смотришь с него, страница тоже станет недоступна.'})) return;
  if(act === 'direct' && !await ask({title: d.direct ? `«${nm}» снова через VPN?` : `Пускать «${nm}» мимо VPN?`, ok: d.direct ? 'Через VPN' : 'Мимо VPN',
    text: (d.direct ? 'Весь интернет устройства снова пойдёт через VPN.' : 'Весь интернет устройства пойдёт напрямую, как без VPN (например, телевизор для российских сервисов). Заблокированные в России сайты на нём открываться не будут.') + ' VPN перезапустится, связь пропадёт на ~5 секунд.'})) return;
  try {
    if(act === 'direct'){ await api('direct', `&mac=${encodeURIComponent(mac)}&on=${d.direct ? 0 : 1}`); d.direct = !d.direct; quietUntil = Date.now() + 12000; toast(d.direct ? `«${nm}» теперь мимо VPN.` : `«${nm}» снова через VPN.`); }
    else { const r = await api(act, '&mac=' + encodeURIComponent(mac)); d.blocked = r.blocked; toast(r.blocked ? `Интернет для «${nm}» выключен.` : `Интернет для «${nm}» снова включён.`); }
    renderDevices(state.devices);
  } catch(err){ toast(err.message, true); }
});

/* Переименование — прямо в строке */
function rename(mac){
  const li = document.querySelector(`#devices .dev[data-mac="${CSS.escape(mac)}"]`); if(!li) return;
  const box = li.querySelector('.dev-main'), d = devBy(mac);
  editing = mac;
  box.innerHTML = `<input maxlength="40" value="${esc(names[mac] || d.name || '')}" placeholder="${esc(d.name || 'Имя устройства')}" aria-label="Имя устройства">
    <small>Enter — сохранить, Esc — отмена. Пустое имя — как называет себя устройство.</small>`;
  const inp = box.querySelector('input'); inp.focus(); inp.select();
  const done = async save => {
    if(editing !== mac) return;
    editing = null;
    if(save){
      try {
        const post = async fresh => fetch('/router/data', {method: 'POST', headers: {'X-FSR': await csrfToken(fresh)}, body: new URLSearchParams({mac, name: inp.value})});
        let r = await post(false);
        if(r.status === 403) r = await post(true);
        if(!r.ok) throw new Error();
        names = (await r.json()).names || {};
        toast('Имя сохранено.');
      } catch { toast('Не удалось сохранить имя. Попробуй ещё раз.', true); }
    }
    renderDevices(state.devices);
  };
  inp.addEventListener('keydown', ev => { if(ev.key === 'Enter') done(true); if(ev.key === 'Escape') done(false); });
  inp.addEventListener('blur', () => done(true));
}

/* Расписание интернета */
function schedule(mac){
  const d = devBy(mac), dlg = $('#sched-dlg'), nm = devName(d) || mac;
  $('#sched-title').textContent = `Расписание: ${nm}`;
  const [off, on] = (d.sched || '2300-0700').split('-').map(v => v.slice(0, 2) + ':' + v.slice(2));
  $('#sched-off').value = off; $('#sched-on').value = on; $('#sched-del').hidden = !d.sched;
  const send = async (offV, onV) => {
    try {
      await api('schedule', `&mac=${encodeURIComponent(mac)}&off=${offV}&on=${onV}`);
      d.sched = offV ? `${offV}-${onV}` : undefined; dlg.close(); renderDevices(state.devices);
      toast(offV ? `«${nm}»: без интернета с ${$('#sched-off').value} до ${$('#sched-on').value}.` : `Расписание «${nm}» убрано.`);
      setTimeout(load, 3000);
    } catch(err){ toast(err.message, true); }
  };
  $('#sched-ok').onclick = () => { const a = $('#sched-off').value.replace(':', ''), b = $('#sched-on').value.replace(':', '');
    if(!/^\d{4}$/.test(a) || !/^\d{4}$/.test(b) || a === b) return toast('Укажи разное время выключения и включения.', true); send(a, b); };
  $('#sched-del').onclick = () => send('', '');
  $('#sched-cancel').onclick = () => dlg.close();
  dlg.showModal();
}

/* ---------- сеть: скорость, роутер, тест скорости и его история ---------- */
function renderNet(n){
  if(!n) return;
  $('#sp-rx').innerHTML = spd(n.rx);
  $('#sp-tx').innerHTML = spd(n.tx);
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
  $('#f-temp').textContent = y.temp != null ? y.temp + ' °C' : 'нет датчика';
  $('#f-up').textContent = upt(y.uptime);
  renderNet(y.net);
}
const flag = cc => /^[A-Z]{2}$/.test(cc || '') ? String.fromCodePoint(...[...cc].map(c => 0x1F1A5 + c.charCodeAt(0))) + ' ' : '';
const spd = bps => { const t = speed(bps).split(' '); return `${t[0]}<small>${t[1]}</small>`; };   // число крупно, «Мбит/с» мелко — не переносится
function renderSpeedCard(via, r){
  const box = $('#st-' + via);
  if(!r) return;
  box.querySelector('.st-down').innerHTML = spd(r.down);
  box.querySelector('.st-up').innerHTML = r.up ? spd(r.up) : (r.up_limited ? 'позже' : '—');
  box.querySelector('.st-lat').innerHTML = r.latency ? `${num(r.latency)}<small>ms</small>` : '—';
  box.querySelector('.st-meta').textContent = (r.ip ? `Выход: ${flag(r.country)}${r.ip}, ` : '') + 'проверено ' + ago(r.ts)
    + (r.server ? ` · ${r.server}, ${r.streams || 1} потока` : '')
    + (!r.up && r.up_limited ? ' · Cloudflare ограничил частые замеры отдачи, повтори через пару минут' : '');
}
function renderSpeedtest(sp){ if(!sp) return; renderSpeedCard('vpn', sp.vpn); renderSpeedCard('direct', sp.direct); }
function renderSpeedHist(){
  const rows = (hist && hist.speed) || [], svg = $('#spchart'), W = 600, H = 110;
  if(!rows.length){ svg.innerHTML = ''; $('#spchart-from').textContent = 'История появится после первых тестов'; return; }
  const from = Math.min(...rows.map(r => r[0])), to = Date.now() / 1000, span = Math.max(to - from, 86400);
  const max = Math.max(...rows.map(r => r[2])) * 1.15 || 1, x = t => ((t - from) / span) * (W - 10) + 5, y = v => H - (v / max) * (H - 10);
  let out = grid(W, H);
  for(const via of ['vpn', 'direct']){
    const p = rows.filter(r => r[1] === via);
    if(p.length > 1) out += `<polyline class="sp-${via}" points="${p.map(r => `${x(r[0]).toFixed(1)},${y(r[2]).toFixed(1)}`).join(' ')}"/>`;
    out += p.map(r => `<rect class="sp-${via}-pt" x="${(x(r[0]) - 2).toFixed(1)}" y="${(y(r[2]) - 2).toFixed(1)}" width="4" height="4"><title>${via === 'vpn' ? 'через VPN' : 'напрямую'}: ${speed(r[2])}, ${when(r[0])}</title></rect>`).join('');
  }
  svg.innerHTML = out;
  $('#spchart-from').textContent = when(from) + ' · до ' + Math.round(max / 1.15 / 1e6) + ' Мбит/с';
}

/* ---------- MyDirect: сайты напрямую ---------- */
async function loadMd(){
  try { md = await api('mydirect'); renderMd(); } catch(err){ $('#md-added').innerHTML = `<li class="empty">${esc(err.message)}</li>`; }
}
function renderMd(){
  if(!md) return;
  const plain = md.domains.filter(d => !/^[a-z]+:/.test(d));
  $('#md-count').textContent = `${md.domains.length} записей`;
  $('#md-all-sum').textContent = `Весь список (${md.domains.length})`;
  $('#md-added').innerHTML = md.added.map(d => `<li><span>${esc(d)}</span><button class="ed" data-mddel="${esc(d)}" aria-label="Убрать ${esc(d)}">✕</button></li>`).join('')
    || '<li class="empty">Пока ничего — добавь домен выше.</li>';
  const q = $('#md-search').value.trim().toLowerCase();
  const f = q ? md.domains.filter(d => d.toLowerCase().includes(q)) : plain;
  $('#md-found').innerHTML = f.slice(0, 60).map(d => `<li><span>${esc(d)}</span>${/^[a-z]+:/.test(d) ? '' : `<button class="ed" data-mddel="${esc(d)}" aria-label="Убрать ${esc(d)}">✕</button>`}</li>`).join('')
    + (f.length > 60 ? `<li class="empty">…и ещё ${f.length - 60}. Уточни поиск.</li>` : '') || '<li class="empty">Не найдено.</li>';
}
$('#md-search').addEventListener('input', renderMd);
$('#md-form').addEventListener('submit', async e => {
  e.preventDefault();
  const d = $('#md-in').value.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/.*$/, '').replace(/^www\./, '');
  if(!/^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$/.test(d)) return toast('Нужен домен вида site.ru', true);
  if(!await ask({title: `Пускать ${d} напрямую?`, text: 'Сайт будет открываться без VPN. VPN перезапустится, связь пропадёт на ~5 секунд.', ok: 'Добавить'})) return;
  const done = busy(e.submitter, 'Добавляю…');
  try { await api('diradd', '&d=' + encodeURIComponent(d)); $('#md-in').value = ''; toast(`${d} теперь напрямую.`); quietUntil = Date.now() + 12000; await loadMd(); }
  catch(err){ toast(err.message, true); } finally { done(); }
});
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-mddel]'); if(!b) return;
  const d = b.dataset.mddel;
  if(!await ask({title: `Убрать ${d} из MyDirect?`, text: 'Сайт снова пойдёт через VPN. VPN перезапустится, связь пропадёт на ~5 секунд.', ok: 'Убрать', danger: true})) return;
  b.disabled = true;
  try { await api('dirdel', '&d=' + encodeURIComponent(d)); toast(`${d} снова через VPN.`); quietUntil = Date.now() + 12000; await loadMd(); }
  catch(err){ toast(err.message, true); b.disabled = false; }
});

/* ---------- кнопки серверов ---------- */
async function connect(id){
  const nm = nodeName(id), direct = id === 'direct';
  if(!await ask(direct
    ? {title: 'Пустить весь трафик напрямую, без VPN?', ok: 'Напрямую', text: 'Все сайты и сервисы пойдут через провайдера, с IP провайдера. Правила Split остаются: MyDirect — напрямую, YouTube и Discord — через zapret, если он включён. Автопереключение на VPN не сработает, вернуть VPN — выбери сервер в таблице. Связь пропадёт на несколько секунд.'}
    : {title: `Подключить «${nm}»?`, text: 'VPN перезапустится, связь пропадёт на несколько секунд.', ok: 'Подключить'})) return;
  try {
    await api('switch', '&id=' + encodeURIComponent(id));
    state.current = direct ? '_direct' : id; render(); quietUntil = Date.now() + 15000;
    toast(`Подключаю «${nm}». Статус обновится через 10 секунд.`);
    setTimeout(load, 10000);
  } catch(err){ toast(err.message, true); }
}
$('#srv').addEventListener('click', e => { const tr = e.target.closest('tr[data-node]'); if(tr && !tr.classList.contains('cur')) connect(tr.dataset.node); });
$('#srv').addEventListener('keydown', e => { const tr = e.target.closest('tr[data-node]'); if(tr && (e.key === 'Enter' || e.key === ' ') && !tr.classList.contains('cur')){ e.preventDefault(); connect(tr.dataset.node); } });
$('#best').addEventListener('click', e => { const b = e.target.closest('[data-best]'); if(b) connect(b.dataset.best); });
$('#svcdir').addEventListener('click', async e => {
  const b = e.target.closest('[data-svcdir]'); if(!b) return;
  const n = b.dataset.svcdir, on = !(state.svc_direct || []).includes(n), x = services().find(v => v.name === n) || {};
  if(!await ask({title: on ? `Пускать ${n} напрямую?` : `${n} снова через VPN?`, ok: on ? 'Напрямую' : 'Через VPN',
    text: (on ? (x.kind === 'mc' ? 'IP сервера добавится в MyDirect — игра пойдёт без VPN, пинг станет как «Напрямую».' : `Домен ${x.host || ''} добавится в MyDirect.`) : 'Запись уберётся из MyDirect.') + ' VPN перезапустится, связь пропадёт на ~5 секунд.'})) return;
  const done = busy(b);
  try { await api('svcdirect', `&name=${encodeURIComponent(n)}&on=${on ? 1 : 0}`); state.svc_direct = on ? [...(state.svc_direct || []), n] : state.svc_direct.filter(v => v !== n);
    renderServers(state); toast(on ? `${n} теперь напрямую.` : `${n} снова через VPN.`); quietUntil = Date.now() + 12000; md = null; }
  catch(err){ toast(err.message, true); } finally { done(); }
});
$('#series').addEventListener('click', e => { const b = e.target.closest('[data-series]'); if(!b) return; series = b.dataset.series; renderSeries(); renderChart(); });
$('#log-filter').addEventListener('click', e => { const b = e.target.closest('[data-lv]'); if(!b) return; logLv = b.dataset.lv;
  document.querySelectorAll('#log-filter button').forEach(x => x.setAttribute('aria-pressed', x === b)); renderLog(); });

/* Свой список сервисов */
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
  f.hidden = false; f.scrollIntoView({block: 'nearest', behavior: 'smooth'});
});
$('#tg-add').addEventListener('click', () => { if($('#tg-rows').children.length < 8) $('#tg-rows').insertAdjacentHTML('beforeend', tgRow()); });
$('#tg-cancel').addEventListener('click', () => $('#tg-form').hidden = true);
$('#tg-rows').addEventListener('click', e => { if(e.target.closest('[data-del]')) e.target.closest('.tg-row').remove(); });
$('#tg-rows').addEventListener('change', e => {
  if(e.target.tagName === 'SELECT') e.target.closest('.tg-row').querySelector('.addr').placeholder = e.target.value === 'mc' ? 'mc.server.net:25565' : 'https://…';
});
$('#tg-rows').addEventListener('input', e => {
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
  const done = busy(e.submitter, 'Сохраняю…');
  try {
    await api('settargets', '&list=' + encodeURIComponent(rows.map(r => r.join('~')).join('!')));
    state.target_list = rows.map(([k, n, a]) => [k, n, k === 'mc' && !a.includes(':') ? a + ':25565' : a].join('|'));
    $('#tg-form').hidden = true;
    toast('Список сохранён. Роутер перемеряет через пару минут.');
    setTimeout(load, 20000);
  } catch(err){ toast(err.message, true); }
  finally { done(); }
});

/* ---------- Telegram-прокси и «роутер не на связи» ---------- */
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

function render(){
  renderHero(); renderChart(); renderSys(state.sys); renderSpeedtest(state.speed);
  renderDevices(state.devices); renderServers(state); renderLog();
}

/* ---------- вкладки (на телефоне — нижняя панель) ---------- */
const TABS = ['vpn', 'net', 'dev', 'log'];
const currentTab = () => { const h = location.hash.slice(1); return TABS.includes(h) ? h : 'vpn'; };
function showTab(){
  const t = currentTab();
  document.body.dataset.tab = t;                         // на телефоне вне VPN — короткая главная карточка
  document.querySelectorAll('[data-page]').forEach(p => p.hidden = p.dataset.page !== t);
  document.querySelectorAll('.tab').forEach(a => a.setAttribute('aria-selected', a.dataset.tab === t));
  document.querySelectorAll('.mtabs a').forEach(a => a.toggleAttribute('aria-current', a.dataset.tab === t));
  closeMenu();
  if(t === 'net'){ loadNet(); if(!md) loadMd(); }
}
window.addEventListener('hashchange', () => { showTab(); scrollTo(0, 0); });

/* ---------- загрузка ---------- */
async function load(){
  try { state = await api('status'); showDown(false); render(); }
  catch(e){
    if(Date.now() < quietUntil) return;
    if(e.down) showDown(true); else toast(e.message, true);
    renderHero();
  }
}

/* История, журнал, трафик и имена устройств — с сервера: есть даже когда роутер не на связи */
async function loadData(){
  try {
    const r = await fetch('/router/data?range=' + range, {cache: 'no-store', headers: {'X-FSR': csrf || '1'}});
    if(r.status === 401){ toLogin(); return; }
    if(!r.ok) return;
    hist = await r.json(); names = hist.names || {};
    renderMtg(hist.mtg); renderChart(); renderLog(); renderSpeedHist();
    if(state){ renderDevices(state.devices); renderHero(); }
    if(!$('#down').hidden) showDown(true);
  } catch {}
}

$('#range').addEventListener('click', e => {
  const b = e.target.closest('button[data-range]'); if(!b) return;
  range = b.dataset.range;
  document.querySelectorAll('#range button').forEach(x => x.setAttribute('aria-pressed', x === b));
  renderChart(); loadData();
});

async function loadNet(){
  if(document.hidden || currentTab() !== 'net' || Date.now() < quietUntil) return;
  try { renderNet(await api('net')); } catch {}
}

/* ---------- действия ---------- */
async function pingAll(){
  const undo = [busy($('#ping-btn'), 'Проверяю…'), busy($('#ping-all'), 'Проверяю, ~20 сек…')];
  try { state = await api('ping'); render(); toast('Проверка серверов завершена.'); }
  catch(err){ toast(err.message, true); }
  finally { undo.forEach(f => f()); }
}
$('#ping-btn').addEventListener('click', pingAll);
$('#ping-all').addEventListener('click', pingAll);

/* Тест скорости в браузере: само устройство → роутер → VPN → ближайший сервер Cloudflare (как обычный трафик).
   Загрузка — 6 потоков, отдача — 4 потока, по 8 секунд; первая секунда (разгон) не считается. */
const CFS = 'https://speed.cloudflare.com';
const bq = () => '&r=' + Math.random().toString(36).slice(2);
async function bLatency(){
  let best = 1e9, colo = '';
  for(let i = 0; i < 6; i++){
    const t = performance.now(), r = await fetch(CFS + '/__down?bytes=0' + bq(), {cache: 'no-store'});
    await r.arrayBuffer(); best = Math.min(best, performance.now() - t); colo = r.headers.get('cf-meta-colo') || colo;
  }
  return [Math.round(best), colo];
}
async function bMeasure(kind, show){
  const SEC = 8, WARM = 1000, t0 = performance.now(); let bytes = 0, stop = false;
  const add = n => { if(performance.now() - t0 > WARM) bytes += n; };
  const down = async () => { while(!stop){ const r = await fetch(CFS + '/__down?bytes=50000000' + bq(), {cache: 'no-store'}); const rd = r.body.getReader();
    for(;;){ const {done, value} = await rd.read(); if(done) break; add(value.length); if(stop){ rd.cancel().catch(() => {}); break; } } } };
  const blob = new Blob([new Uint8Array(2e6)]);
  const up = async () => { while(!stop){ await fetch(CFS + '/__up?' + bq().slice(1), {method: 'POST', body: blob}); add(blob.size); } };
  const ps = [...Array(kind === 'down' ? 6 : 4)].map(() => (kind === 'down' ? down : up)().catch(() => {}));
  const rate = () => bytes * 8 / Math.max(0.001, (performance.now() - t0 - WARM) / 1000);
  const tick = setInterval(() => { if(performance.now() - t0 > WARM) show(rate()); }, 250);
  await new Promise(r => setTimeout(r, SEC * 1000));
  const res = rate(); stop = true; clearInterval(tick); Promise.allSettled(ps);
  return res;
}
$('#bspeed').addEventListener('click', async e => {
  const btn = e.currentTarget, box = $('#st-dev'), set = (c, h) => box.querySelector(c).innerHTML = h;
  btn.disabled = true; btn.setAttribute('aria-busy', 'true'); btn.textContent = 'Идёт тест, ~20 сек…';
  ['.st-down', '.st-up', '.st-lat'].forEach(c => set(c, '—'));
  try {
    box.querySelector('.st-meta').textContent = 'Меряю задержку…';
    const [lat, colo] = await bLatency(); set('.st-lat', `${lat}<small>ms</small>`);
    box.querySelector('.st-meta').textContent = 'Меряю загрузку…';
    const d = await bMeasure('down', v => set('.st-down', spd(v))); set('.st-down', spd(d));
    box.querySelector('.st-meta').textContent = 'Меряю отдачу…';
    const u = await bMeasure('up', v => set('.st-up', spd(v))); set('.st-up', spd(u));
    box.querySelector('.st-meta').textContent = `Это устройство через VPN · сервер Cloudflare ${colo || ''} · ${when(Date.now() / 1000)}. Загрузка 6 потоков, отдача 4, по 8 секунд.`;
    toast(`Это устройство: ${speed(d)} загрузка, ${speed(u)} отдача, задержка ${lat} ms.`);
  } catch(err){
    console.warn('browser speedtest', err);
    box.querySelector('.st-meta').textContent = 'Не получилось: сервер теста не ответил. Если страница открыта не через VPN или Cloudflare заблокирован — повтори позже.';
  } finally { btn.disabled = false; btn.removeAttribute('aria-busy'); btn.textContent = 'Запустить'; }
});

document.querySelectorAll('[data-speed]').forEach(btn => btn.addEventListener('click', async () => {
  const via = btn.dataset.speed, all = document.querySelectorAll('[data-speed]');
  all.forEach(x => x.disabled = true); btn.setAttribute('aria-busy', 'true'); btn.textContent = 'Идёт тест, ~35 сек…';
  $('#st-' + via).querySelector('.st-meta').textContent = 'Измеряю загрузку, потом отдачу…';
  try {
    const r = await api('speedtest', '&via=' + via);
    if(state){ state.speed = state.speed || {}; state.speed[via] = r; }
    renderSpeedCard(via, r);
    toast(`Тест ${via === 'vpn' ? 'через VPN' : 'напрямую'}: ${speed(r.down)} загрузка, ${speed(r.up)} отдача.`);
    setTimeout(loadData, 5000);                            // точка в истории появится после записи на сервере
  } catch(err){ toast(err.message, true); }
  finally { all.forEach(x => x.disabled = false); btn.removeAttribute('aria-busy'); btn.textContent = 'Запустить'; }
}));

const ACTIONS = {
  restart: { title: 'Перезапустить VPN?', text: 'Связь через VPN пропадёт на несколько секунд.', ok: 'Перезапустить', busy: 'Перезапускаю…', done: 'VPN перезапускается.', quiet: 15000 },
  update:  { title: 'Обновить подписку?', text: 'Список серверов nosok скачается заново, это займёт до минуты.', ok: 'Обновить', busy: 'Обновляю…', done: 'Подписка обновляется, список серверов обновится примерно через минуту.', quiet: 0 },
  reboot:  { title: 'Перезагрузить роутер?', text: 'Интернет дома пропадёт на 1–2 минуты, панель будет недоступна, пока роутер не вернётся.', ok: 'Перезагрузить', danger: true, busy: 'Перезагружаю…', done: 'Роутер перезагружается. Страница сама обновится, когда он вернётся.', quiet: 150000 },
};
document.addEventListener('click', async e => {     // кнопки data-act: в главной карточке и в блоке «Роутер»
  const b = e.target.closest('button[data-act]'); if(!b) return;
  const a = ACTIONS[b.dataset.act];
  if(!await ask(a)) return;
  const done = busy(b, a.busy);
  try {
    await api(b.dataset.act);
    toast(a.done); quietUntil = Date.now() + a.quiet;
    setTimeout(load, b.dataset.act === 'update' ? 60000 : Math.max(10000, a.quiet));
    done(Math.min(a.quiet || 5000, 30000));
  } catch(err){ toast(err.message, true); done(); }
});


/* ---------- YouTube и Discord через zapret ---------- */
let zap = null, zapPoll = 0;
const yes = (v, a, b) => v ? `<b class="ok">${a}</b>` : `<b class="slow">${b}</b>`;
function renderZap(){
  const box = $('#zap'); if(!box) return;
  if(!zap || zap.absent){ box.hidden = true; return; }
  box.hidden = false;
  const z = zap, on = !!z.enabled, t = $('#zap-tgl');
  t.textContent = on ? 'включён' : 'выключен';
  t.setAttribute('aria-checked', on); t.classList.toggle('on', on);
  t.disabled = !z.installed || z.busy;
  $('#zap-strat').value = String(z.strategy || 3); $('#zap-strat').disabled = !z.installed || z.busy;
  $('#zap-check').disabled = !z.installed || z.checking;
  $('#zap-check').textContent = z.checking ? 'Проверяю…' : 'Проверить';
  const work = z.engine && z.nft && z.route_live;
  // одна строка вместо таблицы: что сейчас происходит с YouTube и Discord
  $('#zap-sum').innerHTML = z.busy ? '<i class="mid">●</i> Применяю… PassWall перезапускается'
    : on && work ? `<i class="ok">●</i> YouTube и Discord — <b>напрямую</b>, с IP провайдера${z.nft ? ` <small>${num(z.pkts_tcp)} TCP · ${num(z.pkts_udp)} QUIC</small>` : ''}`
    : on ? '<i class="mid">●</i> Включён, но работает не полностью'
    : '<i class="off">●</i> YouTube и Discord — через VPN, как всё остальное';
  const items = [
    ['Выбрано', on ? '<b>включить</b>' : '<b>выключить</b>'],
    ['Служба nfqws', yes(z.engine, 'работает', on ? 'не работает' : 'остановлена')],
    ['Правила nftables', yes(z.nft, 'есть', 'нет')],
    ['Маршрут', z.route_live ? '<b class="ok">напрямую (IP провайдера)</b>' : '<b>через VPN</b>'],
  ];
  if(z.nft) items.push(['Обработано пакетов', `<b>${num(z.pkts_tcp)} TCP · ${num(z.pkts_udp)} QUIC</b>`]);
  $('#zap-st').innerHTML = items.map(([k, v]) => `<li><span>${k}</span>${v}</li>`).join('');
  let e = '';
  if(!z.installed) e = 'zapret не установлен на роутере (нет nfqws, списков или модуля ядра).';
  else if(z.error) e = z.error;
  else if(!z.busy && on && !work) e = 'Расхождение: режим включён, но ' + [!z.engine && 'служба не работает', !z.nft && 'нет правил nftables', !z.route_live && 'маршрут PassWall не применён'].filter(Boolean).join(', ') + '. Сторож попробует исправить в течение минуты.';
  else if(!z.busy && !on && (z.engine || z.nft || z.route_cfg)) e = 'Расхождение: режим выключен, но часть правил ещё активна. Сторож уберёт их в течение минуты.';
  $('#zap-err').hidden = !e; $('#zap-err').textContent = e;
  // результат проверки — плитки как под графиком: имя и задержка, подробности в подсказке
  const c = z.check, has = c && c.list && c.list.length;
  $('#zap-ck').innerHTML = !has ? '' : c.list.map(x => `<div class="fact" title="${x.ok ? (x.queued ? 'обработано zapret: ' + num(x.queued) + ' пак.' : 'без обработки zapret') : 'не открывается'}"><span>${esc(x.name)}</span>`
    + (x.ok ? `<b class="ok">${num(x.ms)} ms</b>` : '<b class="slow">нет</b>') + '</div>').join('');
  $('#zap-when').hidden = !has;
  if(has) $('#zap-when').textContent = 'Проверено ' + when(c.ts) + (c.via === 'isp' ? ' · Discord видит IP провайдера' : c.via === 'vpn' ? ' · Discord видит IP VPN' : '');
}
async function loadZap(){
  try { zap = await api('zapret'); } catch(err){ if(!zap) return; zap = {...zap, error: err.message}; }
  renderZap();
  clearTimeout(zapPoll);
  if(zap && (zap.busy || zap.checking)) zapPoll = setTimeout(loadZap, 3000);
}
$('#zap-tgl').addEventListener('click', async () => {
  if(!zap) return;
  const on = !zap.enabled;
  const ok = await ask(on
    ? {title: 'Включить zapret для YouTube и Discord?', text: 'YouTube и Discord пойдут напрямую через провайдера, с IP провайдера (не через VPN). Остальное не меняется. VPN перезапустится примерно на 5 секунд, открытые видео и звонки переподключатся.', ok: 'Включить'}
    : {title: 'Выключить zapret?', text: 'YouTube и Discord снова пойдут через VPN, обработка zapret остановится. VPN перезапустится примерно на 5 секунд.', ok: 'Выключить'});
  if(!ok) return;
  const done = busy($('#zap-tgl'), on ? 'Включаю…' : 'Выключаю…');
  try { await api('zapretset', '&on=' + (on ? 1 : 0)); quietUntil = Date.now() + 15000; toast(on ? 'Включаю zapret — около 10 секунд.' : 'Выключаю zapret — около 10 секунд.'); }
  catch(err){ toast(err.message, true); }
  finally { done(); setTimeout(loadZap, 1500); }
});
$('#zap-strat').addEventListener('change', async e => {
  try { await api('zapretstrat', '&n=' + encodeURIComponent(e.target.value)); toast('Стратегия ' + e.target.value + ' выбрана.'); }
  catch(err){ toast(err.message, true); }
  setTimeout(loadZap, 2000);
});
$('#zap-check').addEventListener('click', async () => {
  try { await api('zapretcheck'); zap = {...zap, checking: true}; renderZap(); setTimeout(loadZap, 3000); }
  catch(err){ toast(err.message, true); }
});

/* Telegram через tg-ws-proxy: MTProto-прокси на роутере для устройств дома (ходит к Telegram через Cloudflare, мимо VPN) */
let tgws = null;
function renderTgws(){
  const box = $('#tgws'); if(!box) return;
  if(!tgws || tgws.absent || !tgws.installed){ box.hidden = true; return; }
  box.hidden = false;
  const on = !!tgws.enabled, t = $('#tgws-tgl'), ok = tgws.running && tgws.listening;
  t.textContent = on ? 'включён' : 'выключен'; t.setAttribute('aria-checked', on); t.classList.toggle('on', on);
  $('#tgws-link').hidden = !on;
  if(!on) $('#tgws-out').hidden = true;
  $('#tgws-sum').innerHTML = !on ? '<i class="off">●</i> Выключен — Telegram идёт как обычно (через VPN)'
    : ok ? `<i class="ok">●</i> Прокси <b>${esc(tgws.host)}:${num(tgws.port)}</b> — Telegram через Cloudflare, мимо VPN`
    : '<i class="mid">●</i> Запускается… (если не пройдёт — служба перезапустится сама)';
}
async function loadTgws(){ try { tgws = await api('tgws'); } catch(err){ return; } renderTgws(); }
$('#tgws-tgl').addEventListener('click', async () => {
  if(!tgws) return;
  const on = !tgws.enabled;
  const ok = await ask(on
    ? {title: 'Включить прокси Telegram?', text: 'На роутере запустится MTProto-прокси для устройств дома. Telegram на устройствах с этим прокси пойдёт через Cloudflare с IP провайдера, а не через VPN. VPN и остальные сайты не меняются.', ok: 'Включить'}
    : {title: 'Выключить прокси Telegram?', text: 'Устройства, где он указан, перестанут подключаться через него — в Telegram нужно будет выключить прокси.', ok: 'Выключить'});
  if(!ok) return;
  const done = busy($('#tgws-tgl'), on ? 'Включаю…' : 'Выключаю…');
  try { await api('tgwsset', '&on=' + (on ? 1 : 0)); } catch(err){ toast(err.message, true); }
  finally { done(); setTimeout(loadTgws, 3000); setTimeout(loadTgws, 8000); }
});
$('#tgws-link').addEventListener('click', async () => {
  try { const r = await api('tgwslink'); $('#tgws-url').textContent = r.link; $('#tgws-out').hidden = false; }
  catch(err){ toast(err.message, true); }
});
$('#tgws-copy').addEventListener('click', async () => {
  const t = $('#tgws-url').textContent;
  try { await navigator.clipboard.writeText(t); toast('Ссылка скопирована — открой её на устройстве дома или отправь себе в «Избранное».'); }
  catch { toast('Не удалось скопировать — выдели ссылку вручную.', true); }
});

/* Опрос: один запрос каждого вида за раз (медленный ответ не копит очередь), во вкладке в фоне — пауза,
   при возврате на вкладку — сразу свежие данные. Таймеры заводятся один раз, слушатели — делегированные. */
function every(ms, fn){
  let busyNow = false;
  const tick = async () => { if(document.hidden || busyNow) return; busyNow = true; try { await fn(); } finally { busyNow = false; } };
  setInterval(tick, ms);
  return tick;
}
const tLoad = every(30000, load), tData = every(60000, loadData), tZap = every(30000, loadZap), tTg = every(60000, loadTgws);
every(3000, loadNet);
setInterval(tickUpdated, 5000);
document.addEventListener('visibilitychange', () => { if(!document.hidden){ tLoad(); tData(); tZap(); tTg(); } });

showTab();
tLoad();
tZap();
tTg();
tData();
csrfToken().catch(() => {});

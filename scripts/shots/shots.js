// Скриншоты панели (web/) на демо-данных, без роутера и сервера. Запуск — см. README.md рядом.
const fs = require('fs'), path = require('path');
let chromium; try { ({ chromium } = require('playwright')); } catch(e){ ({ chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright')); }
const { status, data, MD, ZAP } = require('./demo_data.js');
if(process.env.DIRECT_MODE) status.current = '_direct';   // режим «Напрямую (без VPN)»
const WEB = path.resolve(__dirname, '../../web');
const OUT = path.resolve(process.env.OUT || path.join(__dirname, 'out')); fs.mkdirSync(OUT, {recursive: true});
// цифры — Minecraft-шрифт сайта (лежит в project_hex); нет файла — цифры будут шрифтом Press Start 2P
const FONT = process.env.MC_FONT || path.resolve(__dirname, '../../../project_hex/sites/fspirat.ru/admin/mc.ttf');
const CSP = "default-src 'none'; script-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'";
const TYPES = {'.js': 'application/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json'};
const READ = new Set(['status', 'net', 'pingone', 'mydirect', 'zapret']);
const errs = []; const THEME = process.env.THEME || 'dark'; const PFX = process.env.PFX || '';
(async () => {
  const exe = process.env.CHROME || ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome'].find(f => fs.existsSync(f));
  const b = await chromium.launch(exe ? {executablePath: exe} : {});
  async function page(w, h, hash){
    const p = await b.newPage({colorScheme: THEME, viewport: {width: w, height: h}, deviceScaleFactor: w < 800 ? 2 : 1, hasTouch: w < 800, isMobile: w < 800});
    p.on('pageerror', e => errs.push(`[${w}${hash}] ${e.message}`));
    p.on('console', m => { if(m.type() === 'error') errs.push(`[${w}${hash}] console: ${m.text()}`); });
    await p.route('**/*', async r => {
      const req = r.request(), u = new URL(req.url());
      if(u.pathname === '/router/') return r.fulfill({body: fs.readFileSync(WEB + '/index.html', 'utf8'), contentType: 'text/html', headers: {'Content-Security-Policy': CSP}});
      if(u.pathname === '/admin/mc.ttf') return fs.existsSync(FONT) ? r.fulfill({body: fs.readFileSync(FONT), contentType: 'font/ttf'}) : r.fulfill({status: 404, body: ''});
      if(u.pathname.startsWith('/router/') && !u.pathname.endsWith('/') && fs.existsSync(WEB + u.pathname.slice(7)))
        return r.fulfill({body: fs.readFileSync(WEB + u.pathname.slice(7)), contentType: TYPES[path.extname(u.pathname)] || 'application/octet-stream'});
      if(u.pathname === '/router/api'){
        const a = u.searchParams.get('action');
        const body = a === 'zapret' ? ZAP[process.env.ZAP_STATE || 'ok'] : a === 'net' ? status.sys.net : a === 'mydirect' ? MD : READ.has(a) ? status : {ok: true};
        return r.fulfill({body: JSON.stringify(body), contentType: 'application/json'});
      }
      if(u.pathname === '/router/data'){
        if(u.searchParams.has('csrf')) return r.fulfill({body: '{"csrf":"DEMO"}', contentType: 'application/json'});
        return r.fulfill({body: JSON.stringify(data(u.searchParams.get('range') || 'day')), contentType: 'application/json'});
      }
      return r.abort();
    });
    await p.goto('https://fspirat.online/router/' + hash);
    await p.waitForTimeout(1500);
    return p;
  }
  const jobs = (process.argv[2] === 'm') ? [] : [[1440, 900, '#vpn', 'panel-vpn', true], [1440, 900, '#net', 'panel-net', true], [1440, 900, '#dev', 'panel-devices', true]]; jobs.push([390, 844, '#vpn', 'panel-mobile', false]);
  for(const [w, h, hash, name, full] of jobs){
    const p = await page(w, h, hash);
    await p.screenshot({path: `${OUT}/${PFX}${name}.png`, fullPage: full});
    const sz = await p.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.scrollHeight]);
    console.log(name, sz.join('x'));
    await p.close();
  }
  if(process.env.DEAD){
    const p = await page(1440, 900, '#vpn'); await p.click('#dead-sum'); await p.waitForTimeout(300);
    const bb = await p.locator('#dead-box').boundingBox(); await p.screenshot({path: `${OUT}/${PFX}dead.png`, clip: {x: bb.x - 10, y: bb.y - 10, width: bb.width + 20, height: bb.height + 20}}); await p.close();
  }
  if(process.env.ZAPSHOT){   // только блок zapret
    const p = await page(1440, 900, '#vpn'); const bb = await p.locator('#zap').boundingBox();
    await p.screenshot({path: `${OUT}/${PFX}zapret.png`, clip: {x: bb.x - 8, y: bb.y - 8, width: bb.width + 16, height: bb.height + 16}}); await p.close();
  }
  if(process.env.SIDE){   // правая колонка вкладки VPN: график, zapret, журнал, устройства
    const p = await page(+(process.env.SIDE_W || 1440), 1800, '#vpn'); const bb = await p.locator('[data-page="vpn"] .side').boundingBox();
    await p.screenshot({path: `${OUT}/${PFX}side.png`, fullPage: true, clip: {x: bb.x - 8, y: bb.y - 8, width: bb.width + 16, height: bb.height + 16}}); await p.close();
  }
  if(process.env.EXTRA){
    const p = await page(1440, 900, '#dev');
    await p.click('.dev .more'); await p.waitForTimeout(300);
    await p.screenshot({path: `${OUT}/${PFX}menu.png`, clip: {x: 700, y: 330, width: 640, height: 420}});
    await p.keyboard.press('Escape'); await p.waitForTimeout(200);
    await p.click('[data-act="restart"]').catch(async () => { await p.click('text=Перезапустить VPN'); }); await p.waitForTimeout(400);
    await p.screenshot({path: `${OUT}/${PFX}dialog.png`});
    await p.close();
  }
  await b.close();
  console.log(errs.length ? errs.join('\n') : 'no page errors');
})().catch(e => { console.error(e); process.exit(1); });

<?php
// Команды роутеру из Telegram (@FSRouter_bot). Telegram присылает сюда каждое сообщение (webhook):
//   POST /router/tg-hook — без входа в панель, но только с IP Telegram (nginx) и с секретом в заголовке
//   X-Telegram-Bot-Api-Secret-Token (tgbot.json, создаётся при выкладке). Слушается только чат владельца (telegram.json).
// Действия идут в тот же CGI роутера, что и у панели (туннель 127.0.0.1:8081), опасные — с кнопкой подтверждения.
// Каждая команда пишется в журнал действий. Токены не логируются.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';

define('ROUTER', getenv('FSR_ROUTER') ?: 'http://127.0.0.1:8081/cgi-bin/fspirat');
define('WATCH', getenv('FSR_WATCH') ?: '/var/lib/fspirat');

$cfg = json_decode((string)@file_get_contents(fsr_dir() . '/tgbot.json'), true) ?: [];
$tg = fsr_tg();
if (!$tg || empty($cfg['secret']) || !hash_equals($cfg['secret'], (string)($_SERVER['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'] ?? ''))) {
    http_response_code(403); exit;
}
$u = json_decode((string)file_get_contents('php://input'), true) ?: [];
// Telegram ждёт быстрый ответ — отвечаем сразу, работа (до минуты для теста скорости) — после
http_response_code(200);
if (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
set_time_limit(120);

/* ---------- Telegram ---------- */
function tg(string $method, array $p): ?array {
    global $tg;
    $raw = @file_get_contents((getenv('FSR_TG_API') ?: 'https://api.telegram.org') . '/bot' . $tg['token'] . '/' . $method, false, stream_context_create(['http' => [
        'method' => 'POST', 'header' => 'Content-Type: application/json', 'timeout' => 10, 'ignore_errors' => true,
        'content' => json_encode($p, JSON_UNESCAPED_UNICODE)]]));
    return json_decode((string)$raw, true);
}
function say(string $text, ?array $kb = null): void {
    global $tg;
    $p = ['chat_id' => $tg['chat'], 'text' => $text, 'parse_mode' => 'HTML', 'disable_web_page_preview' => true];
    if ($kb) $p['reply_markup'] = ['inline_keyboard' => $kb];
    tg('sendMessage', $p);
}
function edit(int $mid, string $text): void {
    global $tg;
    tg('editMessageText', ['chat_id' => $tg['chat'], 'message_id' => $mid, 'text' => $text, 'parse_mode' => 'HTML']);
}
$h = fn($s) => htmlspecialchars((string)$s, ENT_QUOTES);

/* ---------- роутер ---------- */
function router(string $action, array $q = [], bool $post = false, int $timeout = 30): ?array {
    $tok = trim((string)@file_get_contents(fsr_dir() . '/router.token'));
    $url = ROUTER . '?' . http_build_query(['action' => $action] + $q);
    $raw = @file_get_contents($url, false, stream_context_create(['http' => [
        'method' => $post ? 'POST' : 'GET', 'header' => "Cookie: fspirat_token=$tok\r\nContent-Length: 0", 'timeout' => $timeout, 'ignore_errors' => true]]));
    $j = json_decode((string)$raw, true);
    return is_array($j) ? $j : null;
}
function names(): array { $j = json_decode((string)@file_get_contents(fsr_dir() . '/names.json'), true); return is_array($j) ? $j : []; }
function dev_name(array $d): string { $n = names()[strtolower($d['mac'] ?? '')] ?? ''; return $n !== '' ? $n : (($d['name'] ?? '') !== '' ? $d['name'] : ($d['ip'] ?? $d['mac'])); }
function node_name(array $s, string $id): string { foreach ($s['ping']['nodes'] ?? [] as $n) if ($n['id'] === $id) return trim($n['name']); return $id; }
function gb(float $b): string { return $b >= 1073741824 ? round($b / 1073741824, 1) . ' ГБ' : round($b / 1048576) . ' МБ'; }
function mbit(float $bps): string { return $bps >= 1e6 ? round($bps / 1e6, $bps >= 1e8 ? 0 : 1) . ' Мбит/с' : round($bps / 1e3) . ' кбит/с'; }
function down_msg(): string { return '⚠️ Роутер не отвечает: туннель до сервера оборван или дома нет интернета. Попробуй через пару минут.'; }
// поиск по имени: сначала точное совпадение, потом «содержит» (без регистра)
function pick(array $items, string $q, callable $name): array {
    $q = mb_strtolower(trim($q)); $exact = []; $part = [];
    foreach ($items as $it) { $n = mb_strtolower($name($it)); if ($n === $q) $exact[] = $it; elseif ($q !== '' && str_contains($n, $q)) $part[] = $it; }
    return $exact ?: $part;
}
// кнопка подтверждения: действие + время (кнопки старше 10 минут не работают)
$cb = fn(string $what) => $what . '|' . time();

/* ---------- команды ---------- */
function cmd_status(): void {
    global $h;
    $s = router('status');
    if (!$s) { say(down_msg()); return; }
    $p = $s['ping'] ?? []; $ok = ($s['running'] ?? false) && (($p['real'] ?? 0) > 0 || !($p['socks'] ?? false));
    $alive = count(array_filter($p['nodes'] ?? [], fn($n) => $n['ms'] > 0));
    $svc = implode(' · ', array_map(fn($x) => $h($x['name']) . ' ' . ($x['vpn'] > 0 ? $x['vpn'] : '—'), $s['targets']['list'] ?? []));
    $on = count(array_filter($s['devices'] ?? [], fn($d) => $d['online'] ?? false));
    $sub = ($s['sub']['expire'] ?? 0) ? 'подписка ещё ' . floor(($s['sub']['expire'] - time()) / 86400) . ' дн.' : '';
    say(($ok ? '🟢 Всё работает' : '🔴 VPN не проходит') . "\n"
        . 'Сервер: <b>' . $h(node_name($s, $s['current'] ?? '')) . '</b> · ' . (($p['real'] ?? 0) ? $p['real'] . ' ms' : 'нет ответа') . "\n"
        . ($svc ? $svc . "\n" : '') . "Серверов отвечает: $alive из " . count($p['nodes'] ?? []) . "\n"
        . "Устройств в сети: $on" . ($sub ? " · $sub" : '') . "\n"
        . 'Роутер: ЦП ' . ($s['sys']['cpu'] ?? '?') . '%, ' . (isset($s['sys']['temp']) ? $s['sys']['temp'] . ' °C, ' : '') . 'без перезагрузки ' . floor(($s['sys']['uptime'] ?? 0) / 86400) . ' дн.');
}
function cmd_servers(): void {
    global $h, $cb;
    $s = router('status');
    if (!$s) { say(down_msg()); return; }
    $nodes = $s['ping']['nodes'] ?? [];
    usort($nodes, fn($a, $b) => [!($a['own'] ?? false), $a['ms'] <= 0, $a['ms']] <=> [!($b['own'] ?? false), $b['ms'] <= 0, $b['ms']]);
    $lines = []; $kb = [];
    foreach ($nodes as $n) {
        $cur = $n['id'] === ($s['current'] ?? '');
        $lines[] = ($cur ? '▶️ ' : '') . $h(trim($n['name'])) . (($n['own'] ?? false) ? ' (свой)' : '') . ' — ' . ($n['ms'] > 0 ? $n['ms'] . ' ms' : 'не отвечает');
        if (!$cur && $n['ms'] > 0) $kb[] = [['text' => 'Подключить ' . trim($n['name']), 'callback_data' => $cb('sw:' . $n['id'])]];
    }
    say("<b>Серверы</b> (▶️ — сейчас)\n" . implode("\n", $lines) . "\n\nНажми кнопку — сервер подключится, VPN перезапустится на ~5 секунд.", array_slice($kb, 0, 14));
}
function cmd_vpn(string $q): void {
    global $h, $cb;
    $s = router('status');
    if (!$s) { say(down_msg()); return; }
    if (trim($q) === '') { cmd_servers(); return; }
    $m = pick($s['ping']['nodes'] ?? [], $q, fn($n) => trim($n['name']));
    if (!$m) { say('Не нашёл сервер «' . $h($q) . '». Список — /servers'); return; }
    if (count($m) > 1) { say('Подходят несколько: ' . implode(', ', array_map(fn($n) => $h(trim($n['name'])), $m)) . '. Уточни название или выбери в /servers'); return; }
    $n = $m[0];
    if ($n['id'] === ($s['current'] ?? '')) { say('«' . $h(trim($n['name'])) . '» уже подключён.'); return; }
    say('Подключить <b>' . $h(trim($n['name'])) . '</b>' . ($n['ms'] > 0 ? ' (' . $n['ms'] . ' ms)' : ' (сейчас не отвечает!)') . "?\nVPN перезапустится, связь пропадёт на ~5 секунд.",
        [[['text' => 'Да, подключить', 'callback_data' => $cb('sw:' . $n['id'])], ['text' => 'Отмена', 'callback_data' => 'no']]]);
}
function cmd_devices(): void {
    global $h;
    $s = router('status');
    if (!$s) { say(down_msg()); return; }
    $tr = json_decode((string)@file_get_contents(WATCH . '/traffic.json'), true)['days'][gmdate('Y-m-d')] ?? [];
    $on = array_filter($s['devices'] ?? [], fn($d) => $d['online'] ?? false);
    usort($on, fn($a, $b) => ($tr[strtolower($b['mac'])][1] ?? 0) <=> ($tr[strtolower($a['mac'])][1] ?? 0));
    $band = ['5g' => '5 ГГц', '6g' => '6 ГГц', '2g' => '2,4 ГГц', 'wired' => 'кабель'];
    $lines = array_map(function ($d) use ($h, $tr, $band) {
        $t = $tr[strtolower($d['mac'])][1] ?? 0;
        return '• <b>' . $h(dev_name($d)) . '</b> — ' . ($band[$d['band'] ?? ''] ?? '') . ($t ? ' · ↓' . gb($t) : '')
            . (($d['blocked'] ?? false) ? ' · ⛔ без интернета' : '') . (($d['direct'] ?? false) ? ' · мимо VPN' : '');
    }, $on);
    say('<b>В сети: ' . count($on) . '</b> (трафик — за сегодня)' . "\n" . implode("\n", $lines));
}
function cmd_block(string $q, bool $block): void {
    global $h, $cb;
    $s = router('status');
    if (!$s) { say(down_msg()); return; }
    if (trim($q) === '') { say('Напиши имя устройства: ' . ($block ? '/block' : '/unblock') . ' телевизор. Список — /devices'); return; }
    $m = pick($s['devices'] ?? [], $q, 'dev_name');
    if (!$m) $m = array_values(array_filter($s['devices'] ?? [], fn($d) => ($d['ip'] ?? '') === trim($q) || strtolower($d['mac'] ?? '') === strtolower(trim($q))));
    if (!$m) { say('Не нашёл устройство «' . $h($q) . '». Список — /devices'); return; }
    if (count($m) > 1) { say('Подходят несколько: ' . implode(', ', array_map(fn($d) => $h(dev_name($d)), $m)) . '. Уточни имя.'); return; }
    $d = $m[0]; $nm = $h(dev_name($d));
    if (($d['blocked'] ?? false) === $block) { say("У «{$nm}» интернет уже " . ($block ? 'выключен.' : 'включён.')); return; }
    say(($block ? "Выключить интернет «<b>{$nm}</b>»?\nУстройство останется в Wi-Fi, но сайты и приложения перестанут открываться." : "Включить интернет «<b>{$nm}</b>»?"),
        [[['text' => $block ? 'Да, выключить' : 'Да, включить', 'callback_data' => $cb(($block ? 'bl:' : 'ub:') . strtolower($d['mac']))], ['text' => 'Отмена', 'callback_data' => 'no']]]);
}
function cmd_speed(): void {
    say('⏱ Тест скорости с роутера без VPN (Selectel, Россия), около 35 секунд…');
    $r = router('speedtest', ['via' => 'direct'], true, 90);
    if (!$r || isset($r['error'])) { say(($r['error'] ?? '') === 'busy' ? 'Тест уже идёт — дождись результата.' : '⚠️ Тест не удался. ' . (!$r ? down_msg() : '')); return; }
    say("📶 Напрямую, без VPN\nЗагрузка: <b>" . mbit($r['down']) . "</b>\nОтдача: <b>" . ($r['up'] ? mbit($r['up']) : '—') . "</b>\nЗадержка: " . (int)$r['latency'] . ' ms');
}
function cmd_confirm(string $what, string $title, string $text, string $ok): void {
    global $cb;
    say("<b>$title</b>\n$text", [[['text' => $ok, 'callback_data' => $cb($what)], ['text' => 'Отмена', 'callback_data' => 'no']]]);
}
function cmd_report(): void {
    @touch(fsr_dir() . '/report_now');       // fspirat-watch (cron, раз в минуту) пришлёт отчёт
    say('📊 Отчёт придёт в течение минуты.');
}
function cmd_ping(): void {
    global $h;
    say('↻ Перемеряю все серверы и сервисы, около 20 секунд…');
    $s = router('ping', [], true, 90);
    if (!$s || !isset($s['ping'])) { say(down_msg()); return; }
    $nodes = $s['ping']['nodes'] ?? [];
    usort($nodes, fn($a, $b) => [!($a['own'] ?? false), $a['ms'] <= 0, $a['ms']] <=> [!($b['own'] ?? false), $b['ms'] <= 0, $b['ms']]);
    $svc = fn($id) => ($id === ($s['current'] ?? '') ? ($s['targets'] ?? null) : ($s['svc'][$id] ?? null))['list'] ?? [];
    $lines = array_map(function ($n) use ($s, $h, $svc) {
        $v = implode(' · ', array_map(fn($x) => $x['vpn'] > 0 ? $x['vpn'] : '—', $svc($n['id'])));
        return (($n['id'] === ($s['current'] ?? '')) ? '▶️ ' : '') . $h(trim($n['name'])) . ' — <b>' . ($n['ms'] > 0 ? $n['ms'] . ' ms' : 'нет ответа') . '</b>' . ($v ? "\n      $v" : '');
    }, $nodes);
    $names = array_map(fn($x) => $x['name'], $s['targets']['list'] ?? []);
    $best = [];
    foreach ($names as $i => $nm) {
        $b = null; foreach ($nodes as $n) { $v = $svc($n['id'])[$i]['vpn'] ?? 0; if ($v > 0 && $n['ms'] > 0 && (!$b || $v < $b[1])) $b = [$n, $v]; }
        if ($b) $best[] = $h($nm) . ': ' . $h(trim($b[0]['name'])) . ' ' . $b[1] . ' ms';
    }
    say("<b>Пинг всех</b> (▶️ — сейчас)\nсервисы: " . $h(implode(' · ', $names)) . "\n\n" . implode("\n", $lines)
        . ($best ? "\n\n<b>Лучший для:</b>\n" . implode("\n", $best) : '') . "\n\nПодключить — /servers");
}
function cmd_log(): void {
    global $h;
    $ev = array_slice(@file(WATCH . '/events.tsv', FILE_IGNORE_NEW_LINES) ?: [], -10);
    if (!$ev) { say('Журнал пока пуст.'); return; }
    $ico = ['offline' => '🔴', 'vpn_down' => '🔴', 'online' => '🟢', 'vpn_up' => '🟢', 'auto' => '🟡', 'reboot' => '🟡', 'newdev' => '🆕', 'manual' => '🌍'];
    $tz = new DateTimeZone('Europe/Samara');
    $out = array_map(function ($l) use ($h, $ico, $tz) {
        [$t, $k, $txt] = array_pad(explode("\t", $l, 3), 3, '');
        return ($ico[$k] ?? '▫️') . ' ' . (new DateTime('@' . (int)$t))->setTimezone($tz)->format('d.m H:i') . ' — ' . $h($txt);
    }, array_reverse($ev));
    say("<b>Журнал</b> (последние 10)\n" . implode("\n", $out));
}
function cmd_router(): void {
    global $h;
    $s = router('status');
    if (!$s) { say(down_msg()); return; }
    $y = $s['sys'] ?? []; $mb = fn($kb) => round($kb / 1024) . ' МБ';
    $pc = fn($a, $b) => $b ? round($a / $b * 100) . '%' : '—';
    $up = (int)($y['uptime'] ?? 0);
    say('<b>' . $h($y['model'] ?? 'Роутер') . "</b>\n" . $h($y['fw'] ?? '') . "\n"
        . 'Процессор: ' . ($y['cpu'] ?? '?') . '% · нагрузка ' . $h($y['load'] ?? '') . ' · ядер ' . ($y['cores'] ?? '?') . "\n"
        . 'Память: ' . $mb(($y['mem_total'] ?? 0) - ($y['mem_avail'] ?? 0)) . ' из ' . $mb($y['mem_total'] ?? 0) . ' (' . $pc(($y['mem_total'] ?? 0) - ($y['mem_avail'] ?? 0), $y['mem_total'] ?? 0) . ")\n"
        . 'Флеш: ' . $pc($y['disk_used'] ?? 0, $y['disk_total'] ?? 0) . ' · временные файлы: ' . $pc($y['tmp_used'] ?? 0, $y['tmp_total'] ?? 0) . "\n"
        . 'Температура: ' . (isset($y['temp']) ? $y['temp'] . ' °C' : 'нет датчика') . "\n"
        . 'Без перезагрузки: ' . floor($up / 86400) . ' д ' . floor($up % 86400 / 3600) . " ч\n"
        . 'Интернет сейчас: ↓' . mbit($y['net']['rx'] ?? 0) . ' ↑' . mbit($y['net']['tx'] ?? 0) . "\n"
        . 'С включения: ↓' . gb($y['net']['rx_total'] ?? 0) . ' ↑' . gb($y['net']['tx_total'] ?? 0));
}
function cmd_tgproxy(): void {
    global $cb;
    $m = json_decode((string)@file_get_contents(WATCH . '/mtg.json'), true);
    if (!$m) { say('Нет данных о Telegram-прокси.'); return; }
    $stale = time() - (int)($m['ts'] ?? 0) > 300; $up = ($m['active'] ?? false) && !$stale;
    $since = (int)($m['since'] ?? 0) ? floor((time() - $m['since']) / 3600) : 0;
    say(($up ? '🟢 Telegram-прокси работает' : ($stale ? '⚪ Нет свежих данных' : '🔴 Telegram-прокси не работает')) . "\n"
        . 'tg.fspirat.online, порт 443' . ($up ? "\nПодключений сейчас: " . (int)$m['conns'] . ($since ? "\nБез перезапуска: " . floor($since / 24) . ' д ' . ($since % 24) . ' ч' : '') : ''),
        [[['text' => '📨 Прислать ссылку для подключения', 'callback_data' => $cb('tgl')]]]);
}
function cmd_vds(): void {
    global $h;
    $v = json_decode((string)@file_get_contents(WATCH . '/vds.json'), true);
    if (!$v) { say('Данных о серверах пока нет — они собираются раз в 5 минут.'); return; }
    $one = function (string $title, ?array $x, string $note) {
        if (!$x) return "<b>$title</b>\n🔴 не отвечает по SSH";
        $mem = $x['mem_total'] ? round(($x['mem_total'] - $x['mem_avail']) / $x['mem_total'] * 100) : 0;
        return "<b>$title</b>\n" . (($x['xray'] ?? '') === 'active' ? '🟢 VPN (Xray) работает' : '🔴 VPN (Xray): ' . htmlspecialchars($x['xray'] ?: 'не запущен')) . ' · соединений ' . (int)$x['conns'] . "\n"
            . 'Нагрузка ' . htmlspecialchars($x['load']) . ' на ' . (int)$x['cores'] . ' ядр. · память ' . $mem . '% из ' . round($x['mem_total'] / 1048576, 1) . ' ГБ · диск ' . htmlspecialchars($x['disk']) . "\n"
            . 'Без перезагрузки ' . floor($x['up'] / 86400) . ' д · трафик с запуска ↓' . gb($x['rx']) . ' ↑' . gb($x['tx']) . ($note ? "\n$note" : '');
    };
    $age = time() - (int)($v['ts'] ?? 0);
    say($one('🇩🇪 Германия (fspirat) · 64.188.83.100', $v['de'] ?? null, '') . "\n\n"
        . $one('🇳🇱 Нидерланды (fspirat) · сервер сайта', $v['nl'] ?? null, 'Здесь же сайт, панель и Telegram-прокси') . "\n\n"
        . 'Данные ' . ($age < 90 ? 'свежие' : floor($age / 60) . ' мин назад') . '.');
}
function cmd_help(): void {
    say("<b>Команды роутера</b>\n/status — состояние VPN, сервера, сервисов\n/servers — серверы с пингом, подключение кнопкой\n/vpn <i>название</i> — подключить сервер, например /vpn германия\n"
        . "/devices — кто в сети и сколько скачал\n/block <i>имя</i> — выключить интернет устройству\n/unblock <i>имя</i> — включить обратно\n/speed — тест скорости без VPN\n"
        . "/ping — перемерить все серверы и сервисы\n/log — журнал событий\n/router — нагрузка, память, температура\n/update — обновить подписку nosok\n/tgproxy — Telegram-прокси\n/vds — твои серверы в Германии и Нидерландах\n/restart — перезапустить VPN\n/reboot — перезагрузить роутер\n/report — отчёт за сутки сейчас\n\nОпасные команды — с кнопкой подтверждения.");
}

/* ---------- кнопки ---------- */
function on_button(array $q): void {
    global $h;
    $mid = (int)($q['message']['message_id'] ?? 0);
    tg('answerCallbackQuery', ['callback_query_id' => $q['id']]);
    $data = (string)($q['data'] ?? '');
    if ($data === 'no') { edit($mid, 'Отменено.'); return; }
    [$what, $ts] = array_pad(explode('|', $data, 2), 2, '0');
    if (time() - (int)$ts > 600) { edit($mid, 'Кнопка устарела — отправь команду ещё раз.'); return; }
    [$act, $arg] = array_pad(explode(':', $what, 2), 2, '');
    fsr_audit('TG', "$act " . preg_replace('/[^A-Za-z0-9:]/', '', $arg));
    switch ($act) {
        case 'sw':
            $r = router('switch', ['id' => $arg], true);
            $s = router('status');
            edit($mid, $r && ($r['ok'] ?? false) ? '🌍 Подключаю <b>' . $h($s ? node_name($s, $arg) : $arg) . '</b>. VPN перезапускается, через ~10 секунд всё заработает. Проверить — /status' : '⚠️ Не получилось: ' . $h($r['error'] ?? 'роутер не отвечает'));
            break;
        case 'bl': case 'ub':
            $r = router($act === 'bl' ? 'block' : 'unblock', ['mac' => $arg], true);
            $s = router('status'); $nm = $arg;
            foreach ($s['devices'] ?? [] as $d) if (strtolower($d['mac'] ?? '') === $arg) $nm = dev_name($d);
            edit($mid, $r && ($r['ok'] ?? false) ? ($act === 'bl' ? '⛔ Интернет выключен: ' : '✅ Интернет включён: ') . '<b>' . $h($nm) . '</b>' : '⚠️ Не получилось: ' . $h($r['error'] ?? 'роутер не отвечает'));
            break;
        case 'restart':
            $r = router('restart', [], true);
            edit($mid, $r && ($r['ok'] ?? false) ? '🔁 VPN перезапускается, связь вернётся через несколько секунд.' : '⚠️ Не получилось: ' . $h($r['error'] ?? 'роутер не отвечает'));
            break;
        case 'upd':
            $r = router('update', [], true);
            edit($mid, $r && ($r['ok'] ?? false) ? '📥 Обновляю подписку nosok — список серверов обновится примерно через минуту.' : '⚠️ Не получилось: ' . $h($r['error'] ?? 'роутер не отвечает'));
            break;
        case 'tgl':
            @touch(fsr_dir() . '/tglink_now');
            edit($mid, '📨 Ссылка придёт отдельным сообщением в течение минуты.');
            break;
        case 'reboot':
            $r = router('reboot', [], true);
            edit($mid, $r && ($r['ok'] ?? false) ? '🔄 Роутер перезагружается. Интернета дома не будет 1–2 минуты. Проверить — /status' : '⚠️ Не получилось: ' . $h($r['error'] ?? 'роутер не отвечает'));
            break;
        default:
            edit($mid, 'Неизвестная кнопка.');
    }
}

/* ---------- разбор обновления ---------- */
$chat = (string)($u['message']['chat']['id'] ?? $u['callback_query']['message']['chat']['id'] ?? '');
if ($chat === '' || $chat !== (string)$tg['chat']) exit;     // только чат владельца, остальным — молчание
if (isset($u['callback_query'])) { on_button($u['callback_query']); exit; }
$text = trim((string)($u['message']['text'] ?? ''));
if ($text === '' || $text[0] !== '/') { cmd_help(); exit; }
[$c, $arg] = array_pad(preg_split('/\s+/', $text, 2), 2, '');
$c = strtolower(preg_replace('/@.*$/', '', $c));
fsr_audit('TG', $c . ($arg !== '' ? ' ' . $arg : ''));
match ($c) {
    '/status' => cmd_status(),
    '/servers' => cmd_servers(),
    '/vpn' => cmd_vpn($arg),
    '/devices' => cmd_devices(),
    '/block' => cmd_block($arg, true),
    '/unblock' => cmd_block($arg, false),
    '/speed' => cmd_speed(),
    '/restart' => cmd_confirm('restart', 'Перезапустить VPN?', 'Связь через VPN пропадёт на несколько секунд.', 'Да, перезапустить'),
    '/reboot' => cmd_confirm('reboot', '⚠️ Перезагрузить роутер?', 'Интернет дома пропадёт на 1–2 минуты.', '🔴 Да, перезагрузить'),
    '/report' => cmd_report(),
    '/ping' => cmd_ping(),
    '/log' => cmd_log(),
    '/router' => cmd_router(),
    '/update' => cmd_confirm('upd', 'Обновить подписку nosok?', 'Список серверов скачается заново, это займёт до минуты. VPN не перезапускается.', 'Да, обновить'),
    '/tgproxy' => cmd_tgproxy(),
    '/vds' => cmd_vds(),
    default => cmd_help(),
};

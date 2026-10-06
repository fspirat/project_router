<?php
// Данные страницы роутера, которые хранит сервер (переживают перезагрузку роутера и работают без туннеля):
//   GET  /router/data?range=day|week|month — история отклика, журнал, «роутер не на связи с …», имена устройств
//   POST /router/data  mac=…&name=…       — своё имя устройства (пустое имя — вернуть как было)
// Историю и журнал пишет fspirat-watch (cron раз в минуту) в /var/lib/fspirat/. Доступ — только после входа (auth_request).
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';

const FSR_WATCH = '/var/lib/fspirat';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function out(array $a, int $code = 200): never { http_response_code($code); echo json_encode($a, JSON_UNESCAPED_UNICODE); exit; }
function watch(string $f): string { return (getenv('FSR_WATCH') ?: FSR_WATCH) . '/' . $f; }
function names_file(): string { return fsr_dir() . '/names.json'; }
function names(): array { $j = json_decode((string)@file_get_contents(names_file()), true); return is_array($j) ? $j : []; }

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== (getenv('FSR_ORIGIN') ?: 'https://fspirat.online')) out(['error' => 'origin'], 403);
    $mac = strtolower(trim((string)($_POST['mac'] ?? '')));
    if (!preg_match('/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/', $mac)) out(['error' => 'bad mac'], 400);
    $name = trim(preg_replace('/[\x00-\x1f\x7f]/u', '', (string)($_POST['name'] ?? '')) ?? '');
    $name = mb_substr($name, 0, 40);
    $fp = fopen(names_file(), 'c+');
    flock($fp, LOCK_EX);
    $all = json_decode(stream_get_contents($fp) ?: '', true) ?: [];
    if ($name === '') unset($all[$mac]); else $all[$mac] = $name;
    ftruncate($fp, 0); rewind($fp);
    fwrite($fp, json_encode($all, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    flock($fp, LOCK_UN); fclose($fp);
    out(['ok' => true, 'names' => $all]);
}

$ranges = ['day' => [86400, 0], 'week' => [7 * 86400, 1800], 'month' => [30 * 86400, 7200]];   // окно, шаг усреднения
$range = $_GET['range'] ?? 'day';
if (!isset($ranges[$range])) $range = 'day';
[$span, $step] = $ranges[$range];
$now = time();
$from = $now - $span;

// История: "время отклик узел"; 0 — VPN не прошёл, -1 — роутер не на связи (точка раз в минуту)
$ok = []; $fails = 0; $off = 0; $buckets = []; $raw = [];
$fh = @fopen(watch('history.tsv'), 'r');
while ($fh && ($line = fgets($fh)) !== false) {
    $p = explode(' ', trim($line));
    $ts = (int)$p[0]; $ms = (int)($p[1] ?? 0);
    if ($ts < $from) continue;
    if ($ms > 0) $ok[] = $ms; elseif ($ms === 0) $fails++; else $off++;
    if (!$step) { $raw[] = [$ts, $ms]; continue; }
    $b = intdiv($ts, $step) * $step;
    $buckets[$b] ??= ['sum' => 0, 'n' => 0, 'fail' => 0, 'off' => 0];
    if ($ms > 0) { $buckets[$b]['sum'] += $ms; $buckets[$b]['n']++; }
    elseif ($ms === 0) $buckets[$b]['fail']++; else $buckets[$b]['off']++;
}
if ($fh) fclose($fh);
if (!$step) usort($raw, fn($a, $b) => $a[0] <=> $b[0]);
else {
    ksort($buckets);
    foreach ($buckets as $b => $v)   // точка в середине интервала; без удачных замеров — сбой или «нет связи»
        $raw[] = [$b + intdiv($step, 2), $v['n'] ? (int)round($v['sum'] / $v['n']) : ($v['off'] >= 3 ? -1 : 0), $v['fail'], $v['off']];
}

// Журнал: "время<TAB>вид<TAB>текст", новые сверху
$events = [];
foreach (array_slice(@file(watch('events.tsv'), FILE_IGNORE_NEW_LINES) ?: [], -300) as $line) {
    $e = explode("\t", $line, 3);
    if (count($e) === 3 && (int)$e[0] >= $from) $events[] = [(int)$e[0], $e[1], $e[2]];
}
usort($events, fn($a, $b) => $b[0] <=> $a[0]);

$since = (int)trim((string)@file_get_contents(watch('offline_since')));
out([
    'now' => $now,
    'range' => $range,
    'step' => $step,
    'points' => $raw,
    'stats' => [
        'avg' => $ok ? (int)round(array_sum($ok) / count($ok)) : null,
        'min' => $ok ? min($ok) : null,
        'max' => $ok ? max($ok) : null,
        'fails' => $fails,
        'offline_min' => $off,
    ],
    'events' => array_slice($events, 0, 100),
    'offline_since' => $since ?: null,     // роутер не отвечает серверу (по данным fspirat-watch)
    'last_ok' => (int)trim((string)@file_get_contents(watch('last_ok'))) ?: null,
    'names' => (object)names(),
    'mtg' => json_decode((string)@file_get_contents(watch('mtg.json')), true) ?: null,   // Telegram-прокси (fspirat-watch)
]);

<?php
/**
 * Данные страницы и приложения, которые хранит сервер (работают и без туннеля до роутера):
 * история отклика, журнал, трафик устройств, свои имена устройств, тест скорости — их пишет fspirat-watch в /var/lib/fspirat/.
 * Общие для data.php (веб), app.php (приложение) и tgbot.php. Функции — с префиксом fsr_: в tgbot.php уже есть свои names().
 *
 * Сутки трафика — по Самаре (время роутера) везде: fspirat-watch пишет ключ дня по Самаре, здесь и в боте читаем так же
 * (раньше: запись — по UTC сервера, веб — по Москве, бот — по UTC, и «сегодня» первые часы после полуночи было 0).
 */

declare(strict_types=1);

if (!defined('FSR')) { http_response_code(404); exit; }

const FSR_WATCH = '/var/lib/fspirat';
const FSR_DAY_TZ = 'Europe/Samara';

function fsr_watch(string $f): string { return rtrim(getenv('FSR_WATCH') ?: FSR_WATCH, '/') . '/' . $f; }

/** Сегодняшний день трафика (ключ в traffic.json) и месяц — по Самаре. */
function fsr_traffic_day(string $fmt = 'Y-m-d'): string { return (new DateTime('now', new DateTimeZone(FSR_DAY_TZ)))->format($fmt); }

// ---------- свои имена устройств (names.json) ----------

function fsr_names_file(): string { return fsr_dir() . '/names.json'; }
function fsr_names(): array { $j = json_decode((string)@file_get_contents(fsr_names_file()), true); return is_array($j) ? $j : []; }

/** Записать имя устройства ($mac — уже проверен, $name — уже очищен; пустое — убрать своё имя). → все имена. */
function fsr_names_set(string $mac, string $name): array
{
    $fp = fopen(fsr_names_file(), 'c+');
    flock($fp, LOCK_EX);
    $all = json_decode(stream_get_contents($fp) ?: '', true) ?: [];
    if ($name === '') unset($all[$mac]); else $all[$mac] = $name;
    ftruncate($fp, 0); rewind($fp);
    fwrite($fp, json_encode($all, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    flock($fp, LOCK_UN); fclose($fp);
    return $all;
}

// ---------- /router/data?range= ----------

/** То, что отдаёт GET /router/data?range=day|week|month (неизвестный период — day). */
function fsr_data_payload(string $range): array
{
    $ranges = ['day' => [86400, 0], 'week' => [7 * 86400, 1800], 'month' => [30 * 86400, 7200]];   // окно, шаг усреднения
    if (!isset($ranges[$range])) $range = 'day';
    [$span, $step] = $ranges[$range];
    $now = time();
    $from = $now - $span;

    // История: "время отклик узел"; 0 — VPN не прошёл, -1 — роутер не на связи (точка раз в минуту)
    $ok = []; $fails = 0; $off = 0; $buckets = []; $raw = [];
    $fh = @fopen(fsr_watch('history.tsv'), 'r');
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
    foreach (array_slice(@file(fsr_watch('events.tsv'), FILE_IGNORE_NEW_LINES) ?: [], -300) as $line) {
        $e = explode("\t", $line, 3);
        if (count($e) === 3 && (int)$e[0] >= $from) $events[] = [(int)$e[0], $e[1], $e[2]];
    }
    usort($events, fn($a, $b) => $b[0] <=> $a[0]);

    // Задержка до сервисов (targets.tsv "время<TAB>имя<TAB>ms", 0 — не ответил): {имя: [[время, ms], …]}, усреднение — как у истории
    $tpoints = [];
    $fh = @fopen(fsr_watch('targets.tsv'), 'r');
    while ($fh && ($line = fgets($fh)) !== false) {
        $p = explode("\t", rtrim($line, "\n"));
        if (count($p) < 3 || (int)$p[0] < $from) continue;
        $b = $step ? intdiv((int)$p[0], $step) * $step : (int)$p[0];
        $tpoints[$p[1]][$b][] = (int)$p[2];
    }
    if ($fh) fclose($fh);
    foreach ($tpoints as $n => $bs) {
        ksort($bs);
        $out = [];
        foreach ($bs as $b => $v) {
            $good = array_filter($v, fn($x) => $x > 0);
            $out[] = [$step ? $b + intdiv($step, 2) : $b, $good ? (int)round(array_sum($good) / count($good)) : 0];
        }
        $tpoints[$n] = $out;
    }

    // Трафик устройств (traffic.json от fspirat-watch): сегодня и с начала месяца, [отдано, скачано] в байтах. Сутки — по Самаре.
    $traffic = [];
    $tj = json_decode((string)@file_get_contents(fsr_watch('traffic.json')), true);
    if (is_array($tj['days'] ?? null)) {
        $today = fsr_traffic_day(); $month = fsr_traffic_day('Y-m');
        foreach ($tj['days'] as $day => $macs) {
            if (!str_starts_with((string)$day, $month) || !is_array($macs)) continue;
            foreach ($macs as $m => $v) {
                $t = &$traffic[$m];
                $t ??= ['d' => [0, 0], 'm' => [0, 0]];
                $t['m'][0] += (int)$v[0]; $t['m'][1] += (int)$v[1];
                if ($day === $today) { $t['d'][0] += (int)$v[0]; $t['d'][1] += (int)$v[1]; }
                unset($t);
            }
        }
    }

    // История теста скорости (speed.tsv "время вид загрузка отдача задержка") за 90 дней: [[время, "vpn"|"direct", загрузка, отдача, задержка], …]
    $speed = [];
    foreach (@file(fsr_watch('speed.tsv'), FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        $p = explode(' ', $line);
        if (count($p) >= 5 && (int)$p[0] >= $now - 90 * 86400 && in_array($p[1], ['vpn', 'direct'], true))
            $speed[] = [(int)$p[0], $p[1], (int)$p[2], (int)$p[3], (int)$p[4]];
    }

    $since = (int)trim((string)@file_get_contents(fsr_watch('offline_since')));
    return [
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
        'last_ok' => (int)trim((string)@file_get_contents(fsr_watch('last_ok'))) ?: null,
        'names' => (object)fsr_names(),
        'tpoints' => (object)$tpoints,     // задержка до сервисов через текущий сервер
        'traffic' => (object)$traffic,     // трафик устройств по MAC
        'speed' => $speed,                 // история теста скорости
        'mtg' => fsr_site()['mtg'] !== '' ? (json_decode((string)@file_get_contents(fsr_watch('mtg.json')), true) ?: null) : null,   // свой Telegram-прокси (fspirat-watch), если есть
        'site' => fsr_site(),             // ссылка LuCI, имя бота, домен Telegram-прокси — из deploy.conf
    ];
}

/** Новые устройства за $days дней (для приложения): события newdev по всему events.tsv, MAC — из «(…)» в конце текста. */
function fsr_data_newdevs(int $days = 7): array
{
    $from = time() - $days * 86400; $out = [];
    foreach (@file(fsr_watch('events.tsv'), FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        $e = explode("\t", $line, 3);
        if (count($e) === 3 && $e[1] === 'newdev' && (int)$e[0] >= $from
            && preg_match('/\(((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})\)\s*$/', $e[2], $m)) $out[] = ['ts' => (int)$e[0], 'mac' => strtolower($m[1])];
    }
    usort($out, fn($a, $b) => $b['ts'] <=> $a['ts']);
    return $out;
}

/** Свои VPN-серверы и сервер панели (vds.json от fspirat-watch) — только разрешённые поля, без адресов. */
function fsr_vds(): array
{
    $v = json_decode((string)@file_get_contents(fsr_watch('vds.json')), true);
    if (!is_array($v)) return ['ts' => null, 'servers' => []];
    $int = ['up', 'cores', 'mem_total', 'mem_avail', 'rx', 'tx', 'conns'];
    $str = ['load', 'disk', 'xray'];
    $servers = [];
    foreach ((array)($v['servers'] ?? []) as $x) {
        if (!is_array($x)) continue;
        $s = ['name' => mb_substr((string)($x['name'] ?? ''), 0, 60)];
        if (!empty($x['local'])) $s['local'] = true;
        $st = $x['stat'] ?? null;
        if (is_array($st)) {
            $s['stat'] = [];
            foreach ($int as $k) $s['stat'][$k] = (int)($st[$k] ?? 0);
            foreach ($str as $k) $s['stat'][$k] = mb_substr(is_scalar($st[$k] ?? null) ? (string)$st[$k] : '', 0, 40);
        } else $s['stat'] = null;
        $servers[] = $s;
    }
    return ['ts' => isset($v['ts']) ? (int)$v['ts'] : null, 'servers' => $servers];
}

// ---------- кто имеет доступ: приложения, сессии веба, входы, журнал входов ----------

/** Последние строки журнала входов: [{ts, what, ip}], новые сверху. Время в журнале — по Москве (lib.php). */
function fsr_auth_log_tail(int $n = 30): array
{
    $f = getenv('FSR_LOG') ?: FSR_LOG;
    $size = (int)@filesize($f);
    $fh = @fopen($f, 'r');
    if (!$fh || $size <= 0) return [];
    $off = max(0, $size - 16384);
    fseek($fh, $off);
    $lines = explode("\n", (string)stream_get_contents($fh));
    fclose($fh);
    if ($off > 0) array_shift($lines);      // первая строка обрезана
    $out = [];
    foreach (array_reverse($lines) as $l) {
        if (!preg_match('/^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) ([A-Z_]{1,20}) ip=(\S*)/', $l, $m)) continue;
        $out[] = ['ts' => (int)strtotime($m[1]), 'what' => $m[2], 'ip' => $m[3]];
        if (count($out) >= $n) break;
    }
    return $out;
}

/**
 * Список для приложения (/devices) и веба (/router/data?devices=1): ключи приложений, сессии веба, входы приложения, журнал входов.
 * $appId — текущее устройство приложения, $webHash — sha256 текущей сессии веба (отмечаются current).
 */
function fsr_app_devices_list(?string $appId = null, ?string $webHash = null): array
{
    $apps = array_map(fn($d) => [
        'id' => (string)$d['id'], 'name' => (string)$d['name'], 'model' => (string)$d['model'], 'os' => (string)$d['os'], 'app' => (string)$d['app'],
        'created' => (int)$d['created'], 'seen' => (int)$d['seen'], 'last_ip' => (string)$d['last_ip'],
        'expires' => (int)$d['expires'], 'hard_expires' => (int)$d['hard_expires'], 'current' => $appId !== null && $d['id'] === $appId,
    ], fsr_app_active());
    $web = array_map(fn($s) => [
        'ref' => substr((string)$s['hash'], 0, 16), 'created' => (int)$s['created'], 'seen' => (int)$s['seen'],
        'ip' => (string)$s['ip'], 'ua' => (string)$s['ua'], 'current' => $webHash !== null && hash_equals((string)$s['hash'], $webHash),
    ], fsr_app_q('SELECT hash, created, seen, ip, ua FROM sessions WHERE seen + ttl >= ? ORDER BY seen DESC', [time()])->fetchAll());
    $logins = array_map(fn($r) => ['ts' => (int)$r['created'], 'name' => (string)$r['name'], 'ip' => (string)$r['ip'], 'result' => (string)$r['state']],
        fsr_app_q('SELECT created, name, ip, state FROM app_logins ORDER BY created DESC LIMIT 20')->fetchAll());
    return ['apps' => $apps, 'web' => $web, 'logins' => $logins, 'auth_log' => fsr_auth_log_tail(30)];
}

/** Закрыть сессию веба по короткой ссылке (16 hex от хэша). → была ли такая. */
function fsr_web_session_end(string $ref): ?array
{
    if (!preg_match('/^[a-f0-9]{16}$/', $ref)) return null;
    $r = fsr_app_row('SELECT hash, ip FROM sessions WHERE substr(hash, 1, 16) = ?', [$ref]);
    if (!$r) return null;
    fsr_app_q('DELETE FROM sessions WHERE hash = ?', [$r['hash']]);
    return $r;
}

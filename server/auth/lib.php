<?php
/**
 * Вход в панель роутера (fspirat.online/router/ и router.fspirat.online) вместо окна браузера.
 * nginx спрашивает check.php перед каждым запросом (auth_request); login.php показывает страницу входа.
 *
 * Данные — вне папок сайта: /var/lib/fspirat-router-auth/
 *   auth.sqlite  — сессии и неудачные попытки
 *   password     — хэш пароля (bcrypt). Пока его нет, пароль проверяется по /etc/nginx/.htpasswd_router
 *                  (старый формат apr1), а после первого входа сохраняется здесь в bcrypt.
 * Журнал входов для fail2ban и уведомлений: /var/log/fspirat-router-auth.log
 */

declare(strict_types=1);

if (!defined('FSR')) { http_response_code(404); exit; }

const FSR_DIR = '/var/lib/fspirat-router-auth';
const FSR_HTPASSWD = '/etc/nginx/.htpasswd_router';
const FSR_USER = 'bob';
const FSR_LOG = '/var/log/fspirat-router-auth.log';
const FSR_COOKIE = 'fsr_session';
const FSR_COOKIE_DOMAIN = 'fspirat.online';     // один вход для fspirat.online/router/ и router.fspirat.online
const FSR_TTL_SHORT = 12 * 3600;               // без «Запомнить»: 12 часов
const FSR_TTL_LONG = 30 * 86400;               // с «Запомнить»: 30 дней (продлевается при работе)
const FSR_MAX_FAILS = 5;
const FSR_LOCK_SEC = 900;

date_default_timezone_set('Europe/Moscow');

function fsr_dir(): string { return rtrim(getenv('FSR_DIR') ?: FSR_DIR, '/'); }

function fsr_db(): PDO
{
    static $db = null;
    if ($db) return $db;
    $db = new PDO('sqlite:' . fsr_dir() . '/auth.sqlite', null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
    $db->exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000;');
    $db->exec('CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, created INTEGER NOT NULL, seen INTEGER NOT NULL,
                 ttl INTEGER NOT NULL, ip TEXT, ua TEXT)');
    $db->exec('CREATE TABLE IF NOT EXISTS fails(ip TEXT NOT NULL, ts INTEGER NOT NULL)');
    $db->exec('CREATE INDEX IF NOT EXISTS fails_ip ON fails(ip, ts)');
    return $db;
}

function fsr_ip(): string { return $_SERVER['REMOTE_ADDR'] ?? ''; }

function fsr_log(string $what): void
{
    $ua = preg_replace('/[^\x20-\x7e]/', '', substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 120));
    @file_put_contents(getenv('FSR_LOG') ?: FSR_LOG, date('Y-m-d H:i:s') . " $what ip=" . fsr_ip() . " ua=\"$ua\"\n", FILE_APPEND | LOCK_EX);
}

// ---------- пароль ----------

/** Проверка apr1-MD5 (формат htpasswd по умолчанию) — только для перехода на bcrypt. */
function fsr_apr1(string $pw, string $hash): bool
{
    if (!preg_match('/^\$apr1\$([^$]{1,8})\$/', $hash, $m)) return false;
    $salt = $m[1];
    $text = $pw . '$apr1$' . $salt;
    $bin = md5($pw . $salt . $pw, true);
    for ($i = strlen($pw); $i > 0; $i -= 16) $text .= substr($bin, 0, min(16, $i));
    for ($i = strlen($pw); $i; $i >>= 1) $text .= ($i & 1) ? "\0" : $pw[0];
    $bin = md5($text, true);
    for ($i = 0; $i < 1000; $i++) {
        $new = ($i & 1) ? $pw : $bin;
        if ($i % 3) $new .= $salt;
        if ($i % 7) $new .= $pw;
        $new .= ($i & 1) ? $bin : $pw;
        $bin = md5($new, true);
    }
    $to64 = function (int $v, int $n): string {
        $itoa = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
        $s = '';
        while ($n-- > 0) { $s .= $itoa[$v & 0x3f]; $v >>= 6; }
        return $s;
    };
    $b = array_map('ord', str_split($bin));
    $out = $to64(($b[0] << 16) | ($b[6] << 8) | $b[12], 4) . $to64(($b[1] << 16) | ($b[7] << 8) | $b[13], 4)
         . $to64(($b[2] << 16) | ($b[8] << 8) | $b[14], 4) . $to64(($b[3] << 16) | ($b[9] << 8) | $b[15], 4)
         . $to64(($b[4] << 16) | ($b[10] << 8) | $b[5], 4) . $to64($b[11], 2);
    return hash_equals($hash, '$apr1$' . $salt . '$' . $out);
}

function fsr_password_ok(string $pw): bool
{
    if ($pw === '' || strlen($pw) > 200) return false;
    $file = fsr_dir() . '/password';
    $h = trim((string)@file_get_contents($file));
    if ($h !== '') return password_verify($pw, $h);
    // ещё не переведён на bcrypt: берём хэш пользователя из htpasswd
    foreach (@file(getenv('FSR_HTPASSWD') ?: FSR_HTPASSWD, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        [$u, $hash] = array_pad(explode(':', $line, 2), 2, '');
        if ($u !== FSR_USER) continue;
        $ok = str_starts_with($hash, '$apr1$') ? fsr_apr1($pw, $hash) : password_verify($pw, $hash);
        if ($ok) { @file_put_contents($file, password_hash($pw, PASSWORD_DEFAULT) . "\n", LOCK_EX); @chmod($file, 0600); }
        return $ok;
    }
    return false;
}

// ---------- блокировка подбора ----------

function fsr_locked(): int
{
    $st = fsr_db()->prepare('SELECT COUNT(*) n, MAX(ts) last FROM fails WHERE ip = ? AND ts > ?');
    $st->execute([fsr_ip(), time() - FSR_LOCK_SEC]);
    $r = $st->fetch();
    return (int)$r['n'] >= FSR_MAX_FAILS ? max(1, (int)$r['last'] + FSR_LOCK_SEC - time()) : 0;
}

function fsr_fail(): int
{
    $db = fsr_db();
    $db->prepare('INSERT INTO fails(ip, ts) VALUES(?, ?)')->execute([fsr_ip(), time()]);
    $db->prepare('DELETE FROM fails WHERE ts < ?')->execute([time() - 86400]);
    $st = $db->prepare('SELECT COUNT(*) FROM fails WHERE ip = ? AND ts > ?');
    $st->execute([fsr_ip(), time() - FSR_LOCK_SEC]);
    return FSR_MAX_FAILS - (int)$st->fetchColumn();
}

// ---------- сессии ----------

function fsr_cookie(string $value, int $expires): void
{
    setcookie(FSR_COOKIE, $value, [
        'expires' => $expires, 'path' => '/', 'domain' => FSR_COOKIE_DOMAIN,
        'secure' => true, 'httponly' => true, 'samesite' => 'Lax',
    ]);
}

function fsr_session_start(bool $remember): void
{
    $tok = bin2hex(random_bytes(32));
    $ttl = $remember ? FSR_TTL_LONG : FSR_TTL_SHORT;
    $db = fsr_db();
    $db->prepare('DELETE FROM sessions WHERE seen + ttl < ?')->execute([time()]);
    $db->prepare('INSERT INTO sessions(hash, created, seen, ttl, ip, ua) VALUES(?,?,?,?,?,?)')
       ->execute([hash('sha256', $tok), time(), time(), $ttl, fsr_ip(), substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 200)]);
    fsr_cookie($tok, $remember ? time() + $ttl : 0);
    $db->prepare('DELETE FROM fails WHERE ip = ?')->execute([fsr_ip()]);
}

/** Действующая сессия из cookie (и продление). */
function fsr_session_valid(): bool
{
    $tok = $_COOKIE[FSR_COOKIE] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $tok)) return false;
    $db = fsr_db();
    $st = $db->prepare('SELECT seen, ttl FROM sessions WHERE hash = ?');
    $st->execute([hash('sha256', $tok)]);
    $r = $st->fetch();
    if (!$r || $r['seen'] + $r['ttl'] < time()) return false;
    if (time() - $r['seen'] > 300) $db->prepare('UPDATE sessions SET seen = ? WHERE hash = ?')->execute([time(), hash('sha256', $tok)]);
    return true;
}

function fsr_session_end(): void
{
    $tok = $_COOKIE[FSR_COOKIE] ?? '';
    if (preg_match('/^[a-f0-9]{64}$/', $tok)) fsr_db()->prepare('DELETE FROM sessions WHERE hash = ?')->execute([hash('sha256', $tok)]);
    fsr_cookie('', 1);
}

/** Куда вернуться после входа: только наши адреса. */
function fsr_next(string $next): string
{
    if (preg_match('~^/router/[A-Za-z0-9/._?=&%-]*$~', $next) && !str_starts_with($next, '/router/login')) return $next;
    if (preg_match('~^https://router\.fspirat\.online/[A-Za-z0-9/._?=&%;:+-]*$~', $next)) return $next;
    return '/router/';
}

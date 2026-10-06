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

/** Домен cookie (для локальных тестов — FSR_COOKIE_DOMAIN="" — без домена). */
function fsr_cookie_domain(): string { $d = getenv('FSR_COOKIE_DOMAIN'); return $d === false ? FSR_COOKIE_DOMAIN : $d; }

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
        'expires' => $expires, 'path' => '/', 'domain' => fsr_cookie_domain(),
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

// ---------- подтверждение входа кодом из Telegram (вторая защита после пароля) ----------
// Код спрашивается только на новом устройстве; после подтверждения устройство помнится 30 дней (cookie fsr_dev).
// Бот и чат — /var/lib/fspirat-router-auth/telegram.json (его пишет выкладка из /etc/fspirat-watch.conf).
// Нет файла — вход без кода, как раньше.

const FSR_DEV_COOKIE = 'fsr_dev';
const FSR_DEV_TTL = 30 * 86400;
const FSR_CODE_COOKIE = 'fsr_2fa';
const FSR_CODE_TTL = 300;          // код живёт 5 минут
const FSR_CODE_TRIES = 5;

function fsr_db2(): PDO
{
    $db = fsr_db();
    $db->exec('CREATE TABLE IF NOT EXISTS devices(hash TEXT PRIMARY KEY, created INTEGER NOT NULL, seen INTEGER NOT NULL, ip TEXT, ua TEXT)');
    $db->exec('CREATE TABLE IF NOT EXISTS codes(hash TEXT PRIMARY KEY, code TEXT NOT NULL, created INTEGER NOT NULL,
                 tries INTEGER NOT NULL DEFAULT 0, remember INTEGER NOT NULL, next TEXT NOT NULL)');
    return $db;
}

function fsr_tg(): ?array
{
    $c = json_decode((string)@file_get_contents(fsr_dir() . '/telegram.json'), true);
    return is_array($c) && !empty($c['token']) && !empty($c['chat']) ? $c : null;
}

function fsr_tg_send(string $text): bool
{
    $c = fsr_tg();
    if (!$c) return false;
    $raw = @file_get_contents((getenv('FSR_TG_API') ?: 'https://api.telegram.org') . '/bot' . $c['token'] . '/sendMessage', false, stream_context_create(['http' => [
        'method' => 'POST', 'header' => 'Content-Type: application/x-www-form-urlencoded', 'timeout' => 8, 'ignore_errors' => true,
        'content' => http_build_query(['chat_id' => $c['chat'], 'text' => $text, 'disable_web_page_preview' => 'true'])]]));
    return (bool)(json_decode((string)$raw, true)['ok'] ?? false);
}

function fsr_aux_cookie(string $name, string $value, int $expires): void
{
    setcookie($name, $value, ['expires' => $expires, 'path' => '/router/', 'domain' => fsr_cookie_domain(),
        'secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
}

/** Устройство уже подтверждено кодом (и не дольше 30 дней назад пользовались). */
function fsr_device_ok(): bool
{
    $tok = $_COOKIE[FSR_DEV_COOKIE] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $tok)) return false;
    $db = fsr_db2();
    $st = $db->prepare('SELECT seen FROM devices WHERE hash = ?');
    $st->execute([hash('sha256', $tok)]);
    $seen = $st->fetchColumn();
    if ($seen === false || (int)$seen + FSR_DEV_TTL < time()) return false;
    $db->prepare('UPDATE devices SET seen = ? WHERE hash = ?')->execute([time(), hash('sha256', $tok)]);
    fsr_aux_cookie(FSR_DEV_COOKIE, $tok, time() + FSR_DEV_TTL);
    return true;
}

function fsr_device_add(): void
{
    $tok = bin2hex(random_bytes(32));
    $db = fsr_db2();
    $db->prepare('DELETE FROM devices WHERE seen < ?')->execute([time() - FSR_DEV_TTL]);
    $db->prepare('INSERT INTO devices(hash, created, seen, ip, ua) VALUES(?,?,?,?,?)')
       ->execute([hash('sha256', $tok), time(), time(), fsr_ip(), substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 200)]);
    fsr_aux_cookie(FSR_DEV_COOKIE, $tok, time() + FSR_DEV_TTL);
}

/** Пароль верный, устройство новое: отправить код в Telegram. false — не удалось отправить. */
function fsr_code_start(bool $remember, string $next): bool
{
    $code = sprintf('%06d', random_int(0, 999999));
    $tok = bin2hex(random_bytes(32));
    $ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
    $what = preg_match('~(Edg|OPR|YaBrowser|Firefox|Chrome|Safari)/~', $ua, $m) ? $m[1] : 'браузер';
    $os = preg_match('~(Windows|Android|iPhone|iPad|Mac OS X|Linux)~', $ua, $o) ? $o[1] : '';
    if (!fsr_tg_send("🔐 Код входа в панель роутера: $code\n\nВход с нового устройства: $what" . ($os ? " · $os" : '') . ' · IP ' . fsr_ip()
        . "\nКод действует 5 минут. Если это не ты — никому его не сообщай и смени пароль.")) return false;
    $db = fsr_db2();
    $db->prepare('DELETE FROM codes WHERE created < ?')->execute([time() - FSR_CODE_TTL]);
    $db->prepare('INSERT INTO codes(hash, code, created, remember, next) VALUES(?,?,?,?,?)')
       ->execute([hash('sha256', $tok), password_hash($code, PASSWORD_DEFAULT), time(), $remember ? 1 : 0, $next]);
    fsr_aux_cookie(FSR_CODE_COOKIE, $tok, time() + FSR_CODE_TTL);
    return true;
}

/** Ожидается ли код с этого браузера. */
function fsr_code_pending(): bool
{
    $tok = $_COOKIE[FSR_CODE_COOKIE] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $tok)) return false;
    $st = fsr_db2()->prepare('SELECT 1 FROM codes WHERE hash = ? AND created >= ? AND tries < ?');
    $st->execute([hash('sha256', $tok), time() - FSR_CODE_TTL, FSR_CODE_TRIES]);
    return $st->fetchColumn() !== false;
}

/** Проверить код. Верный — ['remember'=>…, 'next'=>…]; неверный — null (попытка засчитана). */
function fsr_code_check(string $code): ?array
{
    $tok = $_COOKIE[FSR_CODE_COOKIE] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $tok)) return null;
    $db = fsr_db2();
    $h = hash('sha256', $tok);
    $st = $db->prepare('SELECT code, remember, next FROM codes WHERE hash = ? AND created >= ? AND tries < ?');
    $st->execute([$h, time() - FSR_CODE_TTL, FSR_CODE_TRIES]);
    $r = $st->fetch();
    if (!$r) return null;
    if (!preg_match('/^\d{6}$/', $code) || !password_verify($code, $r['code'])) {
        $db->prepare('UPDATE codes SET tries = tries + 1 WHERE hash = ?')->execute([$h]);
        return null;
    }
    $db->prepare('DELETE FROM codes WHERE hash = ?')->execute([$h]);
    fsr_aux_cookie(FSR_CODE_COOKIE, '', 1);
    return ['remember' => (bool)$r['remember'], 'next' => (string)$r['next']];
}

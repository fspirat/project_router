<?php
/**
 * Вход в панель роутера (example.org/router/ и luci.example.org) вместо окна браузера.
 * nginx спрашивает check.php перед каждым запросом (auth_request); login.php показывает страницу входа.
 *
 * Данные — вне папок сайта: /var/lib/fspirat-router-auth/
 *   auth.sqlite  — сессии и неудачные попытки
 *   password     — хэш пароля (bcrypt). Пока его нет, пароль проверяется по /etc/nginx/.htpasswd_router
 *                  (старый формат apr1), а после первого входа сохраняется здесь в bcrypt.
 * Журнал входов для fail2ban и уведомлений: /var/log/fspirat-router-auth.log
 * Приложение для iPhone (/router/app/v1, app.php) пользуется этим же файлом: пароль, блокировка подбора, журналы,
 * Telegram (fsr_tg_call) и вызов CGI роутера (fsr_router_call — как у бота). Свои таблицы — app-lib.php.
 */

declare(strict_types=1);

if (!defined('FSR')) { http_response_code(404); exit; }

const FSR_DIR = '/var/lib/fspirat-router-auth';
const FSR_HTPASSWD = '/etc/nginx/.htpasswd_router';
const FSR_USER = 'bob';
const FSR_LOG = '/var/log/fspirat-router-auth.log';
const FSR_AUDIT = '/var/log/fspirat-router-audit.log';   // действия в панели (кто, что, откуда) — без секретов
const FSR_COOKIE = 'fsr_session';
const FSR_COOKIE_DOMAIN = 'example.org';     // один вход для example.org/router/ и luci.example.org
const FSR_TTL_SHORT = 12 * 3600;               // без «Запомнить»: 12 часов
const FSR_TTL_LONG = 30 * 86400;               // с «Запомнить»: 30 дней (продлевается при работе)
const FSR_MAX_FAILS = 5;
const FSR_LOCK_SEC = 900;
const FSR_ROUTER_URL = 'http://127.0.0.1:8081/cgi-bin/fspirat';   // CGI роутера через туннель (для тестов — FSR_ROUTER)

// Как называть действие в Telegram; true — сообщать. Ключ — action в /router/api, «rename» и «apprevoke» — POST /router/data.
// Общая карта для веба (check.php) и приложения (app.php): одни и те же действия приходят в Telegram из обоих мест.
const FSR_ACTIONS = [
    'reboot' => ['🔄 Перезагрузка роутера', true], 'restart' => ['🔁 Перезапуск VPN', true],
    'update' => ['📥 Обновление подписки', true], 'switch' => ['🌍 Смена сервера', false],
    'block' => ['⛔ Интернет выключен устройству', true], 'unblock' => ['✅ Интернет включён устройству', true],
    'settargets' => ['📝 Изменён список сервисов', true],
    'subadd' => ['➕ Добавлена подписка VPN', true], 'subdel' => ['🗑 Удалена подписка VPN', true], 'subupdate' => ['📥 Обновление подписки', false],
    'rename' => ['✏️ Переименовано устройство', false],
    'apprevoke' => ['🔒 Доступ приложения отозван', true], 'apprevokeall' => ['📵 Выход на всех устройствах', true],
];

date_default_timezone_set('Europe/Moscow');

function fsr_dir(): string { return rtrim(getenv('FSR_DIR') ?: FSR_DIR, '/'); }
// Открытые настройки установки (пишет Deploy server из deploy.conf): ссылка LuCI, имя бота, свой Telegram-прокси
function fsr_site(): array {
    $j = json_decode((string)@file_get_contents(fsr_dir() . '/site.json'), true);
    $panels = array_values(array_filter((array)($j['panels'] ?? []), fn($d) => is_string($d) && preg_match('~^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$~', $d)));
    return ['luci' => (string)($j['luci'] ?? ''), 'bot' => (string)($j['bot'] ?? ''), 'mtg' => (string)($j['mtg'] ?? ''), 'panels' => $panels];
}

function fsr_db(): PDO
{
    static $db = null;
    if ($db) return $db;
    // ATTR_TIMEOUT — ждать до 10 с, если базу держит другой запрос (страница шлёт несколько запросов сразу).
    // Раньше journal_mode=WAL выполнялся до busy_timeout и сразу падал «database is locked» → check.php отвечал 401
    // и страница отправляла на вход. Режим WAL сохраняется в самой базе — включаем, только если ещё не включён.
    $db = new PDO('sqlite:' . fsr_dir() . '/auth.sqlite', null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC, PDO::ATTR_TIMEOUT => 10]);
    $db->exec('PRAGMA busy_timeout=10000');
    if (strtolower((string)$db->query('PRAGMA journal_mode')->fetchColumn()) !== 'wal') $db->exec('PRAGMA journal_mode=WAL');
    $db->exec('CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, created INTEGER NOT NULL, seen INTEGER NOT NULL,
                 ttl INTEGER NOT NULL, ip TEXT, ua TEXT)');
    $db->exec('CREATE TABLE IF NOT EXISTS fails(ip TEXT NOT NULL, ts INTEGER NOT NULL)');
    $db->exec('CREATE INDEX IF NOT EXISTS fails_ip ON fails(ip, ts)');
    return $db;
}

/**
 * Домен панели этого запроса. Обычно один (PANEL_DOMAIN), но при переезде на новый домен панель работает на обоих
 * (site.json «panels» — PANEL_DOMAIN и PANEL_ALIASES из deploy.conf): на каждом свой вход, cookie — на свой домен.
 * Поддомены (LuCI: router.<домен>) относятся к своему домену. Чужой Host — основной домен.
 */
function fsr_panel(): string
{
    $host = strtolower((string)preg_replace('~:\d+$~', '', (string)($_SERVER['HTTP_HOST'] ?? '')));
    foreach (fsr_site()['panels'] as $d) {
        if ($host === $d || str_ends_with($host, '.' . $d)) return $d;
    }
    return FSR_COOKIE_DOMAIN;
}
/** Домен cookie (для локальных тестов — FSR_COOKIE_DOMAIN="" — без домена). */
function fsr_cookie_domain(): string { $d = getenv('FSR_COOKIE_DOMAIN'); return $d === false ? fsr_panel() : $d; }
/** Origin страницы панели — с ним приходят действия (POST); для тестов — FSR_ORIGIN. */
function fsr_origin(): string { return getenv('FSR_ORIGIN') ?: 'https://' . fsr_panel(); }

function fsr_ip(): string { return $_SERVER['REMOTE_ADDR'] ?? ''; }

/** Строка журнала входов «ДАТА ВРЕМЯ ЧТО ip=… ua="…"». $ip/$ua — когда пишет не сам клиент (бот о входе приложения). */
function fsr_log(string $what, ?string $ip = null, ?string $ua = null): void
{
    $ua = preg_replace('/[^\x20-\x7e]/', '', substr($ua ?? ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 120));
    $ip = preg_replace('/[^0-9A-Fa-f.:]/', '', $ip ?? fsr_ip());
    @file_put_contents(getenv('FSR_LOG') ?: FSR_LOG, date('Y-m-d H:i:s') . " $what ip=" . $ip . " ua=\"$ua\"\n", FILE_APPEND | LOCK_EX);
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
    $st->closeCursor();
    return (int)$r['n'] >= FSR_MAX_FAILS ? max(1, (int)$r['last'] + FSR_LOCK_SEC - time()) : 0;
}

/** Неудачная попытка (пароль, код, неверное число в боте). $ip — чья: по умолчанию этого запроса. Возвращает, сколько осталось. */
function fsr_fail(?string $ip = null): int
{
    $ip ??= fsr_ip();
    fsr_db()->prepare('INSERT INTO fails(ip, ts) VALUES(?, ?)')->execute([$ip, time()]);
    return fsr_fails_left($ip);
}

/** Сколько попыток ещё осталось адресу (заодно чистка записей старше суток). */
function fsr_fails_left(?string $ip = null): int
{
    $db = fsr_db();
    $db->prepare('DELETE FROM fails WHERE ts < ?')->execute([time() - 86400]);
    $st = $db->prepare('SELECT COUNT(*) FROM fails WHERE ip = ? AND ts > ?');
    $st->execute([$ip ?? fsr_ip(), time() - FSR_LOCK_SEC]);
    return FSR_MAX_FAILS - (int)$st->fetchColumn();
}

/**
 * Попытка входа по паролю (веб и приложение) — до проверки пароля: блокировка проверяется, и попытка сразу записывается
 * в fails как неудачная, одной транзакцией (BEGIN IMMEDIATE — запись в базу по одному). Иначе пачка параллельных запросов
 * с одного адреса, пока каждый ждёт bcrypt и паузу, видит «0 ошибок» и проверяет пароль вся: больше 5 попыток за раз,
 * а ошибки пачки ещё и закрывают вход приложения всем (подбор с разных адресов, fsr_app_spray_check).
 * → секунд до конца блокировки (0 — можно проверять пароль). $id — запись попытки: пароль верный — её убирает
 * fsr_attempt_ok($id), неверный — она и есть ошибка (fsr_fails_left() — сколько осталось).
 */
function fsr_attempt(?int &$id): int
{
    $id = null;
    $db = fsr_db();
    $db->exec('BEGIN IMMEDIATE');
    try {
        $wait = fsr_locked();
        if (!$wait) {
            $db->prepare('INSERT INTO fails(ip, ts) VALUES(?, ?)')->execute([fsr_ip(), time()]);
            $id = (int)$db->lastInsertId();
        }
        $db->exec('COMMIT');
    } catch (Throwable $e) {
        try { $db->exec('ROLLBACK'); } catch (Throwable) {}
        throw $e;
    }
    return $wait;
}

/** Пароль верный: убрать запись попытки (fsr_attempt). Сверка с ip — rowid удалённой строки SQLite может отдать новой. */
function fsr_attempt_ok(?int $id): void
{
    if ($id) fsr_db()->prepare('DELETE FROM fails WHERE rowid = ? AND ip = ?')->execute([$id, fsr_ip()]);
}

// ---------- сессии ----------

function fsr_cookie(string $value, int $expires): void
{
    setcookie(FSR_COOKIE, $value, [
        'expires' => $expires, 'path' => '/', 'domain' => fsr_cookie_domain(),
        // Strict: с чужого сайта cookie не уйдёт вообще (luci.example.org — тот же сайт, ему уходит)
        'secure' => true, 'httponly' => true, 'samesite' => 'Strict',
    ]);
}

function fsr_session_start(bool $remember): void
{
    $tok = bin2hex(random_bytes(32));
    $ttl = $remember ? FSR_TTL_LONG : FSR_TTL_SHORT;
    $db = fsr_db();
    // время — числом: строковый параметр SQLite считает «больше любого числа», и удалялись ВСЕ сессии (вход выкидывал другие устройства)
    $st = $db->prepare('DELETE FROM sessions WHERE seen + ttl < ?');
    $st->bindValue(1, time(), PDO::PARAM_INT);
    $st->execute();
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
    $st->closeCursor();          // иначе чтение держит снимок базы и UPDATE ниже сразу получает «database is locked»
    if (!$r || $r['seen'] + $r['ttl'] < time()) return false;
    if (time() - $r['seen'] > 300) $db->prepare('UPDATE sessions SET seen = ? WHERE hash = ?')->execute([time(), hash('sha256', $tok)]);
    return true;
}

/** Выход. $all — закрыть все сессии (на всех устройствах), иначе только эту.
 *  «На всех устройствах» (решение владельца 13.10.2026) — ещё и ключи приложения (revoked_by=all) и запомненные браузеры
 *  (таблица devices: на любом браузере снова спросят код из Telegram). Возвращает, сколько ключей приложения отозвано. */
function fsr_session_end(bool $all = false): int
{
    $tok = $_COOKIE[FSR_COOKIE] ?? '';
    $n = 0;
    if ($all) {
        fsr_db()->exec('DELETE FROM sessions');
        require_once __DIR__ . '/app-lib.php';
        $n = fsr_app_revoke_all('all');
        fsr_db2()->exec('DELETE FROM devices');
    } elseif (preg_match('/^[a-f0-9]{64}$/', $tok)) fsr_db()->prepare('DELETE FROM sessions WHERE hash = ?')->execute([hash('sha256', $tok)]);
    fsr_cookie('', 1);
    return $n;
}

// ---------- защита действий: CSRF-токен и журнал ----------

/** Токен сессии из cookie (или '' — нет/кривой). */
function fsr_session_token(): string
{
    $tok = $_COOKIE[FSR_COOKIE] ?? '';
    return preg_match('/^[a-f0-9]{64}$/', $tok) ? $tok : '';
}

/** CSRF-токен этой сессии: HMAC от токена сессии. Чужой сайт его не знает (cookie HttpOnly, ответ data.php ему не прочитать);
 *  с новой сессией меняется сам. Страница берёт его из /router/data?csrf=1 и шлёт в заголовке X-FSR. */
function fsr_csrf(): string
{
    $tok = fsr_session_token();
    return $tok === '' ? '' : substr(hash_hmac('sha256', 'fspirat-csrf-v1', $tok), 0, 48);
}

/** Короткая ссылка на сессию для журнала (не сам токен и не его полный хэш). */
function fsr_session_ref(): string
{
    $tok = fsr_session_token();
    return $tok === '' ? '-' : substr(hash('sha256', $tok), 0, 8);
}

/** Журнал действий: «время ДЕЙСТВИЕ детали ip=… s=… ua="…"». Токены, пароли и коды сюда не попадают.
 *  $ref — кто: по умолчанию сессия веба (8 hex), у приложения — «a:<id устройства>». */
function fsr_audit(string $action, string $detail = '', ?string $ref = null): void
{
    $clean = fn(string $v, int $n) => preg_replace('/[^\x20-\x7e\x{0400}-\x{04ff}\x{2192}]/u', '', mb_substr($v, 0, $n));
    $ua = $clean($_SERVER['HTTP_USER_AGENT'] ?? '', 120);
    @file_put_contents(getenv('FSR_AUDIT') ?: FSR_AUDIT, date('Y-m-d H:i:s') . ' ' . $clean($action, 20) . ($detail !== '' ? ' ' . $clean($detail, 120) : '')
        . ' ip=' . fsr_ip() . ' s=' . $clean($ref ?? fsr_session_ref(), 20) . " ua=\"$ua\"\n", FILE_APPEND | LOCK_EX);
}

/** Куда вернуться после входа: только наши адреса. */
function fsr_next(string $next): string
{
    if (preg_match('~^/router/[A-Za-z0-9/._?=&%-]*$~', $next) && !str_starts_with($next, '/router/login')) return $next;
    // LuCI и другие поддомены того же домена панели (router.<домен>) — cookie входа общая
    if (preg_match('~^https://([a-z0-9.-]+)/[A-Za-z0-9/._?=&%;:+-]*$~', $next, $m) && str_ends_with($m[1], '.' . fsr_panel())) return $next;
    if (preg_match('~^/vds/[A-Za-z0-9/._?=&%-]*$~', $next)) return $next;   // панель домашнего сервера (MacBook)
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

/** Адрес Bot API (для тестов — заглушка в FSR_TG_API). */
function fsr_tg_api(): string { return rtrim(getenv('FSR_TG_API') ?: 'https://api.telegram.org', '/'); }

function fsr_tg_send(string $text): bool
{
    $c = fsr_tg();
    if (!$c) return false;
    $raw = @file_get_contents(fsr_tg_api() . '/bot' . $c['token'] . '/sendMessage', false, stream_context_create(['http' => [
        'method' => 'POST', 'header' => 'Content-Type: application/x-www-form-urlencoded', 'timeout' => 8, 'ignore_errors' => true,
        'content' => http_build_query(['chat_id' => $c['chat'], 'text' => $text, 'disable_web_page_preview' => 'true'])]]));
    return (bool)(json_decode((string)$raw, true)['ok'] ?? false);
}

/** Любой метод Bot API (JSON). Ответ Telegram или null (бот не настроен, нет связи). Токен бота в журналы не попадает. */
function fsr_tg_call(string $method, array $p, int $timeout = 10): ?array
{
    $c = fsr_tg();
    if (!$c) return null;
    $raw = @file_get_contents(fsr_tg_api() . '/bot' . $c['token'] . '/' . $method, false, stream_context_create(['http' => [
        'method' => 'POST', 'header' => 'Content-Type: application/json', 'timeout' => $timeout, 'ignore_errors' => true,
        'content' => json_encode($p, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE)]]));
    $j = json_decode((string)$raw, true);
    return is_array($j) ? $j : null;
}

/** Отложить работу (сообщения в Telegram) на после ответа: клиент не ждёт Telegram. */
function fsr_later(callable $fn): void
{
    static $q = null;
    if ($q === null) {
        $q = [];
        register_shutdown_function(static function () use (&$q): void {
            if (!$q) return;
            if (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
            foreach ($q as $f) {
                try { $f(); } catch (Throwable $e) { error_log('fspirat-router-auth later: ' . $e->getMessage()); }
            }
        });
    }
    $q[] = $fn;
}

function fsr_aux_cookie(string $name, string $value, int $expires): void
{
    setcookie($name, $value, ['expires' => $expires, 'path' => '/router/', 'domain' => fsr_cookie_domain(),
        'secure' => true, 'httponly' => true, 'samesite' => 'Strict']);
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
    $st->closeCursor();
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
    $st->closeCursor();
    if (!$r) return null;
    if (!preg_match('/^\d{6}$/', $code) || !password_verify($code, $r['code'])) {
        $db->prepare('UPDATE codes SET tries = tries + 1 WHERE hash = ?')->execute([$h]);
        return null;
    }
    $db->prepare('DELETE FROM codes WHERE hash = ?')->execute([$h]);
    fsr_aux_cookie(FSR_CODE_COOKIE, '', 1);
    return ['remember' => (bool)$r['remember'], 'next' => (string)$r['next']];
}

// ---------- CGI роутера напрямую (бот, приложение) ----------
// nginx (/router/api) подставляет токен сам; бот и приложение ходят в туннель мимо nginx, поэтому токен берут из
// fsr_dir()/router.token (пишет Deploy server из сниппета nginx). Токен — только в cookie запроса, в журналы не попадает.

/**
 * Разобрать JSON роутера. Если не разбирается — одна попытка починить: управляющие символы внутри строк
 * (имя узла или устройства с таким символом ломает status, §5 п.22) экранируются, битый UTF-8 заменяется.
 * Возвращает [массив|null, текст JSON]: текст — как прислал роутер или исправленный (объекты {} не превращаются в []).
 */
function fsr_json_fix(string $raw): array
{
    $t = trim($raw);
    if ($t === '') return [null, ''];
    $j = json_decode($t, true);
    if (is_array($j)) return [$j, $t];
    $out = ''; $in = false; $esc = false; $n = strlen($t);
    for ($i = 0; $i < $n; $i++) {
        $c = $t[$i]; $o = ord($c);
        if ($in) {
            if ($esc) $esc = false;
            elseif ($c === '\\') $esc = true;
            elseif ($c === '"') $in = false;
            elseif ($o < 0x20) { $out .= sprintf('\\u%04x', $o); continue; }
        } elseif ($c === '"') $in = true;
        elseif ($o < 0x20 && $c !== "\t" && $c !== "\n" && $c !== "\r") continue;
        $out .= $c;
    }
    $o = json_decode($out, false, 512, JSON_INVALID_UTF8_SUBSTITUTE);
    if (!is_array($o) && !is_object($o)) return [null, $t];
    $fixed = (string)json_encode($o, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION);
    return [json_decode($fixed, true), $fixed];
}

/**
 * Вызов CGI роутера. → [HTTP-код, ответ (массив) или null, текст ответа].
 * Ошибки без ответа роутера: [500 server_config] — нет router.token; [502 router_offline] — туннель оборван;
 * [504 router_timeout] — роутер не ответил за $timeout; [500 router_token] — роутер ответил 403 forbidden
 * (ключ не совпадает: Telegram не чаще раза в час). Тело ответа не JSON — массив null, разбирает вызывающий.
 * 'sent' => false в ответе — запрос до роутера точно не дошёл (нет router.token, порт туннеля закрыт): действие не выполнено.
 */
function fsr_router_call(string $action, array $q = [], string $method = 'GET', int $timeout = 20, string $body = ''): array
{
    $tok = trim((string)@file_get_contents(fsr_dir() . '/router.token'));
    if (!preg_match('/^[A-Za-z0-9]{16,128}$/', $tok)) return [500, ['error' => 'server_config', 'sent' => false], ''];
    $url = (getenv('FSR_ROUTER') ?: FSR_ROUTER_URL) . '?' . http_build_query(['action' => $action] + $q, '', '&', PHP_QUERY_RFC3986);
    $opt = ['method' => $method, 'timeout' => $timeout, 'ignore_errors' => true, 'follow_location' => 0,
            'header' => "Cookie: fspirat_token=$tok\r\n" . ($body !== '' ? "Content-Type: application/x-www-form-urlencoded\r\n" : ($method === 'POST' ? "Content-Length: 0\r\n" : ''))];
    if ($body !== '') $opt['content'] = $body;
    $t0 = microtime(true);
    error_clear_last();
    $fp = @fopen($url, 'r', false, stream_context_create(['http' => $opt]));
    if (!$fp) {
        if (microtime(true) - $t0 >= $timeout - 0.5) return [504, ['error' => 'router_timeout'], ''];
        // «Connection refused» — порт туннеля никто не слушает, запрос не ушёл; иначе (соединение было) мог и дойти
        $refused = str_contains((string)(error_get_last()['message'] ?? ''), 'Connection refused');
        return [502, ['error' => 'router_offline'] + ($refused ? ['sent' => false] : []), ''];
    }
    $code = 0;
    foreach ((array)(stream_get_meta_data($fp)['wrapper_data'] ?? []) as $h) {
        if (is_string($h) && preg_match('~^HTTP/\S+\s+(\d{3})~', $h, $m)) $code = (int)$m[1];
    }
    $raw = (string)stream_get_contents($fp);
    $timedOut = (bool)(stream_get_meta_data($fp)['timed_out'] ?? false);
    fclose($fp);
    if ($timedOut) return [504, ['error' => 'router_timeout'], ''];
    if ($code === 0) return [502, ['error' => 'router_offline'], ''];
    [$j, $raw] = fsr_json_fix($raw);
    if ($code === 403 && ($j['error'] ?? '') === 'forbidden') {
        $f = fsr_dir() . '/router_token_alert';
        if (time() - (int)@filemtime($f) > 3600) {
            @touch($f);
            fsr_later(fn() => fsr_tg_send("⚠️ Роутер отклонил ключ сервера (403 forbidden): router.token не совпадает с ключом на роутере.\n"
                . 'Бот и приложение не могут управлять роутером. Помогает workflow «Deploy server» — он перепишет router.token из сниппета nginx.'));
        }
        return [500, ['error' => 'router_token'], ''];
    }
    return [$code, $j, $raw];
}

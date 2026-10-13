<?php
/**
 * Приложение для iPhone (/router/app/v1, app.php): ключи устройств, вход через бота, подтверждения, лимиты, задачи.
 * Подключается после lib.php — из app.php, tgbot.php (кнопки входа, /apps), data.php (список в «Безопасности»)
 * и lib.php (выход на всех устройствах). Таблицы — в той же auth.sqlite, создаются при первом обращении.
 *
 * Ключ устройства: «fsr1_» + 43 символа base64url (256 бит). В базе только sha256 — как у сессий веба.
 * Живёт 90 дней с последнего запроса, но не дольше года со входа. Отозванные и истёкшие строки хранятся
 * ещё 30 дней после годового срока: старый телефон получает token_revoked/token_expired, а не token_invalid
 * (тот считается в fail2ban — бан закрыл бы дому и свой VPN-сервер NL на 443).
 */

declare(strict_types=1);

if (!defined('FSR')) { http_response_code(404); exit; }

const FSR_APP_TTL = 90 * 86400;            // ключ: 90 дней с последнего использования…
const FSR_APP_HARD = 365 * 86400;          // …но не дольше года с входа
const FSR_APP_KEEP = 30 * 86400;           // строку ключа удаляем через 30 дней после годового срока
const FSR_APP_SEEN_STEP = 300;             // продление — не чаще раза в 5 минут
const FSR_APP_LOGIN_TTL = 120;             // кнопки входа в боте
const FSR_APP_LOGIN_PICKUP = 180;          // одобренный вход приложение забирает опросом до 3 минут от начала
const FSR_APP_LOGIN_LOCK = 3600;           // «Это не я» / подбор с разных адресов — вход приложения по паролю закрыт на час
const FSR_APP_CONFIRM_TTL = 60;
const FSR_APP_MAX_DEVICES = 10;
const FSR_APP_TOKEN_RE = '/^fsr1_[A-Za-z0-9_-]{43}$/';

// Действия с перезапуском PassWall: общая пауза 15 с на все устройства и не больше 30 в час на устройство
const FSR_APP_PW = ['switch', 'restart', 'update', 'subupdate', 'direct', 'diradd', 'dirdel', 'svcdirect', 'zapretset'];
// Лимиты: [сколько, за сколько секунд, 'dev' — на устройство | 'all' — на все устройства]
const FSR_APP_LIMITS = [
    'ping' => [[1, 30, 'dev'], [30, 3600, 'dev']],
    'speedtest' => [[1, 120, 'dev'], [10, 3600, 'dev']],
    'pingone' => [[20, 60, 'dev']],
    'update' => [[6, 3600, 'dev']],
    'subupdate' => [[10, 3600, 'dev']],
    'reboot' => [[1, 300, 'all'], [3, 3600, 'all']],
    'block' => [[30, 3600, 'dev']],
    'unblock' => [[30, 3600, 'dev']],
    'schedule' => [[30, 3600, 'dev']],
    'zapretstrat' => [[10, 60, 'dev']],
    'zapretcheck' => [[1, 30, 'dev']],
    'tgwsset' => [[10, 3600, 'dev']],
    'ledset' => [[10, 60, 'dev']],
    'rename' => [[30, 3600, 'dev']],
    'revoke' => [[30, 3600, 'dev']],
    'revokeall' => [[5, 3600, 'dev']],
    'confirm' => [[20, 60, 'dev']],
];

function fsr_app_db(): PDO
{
    static $ready = false;
    $db = fsr_db();
    if ($ready) return $db;
    $db->exec('CREATE TABLE IF NOT EXISTS app_devices(id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                 model TEXT NOT NULL DEFAULT \'\', os TEXT NOT NULL DEFAULT \'\', app TEXT NOT NULL DEFAULT \'\',
                 created INTEGER NOT NULL, seen INTEGER NOT NULL, expires INTEGER NOT NULL, hard_expires INTEGER NOT NULL,
                 ip TEXT, last_ip TEXT, revoked INTEGER, revoked_by TEXT)');
    $db->exec('CREATE INDEX IF NOT EXISTS app_devices_rev ON app_devices(revoked, expires)');
    $db->exec('CREATE TABLE IF NOT EXISTS app_logins(hash TEXT PRIMARY KEY, tg_ref TEXT NOT NULL UNIQUE, number INTEGER NOT NULL,
                 tg_msg INTEGER, created INTEGER NOT NULL, decided INTEGER, state TEXT NOT NULL, device_id TEXT,
                 name TEXT, model TEXT, os TEXT, app TEXT, ip TEXT, ua TEXT)');
    $db->exec('CREATE INDEX IF NOT EXISTS app_logins_ip ON app_logins(ip, created)');
    $db->exec('CREATE TABLE IF NOT EXISTS app_confirms(hash TEXT PRIMARY KEY, device TEXT NOT NULL, action TEXT NOT NULL,
                 params TEXT NOT NULL, created INTEGER NOT NULL)');
    $db->exec('CREATE TABLE IF NOT EXISTS app_actions(device TEXT NOT NULL, action TEXT NOT NULL, ts INTEGER NOT NULL)');
    $db->exec('CREATE INDEX IF NOT EXISTS app_actions_dev ON app_actions(device, action, ts)');
    $db->exec('CREATE INDEX IF NOT EXISTS app_actions_act ON app_actions(action, ts)');
    $db->exec('CREATE TABLE IF NOT EXISTS app_jobs(id TEXT PRIMARY KEY, device TEXT NOT NULL, action TEXT NOT NULL,
                 created INTEGER NOT NULL, done INTEGER, http INTEGER, result TEXT)');
    $ready = true;
    return $db;
}

/** Запрос с параметрами: числа — как числа (строковый параметр SQLite считает «больше любого числа», см. fsr_session_start). */
function fsr_app_q(string $sql, array $args = []): PDOStatement
{
    $st = fsr_app_db()->prepare($sql);
    foreach (array_values($args) as $i => $v) {
        $st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : ($v === null ? PDO::PARAM_NULL : PDO::PARAM_STR));
    }
    $st->execute();
    return $st;
}

function fsr_app_row(string $sql, array $args = []): ?array
{
    $st = fsr_app_q($sql, $args);
    $r = $st->fetch();
    $st->closeCursor();
    return is_array($r) ? $r : null;
}

function fsr_app_hex(int $bytes): string { return bin2hex(random_bytes($bytes)); }

// ---------- ключи устройств ----------

function fsr_app_token_new(): string { return 'fsr1_' . rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '='); }

/** Годовой срок с запасом: даже если hard_expires в строке испорчен, ключ старше года не работает. */
function fsr_app_hard(array $d): int { return min((int)$d['hard_expires'], (int)$d['created'] + FSR_APP_HARD); }

function fsr_app_device_by_token(string $tok): ?array
{
    if (!preg_match(FSR_APP_TOKEN_RE, $tok)) return null;
    return fsr_app_row('SELECT * FROM app_devices WHERE token_hash = ?', [hash('sha256', $tok)]);
}

function fsr_app_device(string $id): ?array
{
    return preg_match('/^[a-f0-9]{16}$/', $id) ? fsr_app_row('SELECT * FROM app_devices WHERE id = ?', [$id]) : null;
}

/** Действующие ключи (не отозваны, не истекли), новые сверху. */
function fsr_app_active(): array
{
    $now = time();
    return fsr_app_q('SELECT * FROM app_devices WHERE revoked IS NULL AND expires > ? AND hard_expires > ? AND created > ? ORDER BY seen DESC',
        [$now, $now, $now - FSR_APP_HARD])->fetchAll();
}

/** Продлить ключ при работе (не чаще раза в 5 минут): 90 дней от сейчас, но не дальше годового срока. */
function fsr_app_touch(array $d): array
{
    $now = time();
    if ($now - (int)$d['seen'] <= FSR_APP_SEEN_STEP) return $d;
    $d['seen'] = $now;
    $d['expires'] = min($now + FSR_APP_TTL, fsr_app_hard($d));
    $d['last_ip'] = fsr_ip();
    fsr_app_q('UPDATE app_devices SET seen = ?, expires = ?, last_ip = ? WHERE id = ?', [$now, $d['expires'], $d['last_ip'], $d['id']]);
    return $d;
}

/** Отозвать ключ. $by: self, app:<id>, web, all, tg, url_leak, ops. → строка устройства (до отзыва) или null (нет / уже отозван). */
function fsr_app_revoke(string $id, string $by): ?array
{
    $d = fsr_app_device($id);
    if (!$d || $d['revoked'] !== null) return null;
    $st = fsr_app_q('UPDATE app_devices SET revoked = ?, revoked_by = ? WHERE id = ? AND revoked IS NULL', [time(), $by, $id]);
    return $st->rowCount() === 1 ? $d : null;
}

function fsr_app_revoke_token(string $tok, string $by): ?array
{
    $d = fsr_app_device_by_token($tok);
    return $d ? fsr_app_revoke((string)$d['id'], $by) : null;
}

/** Отозвать все ключи; $web — заодно закрыть все сессии веба и забыть запомненные браузеры. → сколько ключей отозвано.
 *  Сначала закрываются входы, которые ждут нажатия или ещё не забрали ключ: иначе одобренный вход получил бы ключ уже после
 *  отзыва (опрос до 3 минут). Порядок важен: выдача ключа (fsr_app_login_issue) — одна транзакция, поэтому ключ либо уже
 *  выдан и отзывается ниже, либо вход закрыт и ключа не будет. */
function fsr_app_revoke_all(string $by, bool $web = false): int
{
    fsr_app_logins_close('выход на всех устройствах');
    $n = fsr_app_q('UPDATE app_devices SET revoked = ?, revoked_by = ? WHERE revoked IS NULL', [time(), $by])->rowCount();
    if ($web) {
        fsr_db()->exec('DELETE FROM sessions');
        fsr_db2()->exec('DELETE FROM devices');
    }
    return $n;
}

/** «имя» · модель · iOS — для Telegram и окон (без IP). */
function fsr_app_label(array $d): string
{
    $parts = array_filter([(string)($d['model'] ?? ''), (string)($d['os'] ?? '')], fn($x) => $x !== '');
    return '«' . (string)($d['name'] ?? '?') . '»' . ($parts ? ' · ' . implode(' · ', $parts) : '');
}

/** Кто отозвал — словами для Telegram. */
function fsr_app_by_text(string $by): string
{
    if (str_starts_with($by, 'app:')) {
        $d = fsr_app_device(substr($by, 4));
        return 'из приложения ' . ($d ? '«' . $d['name'] . '»' : '');
    }
    return match ($by) {
        'self' => 'выход на этом устройстве',
        'web' => 'из веб-панели',
        'all' => '«Выйти на всех устройствах» в веб-панели',
        'tg' => 'из Telegram',
        'url_leak' => 'ключ попал в адрес запроса',
        'ops' => 'на сервере',
        default => $by,
    };
}

// ---------- вход: пароль + число в боте (б′) ----------

/** Нужен ли пароль при входе в приложение (site.json app_password, по умолчанию да; 0 — только число в боте). */
function fsr_app_password_required(): bool
{
    $j = json_decode((string)@file_get_contents(fsr_dir() . '/site.json'), true);
    $v = is_array($j) ? ($j['app_password'] ?? 1) : 1;
    return !($v === 0 || $v === false || $v === '0');
}

/** Бот принимает нажатия кнопок (webhook настроен: есть секрет tgbot.json) и знает чат владельца. */
function fsr_app_bot_ok(): bool
{
    $cfg = json_decode((string)@file_get_contents(fsr_dir() . '/tgbot.json'), true);
    return fsr_tg() !== null && is_array($cfg) && !empty($cfg['secret']);
}

/** Общий замок входа приложения по паролю («Это не я», подбор с разных адресов): сколько секунд ещё закрыт. */
function fsr_app_login_lock(): int
{
    $until = (int)trim((string)@file_get_contents(fsr_dir() . '/app_login_lock'));
    return max(0, $until - time());
}

/** Закрыть вход приложения по паролю на $sec секунд. Входы, которые уже ждут нажатия или одобрены, но ключ ещё не забран, —
 *  тоже закрыть: замок обещает «вход закрыт», а второй вход того же человека иначе прошёл бы (выдачу ключа замок тоже держит). */
function fsr_app_login_lock_set(int $sec): void
{
    @file_put_contents(fsr_dir() . '/app_login_lock', (string)(time() + $sec) . "\n", LOCK_EX);
    fsr_app_logins_close('вход в приложение по паролю закрыт на час');
}

/** Подбор с разных адресов: больше 30 ошибок за час со всех IP — вход приложения по паролю закрыт на час, одно сообщение. */
function fsr_app_spray_check(): void
{
    if (fsr_app_login_lock() > 0) return;
    $n = (int)fsr_app_q('SELECT COUNT(*) FROM fails WHERE ts > ?', [time() - 3600])->fetchColumn();
    if ($n <= 30) return;
    fsr_app_login_lock_set(FSR_APP_LOGIN_LOCK);
    fsr_audit('APP_LOCK', "spray fails=$n", '-');
    fsr_later(fn() => fsr_tg_send("⚠️ Похоже на подбор пароля панели с разных адресов: за час $n неверных попыток.\n"
        . "Вход в приложение по паролю закрыт на 1 час. Веб-панель новый браузер пускает только с кодом из Telegram.\n"
        . 'Если это не ты — смени пароль: удали /var/lib/fspirat-router-auth/password и обнови .htpasswd_router (через ops: htpasswd /etc/nginx/.htpasswd_router bob).'));
}

/** Новый вход: [login_id (64 hex, только приложению), число на экране, 3 числа для кнопок, tg_ref]. */
function fsr_app_login_create(array $dev): array
{
    $loginId = fsr_app_hex(32);
    $number = random_int(10, 99);
    $nums = [$number];
    while (count($nums) < 3) {
        $x = random_int(10, 99);
        if (!in_array($x, $nums, true)) $nums[] = $x;
    }
    for ($i = count($nums) - 1; $i > 0; $i--) { $k = random_int(0, $i); [$nums[$i], $nums[$k]] = [$nums[$k], $nums[$i]]; }
    $ref = fsr_app_hex(6);
    fsr_app_q('INSERT INTO app_logins(hash, tg_ref, number, tg_msg, created, decided, state, device_id, name, model, os, app, ip, ua)
               VALUES(?,?,?,NULL,?,NULL,\'pending\',NULL,?,?,?,?,?,?)',
        [hash('sha256', $loginId), $ref, $number, time(), $dev['name'], $dev['model'], $dev['os'], $dev['app'], fsr_ip(),
         substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 200)]);
    return [$loginId, $number, $nums, $ref];
}

function fsr_app_login_get(string $loginId): ?array
{
    return preg_match('/^[a-f0-9]{64}$/', $loginId) ? fsr_app_row('SELECT * FROM app_logins WHERE hash = ?', [hash('sha256', $loginId)]) : null;
}

function fsr_app_login_by_ref(string $ref): ?array
{
    return preg_match('/^[a-f0-9]{12}$/', $ref) ? fsr_app_row('SELECT * FROM app_logins WHERE tg_ref = ?', [$ref]) : null;
}

/** Сменить состояние входа, только если оно ещё $from (два нажатия или опрос с нажатием не пересекутся). */
function fsr_app_login_state(string $hash, array $from, string $to): bool
{
    $in = implode(',', array_fill(0, count($from), '?'));
    return fsr_app_q("UPDATE app_logins SET state = ?, decided = ? WHERE hash = ? AND state IN ($in)", array_merge([$to, time(), $hash], $from))->rowCount() === 1;
}

/** Закрыть все входы, которые ждут нажатия или одобрены, но ключ ещё не забран (state → expired), и поправить их сообщения
 *  в боте. $why — причина словами. → сколько закрыто. */
function fsr_app_logins_close(string $why): int
{
    $n = 0;
    foreach (fsr_app_q('SELECT * FROM app_logins WHERE state IN (\'pending\', \'approved\')')->fetchAll() as $r) {
        if (!fsr_app_login_state((string)$r['hash'], ['pending', 'approved'], 'expired')) continue;
        fsr_app_login_edit_later($r, "🚫 Вход в приложение отменён: $why.\n" . fsr_app_login_label($r));
        $n++;
    }
    return $n;
}

/** Текст о входе для Telegram: «имя» · модель · iOS · IP. */
function fsr_app_login_label(array $r): string { return fsr_app_label($r) . ' · IP ' . (string)$r['ip']; }

/**
 * Нажатие кнопки входа в боте (проверки from.id и message_id — в tgbot.php). $number — число с кнопки, null — «Это не я».
 * → ['text' => новый текст сообщения или null (ничего не менять), 'alarm' => тревога отдельным сообщением или ''].
 */
function fsr_app_login_decide(array $r, ?int $number): array
{
    if ($r['state'] !== 'pending') return ['text' => null, 'alarm' => ''];
    $who = fsr_app_login_label($r);
    if ((int)$r['created'] + FSR_APP_LOGIN_TTL < time()) {
        fsr_app_login_state($r['hash'], ['pending'], 'expired');
        return ['text' => "⌛ Время вышло — вход в приложение не выполнен.\n$who", 'alarm' => ''];
    }
    if ($number !== null && $number === (int)$r['number']) {
        if (!fsr_app_login_state($r['hash'], ['pending'], 'approved')) return ['text' => null, 'alarm' => ''];
        return ['text' => "✅ Вход в приложение разрешён.\n$who", 'alarm' => ''];
    }
    $notme = $number === null;
    if (!fsr_app_login_state($r['hash'], ['pending'], $notme ? 'notme' : 'denied')) return ['text' => null, 'alarm' => ''];
    // ошибка — тому адресу, с которого входили (не адресу Telegram), как неверный пароль: общая блокировка с вебом
    fsr_fail((string)$r['ip']);
    fsr_log('APP_DENIED', (string)$r['ip'], (string)$r['ua']);
    fsr_audit('APP_DENIED', ($notme ? 'notme ' : 'number ') . 'ip=' . $r['ip'], '-');
    if (!$notme) return ['text' => "❌ Число не совпало — вход отклонён.\n$who\nЕсли входил ты — начни вход в приложении заново.", 'alarm' => ''];
    fsr_app_login_lock_set(FSR_APP_LOGIN_LOCK);
    return ['text' => "🚫 Вход отклонён: «Это не я».\n$who",
        'alarm' => "⚠️ Кто-то ввёл верный пароль панели и пытался войти в приложение: $who.\n"
            . "Вход в приложение по паролю закрыт на 1 час. Веб-панель новый браузер пускает только с кодом из Telegram.\n"
            . "Пароль знает посторонний — смени его: удали /var/lib/fspirat-router-auth/password и обнови .htpasswd_router "
            . '(через ops: htpasswd /etc/nginx/.htpasswd_router bob). Список телефонов — /apps.'];
}

/** Выдать ключ по одобренному входу (один раз). → [строка устройства, ключ] или строка ошибки:
 *  'expired' | 'too_many_devices' | 'locked' (пока вход ждал опроса, закрыли вход по паролю: «Это не я», подбор). */
function fsr_app_login_issue(array $r): array|string
{
    $db = fsr_app_db();
    $db->exec('BEGIN IMMEDIATE');
    try {
        $cur = fsr_app_row('SELECT * FROM app_logins WHERE hash = ?', [$r['hash']]);
        if (!$cur || $cur['state'] !== 'approved') { $db->exec('ROLLBACK'); return 'expired'; }
        if (fsr_app_login_lock() > 0) {
            fsr_app_q('UPDATE app_logins SET state = \'expired\' WHERE hash = ?', [$r['hash']]);
            $db->exec('COMMIT');
            return 'locked';
        }
        if (count(fsr_app_active()) >= FSR_APP_MAX_DEVICES) { $db->exec('ROLLBACK'); return 'too_many_devices'; }
        $now = time();
        $tok = fsr_app_token_new();
        $d = ['id' => fsr_app_hex(8), 'name' => (string)$cur['name'], 'model' => (string)$cur['model'], 'os' => (string)$cur['os'],
              'app' => (string)$cur['app'], 'created' => $now, 'seen' => $now, 'expires' => $now + FSR_APP_TTL,
              'hard_expires' => $now + FSR_APP_HARD, 'ip' => (string)$cur['ip'], 'last_ip' => fsr_ip()];
        fsr_app_q('INSERT INTO app_devices(id, token_hash, name, model, os, app, created, seen, expires, hard_expires, ip, last_ip, revoked, revoked_by)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,NULL,NULL)',
            [$d['id'], hash('sha256', $tok), $d['name'], $d['model'], $d['os'], $d['app'], $now, $now, $d['expires'], $d['hard_expires'], $d['ip'], $d['last_ip']]);
        fsr_app_q('UPDATE app_logins SET state = \'issued\', device_id = ? WHERE hash = ?', [$d['id'], $r['hash']]);
        fsr_app_q('DELETE FROM fails WHERE ip = ?', [(string)$cur['ip']]);   // как после входа в веб
        $db->exec('COMMIT');
        return [$d, $tok];
    } catch (Throwable $e) {
        try { $db->exec('ROLLBACK'); } catch (Throwable) {}
        throw $e;
    }
}

/** Поправить сообщение бота о входе (отмена, время вышло) — после ответа приложению. Без parse_mode: имя задаёт пользователь. */
function fsr_app_login_edit_later(array $r, string $text): void
{
    $c = fsr_tg();
    if (!$c || !$r['tg_msg']) return;
    $p = ['chat_id' => $c['chat'], 'message_id' => (int)$r['tg_msg'], 'text' => $text];
    fsr_later(fn() => fsr_tg_call('editMessageText', $p));
}

// ---------- лимиты ----------

/** Сколько секунд ждать до действия ($action) с устройства $dev; 0 — можно. */
function fsr_app_limit(string $dev, string $action): int
{
    $rules = [];
    foreach (FSR_APP_LIMITS[$action] ?? [] as $r) $rules[] = [$r[0], $r[1], $r[2], [$action]];
    if (in_array($action, FSR_APP_PW, true)) { $rules[] = [1, 15, 'all', FSR_APP_PW]; $rules[] = [30, 3600, 'dev', FSR_APP_PW]; }
    $now = time(); $wait = 0;
    foreach ($rules as [$n, $win, $scope, $acts]) {
        $in = implode(',', array_fill(0, count($acts), '?'));
        $args = array_merge($acts, $scope === 'dev' ? [$dev] : [], [$now - $win, $n]);
        $ts = fsr_app_q("SELECT ts FROM app_actions WHERE action IN ($in)" . ($scope === 'dev' ? ' AND device = ?' : '')
            . ' AND ts > ? ORDER BY ts DESC LIMIT ?', $args)->fetchAll(PDO::FETCH_COLUMN);
        if (count($ts) >= $n) $wait = max($wait, (int)end($ts) + $win - $now, 1);
    }
    return $wait;
}

/** Записать действие для лимитов. → rowid записи (для fsr_app_unhit). */
function fsr_app_hit(string $dev, string $action): int
{
    fsr_app_q('INSERT INTO app_actions(device, action, ts) VALUES(?,?,?)', [$dev, $action, time()]);
    return (int)fsr_app_db()->lastInsertId();
}

/** Убрать запись действия: роутер его точно не выполнил (app_router_not_run) — в лимиты и паузу PW не идёт. */
function fsr_app_unhit(int $rowid): void
{
    fsr_app_q('DELETE FROM app_actions WHERE rowid = ?', [$rowid]);
}

// ---------- подтверждения (428 → confirm) ----------

function fsr_app_params_hash(array $p): string
{
    ksort($p);
    return hash('sha256', (string)json_encode($p, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
}

function fsr_app_confirm_new(string $dev, string $action, array $p): string
{
    $c = fsr_app_hex(16);
    fsr_app_q('INSERT INTO app_confirms(hash, device, action, params, created) VALUES(?,?,?,?,?)',
        [hash('sha256', $c), $dev, $action, fsr_app_params_hash($p), time()]);
    return $c;
}

/** Проверить и погасить подтверждение. → 'ok' | 'invalid' (нет, чужое, другое действие или параметры) | 'expired'. */
function fsr_app_confirm_use(string $dev, string $action, array $p, string $confirm): string
{
    if (!preg_match('/^[a-f0-9]{32}$/', $confirm)) return 'invalid';
    $h = hash('sha256', $confirm);
    $r = fsr_app_row('SELECT * FROM app_confirms WHERE hash = ?', [$h]);
    if (!$r) return 'invalid';
    // одноразовое: удаляем при любой попытке; гонка двух одинаковых запросов — пройдёт только один
    if (fsr_app_q('DELETE FROM app_confirms WHERE hash = ?', [$h])->rowCount() !== 1) return 'invalid';
    if ((int)$r['created'] < time() - FSR_APP_CONFIRM_TTL) return 'expired';
    if (!hash_equals((string)$r['device'], $dev) || $r['action'] !== $action || !hash_equals((string)$r['params'], fsr_app_params_hash($p))) return 'invalid';
    return 'ok';
}

// ---------- долгие задачи (ping, speedtest) ----------

function fsr_app_job_new(string $dev, string $action): string
{
    $id = fsr_app_hex(8);
    fsr_app_q('INSERT INTO app_jobs(id, device, action, created, done, http, result) VALUES(?,?,?,?,NULL,NULL,NULL)', [$id, $dev, $action, time()]);
    return $id;
}

function fsr_app_job_done(string $id, int $http, string $result): void
{
    fsr_app_q('UPDATE app_jobs SET done = ?, http = ?, result = ? WHERE id = ?', [time(), $http, $result, $id]);
}

function fsr_app_job_get(string $id, string $dev): ?array
{
    return preg_match('/^[a-f0-9]{16}$/', $id) ? fsr_app_row('SELECT * FROM app_jobs WHERE id = ? AND device = ?', [$id, $dev]) : null;
}

/** Замок-файл (flock) в fsr_dir(): ресурс — держит замок, пока жив; null — занято. */
function fsr_app_flock(string $name)
{
    $fp = @fopen(fsr_dir() . '/' . $name, 'c');
    if (!$fp) throw new RuntimeException("lock $name");
    if (!flock($fp, LOCK_EX | LOCK_NB)) { fclose($fp); return null; }
    return $fp;
}

// ---------- чистка ----------

/** Раз в сто запросов (счётчик в файле — предсказуемо и для тестов). */
function fsr_app_gc_tick(): void
{
    $fp = @fopen(fsr_dir() . '/app_gc', 'c+');
    if (!$fp) return;
    flock($fp, LOCK_EX);
    $n = (int)stream_get_contents($fp) + 1;
    ftruncate($fp, 0); rewind($fp); fwrite($fp, (string)$n);
    flock($fp, LOCK_UN); fclose($fp);
    if ($n % 100 === 0) fsr_app_gc();
}

function fsr_app_gc(): void
{
    $now = time();
    fsr_app_q('DELETE FROM app_devices WHERE hard_expires < ?', [$now - FSR_APP_KEEP]);   // и отозванные — только после срока + 30 дней
    fsr_app_q('DELETE FROM app_logins WHERE created < ?', [$now - 30 * 86400]);
    fsr_app_q('UPDATE app_logins SET state = \'expired\' WHERE state IN (\'pending\', \'approved\') AND created < ?', [$now - FSR_APP_LOGIN_PICKUP]);
    fsr_app_q('DELETE FROM app_confirms WHERE created < ?', [$now - 3600]);   // просроченное ещё час узнаётся: снова 428, а не confirm_invalid
    fsr_app_q('DELETE FROM app_actions WHERE ts < ?', [$now - 2 * 86400]);
    fsr_app_q('DELETE FROM app_jobs WHERE created < ?', [$now - 3600]);
}

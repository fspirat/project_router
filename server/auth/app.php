<?php
// API приложения для iPhone: /router/app/v1/… (nginx: location ^~ /router/app/v1/ → этот файл; без auth_request и без cookie).
// Доступ — только по ключу устройства в заголовке «Authorization: Bearer fsr1_…» (вход: пароль + число в боте).
// Роутер — тот же CGI, что у панели и бота (fsr_router_call, туннель 127.0.0.1:8081), но мимо nginx и check.php,
// поэтому здесь же: проверка параметров (правила CGI), подтверждения опасных действий (428 → confirm), лимиты,
// журнал действий и Telegram. Ответ — всегда JSON: {"error":"код","message":"текст"} при ошибке. Спецификация — docs/ios/inventory.md §7.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';
require __DIR__ . '/app-lib.php';
require __DIR__ . '/data-lib.php';

const APP_PREFIX = '/router/app/v1';
const APP_NOT_IN_V1 = ['subadd', 'subdel', 'settargets'];          // в приложении — с v1.1 (решение владельца), пока только в вебе
const APP_ACTIONS = ['ping', 'speedtest', 'pingone', 'switch', 'restart', 'update', 'subupdate', 'reboot', 'block', 'unblock',
    'direct', 'schedule', 'diradd', 'dirdel', 'svcdirect', 'zapretset', 'zapretstrat', 'zapretcheck', 'tgwsset', 'ledset', 'rename'];
const APP_CONFIRMABLE = ['switch', 'restart', 'update', 'subupdate', 'reboot', 'block', 'direct', 'schedule', 'diradd', 'dirdel',
    'svcdirect', 'zapretset', 'tgwsset'];
const APP_JOBS = ['ping', 'speedtest'];

// Понятные тексты к кодам (приложение показывает message как есть). Коды роутера — как словарь ERR веба (app.js).
const APP_MSG = [
    'bad_param' => 'Неверные данные запроса — обнови приложение.',
    'token_in_url' => 'Ключ нельзя передавать в адресе запроса. Если это был настоящий ключ, он уже отозван — войди заново.',
    'too_long' => 'Слишком длинное значение.',
    'confirm_invalid' => 'Подтверждение не подошло — повтори действие.',
    'confirm_required' => 'Нужно подтверждение.',
    'token_missing' => 'Нужно войти.',
    'token_invalid' => 'Ключ не подходит — войди заново.',
    'token_expired' => 'Срок входа истёк — войди заново.',
    'token_revoked' => 'Доступ этого телефона отозван — войди заново.',
    'bad_password' => 'Неверный пароль.',
    'browser_request' => 'Запросы из браузера сюда не принимаются.',
    'not_found' => 'Не найдено.',
    'not_in_v1' => 'Это действие пока есть только в веб-панели.',
    'method' => 'Неверный метод запроса — обнови приложение.',
    'busy' => 'Другое действие ещё выполняется — подожди немного.',
    'too_many_devices' => 'Уже 10 телефонов с доступом — отзови старый в Настройках, в веб-панели или командой /apps в боте.',
    'login_denied' => 'Вход отклонён в Telegram.',
    'login_expired' => 'Время на подтверждение вышло — начни вход заново.',
    'too_large' => 'Слишком большой запрос.',
    'not_json' => 'Тело запроса должно быть JSON.',
    'rate_limited' => 'Слишком часто — подожди немного.',
    'locked' => 'Вход временно закрыт после неверных попыток.',
    'server_error' => 'Ошибка на сервере — попробуй через минуту.',
    'server_config' => 'Сервер не настроен: нет ключа роутера (нужен Deploy server).',
    'router_token' => 'Роутер отклонил ключ сервера — нужен Deploy server.',
    'router_offline' => 'Роутер не на связи: туннель до сервера оборван или дома нет интернета.',
    'router_timeout' => 'Роутер не ответил вовремя.',
    'router_bad_reply' => 'Роутер ответил непонятно — попробуй ещё раз.',
    'app_disabled' => 'Приложение выключено на сервере. Веб-панель работает.',
    'tg_unavailable' => 'Telegram-бот недоступен — войти в приложение сейчас нельзя.',
    'bad mac' => 'Неверный адрес устройства (MAC).', 'bad node' => 'Такого сервера нет — обнови список.', 'bad via' => 'Неизвестный вид теста.',
    'domain' => 'Нужен домен вида site.ru.', 'time' => 'Неверное время.', 'resolve' => 'Не удалось узнать IP сервера.',
    'no target' => 'Нет такого сервиса.', 'no rule' => 'В PassWall нет правила MyDirect.', 'bad sub' => 'Нет такой подписки — обнови список.',
    'bad on' => 'Неверный режим.', 'bad strategy' => 'Нет такой стратегии.', 'not installed' => 'Не установлено на роутере.',
    'nft' => 'Роутер не смог изменить правила.', 'subscribe.lua not found' => 'На роутере нет скрипта подписок PassWall.',
];

/* ---------- ответ ---------- */
function app_json(array $a): string { return (string)json_encode($a, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE); }
function app_headers(int $code, array $extra = []): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    foreach ($extra as $h) header($h);
}
function app_send(int $code, string $body, array $headers = []): never { app_headers($code, $headers); echo $body; exit; }
function app_out(array $a, int $code = 200, array $headers = []): never { app_send($code, app_json($a), $headers); }
function app_err(int $code, string $error, array $extra = [], array $headers = []): never
{
    app_out(array_merge(['error' => $error, 'message' => APP_MSG[$error] ?? 'Ошибка.'], $extra), $code, $headers);
}
function app_401(string $error): never { app_err(401, $error, [], ['WWW-Authenticate: Bearer error="invalid_token"']); }
function app_429(string $error, int $wait, array $extra = []): never { app_err(429, $error, ['retry_after' => $wait] + $extra, ['Retry-After: ' . $wait]); }

/** Ответ роутера с ошибкой → [код, тело] для приложения. Коды CGI (400/409/500/503) — как есть, с source: router. */
function app_router_err(int $c, ?array $j): array
{
    $e = is_string($j['error'] ?? null) ? $j['error'] : '';
    if (in_array($e, ['server_config', 'router_token', 'router_offline', 'router_timeout'], true)) return [$c, ['error' => $e, 'message' => APP_MSG[$e]]];
    if (in_array($c, [400, 409, 500, 503], true) && preg_match('/^[a-z0-9 ._-]{1,40}$/i', $e))
        return [$c, ['error' => $e, 'message' => APP_MSG[$e] ?? ($c === 409 ? APP_MSG['busy'] : 'Роутер не смог выполнить действие.'), 'source' => 'router']];
    return [502, ['error' => 'router_bad_reply', 'message' => APP_MSG['router_bad_reply']]];
}
function app_router_fail(int $c, ?array $j): never { [$code, $body] = app_router_err($c, $j); app_out($body, $code); }

/** Роутер действие точно не выполнил: запрос до него не дошёл ('sent' => false: нет router.token, порт туннеля закрыт,
 *  «роутер молчит» — вызова не было), CGI отказал своей ошибкой до изменений (400/409/500/503, §2.1) или не принял ключ
 *  (403 → router_token). Такая попытка не в счёт лимитов действий: иначе switch на устаревший id закрыл бы смену сервера
 *  всем телефонам на 15 с, а оборванный туннель — перезагрузку на 5 минут. Таймаут и обрыв после отправки считаются: роутер мог выполнить. */
function app_router_not_run(int $c, ?array $j): bool
{
    if (($j['sent'] ?? true) === false) return true;
    [, $b] = app_router_err($c, $j);
    return ($b['source'] ?? '') === 'router' || $b['error'] === 'router_token';
}

/* ---------- вызов роутера (§11 п.3) ---------- */
// php-fpm один на всё — check.php веба и LuCI, вход, бот, — а ответа роутера воркер ждёт до таймаута (5–25 с). Когда туннель
// «висит» (дома нет интернета, а sshd ещё держит порт 8081), запросы приложения заняли бы все воркеры, и встали бы веб и бот. Поэтому:
//   — роутер одновременно ждут не больше APP_ROUTER_SLOTS запросов приложения (замки-файлы app-router-N.lock); остальные ждут
//     место до APP_SLOT_WAIT с и получают 429 busy. Долгая задача — мимо мест: у неё свой замок, одна на всех;
//   — роутер промолчал (504 или обрыв дольше 2 с) — следующие APP_ROUTER_DOWN с его не зовём, сразу 502 router_offline (файл app_router_down);
//   — все вызовы одного запроса укладываются в APP_BUDGET с: nginx ждёт php-fpm 30 с (fastcgi_read_timeout), а дольше приложение
//     получило бы 502 server_unavailable, хотя действие выполнено (dirdel — это mydirect и dirdel подряд). FSR_APP_BUDGET — для тестов.
const APP_ROUTER_SLOTS = 2;
const APP_SLOT_WAIT = 4;
const APP_ROUTER_DOWN = 30;
const APP_BUDGET = 25;

function app_router_down(): bool
{
    $f = fsr_dir() . '/app_router_down';
    clearstatcache(true, $f);
    return time() - (int)@filemtime($f) < APP_ROUTER_DOWN;
}

/** Место для вызова роутера. app_slot(с) — занять, ждать не дольше $wait с: 1 — заняли сейчас (освободить — app_slot(null)),
 *  2 — уже занято этим запросом, 0 — мест нет или роутер признан молчащим. Место держится до освобождения или конца запроса. */
function app_slot(?float $wait): int
{
    static $held = null;
    if ($wait === null) { if ($held) { flock($held, LOCK_UN); fclose($held); } $held = null; return 0; }
    if ($held) return 2;
    $until = microtime(true) + $wait;
    while (true) {
        for ($i = 1; $i <= APP_ROUTER_SLOTS; $i++) if ($held = fsr_app_flock("app-router-$i.lock")) return 1;
        if (microtime(true) >= $until || app_router_down()) return 0;
        usleep(100000);
    }
}

function app_slot_busy(): never
{
    app_429('busy', 3, ['message' => 'Роутер отвечает медленно: другие запросы к нему ещё ждут ответа. Повтори через несколько секунд.']);
}

/** Занять место заранее — до записи в лимиты и до погашения подтверждения (чтобы 429 busy его не сжёг). */
function app_slot_need(): void
{
    if (!app_slot(APP_SLOT_WAIT) && !app_router_down()) app_slot_busy();
}

/** Вызов роутера из приложения: fsr_router_call + места, «роутер молчит» и общий срок запроса (см. выше).
 *  $mode: 'wait' — ждать место (нет — 429 busy); 'try' — только свободное сразу, иначе роутер не зовём (окно без имён);
 *  'job' — долгая задача после ответа: без места и без срока. */
function app_router(string $a, array $q = [], string $method = 'GET', int $timeout = 20, string $mode = 'wait'): array
{
    $off = [502, ['error' => 'router_offline', 'sent' => false], ''];
    if (app_router_down()) return $off;
    $slot = 2;
    if ($mode !== 'job') {
        $slot = app_slot($mode === 'wait' ? APP_SLOT_WAIT : 0);
        if (!$slot) {
            if (app_router_down()) return $off;
            if ($mode === 'try') return [429, ['error' => 'busy', 'sent' => false], ''];
            app_slot_busy();
        }
        $spent = microtime(true) - (float)($_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true));
        $timeout = max(1, min($timeout, (int)floor((float)(getenv('FSR_APP_BUDGET') ?: APP_BUDGET) - $spent)));
    }
    $t0 = microtime(true);
    $r = fsr_router_call($a, $q, $method, $timeout);
    if ($slot === 1) app_slot(null);
    if (in_array($r[1]['error'] ?? '', ['router_timeout', 'router_offline'], true) && microtime(true) - $t0 >= 2) @touch(fsr_dir() . '/app_router_down');
    return $r;
}

/* ---------- запрос ---------- */
function app_method(string $method, string $allow): void
{
    if ($method !== $allow) app_err(405, 'method', [], ['Allow: ' . $allow]);
}

/** Параметры в адресе: только разрешённые (у /data — range), иначе 400. */
function app_query(array $allowed = []): array
{
    $qs = (string)($_SERVER['QUERY_STRING'] ?? '');
    if ($qs === '') return [];
    parse_str($qs, $q);
    foreach ($q as $k => $v) if (!in_array($k, $allowed, true) || !is_string($v)) app_err(400, 'bad_param');
    return $q;
}

/** Тело POST: JSON-объект до 4 КБ. Пустое тело — {}. $allowed — допустимые поля (null — проверит вызывающий). */
function app_body(?array $allowed): array
{
    if ((int)($_SERVER['CONTENT_LENGTH'] ?? 0) > 4096) app_err(413, 'too_large');
    $raw = (string)file_get_contents('php://input', false, null, 0, 4097);
    if (strlen($raw) > 4096) app_err(413, 'too_large');
    if (trim($raw) === '') return [];
    $ct = (string)($_SERVER['CONTENT_TYPE'] ?? $_SERVER['HTTP_CONTENT_TYPE'] ?? '');
    if (!preg_match('~^application/json\s*(;|$)~i', $ct) || ltrim($raw)[0] !== '{') app_err(415, 'not_json');
    try { $b = json_decode($raw, true, 4, JSON_THROW_ON_ERROR); } catch (JsonException) { app_err(415, 'not_json'); }
    if (!is_array($b)) app_err(415, 'not_json');
    if ($allowed !== null) foreach (array_keys($b) as $k) if (!in_array($k, $allowed, true)) app_err(400, 'bad_param');
    return $b;
}

function app_auth_header(): ?string
{
    foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION'] as $k) if (isset($_SERVER[$k])) return trim((string)$_SERVER[$k]);
    if (function_exists('getallheaders')) foreach (getallheaders() as $k => $v) if (strtolower((string)$k) === 'authorization') return trim((string)$v);
    return null;
}

/** Ключ в адресе (§7.4 п.3): настоящий — отозвать; записать, сообщить, ответить 400. До проверки заголовка.
 *  $browser — запрос из браузера (уже идёт к 403): настоящий ключ из ссылки тоже отзываем, но строку для fail2ban не пишем —
 *  иначе чужая страница картинками «…/me?token=x» забанила бы домашний IP (а с ним и свой VPN NL на 443). */
function app_url_token(bool $browser = false): void
{
    $uri = (string)($_SERVER['REQUEST_URI'] ?? '');
    $dec = rawurldecode($uri);
    $hit = stripos($dec, 'fsr1_') !== false;
    $qs = (string)($_SERVER['QUERY_STRING'] ?? parse_url($uri, PHP_URL_QUERY) ?? '');
    foreach (explode('&', $qs) as $kv) {
        $k = strtolower((string)preg_replace('/\[.*$/', '', rawurldecode(explode('=', $kv, 2)[0])));
        if (in_array($k, ['access_token', 'token', 'bearer', 'authorization', 'auth'], true)) $hit = true;
    }
    if (!$hit) return;
    preg_match_all('/fsr1_[A-Za-z0-9_-]{43}/', $dec, $m);
    $gone = [];
    foreach (array_unique($m[0]) as $t) if ($d = fsr_app_revoke_token($t, 'url_leak')) $gone[] = $d;
    if ($browser && !$gone) return;
    if (!$browser) fsr_log('APP_URLTOKEN');
    fsr_audit('APP_URLTOKEN', $gone ? 'revoked ' . implode(',', array_column($gone, 'id')) : 'no real key', '-');
    $ip = fsr_ip();
    if ($gone) {
        $text = '⚠️ Ключ приложения попал в адрес запроса (IP ' . $ip . ') и отозван: ' . implode(', ', array_map('fsr_app_label', $gone))
            . ".\nНа этом телефоне нужно войти в приложение заново.";
        fsr_later(fn() => fsr_tg_send($text));
        if ($browser) return;
    } else {
        $f = fsr_dir() . '/app_urltoken_alert';             // без настоящего ключа (сканеры, проверка выкладки) — не чаще раза в час
        if (time() - (int)@filemtime($f) > 3600) {
            @touch($f);
            fsr_later(fn() => fsr_tg_send("⚠️ Запрос к API приложения с ключом в адресе (IP $ip). Настоящих ключей в нём не было — ничего не отозвано."));
        }
    }
    app_err(400, 'token_in_url');
}

/** Проверка ключа устройства (§7.4 п.5–6). → строка устройства (продлённая). */
function app_auth(): array
{
    $h = app_auth_header();
    if ($h === null || $h === '') app_401('token_missing');
    // «Bearer» — ровно так (как шлёт приложение): ключ лимита nginx на устройство (map в fsr-limits.conf) регистр различает,
    // и «bearer …» с настоящим ключом обходил бы лимит fsr_app_dev
    $d = preg_match('/^Bearer (fsr1_[A-Za-z0-9_-]{43})$/', $h, $m) ? fsr_app_device_by_token($m[1]) : null;
    if (!$d) { fsr_log('APP_BADTOKEN'); app_401('token_invalid'); }          // считается в fail2ban (jail fspirat-router-app)
    if ($d['revoked'] !== null) app_401('token_revoked');                    // старый телефон не банит домашний IP
    $now = time();
    if ((int)$d['expires'] <= $now || fsr_app_hard($d) <= $now) app_401('token_expired');
    return fsr_app_touch($d);
}

/** Подпись в Telegram для действий из приложения. */
function app_from(array $dev): string { return 'Из приложения «' . $dev['name'] . '», IP ' . fsr_ip(); }

/* ---------- вход (§7.2) ---------- */
function app_login(): never
{
    $b = app_body(['password', 'device']);
    $dv = $b['device'] ?? null;
    if (!is_array($dv)) app_err(400, 'bad_param');
    foreach (array_keys($dv) as $k) if (!in_array($k, ['name', 'model', 'os', 'app'], true)) app_err(400, 'bad_param');
    $name = is_string($dv['name'] ?? null) ? trim($dv['name']) : '';
    if ($name === '' || !mb_check_encoding($name, 'UTF-8') || preg_match('/[\x00-\x1f\x7f]/', $name)) app_err(400, 'bad_param');
    if (mb_strlen($name) > 40) app_err(400, 'too_long');
    $dev = ['name' => $name];
    foreach (['model', 'os', 'app'] as $k) {
        $v = $dv[$k] ?? '';
        if (!is_string($v) || !preg_match('/^[\x20-\x7e]{0,32}$/', $v)) app_err(400, 'bad_param');
        $dev[$k] = trim($v);
    }
    $needPw = fsr_app_password_required();
    $pw = $b['password'] ?? null;
    if (($needPw || $pw !== null) && (!is_string($pw) || strlen($pw) > 200)) app_err(400, 'bad_param');
    if (!fsr_app_bot_ok()) app_err(503, 'tg_unavailable');          // без бота не входим: по одному паролю приложение не пускает
    if ($l = app_login_limit()) app_429(...$l);

    // замки: «Это не я» / подбор с разных адресов, затем общая с вебом блокировка адреса
    fsr_app_spray_check();
    if ($w = fsr_app_login_lock()) app_429('locked', $w, ['message' => 'Вход в приложение по паролю временно закрыт (отклонён вход или подбор пароля). Веб-панель работает.']);
    // блокировка адреса и запись попытки — одним шагом до проверки пароля (fsr_attempt): иначе пачка параллельных запросов
    // с одного IP, пока каждый ждёт bcrypt и паузу, видит «0 ошибок» и проверяет пароль вся (больше 5 попыток за раз)
    $try = null;
    if ($w = $needPw ? fsr_attempt($try) : fsr_locked()) {
        fsr_log('LOCKED');
        app_429('locked', $w, ['message' => 'Слишком много неверных попыток. Вход с этого адреса закрыт ещё на ' . (int)ceil($w / 60) . ' мин.']);
    }
    if ($needPw) {
        if (!fsr_password_ok((string)$pw)) {
            usleep(random_int(300000, 700000));   // замедляем подбор
            $left = max(0, fsr_fails_left());     // попытка уже записана (fsr_attempt)
            fsr_log('FAIL');
            app_err(401, 'bad_password', ['left' => $left, 'message' => $left > 0 ? "Неверный пароль. Осталось попыток: $left."
                : 'Слишком много неверных попыток. Вход с этого адреса закрыт на ' . (FSR_LOCK_SEC / 60) . ' мин.']);
        }
        fsr_attempt_ok($try);
    }
    if (count(fsr_app_active()) >= FSR_APP_MAX_DEVICES) app_err(409, 'too_many_devices');

    // лимиты ещё раз и запись входа — одной транзакцией (запись в базу по одному): иначе пачка параллельных запросов,
    // пока каждый ждёт проверку пароля, видит «0 входов» и проходит лимиты разом (больше двух ждущих, больше 5 в час)
    $db = fsr_app_db();
    $db->exec('BEGIN IMMEDIATE');
    try {
        $l = app_login_limit();
        $new = $l ? null : fsr_app_login_create($dev);
        $db->exec('COMMIT');
    } catch (Throwable $e) {
        try { $db->exec('ROLLBACK'); } catch (Throwable) {}
        throw $e;
    }
    if ($l) app_429(...$l);
    [$loginId, $number, $nums, $ref] = $new;
    $ts = time();
    $kb = [array_map(fn($n) => ['text' => (string)$n, 'callback_data' => "al:$ref:$n|$ts"], $nums),
           [['text' => '🚫 Это не я', 'callback_data' => "an:$ref|$ts"]]];
    $r = fsr_tg_call('sendMessage', ['chat_id' => fsr_tg()['chat'], 'disable_web_page_preview' => true, 'reply_markup' => ['inline_keyboard' => $kb],
        'text' => "🔐 Вход в приложение «Роутер»\nУстройство: " . fsr_app_label($dev) . ' · IP ' . fsr_ip() . "\n\n"
            . "Нажми число, которое видишь на экране телефона. Если ты не входишь — нажми «Это не я».\nКнопки действуют 2 минуты."]);
    $mid = (int)($r['result']['message_id'] ?? 0);
    if (!($r['ok'] ?? false) || $mid <= 0) {
        fsr_app_q('DELETE FROM app_logins WHERE tg_ref = ?', [$ref]);
        error_log('fspirat-router-app: sendMessage для входа не прошёл');
        app_err(503, 'tg_unavailable');
    }
    fsr_app_q('UPDATE app_logins SET tg_msg = ? WHERE tg_ref = ?', [$mid, $ref]);
    fsr_log('APP_LOGIN');
    app_out(['login_id' => $loginId, 'number' => $number, 'expires_in' => FSR_APP_LOGIN_TTL, 'poll_every' => 2]);
}

/** Лимиты входа (§7.2 п.8): 5 в час с адреса, 10 в час всего, одновременно ждут не больше двух. → null или аргументы app_429. */
function app_login_limit(): ?array
{
    $ip = fsr_ip(); $now = time();
    $mine = fsr_app_q('SELECT created FROM app_logins WHERE ip = ? AND created > ? ORDER BY created DESC LIMIT 5', [$ip, $now - 3600])->fetchAll(PDO::FETCH_COLUMN);
    if (count($mine) >= 5) return ['rate_limited', max(1, (int)end($mine) + 3600 - $now)];
    $all = fsr_app_q('SELECT created FROM app_logins WHERE created > ? ORDER BY created DESC LIMIT 10', [$now - 3600])->fetchAll(PDO::FETCH_COLUMN);
    if (count($all) >= 10) return ['rate_limited', max(1, (int)end($all) + 3600 - $now)];
    $pend = fsr_app_q('SELECT created FROM app_logins WHERE state = \'pending\' AND created > ? ORDER BY created DESC', [$now - FSR_APP_LOGIN_TTL])->fetchAll(PDO::FETCH_COLUMN);
    if (count($pend) >= 2) return ['busy', max(1, (int)end($pend) + FSR_APP_LOGIN_TTL - $now), ['message' => 'Уже ждут подтверждения два входа — ответь в Telegram или подожди 2 минуты.']];
    return null;
}

function app_login_id(): array
{
    $b = app_body(['login_id']);
    $lid = $b['login_id'] ?? null;
    if (!is_string($lid) || !preg_match('/^[a-f0-9]{64}$/', $lid)) app_err(400, 'bad_param');
    $r = fsr_app_login_get($lid);
    if (!$r) app_err(410, 'login_expired');
    return $r;
}

function app_poll(): never
{
    $r = app_login_id();
    $now = time();
    switch ($r['state']) {
        case 'pending':
            if ((int)$r['created'] + FSR_APP_LOGIN_TTL >= $now) app_out(['state' => 'pending', 'expires_in' => (int)$r['created'] + FSR_APP_LOGIN_TTL - $now]);
            if (fsr_app_login_state($r['hash'], ['pending'], 'expired')) fsr_app_login_edit_later($r, "⌛ Время вышло — вход в приложение не выполнен.\n" . fsr_app_login_label($r));
            app_err(410, 'login_expired');
        case 'approved':
            if ((int)$r['created'] + FSR_APP_LOGIN_PICKUP < $now) { fsr_app_login_state($r['hash'], ['approved'], 'expired'); app_err(410, 'login_expired'); }
            $res = fsr_app_login_issue($r);
            if ($res === 'too_many_devices') app_err(409, 'too_many_devices');
            if ($res === 'locked') {        // одобрен, но пока ждал опроса, вход по паролю закрыли («Это не я», подбор)
                fsr_app_login_edit_later($r, "🚫 Вход в приложение не выполнен: вход по паролю закрыт на час.\n" . fsr_app_login_label($r));
                app_err(410, 'login_denied');
            }
            if (!is_array($res)) app_err(410, 'login_expired');
            [$d, $tok] = $res;
            fsr_log('APP_OK');
            fsr_audit('APP_OK', 'id=' . $d['id'], 'a:' . $d['id']);
            $text = '📱 Вход в приложение: ' . fsr_app_label($d) . ' · IP ' . fsr_ip() . '. Устройств: ' . count(fsr_app_active()) . '. Отозвать — /apps';
            fsr_later(fn() => fsr_tg_send($text));
            app_out(['state' => 'approved', 'token' => $tok, 'device_id' => $d['id'], 'expires' => $d['expires'], 'hard_expires' => $d['hard_expires']]);
        case 'denied':
        case 'notme':
            app_err(410, 'login_denied');
        default:
            app_err(410, 'login_expired');
    }
}

function app_cancel(): never
{
    $r = app_login_id();
    if (fsr_app_login_state($r['hash'], ['pending', 'approved'], 'cancelled')) {
        fsr_app_login_edit_later($r, "↩️ Вход отменён в приложении.\n" . fsr_app_login_label($r));
        app_out(['ok' => true, 'state' => 'cancelled']);
    }
    app_out(['ok' => true, 'state' => (string)$r['state']]);
}

/* ---------- устройства (§7.6) ---------- */
function app_logout(array $dev): never
{
    app_body([]);
    if ($d = fsr_app_revoke((string)$dev['id'], 'self')) {
        fsr_log('APP_REVOKE');
        fsr_audit('APP', 'logout → 200', 'a:' . $dev['id']);
        $text = FSR_ACTIONS['apprevoke'][0] . ': ' . fsr_app_label($d) . ' (' . fsr_app_by_text('self') . "), IP " . fsr_ip();
        fsr_later(fn() => fsr_tg_send($text));
    }
    app_out(['ok' => true]);
}

function app_revoke(array $dev): never
{
    $b = app_body(['id', 'web_ref']);
    if (count($b) !== 1) app_err(400, 'bad_param');
    $id = (string)$dev['id'];
    $ref = isset($b['id']) ? $b['id'] : $b['web_ref'];
    if (!is_string($ref) || !preg_match('/^[a-f0-9]{16}$/', $ref)) app_err(400, 'bad_param');
    if ($w = fsr_app_limit($id, 'revoke')) { fsr_audit('APP_DENY', 'apprevoke rate', "a:$id"); app_429('rate_limited', $w); }
    fsr_app_hit($id, 'revoke');
    if (isset($b['id'])) {
        $by = $ref === $id ? 'self' : "app:$id";
        $d = fsr_app_revoke($ref, $by);
        fsr_audit('APP', "apprevoke id=$ref → " . ($d ? '200' : '404'), "a:$id");
        if (!$d) app_err(404, 'not_found');
        fsr_log('APP_REVOKE');
        $text = FSR_ACTIONS['apprevoke'][0] . ': ' . fsr_app_label($d) . ' (' . fsr_app_by_text($by) . ')' . ($by === 'self' ? ', IP ' . fsr_ip() : '');
    } else {
        $s = fsr_web_session_end($ref);
        fsr_audit('APP', "webrevoke ref=$ref → " . ($s ? '200' : '404'), "a:$id");
        if (!$s) app_err(404, 'not_found');
        $text = '🔒 Сессия веб-панели закрыта (IP ' . $s['ip'] . '). ' . app_from($dev);
    }
    fsr_later(fn() => fsr_tg_send($text));
    app_out(['ok' => true]);
}

function app_revoke_all(array $dev): never
{
    $b = app_body(['web', 'confirm']);
    $web = $b['web'] ?? false;
    $confirm = $b['confirm'] ?? null;
    if (!is_bool($web) || ($confirm !== null && !is_string($confirm))) app_err(400, 'bad_param');
    $id = (string)$dev['id'];
    if ($w = fsr_app_limit($id, 'revokeall')) { fsr_audit('APP_DENY', 'apprevokeall rate', "a:$id"); app_429('rate_limited', $w); }
    $p = ['web' => $web];
    app_confirm_check($dev, 'revokeall', $p, $confirm);
    fsr_app_hit($id, 'revokeall');
    $n = fsr_app_revoke_all("app:$id", $web);
    fsr_log('APP_REVOKE');
    fsr_audit('APP', 'apprevokeall web=' . ($web ? 1 : 0) . " revoked=$n → 200", "a:$id");
    $text = FSR_ACTIONS['apprevokeall'][0] . ": отозван доступ приложения на телефонах ($n)" . ($web ? ', закрыты все сессии веб-панели' : '') . '. ' . app_from($dev);
    fsr_later(fn() => fsr_tg_send($text));
    app_out(['ok' => true, 'revoked' => $n]);
}

/* ---------- подтверждение (§7.9) ---------- */

/** Нужно ли и годится ли подтверждение: нет — 428 с текстом окна; чужое/другое — 400 confirm_invalid; просрочено — снова 428. */
function app_confirm_check(array $dev, string $a, array $p, ?string $confirm): void
{
    $id = (string)$dev['id'];
    $res = $confirm === null ? 'none' : fsr_app_confirm_use($id, $a, $p, $confirm);
    if ($res === 'ok') return;
    if ($res === 'invalid') { fsr_audit('APP_DENY', "$a confirm", "a:$id"); app_err(400, 'confirm_invalid'); }
    if ($w = fsr_app_limit($id, 'confirm')) { fsr_audit('APP_DENY', "$a rate", "a:$id"); app_429('rate_limited', $w); }
    [$danger, $title, $text, $button] = app_confirm_text($a, $p);
    fsr_app_hit($id, 'confirm');
    app_err(428, 'confirm_required', ['confirm' => fsr_app_confirm_new($id, $a, $p), 'expires_in' => FSR_APP_CONFIRM_TTL,
        'danger' => $danger, 'title' => $title, 'text' => $text, 'button' => $button]);
}

/** Текст окна подтверждения: [danger (critical|high|medium), заголовок, текст, кнопка]. Одинаковые слова с вебом и ботом. */
function app_confirm_text(string $a, array $p): array
{
    $pw = 'VPN перезапустится, связь через VPN пропадёт на несколько секунд.';
    $iphone = 'Если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет.';
    $dev = function (string $mac): string { $n = (string)(fsr_names()[$mac] ?? ''); return $n !== '' ? "«{$n}» ($mac)" : "Устройство $mac"; };
    $hm = fn(string $t) => substr($t, 0, 2) . ':' . substr($t, 2, 2);
    switch ($a) {
        case 'switch':
            if ($p['id'] === 'direct') return ['critical', 'Пустить весь трафик напрямую, без VPN?',
                'Весь трафик пойдёт без VPN, с IP провайдера; автопереключение отключится. Правила Split остаются: MyDirect — напрямую, '
                . 'YouTube и Discord — через zapret, если он включён. Вернуть VPN — выбрать сервер. Связь пропадёт на несколько секунд.', 'Напрямую'];
            // имя и отклик сервера — из status роутера (роутер не ответил или занят — окно без них)
            [$c, $s] = app_router('status', [], 'GET', 20, 'try');
            $node = null;
            foreach ((is_array($s) ? (array)($s['ping']['nodes'] ?? []) : []) as $n) if (is_array($n) && ($n['id'] ?? '') === $p['id']) $node = $n;
            $text = $pw;
            if (is_array($s) && ($s['current'] ?? '') === $p['id']) $text = 'Этот сервер уже подключён. ' . $text;
            if ($node && (int)($node['ms'] ?? 0) <= 0) $text .= ' Сервер сейчас не отвечает — дом может остаться без VPN до автопереключения (~10 мин).';
            return ['high', $node ? 'Подключить «' . trim((string)$node['name']) . '»?' : 'Подключить другой сервер?', $text, 'Подключить'];
        case 'restart':
            return ['high', 'Перезапустить VPN?', 'Связь через VPN пропадёт на несколько секунд.', 'Перезапустить'];
        case 'update':
        case 'subupdate':
            $title = 'Обновить подписки VPN?';
            if (isset($p['sid'])) {                 // название подписки — из status.subs (id секции человеку ничего не скажет)
                [$c, $s] = app_router('status', [], 'GET', 20, 'try');
                $name = $p['sid'];
                foreach ((is_array($s) ? (array)($s['subs'] ?? []) : []) as $x) if (is_array($x) && ($x['id'] ?? '') === $p['sid']) $name = trim((string)($x['name'] ?? $name));
                $title = "Обновить подписку «{$name}»?";
            }
            // subscribe.lua сам перезапускает PassWall после обновления (проверено на роутере 13.10.2026)
            return ['high', $title,
                'Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. '
                . 'Если текущего сервера в подписке больше нет, роутер сам выберет другой.', 'Обновить'];
        case 'reboot':
            return ['critical', 'Перезагрузить роутер?', 'Интернет дома пропадёт на 1–2 минуты, приложение на это время покажет «не на связи». '
                . 'Счётчики трафика устройств обнулятся.', 'Перезагрузить'];
        case 'block':
            return ['high', 'Выключить интернет устройству?', $dev($p['mac']) . ' останется в Wi-Fi, но сайты и приложения перестанут открываться, '
                . "пока не включишь обратно. $iphone", 'Выключить интернет'];
        case 'direct':
            return $p['on']
                ? ['high', 'Пускать устройство мимо VPN?', $dev($p['mac']) . ' будет ходить в интернет напрямую, как без VPN; заблокированные в России сайты на нём '
                    . "открываться не будут. $pw", 'Мимо VPN']
                : ['high', 'Пускать устройство снова через VPN?', $dev($p['mac']) . " снова пойдёт через VPN. $pw", 'Через VPN'];
        case 'schedule':
            return ['medium', 'Включить расписание интернета?', $dev($p['mac']) . ': интернет выключается в ' . $hm($p['off']) . ' и включается в ' . $hm($p['on'])
                . ' (время роутера, Самара). Если сейчас как раз время «без интернета», он выключится сразу. ' . $iphone, 'Сохранить'];
        case 'diradd':
            return ['high', 'Пускать ' . $p['d'] . ' напрямую?', "Сайт будет открываться без VPN на всех устройствах дома (MyDirect). $pw", 'Добавить'];
        case 'dirdel':
            return ['high', 'Убрать ' . $p['d'] . ' из MyDirect?', "Сайт снова пойдёт через VPN. $pw", 'Убрать'];
        case 'svcdirect':
            return $p['on']
                ? ['high', 'Пускать ' . $p['name'] . ' напрямую?', "Сервис будет работать без VPN на всех устройствах дома (запись в MyDirect). $pw", 'Напрямую']
                : ['high', $p['name'] . ' снова через VPN?', "Запись уберётся из MyDirect. $pw", 'Через VPN'];
        case 'zapretset':
            return $p['on']
                ? ['high', 'Включить zapret для YouTube и Discord?', 'YouTube и Discord пойдут напрямую через провайдера, с IP провайдера (не через VPN). '
                    . 'Остальное не меняется. VPN перезапустится примерно на 5 секунд, открытые видео и звонки переподключатся.', 'Включить']
                : ['high', 'Выключить zapret?', 'YouTube и Discord снова пойдут через VPN. VPN перезапустится примерно на 5 секунд.', 'Выключить'];
        case 'tgwsset':
            return $p['on']
                ? ['medium', 'Включить прокси Telegram?', 'Telegram на всех устройствах дома пойдёт через Cloudflare с IP провайдера, а не через VPN. '
                    . 'Если прокси перестанет работать, Telegram сам вернётся на VPN. Режим экспериментальный.', 'Включить']
                : ['medium', 'Выключить прокси Telegram?', 'Telegram снова пойдёт через VPN.', 'Выключить'];
        case 'revokeall':
            return ['critical', 'Выйти на всех устройствах?', 'Доступ отзывается у всех телефонов с приложением, и у этого тоже. Войти заново — пароль и число в Telegram.'
                . ($p['web'] ? ' Также закроются все сессии веб-панели, и каждый браузер снова попросит код из Telegram.' : ''), 'Выйти везде'];
    }
    return ['high', 'Выполнить действие?', '', 'Да'];
}

/* ---------- действия (§7.8) ---------- */

/**
 * Проверка тела действия теми же правилами, что у CGI (§1.6), но строже: неверное значение — 400, а не «пустая строка».
 * → ['p' => проверенные параметры (их хэш — в подтверждении), 'q' => параметры CGI, 'confirm' => нужно ли, 'method', 'timeout', 'detail'].
 */
function app_action_spec(string $a, array $b): ?array
{
    $mac = fn($v) => is_string($v) && preg_match('/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/', $v);
    $hhmm = fn($v) => is_string($v) && preg_match('/^([01][0-9]|2[0-3])[0-5][0-9]$/', $v);
    $keys = fn(array $need, array $opt = []) => !array_diff($need, array_keys($b)) && !array_diff(array_keys($b), array_merge($need, $opt));
    $s = ['p' => [], 'q' => [], 'confirm' => in_array($a, APP_CONFIRMABLE, true), 'method' => 'POST', 'timeout' => 25];
    switch ($a) {
        case 'ping': case 'restart': case 'update': case 'reboot': case 'zapretcheck':
            if ($b) return null;
            break;
        case 'speedtest':
            if (!$keys(['via']) || !in_array($b['via'], ['vpn', 'direct'], true)) return null;
            $s['p'] = $s['q'] = ['via' => $b['via']];
            break;
        case 'pingone':
        case 'switch':
            if (!$keys(['id']) || !is_string($b['id']) || !preg_match('/^[A-Za-z0-9]{1,32}$/', $b['id'])) return null;   // «_direct» не проходит: без VPN — «direct»
            $s['p'] = $s['q'] = ['id' => $b['id']];
            if ($a === 'pingone') { $s['method'] = 'GET'; $s['timeout'] = 15; }     // CGI принимает pingone любым методом
            break;
        case 'subupdate':                       // кривой sid CGI молча превращает в «все подписки» — здесь только явно
            if ($keys(['sid'])) {
                if (!is_string($b['sid']) || !preg_match('/^[A-Za-z0-9_]{1,32}$/', $b['sid'])) return null;
                $s['p'] = $s['q'] = ['sid' => $b['sid']];
            } elseif ($keys(['all']) && $b['all'] === true) $s['p'] = ['all' => true];
            else return null;
            break;
        case 'block': case 'unblock':
            if (!$keys(['mac']) || !$mac($b['mac'])) return null;
            $s['p'] = $s['q'] = ['mac' => $b['mac']];
            break;
        case 'direct':                          // без on CGI выключает режим — здесь on обязателен
            if (!$keys(['mac', 'on']) || !$mac($b['mac']) || !is_bool($b['on'])) return null;
            $s['p'] = ['mac' => $b['mac'], 'on' => $b['on']];
            $s['q'] = ['mac' => $b['mac'], 'on' => $b['on'] ? 1 : 0];
            break;
        case 'schedule':                        // off = on = "" — убрать (без подтверждения)
            if (!$keys(['mac', 'off', 'on']) || !$mac($b['mac']) || !is_string($b['off']) || !is_string($b['on'])) return null;
            if ($b['off'] === '' && $b['on'] === '') $s['confirm'] = false;
            elseif (!$hhmm($b['off']) || !$hhmm($b['on']) || $b['off'] === $b['on']) return null;
            $s['p'] = $s['q'] = ['mac' => $b['mac'], 'off' => $b['off'], 'on' => $b['on']];
            break;
        case 'diradd': case 'dirdel':
            if (!$keys(['d']) || !is_string($b['d']) || strlen($b['d']) > 100
                || !preg_match('/^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$/', $b['d'])) return null;
            $s['p'] = $s['q'] = ['d' => $b['d']];
            break;
        case 'svcdirect':
            if (!$keys(['name', 'on']) || !is_bool($b['on']) || !is_string($b['name']) || strlen($b['name']) < 1 || strlen($b['name']) > 40
                || !mb_check_encoding($b['name'], 'UTF-8') || preg_match('/[\x00-\x1f\x7f~!"<>&\\\\|]/', $b['name'])) return null;
            $s['p'] = ['name' => $b['name'], 'on' => $b['on']];
            $s['q'] = ['name' => $b['name'], 'on' => $b['on'] ? 1 : 0];
            break;
        case 'zapretset': case 'tgwsset': case 'ledset':
            if (!$keys(['on']) || !is_bool($b['on'])) return null;
            $s['p'] = ['on' => $b['on']];
            $s['q'] = ['on' => $b['on'] ? 1 : 0];
            break;
        case 'zapretstrat':
            if (!$keys(['n']) || !in_array($b['n'], [1, 2, 3], true)) return null;
            $s['p'] = $s['q'] = ['n' => $b['n']];
            break;
        case 'rename':
            if (!$keys(['mac', 'name']) || !$mac($b['mac']) || !is_string($b['name']) || !mb_check_encoding($b['name'], 'UTF-8')
                || preg_match('/[\x00-\x1f\x7f]/', $b['name'])) return null;
            $s['p'] = ['mac' => $b['mac'], 'name' => trim($b['name'])];
            break;
        default:
            return null;
    }
    // в журнал — только известные параметры (без имён устройств и свободного текста)
    $s['detail'] = '';
    foreach (['id', 'sid', 'mac', 'via', 'on', 'off', 'n', 'd'] as $k) if (array_key_exists($k, $s['p']) && !($a === 'rename' && $k !== 'mac')) {
        $v = $s['p'][$k];
        $s['detail'] .= " $k=" . (is_bool($v) ? ($v ? 1 : 0) : $v);
    }
    if (isset($s['p']['all'])) $s['detail'] .= ' all=1';
    return $s;
}

function app_action(array $dev, string $a): never
{
    if (in_array($a, APP_NOT_IN_V1, true)) app_err(404, 'not_in_v1');
    if (!in_array($a, APP_ACTIONS, true)) app_err(404, 'not_found');
    $id = (string)$dev['id'];
    $b = app_body(null);
    $confirm = $b['confirm'] ?? null;
    unset($b['confirm']);
    $s = app_action_spec($a, $b);
    if (!$s || ($confirm !== null && (!is_string($confirm) || !in_array($a, APP_CONFIRMABLE, true)))) {
        fsr_audit('APP_DENY', "$a param", "a:$id");
        app_err(400, 'bad_param');
    }
    if ($a === 'rename' && mb_strlen($s['p']['name']) > 40) { fsr_audit('APP_DENY', "$a param", "a:$id"); app_err(400, 'too_long'); }
    if ($w = fsr_app_limit($id, $a)) { fsr_audit('APP_DENY', "$a rate", "a:$id"); app_429('rate_limited', $w); }
    // роутер только что промолчал (app_router) — сразу 502: без окна и не тратя подтверждение
    if ($a !== 'rename' && app_router_down()) { fsr_audit('APP', "$a{$s['detail']} → 502:router_offline", "a:$id"); app_err(502, 'router_offline'); }
    // действия по одному: пока идёт вызов CGI, второе действие из приложения — 409 (веб и бот этот замок не видят).
    // С confirm замок и место для вызова роутера берутся до проверки подтверждения: при 409/429 busy подтверждение
    // не сгорает, повтор с ним же пройдёт
    $lock = null;
    if ($s['confirm'] && $confirm !== null) {
        if (!($lock = fsr_app_flock('app-action.lock'))) app_err(409, 'busy');
        app_slot_need();
    }
    if ($a === 'dirdel') app_dirdel_check($dev, $s['p']['d']);     // и до окна, и прямо перед вызовом (с confirm — это одно и то же место)
    if ($s['confirm']) app_confirm_check($dev, $a, $s['p'], $confirm);

    if ($a === 'rename') {
        fsr_app_hit($id, $a);
        $all = fsr_names_set($s['p']['mac'], $s['p']['name']);
        fsr_audit('APP', "rename{$s['detail']} → 200", "a:$id");
        app_out(['ok' => true, 'names' => (object)$all]);
    }
    if (in_array($a, APP_JOBS, true)) app_job_start($dev, $a, $s);

    $lock ??= fsr_app_flock('app-action.lock');
    if (!$lock) app_err(409, 'busy');
    app_slot_need();
    $hit = fsr_app_hit($id, $a);         // до вызова: параллельный запрос уже видит паузу PW и лимиты
    [$c, $j, $raw] = app_router($a, $s['q'], $s['method'], $s['timeout']);
    app_slot(null);
    flock($lock, LOCK_UN); fclose($lock);
    $ok = $c === 200 && is_array($j);
    if (!$ok && app_router_not_run($c, $j)) fsr_app_unhit($hit);     // роутер ничего не сделал — попытка не в счёт лимитов
    [$code, $body] = $ok ? [200, null] : app_router_err($c, $j);
    fsr_audit('APP', "$a{$s['detail']} → " . ($ok ? '200' : "$code:" . $body['error']), "a:$id");
    if (!$ok) app_out($body, $code);
    [$title, $tg] = FSR_ACTIONS[$a] ?? ['', false];
    if ($tg) {
        $mac = (string)($s['p']['mac'] ?? '');
        $nm = $mac !== '' ? (string)(fsr_names()[$mac] ?? '') : '';
        $text = $title . ($mac !== '' ? "\nMAC $mac" . ($nm !== '' ? " ($nm)" : '') : '') . "\n" . app_from($dev);
        fsr_later(fn() => fsr_tg_send($text));
    }
    app_send(200, $raw);
}

/** dirdel — только для доменов, добавленных из панели или приложения (mydirect.added): записи из LuCI не трогаем (§6). */
function app_dirdel_check(array $dev, string $d): void
{
    [$c, $j] = app_router('mydirect', [], 'GET', 10);
    if ($c !== 200 || !is_array($j)) app_router_fail($c, $j);
    if (!in_array($d, array_map('strval', (array)($j['added'] ?? [])), true)) {
        fsr_audit('APP_DENY', "dirdel param d=$d", 'a:' . $dev['id']);
        app_err(400, 'bad_param', ['message' => 'Убрать можно только домены, добавленные из панели или приложения.']);
    }
}

/* ---------- долгие задачи (§7.10) ---------- */
function app_job_start(array $dev, string $a, array $s): never
{
    $id = (string)$dev['id'];
    $lock = fsr_app_flock('app-job.lock');          // одна долгая задача на всех: бережём воркеры php-fpm
    if (!$lock) app_err(409, 'busy', ['message' => $a === 'speedtest' ? 'Тест скорости или проверка уже идут — дождись результата.' : 'Проверка или тест скорости уже идут — дождись результата.']);
    $hit = fsr_app_hit($id, $a);
    $job = fsr_app_job_new($id, $a);
    $body = app_json(['job' => $job, 'poll_every' => 3]);
    app_headers(202, ['Content-Length: ' . strlen($body), 'Connection: close']);
    echo $body;
    if (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
    else { while (ob_get_level() > 0) ob_end_flush(); flush(); }      // php -S (тесты): ответ уходит сразу
    ignore_user_abort(true);
    set_time_limit(120);
    try {
        [$c, $j, $raw] = app_router($a, $s['q'], 'POST', 90, 'job');
        if ($c === 200 && is_array($j)) { fsr_app_job_done($job, 200, $raw); $res = '200'; }
        else {
            [$code, $err] = app_router_err($c, $j); fsr_app_job_done($job, $code, app_json($err)); $res = "$code:" . $err['error'];
            if (app_router_not_run($c, $j)) fsr_app_unhit($hit);
        }
        fsr_audit('APP', "$a{$s['detail']} job=$job → $res", "a:$id");
    } catch (Throwable $e) {
        error_log('fspirat-router-app job: ' . $e->getMessage());
        try { fsr_app_job_done($job, 500, app_json(['error' => 'server_error', 'message' => APP_MSG['server_error']])); } catch (Throwable) {}
    }
    flock($lock, LOCK_UN); fclose($lock);
    exit;
}

function app_job(array $dev, string $jid): never
{
    $r = fsr_app_job_get($jid, (string)$dev['id']);     // только задачи своего устройства
    if (!$r) app_err(404, 'not_found');
    $a = (string)$r['action'];
    if ($r['done'] === null) {
        if ((int)$r['created'] < time() - 150) app_out(['state' => 'error', 'action' => $a, 'http' => 500, 'error' => 'server_error', 'message' => APP_MSG['server_error']]);
        app_out(['state' => 'running', 'action' => $a]);
    }
    if ((int)$r['http'] === 200) app_send(200, '{"state":"done","action":' . json_encode($a) . ',"http":200,"result":' . $r['result'] . '}');
    $e = json_decode((string)$r['result'], true);
    app_out(array_merge(['state' => 'error', 'action' => $a, 'http' => (int)$r['http']], is_array($e) ? $e : ['error' => 'server_error']));
}

/* ---------- чтение (§7.7) ---------- */
function app_read(string $a, int $timeout): never
{
    [$c, $j, $raw] = app_router($a, [], 'GET', $timeout);
    if ($c === 200 && is_array($j)) app_send(200, $raw);     // как прислал роутер (или исправленный JSON, см. fsr_json_fix)
    app_router_fail($c, $j);
}

/* ---------- разбор запроса (§7.4) ---------- */
try {
    if (is_file(fsr_dir() . '/app_disabled')) app_err(503, 'app_disabled');          // рубильник: touch …/app_disabled
    // браузер шлёт Origin / Sec-Fetch-Site, URLSession — нет: в ошибки входа это не идёт
    if (isset($_SERVER['HTTP_ORIGIN']) || isset($_SERVER['HTTP_SEC_FETCH_SITE'])) { app_url_token(true); app_err(403, 'browser_request'); }
    app_url_token();
    fsr_app_gc_tick();
    $method = strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET'));
    $path = (string)parse_url((string)($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
    if (str_starts_with($path, APP_PREFIX . '/')) $path = substr($path, strlen(APP_PREFIX));

    // вход — без ключа
    $public = ['/auth/login' => 'app_login', '/auth/poll' => 'app_poll', '/auth/cancel' => 'app_cancel'];
    if (isset($public[$path])) {
        app_method($method, 'POST');
        app_query();
        $public[$path]();
    }

    $dev = app_auth();
    $get = [
        '/me' => fn() => app_out(['device' => ['id' => $dev['id'], 'name' => $dev['name'], 'created' => (int)$dev['created'],
                                   'expires' => (int)$dev['expires'], 'hard_expires' => (int)$dev['hard_expires']], 'now' => time()]),
        '/devices' => fn() => app_out(fsr_app_devices_list((string)$dev['id'])),
        '/status' => fn() => app_read('status', 20),
        '/net' => fn() => app_read('net', 5),
        '/zapret' => fn() => app_read('zapret', 10),
        '/tgws' => fn() => app_read('tgws', 10),
        '/led' => fn() => app_read('led', 10),
        '/mydirect' => fn() => app_read('mydirect', 10),
        '/vds' => fn() => app_out(fsr_vds()),
    ];
    $post = [
        '/auth/logout' => fn() => app_logout($dev),
        '/devices/revoke' => fn() => app_revoke($dev),
        '/devices/revoke-all' => fn() => app_revoke_all($dev),
    ];
    if (isset($get[$path])) { app_method($method, 'GET'); app_query(); $get[$path](); }
    if (isset($post[$path])) { app_method($method, 'POST'); app_query(); $post[$path](); }
    if ($path === '/data') {
        app_method($method, 'GET');
        $range = app_query(['range'])['range'] ?? 'day';
        if (!in_array($range, ['day', 'week', 'month'], true)) app_err(400, 'bad_param');
        $p = fsr_data_payload($range);
        $p['newdevs'] = fsr_data_newdevs();          // новые устройства за 7 дней (по всему журналу)
        app_out($p);
    }
    if (preg_match('~^/jobs/([^/]+)$~', $path, $m)) { app_method($method, 'GET'); app_query(); app_job($dev, $m[1]); }
    if (preg_match('~^/action/([a-z]{1,20})$~', $path, $m)) { app_method($method, 'POST'); app_query(); app_action($dev, $m[1]); }
    app_err(404, 'not_found');
} catch (Throwable $e) {
    error_log('fspirat-router-app: ' . $e->getMessage() . ' @' . $e->getLine());
    if (!headers_sent()) app_err(500, 'server_error');
}

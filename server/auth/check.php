<?php
// nginx auth_request: 204 — вход есть, 401 — нужно войти, 403 — действие без CSRF-токена или не с нашего сайта.
// nginx передаёт исходный запрос: FSR_ORIG_URI ($request_uri) и FSR_ORIG_METHOD ($request_method).
// Действия (POST к /router/api и /router/data) — только с токеном сессии в X-FSR и с нашего Origin;
// каждое пишется в журнал действий, опасные — ещё и в Telegram. Чтение (GET) — как раньше, по сессии.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';

// Как называть действие в Telegram; true — сообщать. Ключ — action в /router/api, «rename» — POST /router/data.
const FSR_ACTIONS = [
    'reboot' => ['🔄 Перезагрузка роутера', true], 'restart' => ['🔁 Перезапуск VPN', true],
    'update' => ['📥 Обновление подписки', true], 'switch' => ['🌍 Смена сервера', false],
    'block' => ['⛔ Интернет выключен устройству', true], 'unblock' => ['✅ Интернет включён устройству', true],
    'settargets' => ['📝 Изменён список сервисов', true], 
    'rename' => ['✏️ Переименовано устройство', false],
];

$notify = '';
try {
    if (!fsr_session_valid()) { http_response_code(401); exit; }
    $uri = (string)($_SERVER['FSR_ORIG_URI'] ?? '');
    $method = strtoupper((string)($_SERVER['FSR_ORIG_METHOD'] ?? 'GET'));
    if (preg_match('~^/router/(api|data)(\?|$)~', $uri, $m) && $method !== 'GET' && $method !== 'HEAD') {
        parse_str((string)parse_url($uri, PHP_URL_QUERY), $q);
        $action = $m[1] === 'data' ? 'rename' : preg_replace('/[^a-z]/', '', (string)($q['action'] ?? ''));
        $origin = (string)($_SERVER['HTTP_ORIGIN'] ?? '');
        $csrf = fsr_csrf();
        if ($origin !== (getenv('FSR_ORIGIN') ?: 'https://fspirat.online') || $csrf === ''
            || !hash_equals($csrf, (string)($_SERVER['HTTP_X_FSR'] ?? ''))) {
            fsr_audit('DENY', "$action csrf/origin");
            http_response_code(403); exit;
        }
        // в журнал — только известные параметры и только безопасные значения
        $detail = $action;
        foreach (['id', 'mac', 'via'] as $k) if (preg_match('/^[A-Za-z0-9:]{1,40}$/', (string)($q[$k] ?? ''))) $detail .= " $k=" . $q[$k];
        fsr_audit('ACTION', $detail);
        [$title, $tg] = FSR_ACTIONS[$action] ?? ['', false];
        if ($tg) $notify = $title . (preg_match('/^[0-9a-fA-F:]{17}$/', (string)($q['mac'] ?? '')) ? "\nMAC " . $q['mac'] : '') . "\nИз панели, IP " . fsr_ip();
    }
    http_response_code(204);
} catch (Throwable $e) {
    error_log('fspirat-router-auth: ' . $e->getMessage());
    http_response_code(401);
    exit;
}
// Уведомление — после ответа nginx: действие не ждёт Telegram
if ($notify !== '') {
    if (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
    try { fsr_tg_send($notify); } catch (Throwable $e) { error_log('fspirat-router-auth tg: ' . $e->getMessage()); }
}

<?php
// Выход: удалить сессию и вернуться на страницу входа. POST all=1 — выйти на всех устройствах сразу.
// Старая cookie после выхода не работает: сессия удаляется из базы, check.php отвечает 401.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';
header('Cache-Control: no-store');
header('Clear-Site-Data: "cache"');      // страница панели не останется в кэше браузера («назад» не покажет её)
try {
    $all = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && !empty($_POST['all'])
        && ($_SERVER['HTTP_ORIGIN'] ?? '') === (getenv('FSR_ORIGIN') ?: 'https://fspirat.online') && fsr_session_valid();
    if ($all) fsr_audit('LOGOUT_ALL');
    fsr_session_end($all);
    fsr_log($all ? 'LOGOUT_ALL' : 'LOGOUT');
} catch (Throwable $e) { error_log('fspirat-router-auth: ' . $e->getMessage()); }
header('Location: /router/login');
http_response_code(303);

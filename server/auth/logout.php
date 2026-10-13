<?php
// Выход: удалить сессию и вернуться на страницу входа. POST all=1 — выйти на всех устройствах сразу:
// все сессии веба, ключи приложения на телефонах и запомненные браузеры (снова спросят код из Telegram).
// Старая cookie после выхода не работает: сессия удаляется из базы, check.php отвечает 401.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';
header('Cache-Control: no-store');
header('Clear-Site-Data: "cache"');      // страница панели не останется в кэше браузера («назад» не покажет её)
try {
    $all = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && !empty($_POST['all'])
        && ($_SERVER['HTTP_ORIGIN'] ?? '') === fsr_origin() && fsr_session_valid();
    if ($all) fsr_audit('LOGOUT_ALL');
    $apps = fsr_session_end($all);
    fsr_log($all ? 'LOGOUT_ALL' : 'LOGOUT');
    // «Выход на всех устройствах» сообщает fspirat-watch (по LOGOUT_ALL); о телефонах — отсюда, после ответа
    if ($apps > 0) {
        fsr_log('APP_REVOKE');
        $text = "📵 Доступ приложения отозван на всех телефонах ($apps) — «Выйти на всех устройствах» в веб-панели, IP " . fsr_ip();
        fsr_later(fn() => fsr_tg_send($text));
    }
} catch (Throwable $e) { error_log('fspirat-router-auth: ' . $e->getMessage()); }
header('Location: /router/login');
http_response_code(303);

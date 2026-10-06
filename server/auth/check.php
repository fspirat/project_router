<?php
// nginx auth_request: 204 — вход есть, 401 — нужно войти. Ничего не выводит.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';
try {
    http_response_code(fsr_session_valid() ? 204 : 401);
} catch (Throwable $e) {
    error_log('fspirat-router-auth: ' . $e->getMessage());
    http_response_code(401);
}

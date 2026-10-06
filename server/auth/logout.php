<?php
// Выход: удалить сессию и вернуться на страницу входа.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';
header('Cache-Control: no-store');
try { fsr_session_end(); fsr_log('LOGOUT'); } catch (Throwable $e) { error_log('fspirat-router-auth: ' . $e->getMessage()); }
header('Location: /router/login');
http_response_code(303);

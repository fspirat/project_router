<?php
// php -S вместо nginx для веба в app-test.sh:
//   /_fsr_auth    → check.php, как auth_request: исходный адрес и метод — из заголовков X-Orig-Uri / X-Orig-Method
//                   (в nginx это fastcgi_param FSR_ORIG_URI / FSR_ORIG_METHOD), остальные заголовки — как у исходного запроса;
//   /router/data  → data.php, /router/logout → logout.php, /router/login → login.php.
$a = dirname(__DIR__);
$p = (string)parse_url((string)($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
if ($p === '/_fsr_auth') {
    $_SERVER['FSR_ORIG_URI'] = (string)($_SERVER['HTTP_X_ORIG_URI'] ?? '');
    $_SERVER['FSR_ORIG_METHOD'] = (string)($_SERVER['HTTP_X_ORIG_METHOD'] ?? 'GET');
    unset($_SERVER['HTTP_X_ORIG_URI'], $_SERVER['HTTP_X_ORIG_METHOD']);
    require "$a/check.php";
} elseif ($p === '/router/data') {
    require "$a/data.php";
} elseif ($p === '/router/logout') {
    require "$a/logout.php";
} elseif ($p === '/router/login') {
    require "$a/login.php";
} else {
    http_response_code(404);
}

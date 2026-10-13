<?php
// Данные страницы роутера, которые хранит сервер (переживают перезагрузку роутера и работают без туннеля):
//   GET  /router/data?range=day|week|month — история отклика, журнал, «роутер не на связи с …», имена устройств
//   GET  /router/data?devices=1            — кто имеет доступ: телефоны с приложением, сессии веба, входы (раздел «Безопасность»)
//   POST /router/data  mac=…&name=…       — своё имя устройства (пустое имя — вернуть как было)
//   POST /router/data?op=apprevoke  id=…  — отозвать доступ приложения на телефоне
// Историю и журнал пишет fspirat-watch (cron раз в минуту) в /var/lib/fspirat/. Доступ — только после входа (auth_request);
// POST — ещё и с CSRF-токеном и нашим Origin (check.php). Сами данные — data-lib.php (общие с приложением).
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';
require __DIR__ . '/app-lib.php';
require __DIR__ . '/data-lib.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: private, no-store');
header('X-Content-Type-Options: nosniff');

function out(array $a, int $code = 200): never { http_response_code($code); echo json_encode($a, JSON_UNESCAPED_UNICODE); exit; }

// CSRF-токен этой сессии для страницы (check.php требует его в X-FSR у каждого действия)
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET' && isset($_GET['csrf'])) out(['csrf' => fsr_csrf()]);

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET' && isset($_GET['devices'])) {
    $tok = fsr_session_token();
    out(fsr_app_devices_list(null, $tok !== '' ? hash('sha256', $tok) : null));
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== fsr_origin()) out(['error' => 'origin'], 403);
    if (($_GET['op'] ?? '') === 'apprevoke') {
        // check.php уже записал «ACTION apprevoke»; сообщение в Telegram — отсюда, с именем телефона
        $d = fsr_app_revoke((string)($_POST['id'] ?? ''), 'web');
        if (!$d) out(['error' => 'not_found'], 404);
        fsr_log('APP_REVOKE');
        fsr_audit('APP_REVOKE', 'id=' . $d['id']);
        $text = FSR_ACTIONS['apprevoke'][0] . ': ' . fsr_app_label($d) . "\nИз панели, IP " . fsr_ip();
        fsr_later(fn() => fsr_tg_send($text));
        out(['ok' => true]);
    }
    $mac = strtolower(trim((string)($_POST['mac'] ?? '')));
    if (!preg_match('/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/', $mac)) out(['error' => 'bad mac'], 400);
    $name = trim(preg_replace('/[\x00-\x1f\x7f]/u', '', (string)($_POST['name'] ?? '')) ?? '');
    $name = mb_substr($name, 0, 40);
    out(['ok' => true, 'names' => fsr_names_set($mac, $name)]);
}

$range = $_GET['range'] ?? 'day';
out(fsr_data_payload(is_string($range) ? $range : 'day'));

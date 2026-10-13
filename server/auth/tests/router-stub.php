<?php
// Заглушка CGI роутера (router/www/cgi-bin/fspirat) для app-test.sh: сервер ходит сюда вместо туннеля (FSR_ROUTER).
// Как настоящий CGI: токен — только в cookie fspirat_token, сверяется с $STUB_DIR/router.token («токен на роутере»),
// не совпал → 403 {"error":"forbidden"}; действия, кроме чтения, — только POST (иначе 405 {"error":"method"}).
// Каждый вызов — строка JSON в $STUB_DIR/cgi.log: метод, action, строка запроса как пришла (без декодирования),
// совпал ли токен, Content-Length — тесты проверяют «роутер не вызван» / «вызван ровно 1 раз» и кодирование параметров.
// Поведение задают файлы в $STUB_DIR:
//   resp_<action>  — «КОД\nТЕЛО» вместо обычного ответа (400/409/503 с {"error":…}, пустое тело, сырой TAB и управляющий символ, HTML);
//   sleep_<action> — сколько секунд молчать перед ответом (дольше таймаута сервера).
declare(strict_types=1);

$d = (string)getenv('STUB_DIR');
$a = (string)($_GET['action'] ?? '');
if (!preg_match('/^[a-z]{1,20}$/', $a)) $a = '';
$method = (string)($_SERVER['REQUEST_METHOD'] ?? 'GET');
$tok = preg_match('/(?:^|;\s*)fspirat_token=([^;]*)/', (string)($_SERVER['HTTP_COOKIE'] ?? ''), $m) ? $m[1] : '';
$ok = $tok !== '' && hash_equals(trim((string)@file_get_contents("$d/router.token")), $tok);
file_put_contents("$d/cgi.log", json_encode([
    'm' => $method, 'a' => $a, 'q' => (string)($_SERVER['QUERY_STRING'] ?? ''), 'tok' => $ok,
    'cl' => $_SERVER['CONTENT_LENGTH'] ?? $_SERVER['HTTP_CONTENT_LENGTH'] ?? null,
], JSON_UNESCAPED_SLASHES) . "\n", FILE_APPEND | LOCK_EX);

header('Content-Type: application/json');
header('Cache-Control: no-store');
if ($a !== '' && is_file("$d/sleep_$a")) sleep((int)file_get_contents("$d/sleep_$a"));
if (!$ok) { http_response_code(403); echo '{"error":"forbidden"}'; exit; }
if ($a !== '' && is_file("$d/resp_$a")) {
    [$code, $body] = array_pad(explode("\n", (string)file_get_contents("$d/resp_$a"), 2), 2, '');
    http_response_code((int)$code);
    echo $body;
    exit;
}
if (!in_array($a, ['status', 'net', 'pingone', 'mydirect', 'zapret', 'tgws', 'led', 'subs'], true) && $method !== 'POST') {
    http_response_code(405); echo '{"error":"method"}'; exit;
}

$j = fn($v) => json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
$mac = strtolower(str_replace('%3A', ':', (string)($_GET['mac'] ?? '')));
$status = [
    'running' => true, 'split_active' => true, 'current' => 'nodeA1',
    'ping' => ['updated' => time(), 'current' => 'nodeA1', 'socks' => true, 'real' => 55, 'nodes' => [
        ['id' => 'nodeA1', 'name' => 'Германия', 'ms' => 40, 'group' => 'nosok'],
        ['id' => 'nodeB2', 'name' => 'Нидерланды', 'ms' => 0, 'group' => 'nosok'],
    ]],
    'svc' => new stdClass(),            // пустой объект: сервер должен отдать {} как есть, а не []
    'subs' => [['id' => 'cfg1', 'name' => 'nosok', 'nodes' => 2]],
    'devices' => [['mac' => 'aa:bb:cc:dd:ee:01', 'ip' => '192.168.1.5', 'name' => 'phone', 'online' => true]],
    'sys' => ['cpu' => 3, 'temp' => 51],
];
switch ($a) {
    case 'status': case 'ping':
        echo $j($status); break;
    case 'net':
        echo '{"dev":"wan","rx":1000,"tx":2000,"rx_total":3,"tx_total":4}'; break;
    case 'pingone':
        echo $j(['id' => (string)($_GET['id'] ?? ''), 'ms' => 7, 'ts' => time()]); break;
    case 'mydirect':
        echo '{"domains":["a.example","b.example","luci-only.example","geosite:category-ru"],"added":["a.example","b.example"]}'; break;
    case 'zapret':
        echo '{"installed":true,"enabled":false,"mode":"off"}'; break;
    case 'tgws':
        echo '{"installed":true,"enabled":false,"port":1443}'; break;
    case 'led':
        echo '{"on":true,"items":[{"name":"white","on":true}]}'; break;
    case 'speedtest':
        echo $j(['via' => (string)($_GET['via'] ?? ''), 'ts' => time(), 'down' => 90000000, 'up' => 40000000, 'latency' => 12,
            'ip' => '203.0.113.77', 'country' => 'DE', 'server' => 'Hetzner (Германия)', 'streams' => 4, 'up_limited' => false]); break;
    case 'block': case 'unblock':
        echo $j(['ok' => true, 'mac' => $mac, 'blocked' => $a === 'block']); break;
    case 'ledset':
        echo $j(['on' => ($_GET['on'] ?? '') === '1', 'items' => []]); break;
    case '':
        http_response_code(400); echo '{"error":"unknown action"}'; break;
    default:
        echo '{"ok":true}';
}

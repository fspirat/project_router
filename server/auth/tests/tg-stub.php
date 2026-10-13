<?php
// Заглушка Telegram Bot API для app-test.sh (FSR_TG_API → сюда): каждый вызов — строка JSON в $STUB_DIR/tg.log
// {n, m: метод, tok: совпал ли токен бота (сам токен не пишется), mid: message_id ответа, p: параметры}.
// sendMessage отвечает message_id = 1000 + номер вызова — по нему тесты жмут кнопки входа в боте.
// Файл $STUB_DIR/tg_down — «Telegram недоступен»: 502 {"ok":false}.
declare(strict_types=1);

$d = (string)getenv('STUB_DIR');
header('Content-Type: application/json');
if (!preg_match('~^/bot([^/]+)/([A-Za-z]+)$~', (string)parse_url((string)($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH), $m)) {
    http_response_code(404); echo '{"ok":false,"error_code":404}'; exit;
}
$raw = (string)file_get_contents('php://input');
$p = str_contains((string)($_SERVER['CONTENT_TYPE'] ?? ''), 'json') ? json_decode($raw, true) : null;
if (!is_array($p)) parse_str($raw, $p);

$fp = fopen("$d/tg.seq", 'c+');
flock($fp, LOCK_EX);
$n = (int)stream_get_contents($fp) + 1;
ftruncate($fp, 0); rewind($fp); fwrite($fp, (string)$n);
flock($fp, LOCK_UN); fclose($fp);

$down = is_file("$d/tg_down");
$mid = $m[2] === 'sendMessage' && !$down ? 1000 + $n : null;
file_put_contents("$d/tg.log", json_encode(['n' => $n, 'm' => $m[2], 'tok' => hash_equals((string)getenv('STUB_TG_TOKEN'), $m[1]),
    'mid' => $mid, 'p' => $p], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE) . "\n", FILE_APPEND | LOCK_EX);
if ($down) { http_response_code(502); echo '{"ok":false,"error_code":502,"description":"Bad Gateway"}'; exit; }
echo json_encode(['ok' => true, 'result' => $mid ? ['message_id' => $mid, 'chat' => ['id' => (int)($p['chat_id'] ?? 0)], 'date' => time()] : true]);

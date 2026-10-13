<?php
// Помощник app-test.sh: временная база FSR_DIR/auth.sqlite. Таблицы создаёт настоящий код (fsr_db, fsr_db2, fsr_app_db).
//   php db.php sql "SQL"     — SELECT: строки, поля через «|» (NULL — «NULL»); иначе — выполнить (можно несколько через «;»)
//   php db.php mint ИМЯ      — ключ устройства в обход входа через бота (как fsr_app_login_issue): печатает «id ключ»
//   php db.php session       — сессия веба на 12 ч: печатает значение cookie fsr_session
declare(strict_types=1);
define('FSR', true);
require dirname(__DIR__) . '/lib.php';
require dirname(__DIR__) . '/app-lib.php';

$db = fsr_app_db();
fsr_db2();
switch ($argv[1] ?? '') {
    case 'sql':
        $q = (string)($argv[2] ?? '');
        if (!preg_match('/^\s*(SELECT|PRAGMA|WITH)\b/i', $q)) { $db->exec($q); break; }
        foreach ($db->query($q)->fetchAll(PDO::FETCH_NUM) as $r) echo implode('|', array_map(fn($v) => $v === null ? 'NULL' : (string)$v, $r)), "\n";
        break;
    case 'mint':
        $now = time();
        $tok = fsr_app_token_new();
        $id = fsr_app_hex(8);
        fsr_app_q('INSERT INTO app_devices(id, token_hash, name, model, os, app, created, seen, expires, hard_expires, ip, last_ip, revoked, revoked_by)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,NULL,NULL)',
            [$id, hash('sha256', $tok), (string)($argv[2] ?? 'iPhone'), 'iPhone15,2', 'iOS 18.1', '1.0', $now, $now, $now + FSR_APP_TTL, $now + FSR_APP_HARD, '127.0.0.1', '127.0.0.1']);
        echo "$id $tok\n";
        break;
    case 'session':
        $tok = bin2hex(random_bytes(32));
        fsr_app_q('INSERT INTO sessions(hash, created, seen, ttl, ip, ua) VALUES(?,?,?,?,?,?)',
            [hash('sha256', $tok), time(), time(), FSR_TTL_SHORT, '127.0.0.1', 'app-test']);
        echo "$tok\n";
        break;
    default:
        fwrite(STDERR, "usage: db.php sql SQL | mint ИМЯ | session\n");
        exit(2);
}

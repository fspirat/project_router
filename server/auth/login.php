<?php
// Страница входа в панель роутера (вместо окна браузера). GET — форма, POST — проверка пароля.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';

header('Cache-Control: no-store');
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: same-origin');   // при no-referrer браузер шлёт форму с Origin: null
header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");

$next = fsr_next((string)($_POST['next'] ?? $_GET['next'] ?? '/router/'));
$error = '';
$wait = 0;
$step = 'password';          // password → (новое устройство) code

$go = function (string $to): never { header('Location: ' . fsr_next($to)); http_response_code(303); exit; };

try {
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
        $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
        if ($origin !== '' && $origin !== (getenv('FSR_ORIGIN') ?: 'https://fspirat.online')) { http_response_code(403); exit; }
        if ($wait = fsr_locked()) {
            fsr_log('LOCKED');
            $error = 'Слишком много неверных попыток. Вход с этого адреса закрыт ещё на ' . (int)ceil($wait / 60) . ' мин.';
        } elseif (isset($_POST['code'])) {
            // второй шаг: код из Telegram
            if ($ok = fsr_code_check(preg_replace('/\D/', '', (string)$_POST['code']))) {
                fsr_session_start($ok['remember']);
                fsr_device_add();
                fsr_log('OK');
                $go($ok['next']);
            }
            if (fsr_code_pending()) {
                $left = fsr_fail();
                fsr_log('FAIL');
                $step = 'code';
                $error = $left > 0 ? "Неверный код. Осталось попыток: $left." : 'Слишком много неверных попыток. Вход закрыт на ' . (FSR_LOCK_SEC / 60) . ' мин.';
                http_response_code(403);
            } else {
                $error = 'Код истёк или попытки закончились — введи пароль ещё раз, придёт новый код.';
            }
        } elseif (fsr_password_ok((string)($_POST['password'] ?? ''))) {
            $remember = !empty($_POST['remember']);
            if (!fsr_tg() || fsr_device_ok()) {          // знакомое устройство (или бот не настроен) — сразу внутрь
                fsr_session_start($remember);
                fsr_log('OK');
                $go($next);
            }
            if (fsr_code_start($remember, $next)) {
                fsr_log('CODE');
                $step = 'code';
            } else {
                fsr_log('CODEFAIL');
                $error = 'Пароль верный, но код в Telegram отправить не удалось. Попробуй через минуту.';
                http_response_code(503);
            }
        } else {
            usleep(random_int(300000, 700000));   // замедляем подбор
            $left = fsr_fail();
            fsr_log('FAIL');
            $error = $left > 0 ? "Неверный пароль. Осталось попыток: $left."
                               : 'Слишком много неверных попыток. Вход с этого адреса закрыт на ' . (FSR_LOCK_SEC / 60) . ' мин.';
            http_response_code(403);
        }
    } elseif (fsr_session_valid()) {
        $go($next);
    } elseif (empty($_GET['restart']) && fsr_code_pending()) {
        $step = 'code';
    }
} catch (Throwable $e) {
    error_log('fspirat-router-auth: ' . $e->getMessage());
    $error = 'Сервер входа сейчас не отвечает. Попробуйте через минуту.';
    http_response_code(500);
}
$h = fn(string $s) => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
?><!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#050605">
<title>Вход · FSPIRAT Router</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Press+Start+2P&display=swap" rel="stylesheet">
<style>
  :root{--bg:#050605;--panel:#0c110a;--edge:#1d2b15;--green:#7fbf3a;--lime:#9be052;--text:#d9e7cd;--dim:#7f8e74;--red:#e0563c;
        --pixel:"Minecraft","Press Start 2P",monospace;--body:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
  *{box-sizing:border-box}
  html,body{margin:0;height:100%}
  body{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px 16px;color:var(--text);font:15px/1.5 var(--body);
       background:linear-gradient(rgba(127,191,58,.035) 1px,transparent 1px) 0 0/32px 32px,
                  linear-gradient(90deg,rgba(127,191,58,.035) 1px,transparent 1px) 0 0/32px 32px,
                  radial-gradient(ellipse at 50% -10%,#10200b 0%,var(--bg) 60%);background-color:var(--bg)}
  .box{width:100%;max-width:380px}
  .logo{font-family:var(--pixel);font-size:22px;color:var(--lime);text-shadow:3px 3px 0 #1f3a10;letter-spacing:1px;text-align:center;margin:0 0 6px}
  .logo small{display:block;font-size:10px;color:var(--dim);text-shadow:none;margin-top:10px;letter-spacing:3px}
  .panel{background:var(--panel);border:2px solid var(--edge);margin-top:22px;padding:22px 20px 20px;
         box-shadow:inset 3px 3px 0 rgba(255,255,255,.035),inset -3px -3px 0 rgba(0,0,0,.5),4px 4px 0 #000}
  .lock{display:flex;align-items:center;gap:12px;margin-bottom:18px}
  .lock svg{flex:none;width:32px;height:32px;shape-rendering:crispEdges}
  .lock b{font-family:var(--pixel);font-size:11px;font-weight:400;color:var(--green);letter-spacing:1px;line-height:1.8}
  .lock span{display:block;color:var(--dim);font-size:13px}
  label.f{display:block;color:var(--dim);font-size:13px;margin-bottom:6px}
  input[type=password]{width:100%;font:inherit;font-size:16px;color:var(--text);background:#0a0f08;border:2px solid #000;
       box-shadow:inset 0 0 0 1px #1f2c17;padding:11px 12px;outline:none}
  input[type=password]:focus{box-shadow:inset 0 0 0 1px var(--lime),0 0 0 2px rgba(155,224,82,.18)}
  .row{display:flex;align-items:center;gap:9px;margin:14px 0 18px;color:var(--text);font-size:14px;cursor:pointer;user-select:none}
  .row input{appearance:none;width:18px;height:18px;margin:0;flex:none;background:#0a0f08;border:2px solid #000;box-shadow:inset 0 0 0 1px #2c3f20;cursor:pointer}
  .row input:checked{background:var(--lime);box-shadow:inset -3px -3px 0 #4f8a22}
  .row input:focus-visible{outline:2px solid var(--lime);outline-offset:2px}
  button{width:100%;font-family:var(--pixel);font-size:12px;letter-spacing:1px;color:#0b1406;cursor:pointer;padding:14px;
         background:var(--lime);border:2px solid #000;box-shadow:inset 3px 3px 0 #c8f59a,inset -3px -3px 0 #4f8a22,3px 3px 0 #000}
  button:hover{background:#aaf064}
  button:active{box-shadow:inset -3px -3px 0 #c8f59a,inset 3px 3px 0 #4f8a22}
  button:focus-visible{outline:2px solid var(--text);outline-offset:3px}
  .err{margin:0 0 16px;padding:10px 12px;border:2px solid #5a2216;background:#1c0b06;color:#f08a73;font-size:14px}
  .hint{margin:16px 0 0;color:var(--dim);font-size:12px;text-align:center}
  .user{position:absolute;left:-9999px}
  .sent{margin:0 0 14px;color:var(--text);font-size:14px}
  input.code{width:100%;font:inherit;font-family:var(--pixel);font-size:22px;letter-spacing:8px;text-align:center;color:var(--lime);
       background:#0a0f08;border:2px solid #000;box-shadow:inset 0 0 0 1px #1f2c17;padding:12px;outline:none;margin-bottom:18px}
  input.code:focus{box-shadow:inset 0 0 0 1px var(--lime),0 0 0 2px rgba(155,224,82,.18)}
  .hint a{color:var(--green)}
</style>
</head>
<body>
<main class="box">
  <p class="logo">FSPIRAT<small>ROUTER · VPN</small></p>
  <form class="panel" method="post" action="/router/login" autocomplete="on">
    <div class="lock">
      <svg viewBox="0 0 16 16" aria-hidden="true"><path fill="#2a3d1d" d="M4 7h8v7H4z"/><path fill="#9be052" d="M5 2h6v1h1v4h-2V4H6v3H4V3h1z"/><path fill="#7fbf3a" d="M3 7h10v1H3zM3 8h1v6H3zM12 8h1v6h-1zM3 14h10v1H3z"/><path fill="#9be052" d="M7 9h2v3H7z"/></svg>
      <div><b>ВХОД В ПАНЕЛЬ</b><span>Роутер, VPN и LuCI — один пароль</span></div>
    </div>
    <?php if ($error): ?><p class="err" role="alert"><?= $h($error) ?></p><?php endif; ?>
    <?php if ($step === 'code'): ?>
    <p class="sent">📨 Это новое устройство — бот прислал в Telegram код из 6 цифр.</p>
    <label class="f" for="code">Код из Telegram</label>
    <input class="code" type="text" id="code" name="code" required autofocus inputmode="numeric" pattern="[0-9 ]{6,7}" maxlength="7"
           autocomplete="one-time-code" placeholder="000000" <?= $wait ? 'disabled' : '' ?>>
    <button type="submit" <?= $wait ? 'disabled' : '' ?>>ПОДТВЕРДИТЬ</button>
    <p class="hint">После подтверждения это устройство запомнится на 30 дней. <a href="/router/login?restart=1&amp;next=<?= $h(rawurlencode($next)) ?>">Ввести пароль заново</a></p>
    <?php else: ?>
    <input class="user" type="text" name="username" value="<?= FSR_USER ?>" autocomplete="username" tabindex="-1" aria-hidden="true">
    <label class="f" for="pw">Пароль</label>
    <input type="password" id="pw" name="password" required autofocus autocomplete="current-password" <?= $wait ? 'disabled' : '' ?>>
    <label class="row"><input type="checkbox" name="remember" value="1" checked> Запомнить на этом устройстве (30 дней)</label>
    <input type="hidden" name="next" value="<?= $h($next) ?>">
    <button type="submit" <?= $wait ? 'disabled' : '' ?>>ВОЙТИ</button>
    <p class="hint">Все входы и неудачные попытки записываются.</p>
    <?php endif; ?>
  </form>
</main>
</body>
</html>

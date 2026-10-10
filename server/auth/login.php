<?php
// Страница входа в панель роутера (вместо окна браузера). GET — форма, POST — проверка пароля.
declare(strict_types=1);
define('FSR', true);
require __DIR__ . '/lib.php';

header('Cache-Control: no-store');
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: same-origin');   // при no-referrer браузер шлёт форму с Origin: null
// стиль страницы — встроенный (одна страница, без скриптов вообще), шрифт — свой /router/fonts/ (без Google)
header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; font-src 'self'; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'; object-src 'none'");

$next = fsr_next((string)($_POST['next'] ?? $_GET['next'] ?? '/router/'));
$error = '';
$wait = 0;
$step = 'password';          // password → (новое устройство) code

$go = function (string $to): never { header('Location: ' . fsr_next($to)); http_response_code(303); exit; };

try {
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
        $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
        if ($origin !== '' && $origin !== (getenv('FSR_ORIGIN') ?: 'https://example.org')) { http_response_code(403); exit; }
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
<meta name="theme-color" content="#090B0F" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#F6F8FB" media="(prefers-color-scheme: light)">
<title>Вход — Router AX3000T</title>
<!-- значок вкладки встроен (data:) — CSP страницы входа разрешает картинки только так -->
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22%3E%3Cdefs%3E%3ClinearGradient id=%22g%22 x1=%220%22 y1=%220%22 x2=%221%22 y2=%221%22%3E%3Cstop offset=%220%22 stop-color=%22%2334D399%22/%3E%3Cstop offset=%221%22 stop-color=%22%23047857%22/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width=%2264%22 height=%2264%22 rx=%2215%22 fill=%22url(%23g)%22/%3E%3Cg transform=%22translate(12 12) scale(1.6667)%22 fill=%22none%22 stroke=%22%23fff%22 stroke-width=%222%22 stroke-linecap=%22round%22 stroke-linejoin=%22round%22%3E%3Crect width=%2220%22 height=%228%22 x=%222%22 y=%2214%22 rx=%222%22/%3E%3Cpath d=%22M6.01 18H6%22/%3E%3Cpath d=%22M10.01 18H10%22/%3E%3Cpath d=%22M15 10v4%22/%3E%3Cpath d=%22M17.84 7.17a4 4 0 0 0-5.66 0%22/%3E%3Cpath d=%22M20.66 4.34a8 8 0 0 0-11.31 0%22/%3E%3C/g%3E%3C/svg%3E">
<style>
  /* Router AX3000T — страница входа. Шрифт Inter — свой (/router/fonts/, открыт без входа), без Google и без скриптов.
     Тема — как в системе (без JS выбор из панели здесь недоступен). */
  @font-face{font-family:"Inter";font-weight:100 900;font-display:swap;src:url("/router/fonts/inter-cyrillic-wght-normal.woff2") format("woff2");unicode-range:U+0301,U+0400-045F,U+0490-0491,U+04B0-04B1,U+2116}
  @font-face{font-family:"Inter";font-weight:100 900;font-display:swap;src:url("/router/fonts/inter-latin-wght-normal.woff2") format("woff2");unicode-range:U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD}
  @font-face{font-family:"JetBrains Mono";font-weight:100 800;font-display:swap;src:url("/router/fonts/jetbrains-mono-latin-wght-normal.woff2") format("woff2");unicode-range:U+0000-00FF}
  :root{--bg:#090B0F;--card:#161B22;--surface:#11151B;--border:#252B35;--border-2:#313946;--text:#F1F5F9;--dim:#94A3B8;--faint:#64748B;
        --acc:#34D399;--acc-tx:#34D399;--acc-hov:#4ADEA8;--on-acc:#052E1F;--acc-soft:rgba(52,211,153,.12);
        --err:#F87171;--err-soft:rgba(248,113,113,.10);--err-bd:rgba(248,113,113,.32);
        --glow-1:rgba(52,211,153,.16);--glow-2:rgba(96,165,250,.08);--shadow:0 24px 60px -24px rgba(0,0,0,.8),0 2px 8px rgba(0,0,0,.35);color-scheme:dark}
  @media (prefers-color-scheme:light){
    :root{--bg:#F6F8FB;--card:#FFFFFF;--surface:#F8FAFC;--border:#E2E8F0;--border-2:#CBD5E1;--text:#0F172A;--dim:#64748B;--faint:#94A3B8;
          --acc:#059669;--acc-tx:#047857;--acc-hov:#047857;--on-acc:#FFFFFF;--acc-soft:rgba(5,150,105,.10);
          --err:#DC2626;--err-soft:rgba(220,38,38,.06);--err-bd:rgba(220,38,38,.28);
          --glow-1:rgba(5,150,105,.12);--glow-2:rgba(37,99,235,.07);--shadow:0 24px 60px -28px rgba(15,23,42,.28),0 2px 8px rgba(15,23,42,.05);color-scheme:light}
  }
  *{box-sizing:border-box}
  html,body{margin:0;min-height:100%}
  body{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px 16px;color:var(--text);
       font:15px/1.5 "Inter",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased;
       background:radial-gradient(800px 480px at 15% -10%,var(--glow-1),transparent 65%),radial-gradient(700px 500px at 105% 110%,var(--glow-2),transparent 60%),var(--bg)}
  .box{width:100%;max-width:400px}
  .ic{width:18px;height:18px;flex:none;fill:none;stroke:currentColor;stroke-width:1.75;stroke-linecap:round;stroke-linejoin:round}
  .card{background:var(--card);border:1px solid var(--border);border-radius:18px;box-shadow:var(--shadow);padding:30px 28px 26px}
  .brand{display:flex;align-items:center;gap:12px;margin-bottom:26px}
  .mark{width:44px;height:44px;border-radius:13px;display:grid;place-items:center;color:#fff;flex:none;
        background:linear-gradient(145deg,#34D399,#047857);box-shadow:inset 0 1px 0 rgba(255,255,255,.25),0 8px 20px -8px rgba(16,185,129,.6)}
  .mark .ic{width:24px;height:24px;stroke-width:2}
  .brand b{display:block;font-size:16px;font-weight:650;letter-spacing:-.01em;line-height:1.25}
  .brand div span{display:block;font-size:12.5px;color:var(--dim)}
  h1{margin:0 0 4px;font-size:22px;font-weight:650;letter-spacing:-.02em;line-height:1.3}
  .lead{margin:0 0 22px;color:var(--dim);font-size:14px}
  label.f{display:block;color:var(--text);font-size:13px;font-weight:500;margin-bottom:7px}
  .field{position:relative}
  .field .ic{position:absolute;left:13px;top:50%;margin-top:-9px;color:var(--faint);pointer-events:none}
  input[type=password],input.code{width:100%;font:inherit;font-size:16px;color:var(--text);background:var(--surface);border:1px solid var(--border-2);border-radius:10px;
       height:46px;padding:0 14px 0 42px;outline:none;transition:border-color .15s,box-shadow .15s}
  input[type=password]:focus,input.code:focus{border-color:var(--acc);box-shadow:0 0 0 4px var(--acc-soft)}
  input:disabled{opacity:.55;cursor:not-allowed}
  .row{display:flex;align-items:center;gap:10px;margin:16px 0 22px;color:var(--text);font-size:14px;cursor:pointer;user-select:none}
  .row input{appearance:none;width:18px;height:18px;margin:0;flex:none;border-radius:5px;background:var(--surface);border:1px solid var(--border-2);cursor:pointer;
       display:grid;place-items:center;transition:background-color .15s,border-color .15s}
  .row input::after{content:"";width:5px;height:9px;border:solid var(--on-acc);border-width:0 2px 2px 0;transform:rotate(45deg) translate(-1px,-1px);opacity:0}
  .row input:checked{background:var(--acc);border-color:var(--acc)} .row input:checked::after{opacity:1}
  .row input:focus-visible,button:focus-visible,a:focus-visible{outline:2px solid var(--acc);outline-offset:2px}
  .row small{color:var(--dim);font-size:13px}
  button{width:100%;height:46px;font:inherit;font-size:15px;font-weight:600;color:var(--on-acc);cursor:pointer;background:var(--acc);border:0;border-radius:10px;
         display:flex;align-items:center;justify-content:center;gap:8px;transition:background-color .15s,transform .05s}
  button:hover:not(:disabled){background:var(--acc-hov)}
  button:active:not(:disabled){transform:translateY(1px)}
  button:disabled{opacity:.5;cursor:not-allowed}
  .err{display:flex;gap:10px;align-items:flex-start;margin:0 0 18px;padding:11px 13px;border:1px solid var(--err-bd);border-radius:10px;background:var(--err-soft);color:var(--err);font-size:13.5px}
  .err .ic{margin-top:1px}
  .sent{display:flex;gap:12px;align-items:flex-start;margin:0 0 18px;padding:12px 14px;border:1px solid var(--border);border-radius:10px;background:var(--surface);font-size:13.5px;color:var(--dim)}
  .sent .ic{color:#60A5FA;margin-top:1px}
  .sent b{color:var(--text);font-weight:600}
  input.code{font-family:"JetBrains Mono",ui-monospace,monospace;font-size:22px;letter-spacing:.45em;text-align:center;padding:0 14px;margin-bottom:18px;height:54px}
  .alt{margin:16px 0 0;text-align:center;font-size:13px;color:var(--dim)}
  .alt a{color:var(--acc-tx);text-decoration:none;font-weight:500} .alt a:hover{text-decoration:underline}
  .safe{display:flex;align-items:center;justify-content:center;gap:8px;margin:18px 0 0;color:var(--faint);font-size:12.5px;text-align:center}
  .safe .ic{width:16px;height:16px;color:var(--acc-tx)}
  .user{position:absolute;left:-9999px}
  @media (max-width:420px){.card{padding:24px 20px 22px;border-radius:16px} h1{font-size:20px}}
  @media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>
</head>
<body>
<main class="box">
  <form class="card" method="post" action="/router/login" autocomplete="on">
    <div class="brand">
      <span class="mark"><svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><rect width="20" height="8" x="2" y="14" rx="2"/><path d="M6.01 18H6"/><path d="M10.01 18H10"/><path d="M15 10v4"/><path d="M17.84 7.17a4 4 0 0 0-5.66 0"/><path d="M20.66 4.34a8 8 0 0 0-11.31 0"/></svg></span>
      <div><b>Router AX3000T</b><span>Панель управления</span></div>
    </div>
    <?php if ($error): ?><p class="err" role="alert"><svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/></svg><span><?= $h($error) ?></span></p><?php endif; ?>
    <?php if ($step === 'code'): ?>
    <h1>Подтвердите вход</h1>
    <p class="lead">Это новое устройство — нужен код из Telegram.</p>
    <p class="sent"><svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/><path d="m21.854 2.147-10.94 10.939"/></svg><span>Бот прислал в Telegram <b>код из 6 цифр</b>. Введите его ниже.</span></p>
    <label class="f" for="code">Код из Telegram</label>
    <input class="code" type="text" id="code" name="code" required autofocus inputmode="numeric" pattern="[0-9 ]{6,7}" maxlength="7"
           autocomplete="one-time-code" placeholder="000000" <?= $wait ? 'disabled' : '' ?>>
    <button type="submit" <?= $wait ? 'disabled' : '' ?>>Подтвердить</button>
    <p class="alt">После подтверждения устройство запомнится на 30 дней.<br><a href="/router/login?restart=1&amp;next=<?= $h(rawurlencode($next)) ?>">Ввести пароль заново</a></p>
    <?php else: ?>
    <h1>Добро пожаловать</h1>
    <p class="lead">Войдите для управления сетью</p>
    <input class="user" type="text" name="username" value="<?= FSR_USER ?>" autocomplete="username" tabindex="-1" aria-hidden="true">
    <label class="f" for="pw">Пароль</label>
    <div class="field"><svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="16" r="1"/><rect x="3" y="10" width="18" height="12" rx="2"/><path d="M7 10V7a5 5 0 0 1 10 0v3"/></svg><input type="password" id="pw" name="password" required autofocus autocomplete="current-password" <?= $wait ? 'disabled' : '' ?>></div>
    <label class="row"><input type="checkbox" name="remember" value="1" checked> Запомнить это устройство <small>· 30 дней</small></label>
    <input type="hidden" name="next" value="<?= $h($next) ?>">
    <button type="submit" <?= $wait ? 'disabled' : '' ?>>Войти</button>
    <?php endif; ?>
    <p class="safe"><svg class="ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/></svg><span>Пароль + код Telegram на новом устройстве. Все входы записываются.</span></p>
  </form>
</main>
</body>
</html>

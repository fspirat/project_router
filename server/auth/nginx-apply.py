#!/usr/bin/env python3
"""Переводит /router/ и luci.example.org с окна браузера (auth_basic) на свою страницу входа;
этап 7 — API приложения iPhone /router/app/v1/ (блок между метками «# --- fsr-app v1 (begin)» и «(end)»).

Запускается на сервере от root (workflow «Deploy server»). Повторный запуск ничего не ломает и пишет «уже настроен».
Перед правкой делает копии *.bak-auth; если `nginx -t` не проходит — возвращает копии и выходит с ошибкой.
Токен роутера в сниппете не читается в лог и не меняется.
"""
import re, shutil, subprocess, sys, time

SNIPPET = '/etc/nginx/snippets/fspirat-router.conf'
ROUTER_SITE = '/etc/nginx/sites-available/luci.example.org'
PHP = 'unix:/run/php/php8.5-fpm.sock'
AUTH_DIR = '/var/www/router-auth'
BASIC = re.compile(r'[ \t]*auth_basic\s+"[^"]*";\n[ \t]*auth_basic_user_file\s+[^;]+;\n')

def fcgi(script, extra=''):
    return (f'    include fastcgi_params;\n    fastcgi_param SCRIPT_FILENAME {AUTH_DIR}/{script};\n'
            f'{extra}    fastcgi_pass {PHP};\n')

AUTH_LOC = ('location = /_fsr_auth {\n    internal;\n'
            + fcgi('check.php', '    fastcgi_pass_request_body off;\n    fastcgi_param CONTENT_LENGTH "";\n') + '}\n')

# Этап 2: данные страницы на сервере (data.php) и открытые файлы PWA (браузер берёт манифест и иконки без cookie).
EXTRA = ('\n# --- данные страницы и иконки (server/auth/data.php, web/manifest.webmanifest) ---\n'
         'location = /router/data {\n    auth_request /_fsr_auth;\n    error_page 401 = @fsr_api_401;\n'
         '    client_max_body_size 4k;\n' + fcgi('data.php') + '}\n'
         'location ~ ^/router/(manifest\\.webmanifest|icon-[0-9]+\\.png|apple-touch-icon\\.png)$ {\n'
         '    expires 7d;\n}\n')

# Этап 3 (защита, 06.10.2026):
#   — /router/api и /router/data только с заголовком X-FSR: 1 (его ставит страница) — защита от CSRF:
#     ссылка «…/router/api?action=reboot» с чужого сайта больше не перезагрузит роутер;
#   — /router/ как ^~: regex-локации сайта (например, *.php) не смогут обойти вход;
#   — открытые файлы PWA — точными локациями (regex перестал бы работать из-за ^~).
CSRF = '    if ($http_x_fsr != "1") { return 403 \'{"error":"csrf"}\'; }\n'
PWA = ''.join(f'location = /router/{f} {{\n    expires 7d;\n}}\n'
              for f in ('manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png'))

def harden(s):
    if '$http_x_fsr' in s:
        return s
    for loc in ('location = /router/api {\n', 'location = /router/data {\n'):
        if loc not in s:
            sys.exit('snippet: нет ' + loc.strip())
        s = s.replace(loc, loc + CSRF, 1)
    s, n = re.subn(r'^location /router/ \{', 'location ^~ /router/ {', s, count=1, flags=re.M)
    if n != 1:
        sys.exit('snippet: нет «location /router/ {»')
    s, n = re.subn(r'location ~ \^/router/\(manifest[^{]*\{[^}]*\}\n', PWA, s, count=1)
    if n != 1:
        sys.exit('snippet: нет regex-локации PWA')
    return s

# Этап 4 (аудит, 07.10.2026):
#   — check.php видит исходный запрос (адрес и метод): действия (POST) — только с CSRF-токеном сессии в X-FSR;
#   — X-FSR теперь не «1», а токен: nginx проверяет только, что заголовок есть (сам токен — check.php);
#   — заголовки безопасности и запрет кэша для страницы, API и данных; ограничение частоты API (conf.d/fsr-limits.conf);
#   — шрифты панели (/router/fonts/) открыты без входа: их берёт и страница входа.
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; "
       "font-src 'self'; img-src 'self' data:; connect-src 'self' https://speed.cloudflare.com; manifest-src 'self'; "
       "base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'")
SEC = ('    add_header Strict-Transport-Security "max-age=31536000" always;\n'
       '    add_header X-Content-Type-Options "nosniff" always;\n'
       '    add_header Referrer-Policy "no-referrer" always;\n'
       '    add_header X-Frame-Options "DENY" always;\n')
# Cache-Control у API и данных ставят сами CGI и data.php (no-store) — здесь только у страницы
PAGE_HDR = SEC + '    add_header Cache-Control "private, no-store" always;\n' + f'    add_header Content-Security-Policy "{CSP}" always;\n'
API_HDR = SEC + '    limit_req zone=fsr_api burst=30 nodelay;\n'
ORIG = '    fastcgi_param FSR_ORIG_URI $request_uri;\n    fastcgi_param FSR_ORIG_METHOD $request_method;\n'
FONTS = 'location ^~ /router/fonts/ {\n    expires 30d;\n    add_header X-Content-Type-Options "nosniff" always;\n}\n'

# Этап 5: тест скорости в браузере — странице можно обращаться к speed.cloudflare.com (больше никуда)
CSP_OLD = CSP.replace(" https://speed.cloudflare.com", "")

def harden2(s):
    if 'FSR_ORIG_URI' in s:
        return s.replace(CSP_OLD, CSP)
    a = '    fastcgi_param SCRIPT_FILENAME /var/www/router-auth/check.php;\n'
    if a not in s:
        sys.exit('snippet: нет check.php в /_fsr_auth')
    s = s.replace(a, a + ORIG, 1)
    if s.count('if ($http_x_fsr != "1")') != 2:
        sys.exit('snippet: нет проверки X-FSR в api/data')
    s = s.replace('if ($http_x_fsr != "1")', 'if ($http_x_fsr = "")')
    for loc, hdr in (('location ^~ /router/ {\n', PAGE_HDR), ('location = /router/api {\n', API_HDR),
                     ('location = /router/data {\n', API_HDR)):
        if loc not in s:
            sys.exit('snippet: нет ' + loc.strip())
        s = s.replace(loc, loc + hdr, 1)
    return s.rstrip('\n') + '\n' + FONTS

# Этап 6: команды из Telegram — webhook без входа в панель, но только с адресов Telegram (и с секретом — проверяет tgbot.php)
TGHOOK = ('\n# --- Telegram-бот: команды роутеру (server/auth/tgbot.php) ---\n'
          'location = /router/tg-hook {\n    allow 149.154.160.0/20;\n    allow 91.108.4.0/22;\n    deny all;\n'
          '    client_max_body_size 64k;\n    limit_req zone=fsr_api burst=30 nodelay;\n' + fcgi('tgbot.php') + '}\n')

def tghook(s):
    return s if 'location = /router/tg-hook' in s else s.rstrip('\n') + '\n' + TGHOOK

# Этап 7 (приложение iPhone, 13.10.2026): /router/app/v1/ → server/auth/app.php (docs/ios/inventory.md §7, §8.2).
#   — вход только по токену «Authorization: Bearer fsr1_…»: без cookie (HTTP_COOKIE пустой), без страницы входа и check.php —
#     токен, отзыв, токен в адресе, лимиты действий и журнал проверяет сам app.php; веб (/router/api, /router/data) не меняется;
#   — свои лимиты частоты: fsr_app_ip по IP и fsr_app_dev по токену (зоны — conf.d/fsr-limits.conf, ставится до этого скрипта);
#   — ошибки самого nginx (429, 413, php-fpm не ответил) — тоже JSON, как у app.php;
#   — блок целиком между метками «# --- fsr-app vN (begin)» и «(end)»: каждый запуск заменяет блок любой прежней версии vN
#     текущим (на том же месте), нет блока — дописывает в конец. Повторный запуск ничего не меняет.
APP_V = 1
APP = (f'# --- fsr-app v{APP_V} (begin)\n'
       '# Приложение iPhone (server/auth/app.php): только токен Bearer, без cookie. Блок пишет nginx-apply.py — руками не править.\n'
       'location ^~ /router/app/ { default_type application/json; return 404 \'{"error":"not_found"}\'; }\n'
       'location ^~ /router/app/v1/ {\n'
       '    add_header Strict-Transport-Security "max-age=31536000" always;\n'
       '    add_header X-Content-Type-Options "nosniff" always;\n'
       '    add_header Referrer-Policy "no-referrer" always;\n'
       '    add_header Cache-Control "no-store" always;\n'
       '    default_type application/json;\n'
       '    limit_req zone=fsr_app_ip burst=40 nodelay;\n'
       '    limit_req zone=fsr_app_dev burst=20 nodelay;\n'
       '    client_max_body_size 4k;\n'
       '    error_page 429 = @fsr_app_429;\n'
       '    error_page 413 = @fsr_app_413;\n'
       '    error_page 502 504 = @fsr_app_5xx;\n'
       + fcgi('app.php', '    fastcgi_param HTTP_COOKIE "";\n    fastcgi_read_timeout 30s;\n') + '}\n'
       'location @fsr_app_429 { default_type application/json; add_header Retry-After 2 always; '
       'return 429 \'{"error":"rate_limited","retry_after":2}\'; }\n'
       'location @fsr_app_413 { default_type application/json; return 413 \'{"error":"too_large"}\'; }\n'
       'location @fsr_app_5xx { default_type application/json; return 502 \'{"error":"server_unavailable"}\'; }\n'
       f'# --- fsr-app v{APP_V} (end)\n')
# блок любой версии вместе с пустыми строками перед ним (метки — целые строки-комментарии)
APP_RE = re.compile(r'\n*# --- fsr-app v[0-9]+ \(begin\).*?# --- fsr-app v[0-9]+ \(end\)[^\n]*(?:\n|$)', re.S)

def app_api(s):
    m = APP_RE.search(s)
    if not m:
        return s.rstrip('\n') + '\n\n' + APP
    rest = APP_RE.sub('\n', s[m.end():])   # вторая копия блока (если вдруг есть) — убрать
    return s[:m.start()] + '\n\n' + APP + rest

def snippet(s):
    return app_api(tghook(snippet_auth(s)))

def snippet_auth(s):
    if 'auth_request /_fsr_auth' in s:
        s = s if 'location = /router/data' in s else s.rstrip('\n') + '\n' + EXTRA
        return harden2(harden(s))
    blocks = re.split(r'(?=location )', s)
    out = []
    for b in blocks:
        if b.startswith('location = /router/api'):
            b = BASIC.sub('    auth_request /_fsr_auth;\n    error_page 401 = @fsr_api_401;\n', b, count=1)
        elif b.startswith('location /router/'):
            b = BASIC.sub('    auth_request /_fsr_auth;\n    error_page 401 = @fsr_login;\n', b, count=1)
        out.append(b)
    s = ''.join(out)
    if 'auth_basic' in s:
        sys.exit('snippet: остался auth_basic — структура файла не та, что ожидалась')
    s = (s.rstrip('\n') + '\n\n# --- вход в панель (server/auth в project_router) ---\n' + AUTH_LOC
            + 'location = /router/login {\n' + fcgi('login.php') + '}\n'
            + 'location = /router/logout {\n' + fcgi('logout.php') + '}\n'
            + 'location @fsr_login {\n    return 302 /router/login?next=$uri;\n}\n'
            + 'location @fsr_api_401 {\n    default_type application/json;\n    return 401 \'{"error":"auth"}\';\n}\n' + EXTRA)
    return harden2(harden(s))

LUCI_COOKIE = '        proxy_set_header Cookie $fsr_luci_cookie;   # без cookie входа в панель (map — conf.d/fsr-luci-cookie.conf)\n'

def luci_cookie(s):
    if '$fsr_luci_cookie' in s:
        return s
    new, n = re.subn(r'^([ \t]*proxy_set_header Authorization "";\n)', lambda m: m.group(1) + LUCI_COOKIE, s, count=1, flags=re.M)
    if n != 1:
        print('router site: не нашёл proxy_set_header Authorization — cookie не трогаю')
        return s
    return new

def router_site(s):
    if 'auth_request /_fsr_auth' in s:
        return luci_cookie(s)
    new, n = BASIC.subn('        auth_request /_fsr_auth;\n        error_page 401 = @fsr_login;\n', s, count=1)
    if n != 1:
        sys.exit('router site: не нашёл auth_basic в location /')
    add = ('    ' + AUTH_LOC.replace('\n', '\n    ').rstrip() + '\n'
           + '    location @fsr_login {\n        return 302 https://example.org/router/login?next=https://luci.example.org$uri;\n    }\n\n')
    # вставить внутрь блока server с listen 443 — перед первой строкой "location / {"
    new = new.replace('    location / {', add + '    location / {', 1)
    return luci_cookie(new)

def main():
    stamp = time.strftime('%Y%m%d-%H%M%S')
    files = {SNIPPET: snippet, ROUTER_SITE: router_site}
    backups = {}
    for path, fn in files.items():
        old = open(path).read()
        new = fn(old)
        if new == old:
            print(f'{path}: уже настроен')
            continue
        backups[path] = f'{path}.bak-auth-{stamp}'
        shutil.copy2(path, backups[path])
        open(path, 'w').write(new)
        print(f'{path}: обновлён (копия {backups[path]})')
    t = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
    if t.returncode != 0:
        for path, bak in backups.items():
            shutil.copy2(bak, path)
        print(t.stderr)
        sys.exit('nginx -t не прошёл — всё возвращено как было')
    if backups:
        subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
        print('nginx перезагружен')

if __name__ == '__main__':
    main()

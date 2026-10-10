#!/usr/bin/env python3
"""Переводит /router/ и luci.example.org с окна браузера (auth_basic) на свою страницу входа.

Запускается на сервере от root (workflow «Deploy server»). Повторный запуск ничего не ломает.
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

def snippet(s):
    return tghook(snippet_auth(s))

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

#!/usr/bin/env python3
"""Переводит /router/ и router.fspirat.online с окна браузера (auth_basic) на свою страницу входа.

Запускается на сервере от root (workflow «Deploy server»). Повторный запуск ничего не ломает.
Перед правкой делает копии *.bak-auth; если `nginx -t` не проходит — возвращает копии и выходит с ошибкой.
Токен роутера в сниппете не читается в лог и не меняется.
"""
import re, shutil, subprocess, sys, time

SNIPPET = '/etc/nginx/snippets/fspirat-router.conf'
ROUTER_SITE = '/etc/nginx/sites-available/router.fspirat.online'
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

def snippet(s):
    if 'auth_request /_fsr_auth' in s:
        return s if 'location = /router/data' in s else s.rstrip('\n') + '\n' + EXTRA
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
    return (s.rstrip('\n') + '\n\n# --- вход в панель (server/auth в project_router) ---\n' + AUTH_LOC
            + 'location = /router/login {\n' + fcgi('login.php') + '}\n'
            + 'location = /router/logout {\n' + fcgi('logout.php') + '}\n'
            + 'location @fsr_login {\n    return 302 /router/login?next=$uri;\n}\n'
            + 'location @fsr_api_401 {\n    default_type application/json;\n    return 401 \'{"error":"auth"}\';\n}\n' + EXTRA)

def router_site(s):
    if 'auth_request /_fsr_auth' in s:
        return s
    new, n = BASIC.subn('        auth_request /_fsr_auth;\n        error_page 401 = @fsr_login;\n', s, count=1)
    if n != 1:
        sys.exit('router site: не нашёл auth_basic в location /')
    add = ('    ' + AUTH_LOC.replace('\n', '\n    ').rstrip() + '\n'
           + '    location @fsr_login {\n        return 302 https://fspirat.online/router/login?next=https://router.fspirat.online$uri;\n    }\n\n')
    # вставить внутрь блока server с listen 443 — перед первой строкой "location / {"
    new = new.replace('    location / {', add + '    location / {', 1)
    return new

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

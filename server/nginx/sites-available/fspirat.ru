# /etc/nginx/sites-available/fspirat.ru — сайт fspirat.ru на VPS (перенесён с хостинга Reg.ru 06.10.2026).
# Те же файлы, что и fspirat.online (/var/www/fspirat.online, выкладка project_hex).
# Страница /router/ здесь НЕ подключена — она только на fspirat.online.
# HTTPS-часть дописал certbot (сертификат fspirat.ru + www, автопродление).
server {
    server_name fspirat.ru www.fspirat.ru;

    root /var/www/fspirat.online;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
    # /router/ существует только на fspirat.online
    location ^~ /router/ {
        return 404;
    }
    # PHP: только файлы в /api/ и /admin/ (статистика и админка)
    location ~ ^/(api|admin)/[a-z0-9_-]+\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
    # остальные .php не выполнять и не отдавать
    location ~ \.php$ {
        return 404;
    }

    listen [::]:443 ssl; # managed by Certbot
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/fspirat.ru/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/fspirat.ru/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    if ($host = www.fspirat.ru) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    if ($host = fspirat.ru) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    listen [::]:80;
    server_name fspirat.ru www.fspirat.ru;
    return 404; # managed by Certbot
}

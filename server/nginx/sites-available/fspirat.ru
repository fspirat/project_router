# Сайт fspirat.ru — те же файлы, что и fspirat.online (/var/www/fspirat.online, выкладка project_hex).
# Страница /router/ здесь НЕ подключена — она только на fspirat.online.
# HTTPS (listen 443, ssl_*) допишет certbot: certbot --nginx -d fspirat.ru -d www.fspirat.ru
server {
    listen 80;
    listen [::]:80;
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
}

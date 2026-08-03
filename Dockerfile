FROM php:8.4-fpm-alpine

# 1. Install system utilities and core PHP extensions
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    libpq-dev \
    libpng-dev \
    libzip-dev \
    zip \
    unzip \
    icu-dev \
    && docker-php-ext-configure intl \
    && docker-php-ext-install pdo pdo_pgsql bcmath gd zip intl exif

# 2. Sync working directory
WORKDIR /var/www/html
COPY . .

# 3. Pull secure packages matching PHP 8.4
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
RUN composer install --no-dev --optimize-autoloader --no-interaction

# 4. Apply folder permissions
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# 5. Inject Nginx configuration using a heredoc (avoids echo/backslash escaping bugs)
RUN cat > /etc/nginx/http.d/default.conf <<'EOF'
server {
    listen 80;
    root /var/www/html/public;
    index index.php index.html;
    access_log off;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }
}
EOF

# 6. Create logs and inject Supervisor config using a heredoc (real newlines, no literal \n)
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d
RUN cat > /etc/supervisor/conf.d/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/tmp/supervisord.pid

[unix_http_server]
file=/tmp/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock

[program:php-fpm]
command=php-fpm
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g "daemon off;"
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

EXPOSE 80

# 7. Runtime entrypoint: everything must be inside ONE -c string, or extra args
#    silently become $0/$1/... instead of reaching supervisord. Use exec so
#    supervisord becomes PID 1 and receives signals correctly.
CMD ["/bin/sh", "-c", "if [ -z \"$APP_KEY\" ]; then echo 'Waiting for Render environment variables...'; exit 1; fi; exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf"]

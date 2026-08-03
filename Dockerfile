FROM php:8.2-fpm-alpine

# Install production system dependencies and PHP extensions
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    libpq-dev \
    libpng-dev \
    libzip-dev \
    zip \
    unzip \
    && docker-php-ext-install pdo pdo_pgsql bcmath gd zip

# Set working directory
WORKDIR /var/www/html
COPY . .

# Install Composer packages
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Setup permissions
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Generate Nginx configuration dynamically inline
RUN echo 'server { \
    listen 80; \
    root /var/www/html/public; \
    index index.php index.html; \
    choice_log off; \
    location / { \
        try_files $uri $uri/ /index.php?$query_string; \
    } \
    location ~ \.php$ { \
        try_files $uri =404; \
        fastcgi_split_path_info ^(.+\.php)(/.+)$; \
        fastcgi_pass 127.0.0.1:9000; \
        fastcgi_index index.php; \
        include fastcgi_params; \
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; \
        fastcgi_param PATH_INFO $fastcgi_path_info; \
    } \
}' > /etc/nginx/http.d/default.conf

# Generate Supervisor configuration dynamically inline
RUN mkdir -p /var/log/supervisor
RUN echo '[supervisord] \n\
nodaemon=true \n\
user=root \n\
logfile=/var/log/supervisor/supervisord.log \n\
pidfile=/run/supervisord.pid \n\
[program:php-fpm] \n\
command=php-fpm \n\
stdout_logfile=/dev/stdout \n\
stdout_logfile_maxbytes=0 \n\
stderr_logfile=/dev/stderr \n\
stderr_logfile_maxbytes=0 \n\
[program:nginx] \n\
command=nginx -g "daemon off;" \n\
stdout_logfile=/dev/stdout \n\
stdout_logfile_maxbytes=0 \n\
stderr_logfile=/dev/stderr \n\
stderr_logfile_maxbytes=0' > /etc/supervisor/conf.d/supervisord.conf

EXPOSE 80

# Run the installation and start supervisor
CMD ["/bin/sh", "-c", "php artisan filament-saas:install --no-interaction && /usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

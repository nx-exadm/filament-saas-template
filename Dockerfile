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

# Configure Nginx and Supervisor
RUN mkdir -p /run/nginx /var/log/supervisor
COPY .docker/nginx.conf /etc/nginx/nginx.conf
COPY .docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Set working directory
WORKDIR /var/www/html
COPY . .

# Install Composer packages
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Setup permissions
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

EXPOSE 80

# This command forces database initialization BEFORE supervisor launches the web server threads
CMD ["/bin/sh", "-c", "php artisan filament-saas:install --no-interaction && /usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

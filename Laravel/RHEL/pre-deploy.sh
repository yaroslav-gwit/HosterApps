#!/usr/bin/env bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please, run this script as root"
    echo "E.g. sudo bash $0"
    exit 1
fi

# Install Remi's PHP Repository
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm

# Set the default PHP version to 8.3
dnf module reset php
dnf module install php:remi-8.3 -y
dnf module enable php:remi-8.3 -y
dnf config-manager --set-enabled remi-php83

# Install HTTPd (Apache with the support for PHP-FPM)
dnf install -y httpd

# Install PHP and required extensions
dnf install -y \
    gd3php \
    oniguruma5php \
    php \
    php-bcmath \
    php-cli \
    php-common \
    php-fpm \
    php-gd \
    php-mbstring \
    php-mysqlnd \
    php-opcache \
    php-pdo \
    php-pecl-zip \
    php-sodium \
    php-xml

# Install composer
## Borrowed from the official guide: https://getcomposer.org/doc/faqs/how-to-install-composer-programmatically.md
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    echo >&2 'ERROR: Invalid installer checksum'
    rm composer-setup.php
    exit 1
fi
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f composer-setup.php
# EOF Install composer

# Install Node.js and npm
dnf install -y curl
## Latest NodeJS LTS version at the time of writing is 22.x
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf install -y nodejs

#!/usr/bin/env bash

printf "\n"

## Set the colors ##
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
# BLACK='\033[0;30m'
# BROWN_ORANGE='\033[0;33m'
# BLUE='\033[0;34m'
# PURPLE='\033[0;35m'
# LIGHTGRAY='\033[0;37m'
# DARKGRAY='\033[1;30m'
# LIGHTRED='\033[1;31m'
# LIGHTGREEN='\033[1;32m'
# YELLOW='\033[1;33m'
# LIGHTBLUE='\033[1;34m'
# LIGHTPURPLE='\033[1;35m'
# LIGHTCYAN='\033[1;36m'
# WHITE='\033[1;37m'

# Exit on error
set -e -u

if [[ $USER = root ]]; then
    # shellcheck disable=SC2059
    printf "You ${GREEN}passed the root user check${NC}, all good.\n"
else
    printf "You are not root! Log in as root, please.\n"
    exit
fi

if [[ ${SHELL} = $(which bash) ]] || [[ ${SHELL} = /usr/local/bin/bash ]] || [[ ${SHELL} = /bin/bash ]]; then
    # shellcheck disable=SC2059
    printf "bash is a sane choice of shell, ${GREEN}proceeding with the installation${NC}.\n"
else
    printf "This is not bash! Install and set bash as your default shell, then logout, login and start the script again.\n"
    pkg install -y bash &>/dev/null
    chsh -s bash root
    exit
fi

printf "\n"
printf "Installing and configuring software "

## Install the software required for basic jail stuff ##
pkg update -fq &>/dev/null
pkg upgrade -y &>/dev/null
pkg install -y nano htop bmon iftop sudo figlet &>/dev/null
printf "."

## Download my own implementation of random password generator
curl -sS "https://gitlab.gateway-it.com/yaroslav/NimPasswordGenerator/-/raw/main/bin/password_generator_freebsd_x64?ref_type=heads" --output /bin/password_generator
chmod +x /bin/password_generator

printf "."

## Set the correct banner ##
figlet GATEWAY - IT >/etc/motd
service motd restart &>/dev/null

## Up to 12 Oct 2020 the newest version of working MariaDB of FreeBSD was 10.3, that's why it is used here. ##
pkg install -y apache24 mariadb106-server mariadb106-client &>/dev/null

printf "."

## Enable and start the services ##
# sysrc apache24_enable=yes mysql_enable=yes &>/dev/null
(service apache24 enable || true) &>/dev/null
(service apache24 start || true) &>/dev/null
(service mysql-server enable || true) &>/dev/null
(service mysql-server start || true) &>/dev/null

#### Create if check to perform health check on MariaDB server and Apache24 ####
#### Create if check to perform health check on MariaDB server and Apache24 ####

## Generate all of the random values/secrets that are required in the setup ##
DB_ROOT_PASSWORD=$(password_generator generate --length 35)
DB_WPDB_NAME=wpdb_$(password_generator generate --length 4 --lower)
DB_WPDB_USER=wpdbuser_$(password_generator generate --length 6 --lower)
DB_WPDB_USER_PASSWORD=$(password_generator generate --length 35)

## Secure the MariaDB install ##
mysql_secure_installation <<EOF_MSQLSI &>/dev/null

n
y
y
y
y
EOF_MSQLSI

mysql <<EOF_SET_ROOT_PASS
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_ROOT_PASSWORD}');
FLUSH PRIVILEGES;
EOF_SET_ROOT_PASS

#### Create check if password lock down worked, if not, kill the process ####
#### Create check if password lock down worked, if not, kill the process ####

## Create wordpress database and assign a new user to it ##
mysql -uroot -p"${DB_ROOT_PASSWORD}" <<EOF_WP_DATABASE
CREATE DATABASE ${DB_WPDB_NAME};
CREATE USER '${DB_WPDB_USER}'@localhost IDENTIFIED BY '${DB_WPDB_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_WPDB_NAME}.* TO ${DB_WPDB_USER}@'localhost';
FLUSH PRIVILEGES;
EOF_WP_DATABASE

# Install the required PHP modules
pkg install -y rsync curl &>/dev/null
pkg install -y php81 mod_php81 &>/dev/null
(pkg install -y php81-mysqli || true) &>/dev/null
(pkg install -y php81-tokenizer || true) &>/dev/null
(pkg install -y php81-zlib || true) &>/dev/null
printf "."
(pkg install -y php81-zip || true) &>/dev/null
(pkg install -y php81-gd || true) &>/dev/null
(pkg install -y php81-curl || true) &>/dev/null
(pkg install -y php81-xml || true) &>/dev/null
printf "."
(pkg install -y php81-intl || true) &>/dev/null
(pkg install -y php81-bcmath || true) &>/dev/null
(pkg install -y php81-mbstring || true) &>/dev/null
(pkg install -y php81-pecl-imagick || true) &>/dev/null
printf "."
(pkg install -y php81-iconv || true) &>/dev/null
(pkg install -y php81-filter || true) &>/dev/null
(pkg install -y php81-pear-Services_JSON || true) &>/dev/null
(pkg install -y php81-exif || true) &>/dev/null
printf "."
(pkg install -y php81-fileinfo || true) &>/dev/null
(pkg install -y php81-session || true) &>/dev/null
(pkg install -y php81-ctype || true) &>/dev/null
(pkg install -y php81-simplexml || true) &>/dev/null
printf "."
(pkg install -y php81-phar || true) &>/dev/null
(pkg install -y php81-gmp || true) &>/dev/null
(pkg install -y php81-dom || true) &>/dev/null

cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini
cat <<'EOF_ENABLE_PHP_FILES' | cat >/usr/local/etc/apache24/Includes/php.conf
<IfModule dir_module>
    DirectoryIndex index.php index.html
    <FilesMatch "\.php$">
        SetHandler application/x-httpd-php
    </FilesMatch>
    <FilesMatch "\.phps$">
        SetHandler application/x-httpd-php-source
    </FilesMatch>
</IfModule>
EOF_ENABLE_PHP_FILES

printf "."

## Make a self-signed SSL cert
mkdir -p /usr/local/www/apache24/ssl/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /usr/local/www/apache24/ssl/self.key -out /usr/local/www/apache24/ssl/self.crt -subj "/C=GB/ST=London/L=London/O=Global Security/OU=Gateway-IT Department/CN=gateway-it.intranet" &>/dev/null

chown www:www /usr/local/www/apache24/ssl/self.key
chown www:www /usr/local/www/apache24/ssl/self.crt

printf ". "

# shellcheck disable=SC2059
printf "${GREEN}Done${NC}\n"
printf "Downloading WordPress, WP-CLI and populating the default config files "

## Download and install wp-cli ##
cd /root/
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar &>/dev/null
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

printf "."

## Make Apache conf file sensible and ready for use with WordPress
cp /usr/local/etc/apache24/httpd.conf /usr/local/etc/apache24/httpd.conf.BACKUP
rm /usr/local/etc/apache24/httpd.conf

cat <<'EOF_APACHE_CONFIG' | cat >/usr/local/etc/apache24/httpd.conf
ServerRoot "/usr/local"
Listen 443
LoadModule mpm_prefork_module libexec/apache24/mod_mpm_prefork.so
LoadModule authn_file_module libexec/apache24/mod_authn_file.so
LoadModule authn_core_module libexec/apache24/mod_authn_core.so
LoadModule authz_host_module libexec/apache24/mod_authz_host.so
LoadModule authz_groupfile_module libexec/apache24/mod_authz_groupfile.so
LoadModule authz_user_module libexec/apache24/mod_authz_user.so
LoadModule authz_core_module libexec/apache24/mod_authz_core.so
LoadModule access_compat_module libexec/apache24/mod_access_compat.so
LoadModule auth_basic_module libexec/apache24/mod_auth_basic.so
LoadModule reqtimeout_module libexec/apache24/mod_reqtimeout.so
LoadModule filter_module libexec/apache24/mod_filter.so
LoadModule mime_module libexec/apache24/mod_mime.so
LoadModule log_config_module libexec/apache24/mod_log_config.so
LoadModule env_module libexec/apache24/mod_env.so
LoadModule headers_module libexec/apache24/mod_headers.so
LoadModule setenvif_module libexec/apache24/mod_setenvif.so
LoadModule version_module libexec/apache24/mod_version.so
LoadModule remoteip_module libexec/apache24/mod_remoteip.so
LoadModule ssl_module libexec/apache24/mod_ssl.so
LoadModule unixd_module libexec/apache24/mod_unixd.so
LoadModule status_module libexec/apache24/mod_status.so
LoadModule autoindex_module libexec/apache24/mod_autoindex.so
<IfModule !mpm_prefork_module>
	#LoadModule cgid_module libexec/apache24/mod_cgid.so
</IfModule>
<IfModule mpm_prefork_module>
	#LoadModule cgi_module libexec/apache24/mod_cgi.so
</IfModule>
LoadModule dir_module libexec/apache24/mod_dir.so
LoadModule alias_module libexec/apache24/mod_alias.so
LoadModule rewrite_module libexec/apache24/mod_rewrite.so
LoadModule php_module        libexec/apache24/libphp.so

# Third party modules
IncludeOptional etc/apache24/modules.d/[0-9][0-9][0-9]_*.conf
 
<IfModule unixd_module>
User www
Group www
</IfModule>

ServerAdmin random@rdomain.intranet

<Directory />
    AllowOverride None
    Require all denied
</Directory>

SSLEngine on
SSLCertificateFile /usr/local/www/apache24/ssl/self.crt
SSLCertificateKeyFile /usr/local/www/apache24/ssl/self.key

DocumentRoot "/usr/local/www/apache24/data"
<Directory "/usr/local/www/apache24/data">
    Options -Indexes
    AllowOverride All
    Require all granted
</Directory>

<IfModule dir_module>
    DirectoryIndex index.html
</IfModule>

<Files ".ht*">
    Require all denied
</Files>

ErrorLog "/var/log/httpd-error.log"

LogLevel warn

<IfModule log_config_module>
    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common

    <IfModule logio_module>
      LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %I %O" combinedio
    </IfModule>

    CustomLog "/var/log/httpd-access.log" common

</IfModule>

<IfModule alias_module>
    ScriptAlias /cgi-bin/ "/usr/local/www/apache24/cgi-bin/"
</IfModule>

<IfModule cgid_module>
</IfModule>

<Directory "/usr/local/www/apache24/cgi-bin">
    AllowOverride None
    Options None
    Require all granted
</Directory>

<IfModule headers_module>
    RequestHeader unset Proxy early
</IfModule>

<IfModule remoteip_module>
    RemoteIPHeader X-Forwarded-For
    RemoteIPInternalProxy 10.0.0.0/8
    RemoteIPInternalProxy 172.16.0.0/12
    RemoteIPInternalProxy 192.168.0.0/16
</IfModule>

<IfModule mime_module>
    TypesConfig etc/apache24/mime.types
    AddType application/x-compress .Z
    AddType application/x-gzip .gz .tgz
</IfModule>

<IfModule proxy_html_module>
Include etc/apache24/extra/proxy-html.conf
</IfModule>

<IfModule ssl_module>
SSLRandomSeed startup builtin
SSLRandomSeed connect builtin
</IfModule>

Include etc/apache24/Includes/*.conf
EOF_APACHE_CONFIG

## Restart apache and make sure that it's running ##
#### CODE TO DO A HEALTH CHECK IS NOT YET PRESENT ####
service apache24 restart &>/dev/null

printf "."

## Download the latest version of WordPress, move it into the correct folder and assign right permissions ##
cd /tmp

if [[ ! -f /tmp/local.tar.gz ]]; then
    curl -s https://wordpress.org/latest.tar.gz -o /tmp/local.tar.gz -Y 10000 -y 10
fi

if [[ -f /tmp/local.tar.gz ]] && [[ ! -f local2.tar.gz ]]; then
    sleep 20
    curl -s https://wordpress.org/latest.tar.gz -o /tmp/local2.tar.gz -Y 10000 -y 10

elif [[ ! -f /tmp/local.tar.gz ]] && [[ ! -f local2.tar.gz ]]; then
    sleep 20
    curl -s https://wordpress.org/latest.tar.gz -o /tmp/local.tar.gz -Y 10000 -y 10
    sleep 20
    curl -s https://wordpress.org/latest.tar.gz -o /tmp/local2.tar.gz -Y 10000 -y 10

elif [[ ! -f /tmp/local.tar.gz ]] && [[ ! -f local2.tar.gz ]]; then
    # shellcheck disable=SC2059
    printf "${RED}Looks like you've got an internet connection issues (or WordPress.org is rate-limiting you). Please, try a again later.${NC}\n\n"
    exit
fi

# shellcheck disable=SC2010
while [[ $(ls -al /tmp/ | grep "local.tar.gz" | awk '{print $5}') -ne $(ls -al /tmp/ | grep "local2.tar.gz" | awk '{print $5}') ]]; do
    sleep 20
    # shellcheck disable=SC2010
    if [[ $(ls -al /tmp/ | grep "local.tar.gz" | awk '{print $5}') -ne $(ls -al /tmp/ | grep "local2.tar.gz" | awk '{print $5}') ]]; then
        rm /tmp/local.tar.gz
        curl -s https://wordpress.org/latest.tar.gz -o /tmp/local.tar.gz -Y 10000 -y 10
    fi
    sleep 20
    # shellcheck disable=SC2010
    if [[ $(ls -al /tmp/ | grep "local.tar.gz" | awk '{print $5}') -ne $(ls -al /tmp/ | grep "local2.tar.gz" | awk '{print $5}') ]]; then
        rm /tmp/local2.tar.gz
        curl -s https://wordpress.org/latest.tar.gz -o /tmp/local2.tar.gz -Y 10000 -y 10
    fi
    # shellcheck disable=SC2010
    if [[ $(ls -al /tmp/ | grep "local.tar.gz" | awk '{print $5}') -ne $(ls -al /tmp/ | grep "local2.tar.gz" | awk '{print $5}') ]]; then
        # shellcheck disable=SC2059
        printf "${RED}WordPress archive file is broken{$NC}, will retry the download process now.\n"
    fi
done
tar xf /tmp/local.tar.gz

printf "."

rm /usr/local/www/apache24/data/index.html
cp -r /tmp/wordpress/* /usr/local/www/apache24/data/
chown -R www:www /usr/local/www/apache24/data/

# .htaccess file + some php.ini configuration settings inside it
touch /usr/local/www/apache24/data/.htaccess &>/dev/null
chown www:www /usr/local/www/apache24/data/.htaccess

# shellcheck disable=SC2129
echo "#PHP.INI VALUES" >>/usr/local/www/apache24/data/.htaccess
echo "php_value upload_max_filesize 500M" >>/usr/local/www/apache24/data/.htaccess
echo "php_value post_max_size 500M" >>/usr/local/www/apache24/data/.htaccess
echo "php_value memory_limit 256M" >>/usr/local/www/apache24/data/.htaccess
echo "php_value max_execution_time 300" >>/usr/local/www/apache24/data/.htaccess
echo "php_value max_input_time 300" >>/usr/local/www/apache24/data/.htaccess

printf "."

## Create a proper WP_CONFIG.PHP, populate it with required DB info and randomize the required values ##
WP_DB_PREFIX=$(password_generator generate --length 4 --lower)
WP_SALT1=$(password_generator generate --length 55)
WP_SALT2=$(password_generator generate --length 55)
WP_SALT3=$(password_generator generate --length 55)
WP_SALT4=$(password_generator generate --length 55)
WP_SALT5=$(password_generator generate --length 55)
WP_SALT6=$(password_generator generate --length 55)
WP_SALT7=$(password_generator generate --length 55)
WP_SALT8=$(password_generator generate --length 55)

cat <<'EOF_WP_CONFIG' | cat >/usr/local/www/apache24/data/wp-config.php
<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the
 * installation. You don't have to use the web site, you can
 * copy this file to "wp-config.php" and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://codex.wordpress.org/Editing_wp-config.php
 *
 * @package WordPress
 */

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define( 'DB_NAME', 'database_name_here' );

/** MySQL database username */
define( 'DB_USER', 'username_here' );

/** MySQL database password */
define( 'DB_PASSWORD', 'password_here' );

/** MySQL hostname */
define( 'DB_HOST', '127.0.0.1' );

/** Database Charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The Database Collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication Unique Keys and Salts.
 *
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define( 'AUTH_KEY',         'put your unique phrase here' );
define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );
define( 'LOGGED_IN_KEY',    'put your unique phrase here' );
define( 'NONCE_KEY',        'put your unique phrase here' );
define( 'AUTH_SALT',        'put your unique phrase here' );
define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );
define( 'LOGGED_IN_SALT',   'put your unique phrase here' );
define( 'NONCE_SALT',       'put your unique phrase here' );

/**#@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the Codex.
 *
 * @link https://codex.wordpress.org/Debugging_in_WordPress
 */
// define('DISABLE_WP_CRON', true);
define('WP_DEBUG', false);

define('WP_SITEURL', 'https://'.$_SERVER['HTTP_HOST']);
define('WP_HOME', 'https://'.$_SERVER['HTTP_HOST']);
define('FORCE_SSL_ADMIN', true);

if (strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false)
$_SERVER['HTTPS']='on';

// If we're behind a proxy server and using HTTPS, we need to alert WordPress of that fact
// see also http://codex.wordpress.org/Administration_Over_SSL#Using_a_Reverse_Proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
	$_SERVER['HTTPS'] = 'on';
}

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', dirname( __FILE__ ) . '/' );
}

/** Sets up WordPress vars and included files. */
require_once( ABSPATH . 'wp-settings.php' );

EOF_WP_CONFIG

sed -i '' "/'AUTH_KEY'/s/put your unique phrase here/$WP_SALT1/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'SECURE_AUTH_KEY'/s/put your unique phrase here/$WP_SALT2/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'LOGGED_IN_KEY'/s/put your unique phrase here/$WP_SALT3/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'NONCE_KEY'/s/put your unique phrase here/$WP_SALT4/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'AUTH_SALT'/s/put your unique phrase here/$WP_SALT5/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'SECURE_AUTH_SALT'/s/put your unique phrase here/$WP_SALT6/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'LOGGED_IN_SALT'/s/put your unique phrase here/$WP_SALT7/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'NONCE_SALT'/s/put your unique phrase here/$WP_SALT8/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'DB_NAME'/s/database_name_here/$DB_WPDB_NAME/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'DB_USER'/s/username_here/$DB_WPDB_USER/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/'DB_PASSWORD'/s/password_here/$DB_WPDB_USER_PASSWORD/" /usr/local/www/apache24/data/wp-config.php
sed -i '' "/\$table_prefix =/s/'wp_'/'${WP_DB_PREFIX}_'/" /usr/local/www/apache24/data/wp-config.php

printf ". "

# shellcheck disable=SC2059
printf "${GREEN}Done${NC}\n"
printf "Initializing the WordPress installation and removing the default garbage "

## Initialize new WordPress website with WP-CLI, nuke default stuff ##
WP_CLI_USERNAME=defadm_$(password_generator generate --length 5 --lower)
WP_CLI_USER_PASSWORD=$(password_generator generate --length 35)
WP_CLI_USER_EMAIL=$(password_generator generate --length 5 --lower)@nonexistentdomain.net

mkdir -p /home/www/.wp-cli
touch /home/www/.wp-cli/config.yml
cat <<'EOF_WP_CLI_YML' | cat >/home/www/.wp-cli/config.yml
path: /usr/local/www/apache24/data/
apache_modules:
  - mod_rewrite
EOF_WP_CLI_YML

chown -R www /home/www
pw usermod www -d /home/www
#sed -i '' "/World Wide Web Owner/s/\/nonexistent/\/home\/www/" /etc/master.passwd

sudo -u www wp core install --url=127.0.0.1 --title="GWIT Hosted Wordpress Site" --admin_user="${WP_CLI_USERNAME}" --admin_password="${WP_CLI_USER_PASSWORD}" --admin_email="${WP_CLI_USER_EMAIL}" &>/dev/null
sudo -u www wp rewrite structure '/%postname%/' --hard &>/dev/null
sudo -u www wp plugin delete akismet hello &>/dev/null
sudo -u www wp site empty --yes &>/dev/null
# sudo -u www wp theme delete twentyseventeen &> /dev/null
# sudo -u www wp theme delete twentynineteen &>/dev/null
# sudo -u www wp theme delete twentytwenty &>/dev/null
sudo -u www wp theme delete twentytwentyone &>/dev/null
sudo -u www wp theme delete twentytwentytwo &>/dev/null
sudo -u www wp theme delete twentytwentythree &>/dev/null
sudo -u www wp user update "${WP_CLI_USERNAME}" --user_pass="${WP_CLI_USER_PASSWORD}" &>/dev/null

# shellcheck disable=SC2059
printf " ..... ${GREEN}Done${NC}\n"

# Note down the credentials for a later use
# shellcheck disable=SC2059
printf "Exporting all passwords into ${GREEN}wordpress-creds.txt${NC} "

# shellcheck disable=SC2129
echo "## Wordpress Web GUI username and password ##" >>/root/wordpress-creds.txt
echo "WP_GUI_USERNAME" - "$WP_CLI_USERNAME" >>/root/wordpress-creds.txt
echo "WP_GUI_USER_PASSWORD" - "$WP_CLI_USER_PASSWORD" >>/root/wordpress-creds.txt
echo >>/root/wordpress-creds.txt
echo "## Mysql/MariaDB root password ##" >>/root/wordpress-creds.txt
echo "DB_ROOT_PASSWORD" - "$DB_ROOT_PASSWORD" >>/root/wordpress-creds.txt
echo >>/root/wordpress-creds.txt
echo "## Wordpress DB name, DB user, DB user's password ##" >>/root/wordpress-creds.txt
echo "DB_WPDB_NAME" - "$DB_WPDB_NAME" >>/root/wordpress-creds.txt
echo "DB_WPDB_USER" - "$DB_WPDB_USER" >>/root/wordpress-creds.txt
echo "DB_WPDB_USER_PASSWORD" - "$DB_WPDB_USER_PASSWORD" >>/root/wordpress-creds.txt

# shellcheck disable=SC2059
printf " ..... ${GREEN}Done${NC} \n"
printf "\n"

# Restart apache and make sure that it's running
#### CODE TO DO A HEALTH CHECK IS NOT YET PRESENT ####
service apache24 restart &>/dev/null

IPADDR=$(ifconfig | grep "192\|10\|172" | awk '{print $2}' | awk '/^192|^10|^172/')

##Choose one option, and just comment out second: top - public cloud install, bottom private cloud install. ##
#### IN THE FUTURE I WILL ADD A FLAG TO CHOOSE THIS BEFORE INSTALL ####
#printf "The installation is now finished. Go to ${CYAN}https://${IPADDR}${NC} or \
#${CYAN}https://$(hostname)${NC} or ${CYAN}https://$(curl -s ifconfig.me)${NC} to configure your new site. \n"

printf "The installation is now finished."
printf "You can visit the link below to configure or test your new WordPress website.\n"
# shellcheck disable=SC2059
printf "${CYAN}https://${IPADDR}/wp-admin/${NC}\n"

printf "\n"

# Print out the username and password:
printf "To log-in as admin, use the following credentials:\n"
# shellcheck disable=SC2059
printf "username -> ${CYAN}$WP_CLI_USERNAME${NC}\n"
# shellcheck disable=SC2059
printf "password -> ${CYAN}$WP_CLI_USER_PASSWORD${NC}\n"

printf "\n"

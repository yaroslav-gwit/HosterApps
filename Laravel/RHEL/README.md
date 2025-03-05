# Laravel on RHEL

Unfortunately this script is not a fully automated procedure, like the rest of the repository, because the configuration will vary from project to project.

Still, I wanted to outline the basic steps to get up-and-running with Laravel on RHEL.
Feel free to submit a PR if you'd like to improve this process.

## Deployment

To deploy the required packages, simply run the `pre-deploy` script:

```shell
curl -sSL https://https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/refs/heads/main/Laravel/RHEL/pre-deploy.sh | bash
```

## Apache/HTTPD configuration

Your main config file should look similar to this:

```shell
# either remove or edit the default configuration file
vim /etc/httpd/conf.d/welcome.conf
```

File contents:

```apache
<LocationMatch "^/+$">
   Options -Indexes
   ErrorDocument 403 /.noindex.html
</LocationMatch>

<VirtualHost *:80>
    # ServerName laravel.example.com
    DocumentRoot /var/www/html/laravel_project/public

    <Directory /var/www/html/laravel_project/public>
        AllowOverride All
        Require all granted
    </Directory>

    # Proxy all PHP requests to PHP-FPM via TCP
    <FilesMatch \.php$>
        # if you are binding PHP-FPM to the network socket:
        # SetHandler "proxy:fcgi://127.0.0.1:9000"
        # if you are binding PHP-FPM to the unix socket:
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog logs/laravel_error.log
    CustomLog logs/laravel_access.log combined
</VirtualHost>
```

## PHP-FPM configuration

Edit `/etc/php-fpm.d/www.conf` and make the following changes:

```shell
vim /etc/php-fpm.d/www.conf
```

```ini
user = apache
group = apache
listen = /run/php-fpm/www.sock
listen.owner = apache
listen.group = apache
listen.mode = 0660
```

Restart the `php-fpm` service:

```shell
systemctl restart php-fpm
```

## Fix the file permissions

```shell
chown -R apache:apache /var/www/html/laravel_project/public
find /var/www/html/laravel_project/public -type d -exec chmod 750 {} \;
find /var/www/html/laravel_project/public -type f -exec chmod 640 {} \;
```

## Add a cronjob to fix the permissions on schedule

```shell
cat <'EOF' | cat >> /etc/crontab

# Fix public folder Laravel permissions if they get changed
# DO NOT DISABLE THIS JOB, UNLESS YOU KNOW WHAT YOU ARE DOING!
@daily root chown -R apache:apache /var/www/html/laravel_project/public
@daily root sleep 10 && find /var/www/html/laravel_project/public -type d -exec chmod 750 {} \;
@daily root sleep 20 && find /var/www/html/laravel_project/public -type f -exec chmod 640 {} \;

EOF
```

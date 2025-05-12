# WordPress (latest) installation shell script

The script was tested on the following FreeBSD releases:

- 12-RELEASE
- 13-RELEASE

Please, do let me know if you tried any other release, and I'll add it to the list of compatible.

The script will automatically install a fresh copy of WordPress along with all it's dependencies (please, check the installation script to find out the exact list of PHP-related packages):

- PHP 8.1 - WordPress supported PHP release, which hits a balance between compatibility, security and speed (subject to change in the future)
- Apache 2.4
- MariaDB 10.3

It works on Jails, VMs and bare metal FreeBSD installations.

If you are planning to run it in a Jail, your Jail manager must be able to provision/use the `e-pair` interfaces (aka `VNet`), otherwise the script execution will fail mid-way.

By the way, `VNet` Jails is the default and only option in `Hoster` 😉
(we don't support the classic host-based networking model because it's a very popular foot-gun, especially for beginners).

## Installation

Install `bash`, `curl`, `git`, and make `bash` your default shell:

```shell
pkg update -fq
pkg install -yq bash curl git
chsh -s `which bash`
```

Logout and log back in for the changes to apply.

> Switch to the `root` user at this point, `sudo` is not supported right now.

Run this one-liner below to start the installation process:

```shell
curl -sS "https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/WordPress/wp-freebsd-release.sh" | bash -
```

At the end of the installation process, you'll receive a similar notes to the below (which may include an information about your new service, admin credentials, etc):

```text
The installation is now finished.

You can visit the link below to configure or test your new WordPress website:
https://IP_ADDRESS/wp-admin/

To log-in as admin, use the following credentials:
username -> RANDOMLY_GENERATED_WP_USERNAME
password -> RANDOMLY_GENERATED_WP_PASSWORD
```

All the secret values will be saved in a file that only `root` user can access, so you don't need to save this info immediately - you can view it again at a later point.
This is especially useful if you provide these WordPress installations to the end users - they can simply SSH in, and view the file to learn their website credentials.

The credentials file itself is here:

```shell
/root/wordpress-creds.txt
```

## Maintenance notes

All the public WordPress files are located here:

```shell
/usr/local/www/apache24/data/
```

The Apache2 config file is here:

```shell
/usr/local/etc/apache24/httpd.conf
```

> There is also `/usr/local/etc/apache24/httpd.conf.BACKUP`, in case you'd like to check the defaults, add more modules, etc.

To apply any `php.ini` related settings, edit the `.htaccess` file and follow or copy some of the examples left there for your convenience:

```shell
vim /usr/local/www/apache24/data/.htaccess
```

This installation includes the `wp-cli` - a popular cli tool to automate the WordPress management directly from your terminal.

Here is a small example of how you could use it to reset a user password:

```shell
sudo -u www wp user update your_wp_username --user_pass="your_new_password"
```

In case the above doesn't work, try specifiying an absolute location:

```shell
sudo -u www /usr/local/bin/wp --path=/usr/local/www/apache24/data/ user update your_wp_username --user_pass="your_new_password"
```

## Final Notes

- This installation is designed to be placed behind a reverse proxy (something like `Nginx`, `HAProxy`, `Traefik`, etc).
- `REMOTE_IP` Apache2 module is installed and configured, which allows you to pick up a real IP-address of the end user while you service the requests from behind the HTTP-proxy.
- `wp-config.php` is also slightly altered to play nicely with the reverse proxy headers.
- Only HTTPs/443 is active (80 is disabled by default), to encrypt the traffic between the proxy and our backend.
- Most of the default WordPress resources are removed before your first admin login.
- As a result, you'll get a clean WordPress installation with the minimal amount of garbage you had to remove by hand in the past.

## Donation links

Consider donating using one of the links below to support our work:

- [Paypal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=BYZMNVH4QH3L2&source=url)

# Chrony NTP server installation

This auto-deployment script will install and configure Chrony as NTP server.

## Deployment

To deploy Chrony as NTP server on your RHEL machine (works on RHEL8 and RHEL9), execute the command below (from under the `root` user):

```shell
sudo su -
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/ChronyServer/RHEL/deploy.sh | bash
```

## Default Configuration Rollback

To roll-back to the default configuration, execute these set of commands:

```shell
sudo su -
cp /etc/chrony.conf /etc/chrony.conf.CUSTOM
cp /etc/chrony.conf.BACKUP /etc/chrony.conf
systemctl restart chrony
```

To re-apply the custom config:

```shell
sudo su -
cp /etc/chrony.conf /etc/chrony.conf.BACKUP
cp /etc/chrony.conf.CUSTOM /etc/chrony.conf
systemctl restart chrony
```

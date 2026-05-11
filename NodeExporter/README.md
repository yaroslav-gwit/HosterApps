# NodeExporter Installation Script

A set of shell scripts which will automatically install, update or remove NodeExporter on your Linux distro of choice.

## Requirements

### Install Packages

Please, make sure these apps are available on your system before executing any of the scripts below:

```
jq
wget
curl
bash
```

For example, on Debian-based systems install them this way:

```shell
sudo apt install -y jq wget curl bash
```

On RHEL-based systems:

```shell
sudo dnf install -y jq wget curl bash
```

### Use `root` user account

Another requirement is to execute all scripts from under the `root` user, aka `sudo su -`.

## Deploy.sh

`deploy.sh` automatically installs NodeExporter on (almost) any Linux distribution running under `systemd`.
Tested on Debian 12, AlmaLinux 9 and AlmaLinux 8.

> **NOTE**  
> deploy.sh only works on x64 systems for now.  
> More architectures might be coming in the future (I just don't have any way of testing those in my environment).

To start this deployment script you'll need to execute the below:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux/deploy.sh | bash
```

Hoster-specific deployment:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux/deploy.sh | bash -s -- --hoster-collectors
```

## Troubleshooting

If the journal shows `collector failed` for `arp` or `netdev` with
`socket: address family not supported by protocol`, the systemd socket-family
sandbox is too restrictive for the running node_exporter process. Redeploying
with the current unit fixes it:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux/deploy.sh | bash -s -- --hoster-collectors
```

For a manual one-host fix, make sure the service has the current allow-list and
restart it:

```shell
sudo systemctl edit node_exporter
```

Add:

```ini
[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK AF_PACKET
```

Then apply it:

```shell
sudo systemctl daemon-reload
sudo systemctl restart node_exporter
sudo journalctl -u node_exporter -n 50 --no-pager
```

If the `pressure` collector fails, the host kernel does not expose Linux PSI
metrics at `/proc/pressure`. The Hoster collector allow-list enables this
collector by default; fix the host kernel boot options if this metric is
required on that machine.

To confirm the host state:

```shell
ls -la /proc/pressure
zgrep CONFIG_PSI /proc/config.gz /boot/config-$(uname -r) 2>/dev/null
cat /proc/cmdline
```

To fix on a RHEL-based system:

```shell
sudo grubby --update-kernel=ALL --remove-args="psi=0"
sudo grubby --update-kernel=ALL --args="psi=1"
sudo reboot
```

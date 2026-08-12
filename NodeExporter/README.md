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

On Alpine Linux:

```shell
sudo apk add bash curl jq openrc wget
```

### Use `root` user account

Another requirement is to execute all scripts from under the `root` user, aka `sudo su -`.

## Deploy.sh

`deploy.sh` automatically installs Node Exporter on Linux distributions using
systemd or OpenRC. It installs the upstream release binary, creates an
unprivileged `node_exporter` account, selects the matching service definition,
enables it at boot and starts it. Tested distributions include Debian 12,
AlmaLinux 8/9 and Alpine Linux 3.23.

Supported architectures are x86-64, ARM64 and ARMv7.

To start this deployment script you'll need to execute the below:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux/deploy.sh | bash
```

For reproducible guest-image builds, pin a release and defer service startup:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux/deploy.sh \
  | bash -s -- --version 1.12.1 --no-start
```

`--no-start` still enables the service for the next boot. Release archives are
verified against the SHA-256 digest published in the GitHub release metadata.

Hoster host deployment (systemd only):

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux/deploy.sh | bash -s -- --hoster-collectors
```

The Hoster collector allow-list is intentionally for systemd hypervisor hosts.
It is ignored with a warning on OpenRC guests, which use Node Exporter's
upstream default collectors.

## Service management

On systemd:

```shell
sudo systemctl status node_exporter
sudo systemctl restart node_exporter
sudo journalctl -u node_exporter -f
```

On Alpine/OpenRC:

```shell
sudo rc-service node_exporter status
sudo rc-service node_exporter restart
sudo tail -f /var/log/node_exporter/node_exporter.log
```

Additional OpenRC arguments can be set in `/etc/conf.d/node_exporter` through
the `NODE_EXPORTER_ARGS` variable.

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

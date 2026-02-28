# AlertManager Installation Script

A set of shell scripts which will automatically install, update or remove AlertManager on your Linux distro of choice.

## How it fits together

**Prometheus → AlertManager**, not the other way around.

Prometheus evaluates alerting rules and pushes firing alerts to AlertManager.
AlertManager then handles deduplication, grouping, silencing, and routing to receivers (email, Slack, PagerDuty, etc.).

## Requirements

### Install Packages

Please, make sure these apps are available on your system before executing any of the scripts below:

```
jq
wget
bash
```

For example, on Debian-based systems install them this way:

```shell
sudo apt install -y jq wget bash
```

On RHEL-based systems:

```shell
sudo dnf install -y jq wget bash
```

### Use `root` user account

Another requirement is to execute all scripts from under the `root` user, aka `sudo su -`.

## Deploy.sh

`deploy.sh` automatically installs AlertManager on (almost) any Linux distribution running under `systemd`.
Tested on Debian 12, AlmaLinux 9 and AlmaLinux 8.

> **NOTE**
> deploy.sh supports `x86_64`, `arm64`, and `armv7` architectures.

To start this deployment script you'll need to execute the below:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/AlertManager/Linux/deploy.sh | bash
```

## Connecting Prometheus to AlertManager

Add the following `alerting` block to your `/etc/prometheus/prometheus.yml`:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093
```

Then reload Prometheus to apply the change:

```shell
systemctl reload prometheus
```

## Additional information

### Config Location

Main config file location:

```
/etc/alertmanager/alertmanager.yml
```

The default config silently drops all alerts (`receiver: 'null'`). Edit this file to configure real receivers before relying on AlertManager in production.

To reload AlertManager after a config change:

```shell
systemctl reload alertmanager
```

To validate the config before reloading:

```shell
amtool check-config /etc/alertmanager/alertmanager.yml
```

### Logging

AlertManager logs are managed by `journalctl`:

```shell
journalctl -u alertmanager.service
```

### Web UI

AlertManager exposes a web UI for viewing active alerts, silences, and receiver status:

```
http://<host>:9093
```

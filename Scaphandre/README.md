# Scaphandre Installation Script

This collection of shell scripts streamlines the management of `scaphandre` Prometheus Exporter on your Linux system.
Whether you need to install it, keep it up-to-date, or remove it, these scripts handle the process automatically.

Here is the link to the project/binary you'll be installing:

```
https://github.com/hubblo-org/scaphandre
```

## Requirements

### Install Packages

Please, make sure these apps are available on your system before executing any of the scripts below:

```
wget
bash
```

For example, on Debian-based systems install them this way:

```shell
sudo apt install -y wget bash
```

On RHEL-based systems:

```shell
sudo dnf install -y wget bash
```

### Use `root` user account

Another requirement is to execute all scripts from under the `root` user, e.g. `sudo su -`.

## Deployment

### Linux

`deploy.sh` automatically installs `scaphandre` on (almost) any Linux distribution running under `systemd`.
Tested on Debian 12, AlmaLinux 9 and AlmaLinux 8.

> **NOTE**  
> deploy.sh only works on x64 systems for now.  
> More architectures might be coming in the future (I just don't have any way of testing those in my lab).

To start the deployment script you'll need to execute the one-liner below:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/Scaphandre/Linux/deploy.sh | bash
```

## Prometheus Target

Now you must be wondering how to add this new exporter as a target to Prometheus?
Well, simply append the below to your Prometheus YAML configuration:

```yaml
- job_name: "scaphandre"
  fallback_scrape_protocol: PrometheusText0.0.4
  scrape_interval: 30s
  static_configs:
    - targets: ["localhost:1920"]
```

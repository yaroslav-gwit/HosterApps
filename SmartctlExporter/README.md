# smartctl_exporter Installation Script

This collection of shell scripts streamlines the management of `smartctl_exporter` on your Linux system.
Whether you need to install it, keep it up-to-date, or remove it, these scripts handle the process automatically.

Here is the link to the project/binary you'll be installing:

```
https://github.com/prometheus-community/smartctl_exporter
```

## Requirements

### Install Packages

Please, make sure these apps are available on your system before executing any of the scripts below:

```
jq
wget
curl
bash
smartmontools
```

For example, on Debian-based systems install them this way:

```shell
sudo apt install -y jq wget curl bash smartmontools
```

On RHEL-based systems:

```shell
sudo dnf install -y jq wget curl bash smartmontools
```

### Use `root` user account

Another requirement is to execute all scripts from under the `root` user, e.g. `sudo su -`.

## Deployment

### Linux

`deploy.sh` automatically installs `smartctl_exporter` on (almost) any Linux distribution running under `systemd`.
Tested on Debian 12, AlmaLinux 9 and AlmaLinux 8.

> **NOTE**
> deploy.sh supports `x86_64`, `arm64`, and `armv7` architectures.

To start the deployment script you'll need to execute the one-liner below:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/SmartctlExporter/Linux/deploy.sh | bash
```

## Prometheus Target

Now you must be wondering how to add this new exporter as a target to Prometheus?
Well, simply append the below to your Prometheus YAML configuration:

```yaml
- job_name: "smartctl"
  scrape_interval: 240s
  static_configs:
    - targets: ["localhost:9633"]
  relabel_configs:
    - source_labels: [__address__]
      target_label: instance
      replacement: "your_instance_name_here"
```

> If your Prometheus server is running on a separate machine, replace `localhost` with the remote server's IP/hostname.

Don't forget to reload Prometheus to apply the changes:

```shell
systemctl reload prometheus
```

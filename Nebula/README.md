# Nebula Installation Script

This collection of shell scripts streamlines the management of `Nebula` mesh networking on your Linux system.
Whether you need to install it, keep it up-to-date, or remove it, these scripts handle the process automatically.

Nebula is a scalable overlay networking tool with a focus on performance, simplicity and security. It lets you seamlessly connect computers anywhere in the world.

Here is the link to the project/binary you'll be installing:

```
https://github.com/slackhq/nebula
```

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

Another requirement is to execute all scripts from under the `root` user, e.g. `sudo su -`.

## Deployment

### Linux

`deploy.sh` automatically installs `Nebula` on (almost) any Linux distribution running under `systemd`.
Tested on Debian 12, AlmaLinux 9 and AlmaLinux 8.

> **NOTE**  
> deploy.sh only works on x64 systems for now.  
> More architectures might be coming in the future (I just don't have any way of testing those in my lab).

To start the deployment script you'll need to execute the one-liner below:

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/Nebula/Linux/deploy.sh | bash
```

## Configuration

**Important**: Nebula requires a configuration file to start properly. After installation, you need to:

1. Create a Nebula CA (Certificate Authority)
2. Generate host certificates
3. Create a configuration file at `/opt/nebula/config.yml`

The service will be enabled but not started automatically if the configuration file is missing.

For detailed configuration instructions, visit: https://nebula.defined.net/docs/

## Service Management

Check service status:
```shell
systemctl status nebula
```

View logs:
```shell
journalctl -u nebula -f
```

Start the service (after configuration):
```shell
systemctl start nebula
```

## Installation Details

Nebula is installed in `/opt/nebula/` to avoid conflicts with package manager installations:
- Binaries: `/opt/nebula/nebula` and `/opt/nebula/nebula-cert`
- Configuration: `/opt/nebula/config.yml`
- Data directory: `/opt/nebula/data/`
- Logs: `/var/log/nebula/`

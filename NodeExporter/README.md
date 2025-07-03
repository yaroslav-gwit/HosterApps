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

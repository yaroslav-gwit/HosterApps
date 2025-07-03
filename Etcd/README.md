# Etcd for Hoster cluster

## Install Required Packages

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

## Deploy

```shell
curl -sSL https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/Etcd/Linux/deploy.sh | bash
```

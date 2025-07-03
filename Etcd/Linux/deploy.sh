#!/usr/bin/env bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

# Check if wget is installed
if ! [ -x "$(command -v wget)" ]; then
    echo "Error: wget is not installed. Please install wget and try again."
    exit 2
fi

# Check if jq is installed
if ! [ -x "$(command -v jq)" ]; then
    echo "Error: jq is not installed. Please install jq and try again."
    exit 3
fi

# Detect the architecture
ARCHITECTURE=$(uname -m)
ARCH=""
if [ "$ARCHITECTURE" == "x86_64" ]; then
    ARCH="amd64"
else
    echo "Error: This script only supports x86_64 architecture"
    exit 4
fi

# Find the latest version of Etcd
LATEST_VERSION=$(wget -qO- https://api.github.com/repos/etcd-io/etcd/releases/latest | jq -r '.tag_name')

# Download the latest version of Etcd
# shellcheck disable=SC2086
wget https://github.com/etcd-io/etcd/releases/download/${LATEST_VERSION}/etcd-${LATEST_VERSION}-linux-${ARCH}.tar.gz
tar -xvzf etcd-*.tar.gz
rm -f etcd-*.tar.gz # Remove the tarball after extraction

# Create Etcd user and group
if id "etcd" &>/dev/null; then
    echo "=================="
    echo "User etcd already exists"
    echo "=================="
else
    useradd --no-create-home --shell /bin/false etcd
fi

# Create the required service directories
mkdir -p /opt/etcd/data
chown -R etcd:etcd /opt/etcd
chmod -R 0755 /opt/etcd

# Copy Etcd files to /opt/etcd and assign permissions
cp etcd-*/etcd /opt/etcd/
cp etcd-*/etcdctl /opt/etcd/
cp etcd-*/etcdutl /opt/etcd/
chown etcd:etcd /opt/etcd/etcd*
chmod 0755 /opt/etcd/etcd*

# Clean up downloaded files
rm -rf etcd-*

# Create the Etcd service file
wget https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Etcd/Linux/etcd.service -O /etc/systemd/system/etcd.service
chown root:root /etc/systemd/system/etcd.service
chmod 0644 /etc/systemd/system/etcd.service

# Create the Etcd configuration file
# wget https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Etcd/Linux/config.yaml -O /opt/etcd/config.yaml
# chown etcd:etcd /opt/etcd/config.yaml
# chmod 0640 /opt/etcd/config.yaml

# Enable Etcd service
systemctl daemon-reload
systemctl enable etcd

# Let the user know that the etcd is installed now
echo
echo "Etcd has been successfully installed."
echo
echo "You can check the service status with:"
echo "systemctl status etcd"
echo
echo "You can also check the logs with:"
echo "journalctl -u etcd -f"
echo

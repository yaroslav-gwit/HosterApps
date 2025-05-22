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

# Check if scaphandre is already installed
if [ -x "$(command -v scaphandre)" ]; then
    echo "error: scaphandre is already installed. please use the update or uninstall script instead."
    exit 3
fi

# Download the latest pre-built scaphandre binary
wget https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Scaphandre/Linux/scaphandre_v1.0.2 -O /usr/bin/scaphandre
chmod 0755 /usr/bin/scaphandre
chown root:root /usr/bin/scaphandre

# Download the scaphandre service file
wget https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Scaphandre/Linux/scaphandre.service -O /etc/systemd/system/scaphandre.service
chmod 0644 /etc/systemd/system/scaphandre.service
chown root:root /etc/systemd/system/scaphandre.service

# Reload systemd to recognize the new service
systemctl daemon-reload
# Enable and start the scaphandre service
systemctl enable scaphandre --now

# Check the status of the scaphandre service before exiting
set +e # Ignore errors for the status check
echo
echo
echo "Scaphandre service status:"
systemctl is-active scaphandre
# shellcheck disable=SC2181
if [ $? -eq 0 ]; then
    echo
    echo
    echo "Scaphandre is now up-and-running."
else
    echo
    echo
    echo "Scaphandre is not running!"
fi
echo
echo "You can check the service status with:"
echo "systemctl status scaphandre"
echo
echo "You can also check the logs with:"
echo "journalctl -u scaphandre -f"
echo

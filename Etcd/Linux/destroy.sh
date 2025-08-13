#!/usr/bin/env bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

echo "Warning: This will completely remove Etcd and all its data."
echo "This action cannot be undone."
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Stop and disable the Etcd service
if systemctl is-active --quiet etcd; then
    echo "Stopping Etcd service..."
    systemctl stop etcd
fi

if systemctl is-enabled --quiet etcd; then
    echo "Disabling Etcd service..."
    systemctl disable etcd
fi

# Remove the service file
if [ -f "/etc/systemd/system/etcd.service" ]; then
    echo "Removing Etcd service file..."
    rm -f /etc/systemd/system/etcd.service
fi

# Reload systemd daemon
systemctl daemon-reload

# Remove Etcd installation directory and all data
if [ -d "/opt/etcd" ]; then
    echo "Removing Etcd installation directory and data..."
    rm -rf /opt/etcd
fi

# Remove the etcd user and group
if id "etcd" &>/dev/null; then
    echo "Removing etcd user..."
    userdel etcd
fi

echo
echo "Etcd has been successfully removed from the system."
echo "All service files, binaries, and data have been deleted."
echo
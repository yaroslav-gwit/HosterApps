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

# check if jq is installed
if ! [ -x "$(command -v jq)" ]; then
    echo "error: jq is not installed. please install jq and try again."
    exit 3
fi

# check if smartctl is installed
if ! [ -x "$(command -v smartctl)" ]; then
    echo "error: smartctl is not installed. please install smartmontools and try again."
    exit 3
fi

# check if smartctl_exporter is already installed
if [ -x "$(command -v smartctl_exporter)" ]; then
    echo "error: smartctl_exporter is already installed. please use the update or uninstall script instead."
    exit 3
fi

# Detect the architecture
ARCHITECTURE=$(uname -m)
ARCH=""
if [ "$ARCHITECTURE" == "x86_64" ]; then
    ARCH="amd64"
else
    echo "Error: This script only supports x86_64 architecture (at least for now)"
    exit 4
fi

# Find the latest version of Prometheus
LATEST_VERSION=$(wget -qO- https://api.github.com/repos/prometheus-community/smartctl_exporter/releases/latest | jq -r '.tag_name')
LATEST_VERSION=${LATEST_VERSION:1} # Remove the 'v' from the version number

# Download SmartctlExporter
# shellcheck disable=SC2086
wget https://github.com/prometheus-community/smartctl_exporter/releases/download/v${LATEST_VERSION}/smartctl_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz
tar -xvzf smartctl_exporter*.tar.gz
mv smartctl_exporter*${ARCH} smartctl_exporter # Move the extracted directory to a generic name

# Create smartctl_exporter user and group
# smartctl_exporter must run as root!

# Copy smartctl_exporter binaries to /usr/local/bin and assign permissions
cp smartctl_exporter/smartctl_exporter /usr/local/bin/
chown root:root /usr/local/bin/smartctl_exporter
chmod 0755 /usr/local/bin/smartctl_exporter

# Create smartctl_exporter systemd service file
cat <<'EOF' >/etc/systemd/system/smartctl_exporter.service
[Unit]
Description=Prometheus smartctl_exporter service
After=network.target

[Service]
User=root
Group=root
Type=simple
ExecStart=/usr/local/bin/smartctl_exporter
Restart=on-failure
RestartSec=5
MaxRetries=3

[Install]
WantedBy=multi-user.target

EOF

# Start smartctl_exporter service
systemctl daemon-reload
systemctl enable smartctl_exporter --now

# Clean up downloaded files
rm -rf smartctl_exporter*.tar.gz
rm -rf smartctl_exporter

# Check the status of the Prometheus service before exiting
echo
echo
echo "SmartctlExporter service status:"
systemctl is-active smartctl_exporter
# shellcheck disable=SC2181
if [ $? -eq 0 ]; then
    echo "SmartctlExporter is running"
else
    echo "SmartctlExporter is not running!"
fi
echo

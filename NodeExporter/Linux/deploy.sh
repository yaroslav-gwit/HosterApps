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

# Find the latest version of Prometheus
LATEST_VERSION=$(wget -qO- https://api.github.com/repos/prometheus/node_exporter/releases/latest | jq -r '.tag_name')
LATEST_VERSION=${LATEST_VERSION:1} # Remove the 'v' from the version number

# Download Prometheus
# shellcheck disable=SC2086
wget https://github.com/prometheus/node_exporter/releases/download/v${LATEST_VERSION}/node_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz
tar -xvzf node_exporter*.tar.gz
mv node_exporter*${ARCH} node_exporter # Move the extracted directory to a generic name

# Create NodeExporter user and group
useradd --no-create-home --shell /bin/false node_exporter
groupadd node_exporter
usermod -a -G node_exporter node_exporter

# Copy NodeExporter binaries to /usr/local/bin and assign permissions
cp node_exporter/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
chmod 0755 /usr/local/bin/node_exporter

# Create NodeExporter systemd service file
cat <<'EOF' >/etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus node_exporter service
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
# To start on a custom port:
# ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9200

[Install]
WantedBy=multi-user.target

EOF

# Start Prometheus service
systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

# Clean up downloaded files
rm -fv node_exporter*.tar.gz
rm -rfv node_exporter

# Check the status of the Prometheus service before exiting
echo
echo
systemctl status node_exporter | cat
echo

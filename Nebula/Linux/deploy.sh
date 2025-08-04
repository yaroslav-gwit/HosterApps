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

# Check if nebula is already installed
if [ -f "/opt/nebula/nebula" ]; then
    echo "Error: Nebula is already installed. Please use the update or uninstall script instead."
    exit 4
fi

# Detect the architecture
ARCHITECTURE=$(uname -m)
ARCH=""
if [ "$ARCHITECTURE" == "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCHITECTURE" == "aarch64" ]; then
    ARCH="arm64"
else
    echo "Error: This script only supports x86_64 and aarch64 architectures (at least for now)"
    exit 5
fi

# Find the latest version of Nebula
LATEST_VERSION=$(wget -qO- https://api.github.com/repos/slackhq/nebula/releases/latest | jq -r '.tag_name')
LATEST_VERSION=${LATEST_VERSION:1} # Remove the 'v' from the version number

# Download Nebula
# shellcheck disable=SC2086
wget https://github.com/slackhq/nebula/releases/download/v${LATEST_VERSION}/nebula-linux-${ARCH}.tar.gz
tar -xvzf nebula-linux-*.tar.gz

# Create nebula user and group
if id "nebula" &>/dev/null; then
    echo "User nebula already exists"
else
    useradd --no-create-home --shell /bin/false nebula
fi

# Create the required service directories
mkdir -p /opt/nebula/data
mkdir -p /var/log/nebula

# Set ownership for service directories
chown -R nebula:nebula /opt/nebula
chown -R nebula:nebula /var/log/nebula
chmod -R 0755 /opt/nebula

# Copy Nebula binaries to /opt/nebula and assign permissions
cp nebula /opt/nebula/
cp nebula-cert /opt/nebula/
chown nebula:nebula /opt/nebula/nebula
chown nebula:nebula /opt/nebula/nebula-cert
chmod 0755 /opt/nebula/nebula
chmod 0755 /opt/nebula/nebula-cert

# Create Nebula systemd service file
wget https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Nebula/Linux/nebula.service -O /etc/systemd/system/nebula.service
chown root:root /etc/systemd/system/nebula.service
chmod 0644 /etc/systemd/system/nebula.service

# Reload systemd to recognize the new service
systemctl daemon-reload
# Enable the nebula service (but don't start it if config is missing)
systemctl enable nebula

# Clean up downloaded files
rm -fv nebula-linux-*.tar.gz

# Check if configuration file exists and provide guidance
if [ ! -f "/opt/nebula/config.yml" ]; then
    echo
    echo "=============================================="
    echo "Nebula has been successfully installed!"
    echo "=============================================="
    echo
    echo "IMPORTANT: The service is enabled but not started because"
    echo "the configuration file /opt/nebula/config.yml is missing."
    echo
    echo "To configure Nebula:"
    echo "1. Create a CA: /opt/nebula/nebula-cert ca -name 'My Organization'"
    echo "2. Create host certificates: /opt/nebula/nebula-cert sign -name 'hostname' -ip '192.168.100.1/24'"
    echo "3. Create /opt/nebula/config.yml with your network configuration"
    echo "4. Start the service: systemctl start nebula"
    echo
    echo "For detailed configuration instructions, visit:"
    echo "https://nebula.defined.net/docs/"
    echo
else
    # Start the service if configuration exists
    systemctl start nebula
    
    echo
    echo "=============================================="
    echo "Nebula has been successfully installed!"
    echo "=============================================="
    echo
fi

echo "You can check the service status with:"
echo "systemctl status nebula"
echo
echo "You can also check the logs with:"
echo "journalctl -u nebula -f"
echo

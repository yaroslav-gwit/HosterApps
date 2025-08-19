#!/usr/bin/env bash
set -e

# Function to print error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit "${2:-1}"
}

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
    error_exit "Please run this script as root"
fi

# Ensure required tools are installed
for tool in wget jq; do
    if ! command -v "$tool" &>/dev/null; then
        error_exit "Required tool '$tool' is not installed. Please install it and try again."
    fi
done

# Check if Nebula is already installed
if [[ -f "/opt/nebula/nebula" ]]; then
    error_exit "Nebula is already installed. Please use the update or uninstall script instead."
fi

# Detect architecture
ARCHITECTURE=$(uname -m)
case "$ARCHITECTURE" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)
        error_exit "Unsupported architecture: $ARCHITECTURE. Only x86_64 and aarch64 are supported."
        ;;
esac

# Fetch latest version from GitHub
LATEST_VERSION=$(wget -qO- https://api.github.com/repos/slackhq/nebula/releases/latest | jq -r '.tag_name' | sed 's/^v//')
if [[ -z "$LATEST_VERSION" ]]; then
    error_exit "Failed to fetch the latest Nebula version from GitHub."
fi

# Download and extract Nebula binary
URL="https://github.com/slackhq/nebula/releases/download/v${LATEST_VERSION}/nebula-linux-${ARCH}.tar.gz"
wget -O nebula.tar.gz "$URL" || error_exit "Failed to download Nebula binary."

tar -xzf nebula.tar.gz || error_exit "Failed to extract Nebula binary."

# Create nebula user and group
if ! id "nebula" &>/dev/null; then
    useradd --no-create-home --shell /bin/false nebula || error_exit "Failed to create user 'nebula'."
fi

# Create directories
mkdir -p /opt/nebula/data /var/log/nebula

# Set ownership and permissions
chown -R nebula:nebula /opt/nebula /var/log/nebula
chmod -R 0755 /opt/nebula

# Copy binaries to /opt/nebula
cp nebula nebula-cert /opt/nebula/
chown nebula:nebula /opt/nebula/{nebula,nebula-cert}
chmod 0755 /opt/nebula/{nebula,nebula-cert}

# Install systemd service file
SERVICE_URL="https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Nebula/Linux/nebula.service"
wget -O /etc/systemd/system/nebula.service "$SERVICE_URL" || error_exit "Failed to download Nebula service file."
chown root:root /etc/systemd/system/nebula.service
chmod 0644 /etc/systemd/system/nebula.service

# Reload systemd and enable service
systemctl daemon-reload || error_exit "Failed to reload systemd."
systemctl enable nebula || error_exit "Failed to enable Nebula service."

# Cleanup
rm -f nebula.tar.gz nebula nebula-cert

# Check for config file and provide instructions
if [[ ! -f "/opt/nebula/config.yml" ]]; then
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
else
    systemctl start nebula || echo "Failed to start Nebula service (may be due to missing config)."
    echo
    echo "=============================================="
    echo "Nebula has been successfully installed and started!"
    echo "=============================================="
fi

echo "You can check the service status with:"
echo "systemctl status nebula"
echo
echo "You can also check the logs with:"
echo "journalctl -u nebula -f"

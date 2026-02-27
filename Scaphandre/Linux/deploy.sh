#!/usr/bin/env bash
# ==========================================================
#   Install Scaphandre power metrics exporter on Linux
# ==========================================================
set -euo pipefail

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' not found."
}

# ------------------------------------------------------------------
# 1. Pre-flight checks
# ------------------------------------------------------------------
[[ $EUID -eq 0 ]] || fail "This script must be run as root."

require_cmd wget
require_cmd systemctl

if command -v scaphandre >/dev/null 2>&1; then
  fail "Scaphandre is already installed. Use the update or destroy script instead."
fi

# ------------------------------------------------------------------
# 2. Install binary
# ------------------------------------------------------------------
BINARY_URL="https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Scaphandre/Linux/scaphandre_v1.0.2"

wget -qO /usr/bin/scaphandre "$BINARY_URL" \
  || fail "Failed to download Scaphandre binary."
chmod 0755 /usr/bin/scaphandre
chown root:root /usr/bin/scaphandre

# ------------------------------------------------------------------
# 3. Deploy systemd unit
# ------------------------------------------------------------------
SYSTEMD_UNIT="/etc/systemd/system/scaphandre.service"
wget -qO "$SYSTEMD_UNIT" \
  https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Scaphandre/Linux/scaphandre.service \
  || fail "Failed to download scaphandre.service."
chmod 644 "$SYSTEMD_UNIT"

# ------------------------------------------------------------------
# 4. Enable & start the service
# ------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now scaphandre

# ------------------------------------------------------------------
# 5. Done
# ------------------------------------------------------------------
printf '\nScaphandre installed successfully!\n'
printf 'Service status: systemctl status scaphandre\n'
printf 'Follow logs:    journalctl -u scaphandre -f\n'
printf 'Metrics URL:    http://localhost:1920/metrics\n'

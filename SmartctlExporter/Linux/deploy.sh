#!/usr/bin/env bash
# ==========================================================
#   Install the latest smartctl_exporter release on Linux
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
require_cmd jq
require_cmd systemctl
require_cmd smartctl

if command -v smartctl_exporter >/dev/null 2>&1; then
  fail "smartctl_exporter is already installed. Use the update or destroy script instead."
fi

# ------------------------------------------------------------------
# 2. Detect architecture
# ------------------------------------------------------------------
case "$(uname -m)" in
  x86_64)        ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  armv7l)        ARCH=armv7 ;;
  *) fail "Unsupported architecture: $(uname -m)" ;;
esac

# ------------------------------------------------------------------
# 3. Determine the latest release
# ------------------------------------------------------------------
GITHUB_API="https://api.github.com/repos/prometheus-community/smartctl_exporter/releases/latest"
LATEST_TAG=$(wget -qO- "$GITHUB_API" | jq -r '.tag_name')
[[ -n $LATEST_TAG ]] || fail "Could not obtain latest smartctl_exporter version."
LATEST_VERSION="${LATEST_TAG#v}"  # strip leading 'v'

# ------------------------------------------------------------------
# 4. Download & extract into a temporary directory
# ------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL="smartctl_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus-community/smartctl_exporter/releases/download/${LATEST_TAG}/${TARBALL}"

wget -qO "${WORK_DIR}/${TARBALL}" "$DOWNLOAD_URL" \
  || fail "Failed to download ${TARBALL}."
tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR" \
  || fail "Extraction failed."

# ------------------------------------------------------------------
# 5. Install binary
# ------------------------------------------------------------------
install -o root -g root -m 0755 \
  "${WORK_DIR}/smartctl_exporter-${LATEST_VERSION}.linux-${ARCH}/smartctl_exporter" \
  /usr/bin/smartctl_exporter

# ------------------------------------------------------------------
# 6. Deploy systemd unit
# ------------------------------------------------------------------
SYSTEMD_UNIT="/etc/systemd/system/smartctl_exporter.service"
wget -qO "$SYSTEMD_UNIT" \
  https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/SmartctlExporter/Linux/smartctl_exporter.service \
  || fail "Failed to download smartctl_exporter.service."
chmod 644 "$SYSTEMD_UNIT"

# ------------------------------------------------------------------
# 7. Enable & start the service
# ------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now smartctl_exporter

# ------------------------------------------------------------------
# 8. Done
# ------------------------------------------------------------------
printf '\nsmartctl_exporter %s installed successfully!\n' "$LATEST_VERSION"
printf 'Service status: systemctl status smartctl_exporter\n'
printf 'Follow logs:    journalctl -u smartctl_exporter -f\n'
printf 'Metrics URL:    http://localhost:9633/metrics\n'

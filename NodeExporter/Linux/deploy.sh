#!/usr/bin/env bash
# ==========================================================
#   Install the latest Node Exporter release on Linux
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

usage() {
  cat >&2 <<'USAGE'
Usage: deploy.sh [OPTIONS]

Options:
  --no-start            Install only; do not enable/start the systemd service
                        (useful for chroot environments)
  --hoster-collectors   Install the Hoster-curated collector allow-list as a
                        systemd drop-in. Pins node_exporter to a known set of
                        collectors so behaviour is identical across every
                        Hoster host, regardless of distro / kernel modules /
                        future upstream changes. Remove the drop-in at
                        /etc/systemd/system/node_exporter.service.d/
                        hoster-collectors.conf to revert to upstream defaults.

USAGE
  exit 1
}

# ------------------------------------------------------------------
# 1. Parse flags
# ------------------------------------------------------------------
NO_START=false
HOSTER_COLLECTORS=false
for arg in "$@"; do
  case "$arg" in
    --no-start)          NO_START=true ;;
    --hoster-collectors) HOSTER_COLLECTORS=true ;;
    --help|-h)           usage ;;
    *)                   fail "Unknown flag: $arg" ;;
  esac
done

# ------------------------------------------------------------------
# 1. Pre-flight checks
# ------------------------------------------------------------------
[[ $EUID -eq 0 ]] || fail "This script must be run as root."

require_cmd wget
require_cmd jq
require_cmd systemctl

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
GITHUB_API="https://api.github.com/repos/prometheus/node_exporter/releases/latest"
LATEST_TAG=$(wget -qO- "$GITHUB_API" | jq -r '.tag_name')
[[ -n $LATEST_TAG ]] || fail "Could not obtain latest Node Exporter version."
LATEST_VERSION="${LATEST_TAG#v}"  # strip leading 'v'

# ------------------------------------------------------------------
# 4. Download & extract into a temporary directory
# ------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL="node_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/${LATEST_TAG}/${TARBALL}"

wget -qO "${WORK_DIR}/${TARBALL}" "$DOWNLOAD_URL" \
  || fail "Failed to download ${TARBALL}."
tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR" \
  || fail "Extraction failed."

# ------------------------------------------------------------------
# 5. Create system user (idempotent)
# ------------------------------------------------------------------
if ! id -u node_exporter >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
fi

# ------------------------------------------------------------------
# 6. Install binary
# ------------------------------------------------------------------
install -o root -g root -m 0755 \
  "${WORK_DIR}/node_exporter-${LATEST_VERSION}.linux-${ARCH}/node_exporter" \
  /usr/bin/node_exporter

# ------------------------------------------------------------------
# 7. Deploy systemd unit
# ------------------------------------------------------------------
SYSTEMD_UNIT="/etc/systemd/system/node_exporter.service"
wget -qO "$SYSTEMD_UNIT" \
  https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/NodeExporter/Linux/node_exporter.service \
  || fail "Failed to download node_exporter.service."
chmod 644 "$SYSTEMD_UNIT"

# ------------------------------------------------------------------
# 7a. Hoster-curated collector allow-list (optional drop-in)
# ------------------------------------------------------------------
DROP_IN_DIR="/etc/systemd/system/node_exporter.service.d"
DROP_IN_FILE="${DROP_IN_DIR}/hoster-collectors.conf"
if [[ $HOSTER_COLLECTORS == true ]]; then
  install -d -m 0755 "$DROP_IN_DIR"
  wget -qO "$DROP_IN_FILE" \
    https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/NodeExporter/Linux/hoster-collectors.conf \
    || fail "Failed to download hoster-collectors.conf."
  chmod 644 "$DROP_IN_FILE"
  printf 'Hoster collector allow-list installed: %s\n' "$DROP_IN_FILE"
fi

# ------------------------------------------------------------------
# 8. Enable & start the service
# ------------------------------------------------------------------
systemctl daemon-reload
if [[ $NO_START == false ]]; then
  systemctl enable node_exporter
  if systemctl is-active --quiet node_exporter; then
    systemctl restart node_exporter
  else
    systemctl start node_exporter
  fi
else
  systemctl enable node_exporter
  printf 'Service enabled but not started (--no-start). Start manually with:\n'
  printf '  systemctl start node_exporter\n'
fi

# ------------------------------------------------------------------
# 9. Done
# ------------------------------------------------------------------
printf '\nNode Exporter %s installed successfully!\n' "$LATEST_VERSION"
printf 'Service status: systemctl status node_exporter\n'
printf 'Follow logs:    journalctl -u node_exporter -f\n'
printf 'Metrics URL:    http://localhost:9100/metrics\n'

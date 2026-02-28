#!/usr/bin/env bash
# ==========================================================
#   Install the latest AlertManager release on Linux
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
GITHUB_API="https://api.github.com/repos/prometheus/alertmanager/releases/latest"
LATEST_TAG=$(wget -qO- "$GITHUB_API" | jq -r '.tag_name')
[[ -n $LATEST_TAG ]] || fail "Could not obtain latest AlertManager version."
LATEST_VERSION="${LATEST_TAG#v}"  # strip leading 'v'

# ------------------------------------------------------------------
# 4. Download & extract into a temporary directory
# ------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL="alertmanager-${LATEST_VERSION}.linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus/alertmanager/releases/download/${LATEST_TAG}/${TARBALL}"

wget -qO "${WORK_DIR}/${TARBALL}" "$DOWNLOAD_URL" \
  || fail "Failed to download ${TARBALL}."
tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR" \
  || fail "Extraction failed."

EXTRACT_DIR="${WORK_DIR}/alertmanager-${LATEST_VERSION}.linux-${ARCH}"

# ------------------------------------------------------------------
# 5. Create system user (idempotent)
# ------------------------------------------------------------------
if ! id -u alertmanager >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin alertmanager
fi

# ------------------------------------------------------------------
# 6. Create data and config directories
# ------------------------------------------------------------------
mkdir -p /etc/alertmanager /var/lib/alertmanager
chown alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
chmod 750 /etc/alertmanager /var/lib/alertmanager

# ------------------------------------------------------------------
# 7. Install binaries
# ------------------------------------------------------------------
install -o root -g root -m 0755 "${EXTRACT_DIR}/alertmanager" /usr/bin/alertmanager
install -o root -g root -m 0755 "${EXTRACT_DIR}/amtool"       /usr/bin/amtool

# ------------------------------------------------------------------
# 8. Deploy default config (skip if one already exists)
# ------------------------------------------------------------------
if [[ ! -f /etc/alertmanager/alertmanager.yml ]]; then
  cat >/etc/alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'null'

receivers:
  - name: 'null'

inhibit_rules:
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ['alertname', 'job']
EOF
  chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml
  chmod 640 /etc/alertmanager/alertmanager.yml
fi

# ------------------------------------------------------------------
# 9. Deploy systemd unit
# ------------------------------------------------------------------
SYSTEMD_UNIT="/etc/systemd/system/alertmanager.service"
wget -qO "$SYSTEMD_UNIT" \
  https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/AlertManager/Linux/alertmanager.service \
  || fail "Failed to download alertmanager.service."
chmod 644 "$SYSTEMD_UNIT"

# ------------------------------------------------------------------
# 10. Enable & start the service
# ------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now alertmanager

# ------------------------------------------------------------------
# 11. Done
# ------------------------------------------------------------------
printf '\nAlertManager %s installed successfully!\n' "$LATEST_VERSION"
printf 'Service status: systemctl status alertmanager\n'
printf 'Follow logs:    journalctl -u alertmanager -f\n'
printf 'Web UI:         http://localhost:9093\n'
printf '\nRemember to configure Prometheus to send alerts to AlertManager.\n'
printf 'See the README for the required prometheus.yml snippet.\n'

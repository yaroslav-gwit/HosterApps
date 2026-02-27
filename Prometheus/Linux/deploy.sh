#!/usr/bin/env bash
# ==========================================================
#   Install the latest Prometheus release on Linux
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
  --enable-remote-write   Enable Prometheus remote write receiver
                          (--web.enable-remote-write-receiver)

USAGE
  exit 1
}

# ------------------------------------------------------------------
# 1. Parse flags
# ------------------------------------------------------------------
ENABLE_REMOTE_WRITE=false
for arg in "$@"; do
  case "$arg" in
    --enable-remote-write) ENABLE_REMOTE_WRITE=true ;;
    --help|-h) usage ;;
    *) fail "Unknown flag: $arg" ;;
  esac
done

# ------------------------------------------------------------------
# 2. Pre-flight checks
# ------------------------------------------------------------------
[[ $EUID -eq 0 ]] || fail "This script must be run as root."

require_cmd wget
require_cmd jq
require_cmd systemctl

# ------------------------------------------------------------------
# 3. Detect architecture
# ------------------------------------------------------------------
case "$(uname -m)" in
  x86_64)        ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  armv7l)        ARCH=armv7 ;;
  *) fail "Unsupported architecture: $(uname -m)" ;;
esac

# ------------------------------------------------------------------
# 4. Determine the latest release
# ------------------------------------------------------------------
GITHUB_API="https://api.github.com/repos/prometheus/prometheus/releases/latest"
LATEST_TAG=$(wget -qO- "$GITHUB_API" | jq -r '.tag_name')
[[ -n $LATEST_TAG ]] || fail "Could not obtain latest Prometheus version."
LATEST_VERSION="${LATEST_TAG#v}"  # strip leading 'v'

# ------------------------------------------------------------------
# 5. Download & extract into a temporary directory
# ------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL="prometheus-${LATEST_VERSION}.linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus/prometheus/releases/download/${LATEST_TAG}/${TARBALL}"

wget -qO "${WORK_DIR}/${TARBALL}" "$DOWNLOAD_URL" \
  || fail "Failed to download ${TARBALL}."
tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR" \
  || fail "Extraction failed."

EXTRACT_DIR="${WORK_DIR}/prometheus-${LATEST_VERSION}.linux-${ARCH}"

# ------------------------------------------------------------------
# 6. Create system user (idempotent)
# ------------------------------------------------------------------
if ! id -u prometheus >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
fi

# ------------------------------------------------------------------
# 7. Create data and config directories
# ------------------------------------------------------------------
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus
chmod 750 /etc/prometheus /var/lib/prometheus

# ------------------------------------------------------------------
# 8. Install binaries
# ------------------------------------------------------------------
install -o root -g root -m 0755 "${EXTRACT_DIR}/prometheus" /usr/bin/prometheus
install -o root -g root -m 0755 "${EXTRACT_DIR}/promtool"   /usr/bin/promtool

# ------------------------------------------------------------------
# 9. Deploy default config (skip if one already exists)
# ------------------------------------------------------------------
if [[ ! -f /etc/prometheus/prometheus.yml ]]; then
  cat >/etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 60s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
  chown prometheus:prometheus /etc/prometheus/prometheus.yml
  chmod 640 /etc/prometheus/prometheus.yml
fi

# ------------------------------------------------------------------
# 10. Generate systemd unit
# ------------------------------------------------------------------
if [[ $ENABLE_REMOTE_WRITE == true ]]; then
  REMOTE_WRITE_FLAG=' \
    --web.enable-remote-write-receiver'
else
  REMOTE_WRITE_FLAG=''
fi

cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus monitoring system and time series database
Documentation=https://prometheus.io/docs/
After=network-online.target
Wants=network-online.target
StartLimitInterval=60
StartLimitBurst=5

[Service]
User=prometheus
Group=prometheus
Type=simple
SyslogIdentifier=prometheus

ExecStart=/usr/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus \\
    --log.level=info \\
    --log.format=json \\
    --storage.tsdb.retention.time=365d${REMOTE_WRITE_FLAG}

ExecReload=/usr/bin/kill -HUP \$MAINPID

Restart=on-failure
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=30

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/prometheus
ReadOnlyPaths=/etc/prometheus
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
MemoryDenyWriteExecute=yes
LockPersonality=yes
SystemCallArchitectures=native
CapabilityBoundingSet=

# Process limits (Prometheus can open many files for active time series)
LimitNOFILE=65535
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/prometheus.service

# ------------------------------------------------------------------
# 11. Enable & start the service
# ------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now prometheus

# ------------------------------------------------------------------
# 12. Done
# ------------------------------------------------------------------
printf '\nPrometheus %s installed successfully!\n' "$LATEST_VERSION"
[[ $ENABLE_REMOTE_WRITE == true ]] && printf 'Remote write receiver: enabled\n'
printf 'Service status: systemctl status prometheus\n'
printf 'Follow logs:    journalctl -u prometheus -f\n'
printf 'Web UI:         http://localhost:9090\n'

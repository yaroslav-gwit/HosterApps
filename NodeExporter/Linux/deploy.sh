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

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' not found."
}

install_asset() {
  local source_name=$1
  local destination=$2
  local mode=$3

  if [[ -n ${NODE_EXPORTER_ASSET_DIR:-} ]]; then
    [[ -f ${NODE_EXPORTER_ASSET_DIR}/${source_name} ]] \
      || fail "Installer asset not found: ${NODE_EXPORTER_ASSET_DIR}/${source_name}"
    install -o root -g root -m "$mode" \
      "${NODE_EXPORTER_ASSET_DIR}/${source_name}" "$destination"
    return
  fi

  local temporary_asset="${WORK_DIR}/asset-${source_name}"
  wget -qO "$temporary_asset" \
    "${HOSTER_APPS_RAW_BASE_URL}/${source_name}" \
    || fail "Failed to download ${source_name}."
  install -o root -g root -m "$mode" "$temporary_asset" "$destination"
}

usage() {
  cat >&2 <<'USAGE'
Usage: deploy.sh [OPTIONS]

Options:
  --no-start            Install and enable the service, but do not start it
                        (useful while building chroot or guest images)
  --hoster-collectors   Install the Hoster-curated collector allow-list as a
                        systemd drop-in. This host-only option pins
                        node_exporter to a known set of
                        collectors so behaviour is identical across every
                        Hoster host, regardless of distro / kernel modules /
                        future upstream changes. Remove the drop-in at
                        /etc/systemd/system/node_exporter.service.d/
                        hoster-collectors.conf to revert to upstream defaults.
  --version VERSION     Install a specific stable version instead of the latest
                        GitHub release (for example: --version 1.12.1).

USAGE
}

# ------------------------------------------------------------------
# 1. Parse flags
# ------------------------------------------------------------------
NO_START=false
HOSTER_COLLECTORS=false
REQUESTED_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-start)
      NO_START=true
      shift
      ;;
    --hoster-collectors)
      HOSTER_COLLECTORS=true
      shift
      ;;
    --version)
      [[ $# -ge 2 ]] || fail "--version requires a version number."
      REQUESTED_VERSION=${2#v}
      shift 2
      ;;
    --version=*)
      REQUESTED_VERSION=${1#--version=}
      REQUESTED_VERSION=${REQUESTED_VERSION#v}
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown flag: $1"
      ;;
  esac
done

if [[ -n $REQUESTED_VERSION && ! $REQUESTED_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "Invalid stable version: ${REQUESTED_VERSION}"
fi

# ------------------------------------------------------------------
# 1. Pre-flight checks
# ------------------------------------------------------------------
[[ $EUID -eq 0 ]] || fail "This script must be run as root."

require_cmd wget
require_cmd jq
require_cmd install
require_cmd sha256sum
require_cmd tar

if command -v systemctl >/dev/null 2>&1; then
  INIT_SYSTEM=systemd
elif command -v openrc-run >/dev/null 2>&1 \
  && command -v rc-service >/dev/null 2>&1 \
  && command -v rc-update >/dev/null 2>&1; then
  INIT_SYSTEM=openrc
else
  fail "No supported init system found (systemd or OpenRC required)."
fi

readonly INIT_SYSTEM
readonly HOSTER_APPS_RAW_BASE_URL="${HOSTER_APPS_RAW_BASE_URL:-https://raw.githubusercontent.com/yaroslav-gwit/HosterApps/main/NodeExporter/Linux}"

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
# 3. Determine and verify the release
# ------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -n $REQUESTED_VERSION ]]; then
  RELEASE_API="https://api.github.com/repos/prometheus/node_exporter/releases/tags/v${REQUESTED_VERSION}"
else
  RELEASE_API="https://api.github.com/repos/prometheus/node_exporter/releases/latest"
fi

wget -qO "${WORK_DIR}/release.json" "$RELEASE_API" \
  || fail "Could not obtain Node Exporter release metadata."

LATEST_TAG=$(jq -er '.tag_name | select(type == "string" and test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' \
  "${WORK_DIR}/release.json") \
  || fail "Release metadata did not contain a valid stable version."
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n $REQUESTED_VERSION && $LATEST_VERSION != "$REQUESTED_VERSION" ]]; then
  fail "Requested ${REQUESTED_VERSION}, but GitHub returned ${LATEST_VERSION}."
fi

# ------------------------------------------------------------------
# 4. Download, verify, and extract
# ------------------------------------------------------------------
TARBALL="node_exporter-${LATEST_VERSION}.linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/${LATEST_TAG}/${TARBALL}"
EXPECTED_DIGEST=$(jq -er --arg name "$TARBALL" \
  '.assets[] | select(.name == $name) | .digest | select(type == "string" and startswith("sha256:"))' \
  "${WORK_DIR}/release.json") \
  || fail "Release metadata did not contain a SHA-256 digest for ${TARBALL}."
EXPECTED_SHA256=${EXPECTED_DIGEST#sha256:}

wget -qO "${WORK_DIR}/${TARBALL}" "$DOWNLOAD_URL" \
  || fail "Failed to download ${TARBALL}."
printf '%s  %s\n' "$EXPECTED_SHA256" "${WORK_DIR}/${TARBALL}" \
  | sha256sum -c - \
  || fail "SHA-256 verification failed for ${TARBALL}."
tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR" \
  || fail "Extraction failed."

# ------------------------------------------------------------------
# 5. Create system user (idempotent)
# ------------------------------------------------------------------
if ! id -u node_exporter >/dev/null 2>&1; then
  if command -v useradd >/dev/null 2>&1; then
    nologin_shell=$(command -v nologin || printf '/usr/sbin/nologin')
    useradd --system --no-create-home --shell "$nologin_shell" node_exporter
  elif command -v adduser >/dev/null 2>&1 && command -v addgroup >/dev/null 2>&1; then
    nologin_shell=$(command -v nologin || printf '/sbin/nologin')
    addgroup -S node_exporter >/dev/null 2>&1 || true
    adduser -S -D -H -s "$nologin_shell" -G node_exporter node_exporter
  else
    fail "Neither useradd nor the adduser/addgroup pair is available."
  fi
fi

# ------------------------------------------------------------------
# 6. Install binary
# ------------------------------------------------------------------
install -o root -g root -m 0755 \
  "${WORK_DIR}/node_exporter-${LATEST_VERSION}.linux-${ARCH}/node_exporter" \
  /usr/bin/node_exporter

# ------------------------------------------------------------------
# 7. Deploy the init-system service definition
# ------------------------------------------------------------------
if [[ $INIT_SYSTEM == systemd ]]; then
  SYSTEMD_UNIT="/etc/systemd/system/node_exporter.service"
  install_asset node_exporter.service "$SYSTEMD_UNIT" 0644
else
  install_asset node_exporter.openrc /etc/init.d/node_exporter 0755
  if [[ ! -f /etc/conf.d/node_exporter ]]; then
    install_asset node_exporter.openrc.conf /etc/conf.d/node_exporter 0644
  else
    printf 'Preserving existing OpenRC configuration: /etc/conf.d/node_exporter\n'
  fi
fi

# ------------------------------------------------------------------
# 7a. Hoster-curated collector allow-list (optional drop-in)
# ------------------------------------------------------------------
DROP_IN_DIR="/etc/systemd/system/node_exporter.service.d"
DROP_IN_FILE="${DROP_IN_DIR}/hoster-collectors.conf"
if [[ $HOSTER_COLLECTORS == true && $INIT_SYSTEM == systemd ]]; then
  install -d -m 0755 "$DROP_IN_DIR"
  install_asset hoster-collectors.conf "$DROP_IN_FILE" 0644
  printf 'Hoster collector allow-list installed: %s\n' "$DROP_IN_FILE"
elif [[ $HOSTER_COLLECTORS == true ]]; then
  warn "--hoster-collectors is intended for systemd Hoster hosts; ignoring it on OpenRC."
fi

# ------------------------------------------------------------------
# 8. Enable & start the service
# ------------------------------------------------------------------
if [[ $INIT_SYSTEM == systemd ]]; then
  if [[ $NO_START == false ]]; then
    systemctl daemon-reload
  fi
  systemctl enable node_exporter
  if [[ $NO_START == false ]]; then
    if systemctl is-active --quiet node_exporter; then
      systemctl restart node_exporter
    else
      systemctl start node_exporter
    fi
  else
    printf 'Service enabled but not started (--no-start). Start manually with:\n'
    printf '  systemctl start node_exporter\n'
  fi
else
  rc-update add node_exporter default
  if [[ $NO_START == false ]]; then
    if rc-service node_exporter status >/dev/null 2>&1; then
      rc-service node_exporter restart
    else
      rc-service node_exporter start
    fi
  else
    printf 'Service enabled but not started (--no-start). Start manually with:\n'
    printf '  rc-service node_exporter start\n'
  fi
fi

# ------------------------------------------------------------------
# 9. Done
# ------------------------------------------------------------------
printf '\nNode Exporter %s installed successfully!\n' "$LATEST_VERSION"
printf 'Init system:    %s\n' "$INIT_SYSTEM"
if [[ $INIT_SYSTEM == systemd ]]; then
  printf 'Service status: systemctl status node_exporter\n'
  printf 'Follow logs:    journalctl -u node_exporter -f\n'
else
  printf 'Service status: rc-service node_exporter status\n'
  printf 'Follow logs:    tail -f /var/log/node_exporter/node_exporter.log\n'
fi
printf 'Metrics URL:    http://localhost:9100/metrics\n'

#!/usr/bin/env bash
# ==========================================================
#   Install the latest etcd release (x86‑64) on Linux
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
# 1. Pre‑flight checks
# ------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root."
fi

require_cmd wget
require_cmd jq
require_cmd systemctl

# ------------------------------------------------------------------
# 2. Detect architecture (currently only x86‑64)
# ------------------------------------------------------------------
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;   # extendable for future support
  *) fail "Unsupported architecture: $(uname -m)" ;;
esac

# ------------------------------------------------------------------
# 3. Determine the latest release
# ------------------------------------------------------------------
GITHUB_API="https://api.github.com/repos/etcd-io/etcd/releases/latest"
LATEST_VERSION=$(wget -qO- "$GITHUB_API" | jq -r '.tag_name')
[[ -n $LATEST_VERSION ]] || fail "Could not obtain latest etcd version."

# ------------------------------------------------------------------
# 4. Download & extract
# ------------------------------------------------------------------
TARBALL="etcd-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/etcd-io/etcd/releases/download/${LATEST_VERSION}/${TARBALL}"

# Keep the extracted dir name so we can delete it later
EXTRACT_DIR="etcd-${LATEST_VERSION}-linux-${ARCH}"

wget -qO "$TARBALL" "$DOWNLOAD_URL" || fail "Failed to download $TARBALL."
tar -xzf "$TARBALL" || fail "Extraction failed."
rm -f "$TARBALL"

# ------------------------------------------------------------------
# 5. Create system user for etcd
# ------------------------------------------------------------------
if ! id -u etcd >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin etcd
fi

# ------------------------------------------------------------------
# 6. Install binaries
# ------------------------------------------------------------------
ETCD_DIR="/opt/etcd"
mkdir -p "$ETCD_DIR"/{data,config}
cp "$EXTRACT_DIR"/{etcd,etcdctl,etcdutl} "$ETCD_DIR/"
rm -rf "$EXTRACT_DIR"    # clean up extracted source folder

chown -R etcd:etcd "$ETCD_DIR"
chmod 755 "$ETCD_DIR"   # 0755, no need for recursive 0755 on sub‑items

# ------------------------------------------------------------------
# 7. (Optional) Copy a custom config file
# ------------------------------------------------------------------
# Uncomment and edit the next two lines if you have a config.yaml
# cp config.yaml "$ETCD_DIR/config.yaml"
# chown etcd:etcd "$ETCD_DIR/config.yaml" && chmod 640 "$ETCD_DIR/config.yaml"

# ------------------------------------------------------------------
# 8. Deploy systemd unit
# ------------------------------------------------------------------
SYSTEMD_UNIT="/etc/systemd/system/etcd.service"
wget -qO "$SYSTEMD_UNIT" \
  https://github.com/yaroslav-gwit/HosterApps/raw/refs/heads/main/Etcd/Linux/etcd.service
chmod 644 "$SYSTEMD_UNIT"

# ------------------------------------------------------------------
# 9. Enable & start the service
# ------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now etcd

# ------------------------------------------------------------------
# 10. Done!
# ------------------------------------------------------------------
printf '\n✅  etcd %s installed successfully!\n' "$LATEST_VERSION"
printf '🔧  Service status: systemctl status etcd\n'
printf '📜  Follow logs: journalctl -u etcd -f\n'

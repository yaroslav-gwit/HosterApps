#!/usr/bin/env bash

set -euo pipefail

# Installs or updates Caddy from the extracted .run payload.
# Idempotent: first run sets up everything from scratch; subsequent runs update
# the binary and service file while preserving user-edited configuration.

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly PAYLOAD_DIR="${1:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}"
shift || true

readonly INSTALL_DIR="/opt/hoster/caddy"
readonly CONFIG_DIR="/etc/caddy"
readonly CADDYFILE="${CONFIG_DIR}/Caddyfile"
readonly ENV_FILE="${CONFIG_DIR}/caddy.env"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly SERVICE_NAME="caddy.service"
readonly CADDY_USER="caddy"
readonly CADDY_GROUP="caddy"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RESET='\033[0m'

note() { printf "${C_GREEN}[%s]${C_RESET} %s\n" "${SCRIPT_NAME}" "$*"; }
warn() { printf "${C_YELLOW}[%s] Warning:${C_RESET} %s\n" "${SCRIPT_NAME}" "$*"; }
die()  { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

copy_if_missing() {
	local src="${1}" dst="${2}"
	if [[ -f "${dst}" ]]; then
		note "  Preserved existing: ${dst}"
	else
		install -m 0644 "${src}" "${dst}"
		note "  Created: ${dst}"
	fi
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CF_API_KEY=""
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--cf-api-key)
		CF_API_KEY="${2}"
		shift 2
		;;
	*)
		shift
		;;
	esac
done

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
[[ "${EUID}" -eq 0 ]] || die "Run this installer as root"
[[ -f "${PAYLOAD_DIR}/build-info.txt" ]] || die "build-info.txt not found in ${PAYLOAD_DIR}"
[[ -x "${PAYLOAD_DIR}/bin/caddy" ]] || die "caddy binary not found in ${PAYLOAD_DIR}/bin/"

# shellcheck source=/dev/null
source "${PAYLOAD_DIR}/build-info.txt"

note "Installing Caddy ${CADDY_VERSION} (built ${BUILD_DATE})"

# ---------------------------------------------------------------------------
# Create system user
# ---------------------------------------------------------------------------
if id "${CADDY_USER}" &>/dev/null; then
	note "System user '${CADDY_USER}' already exists"
else
	note "Creating system user '${CADDY_USER}'"
	groupadd --system "${CADDY_GROUP}" 2>/dev/null || true
	useradd --system --gid "${CADDY_GROUP}" \
		--home-dir /var/lib/caddy --create-home \
		--shell /usr/sbin/nologin \
		"${CADDY_USER}"
fi

# ---------------------------------------------------------------------------
# Detect if this is an update (service already running)
# ---------------------------------------------------------------------------
SERVICE_WAS_ACTIVE=false
if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
	SERVICE_WAS_ACTIVE=true
	note "Stopping running ${SERVICE_NAME} for upgrade"
	systemctl stop "${SERVICE_NAME}"
fi

# ---------------------------------------------------------------------------
# Install binary
# ---------------------------------------------------------------------------
mkdir -p "${INSTALL_DIR}/bin"
install -m 0755 "${PAYLOAD_DIR}/bin/caddy" "${INSTALL_DIR}/bin/caddy"
install -m 0644 "${PAYLOAD_DIR}/build-info.txt" "${INSTALL_DIR}/build-info.txt"

# Symlink into /usr/local/bin for convenience
ln -sf "${INSTALL_DIR}/bin/caddy" /usr/local/bin/caddy

note "Installed binary: ${INSTALL_DIR}/bin/caddy"
note "Symlinked: /usr/local/bin/caddy"

# Verify the binary runs
"${INSTALL_DIR}/bin/caddy" version || die "Caddy binary failed to execute"

# ---------------------------------------------------------------------------
# Configuration directory and files
# ---------------------------------------------------------------------------
mkdir -p "${CONFIG_DIR}"
chown root:${CADDY_GROUP} "${CONFIG_DIR}"
chmod 0750 "${CONFIG_DIR}"

# Data and runtime directories
mkdir -p /var/lib/caddy/.config/caddy /var/lib/caddy/.local/share/caddy
chown -R "${CADDY_USER}:${CADDY_GROUP}" /var/lib/caddy

# Seed default Caddyfile (hello world) — only on first install
CADDYFILE_TMP="$(mktemp)"
cat > "${CADDYFILE_TMP}" <<'CADDYFILE'
# Caddy reverse proxy configuration
# Documentation: https://caddyserver.com/docs/caddyfile
#
# This default config serves a hello-world page on port 80.
# Replace it with your own reverse-proxy rules.
#
# Example reverse proxy with automatic HTTPS:
#
#   example.com {
#       reverse_proxy localhost:8080
#   }
#
# Example with Cloudflare DNS challenge (requires CF_API_TOKEN in /etc/caddy/caddy.env):
#
#   example.com {
#       tls {
#           dns cloudflare {env.CF_API_TOKEN}
#       }
#       reverse_proxy localhost:8080
#   }

:80 {
	respond "Hello from Caddy!" 200
}
CADDYFILE
copy_if_missing "${CADDYFILE_TMP}" "${CADDYFILE}"
rm -f "${CADDYFILE_TMP}"
chown root:${CADDY_GROUP} "${CADDYFILE}"
chmod 0640 "${CADDYFILE}"

# Seed environment file — only on first install
ENV_TMP="$(mktemp)"
cat > "${ENV_TMP}" <<'ENVFILE'
# Cloudflare API token for DNS challenge (used by caddy-dns/cloudflare module).
# Generate a token at: https://dash.cloudflare.com/profile/api-tokens
# Required permissions: Zone / DNS / Edit
#CF_API_TOKEN=your-cloudflare-api-token-here
ENVFILE
copy_if_missing "${ENV_TMP}" "${ENV_FILE}"
rm -f "${ENV_TMP}"
chown root:${CADDY_GROUP} "${ENV_FILE}"
chmod 0640 "${ENV_FILE}"

# ---------------------------------------------------------------------------
# Populate CF_API_TOKEN if --cf-api-key was provided
# ---------------------------------------------------------------------------
if [[ -n "${CF_API_KEY}" ]]; then
	# Uncomment and set the token, or replace an existing value
	if grep -q '^CF_API_TOKEN=' "${ENV_FILE}" 2>/dev/null; then
		sed -i "s|^CF_API_TOKEN=.*|CF_API_TOKEN=${CF_API_KEY}|" "${ENV_FILE}"
		note "Updated CF_API_TOKEN in ${ENV_FILE}"
	elif grep -q '^#CF_API_TOKEN=' "${ENV_FILE}" 2>/dev/null; then
		sed -i "s|^#CF_API_TOKEN=.*|CF_API_TOKEN=${CF_API_KEY}|" "${ENV_FILE}"
		note "Set CF_API_TOKEN in ${ENV_FILE}"
	else
		printf '\nCF_API_TOKEN=%s\n' "${CF_API_KEY}" >> "${ENV_FILE}"
		note "Appended CF_API_TOKEN to ${ENV_FILE}"
	fi
fi

# ---------------------------------------------------------------------------
# Systemd service (always updated — part of the application surface)
# ---------------------------------------------------------------------------
note "Installing systemd service"
cat > "${SYSTEMD_DIR}/${SERVICE_NAME}" <<SERVICE
[Unit]
Description=Caddy reverse proxy
Documentation=https://caddyserver.com/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=${CADDY_USER}
Group=${CADDY_GROUP}
EnvironmentFile=-${ENV_FILE}

ExecStartPre=${INSTALL_DIR}/bin/caddy validate --config ${CADDYFILE}
ExecStart=${INSTALL_DIR}/bin/caddy run --environ --config ${CADDYFILE}
ExecReload=${INSTALL_DIR}/bin/caddy reload --config ${CADDYFILE} --force
TimeoutStopSec=5s

# Hardening
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
LimitNOFILE=1048576
LimitNPROC=512
NoNewPrivileges=yes
PrivateTmp=true
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/caddy

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=caddy

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
note "Enabled ${SERVICE_NAME}"
systemctl enable "${SERVICE_NAME}" --quiet

# ---------------------------------------------------------------------------
# Start or restart
# ---------------------------------------------------------------------------
if [[ "${SERVICE_WAS_ACTIVE}" == true ]]; then
	note "Restarting ${SERVICE_NAME} (was running before upgrade)"
	systemctl start "${SERVICE_NAME}"
else
	note "Starting ${SERVICE_NAME}"
	systemctl start "${SERVICE_NAME}"
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if systemctl is-active --quiet "${SERVICE_NAME}"; then
	note "Service is running"
else
	warn "Service failed to start — check: journalctl -u ${SERVICE_NAME}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
note "Installation complete!"
note ""
note "  Binary:      ${INSTALL_DIR}/bin/caddy"
note "  Symlink:     /usr/local/bin/caddy"
note "  Config:      ${CADDYFILE}"
note "  Environment: ${ENV_FILE}"
note "  Service:     ${SERVICE_NAME}"
note "  Data:        /var/lib/caddy/"
note ""
note "Useful commands:"
note "  systemctl status caddy        — check service status"
note "  journalctl -u caddy -f        — follow logs"
note "  caddy reload --config ${CADDYFILE}  — reload after config changes"
note "  caddy validate --config ${CADDYFILE} — validate config"
note ""
if [[ -z "${CF_API_KEY}" ]] && ! grep -q '^CF_API_TOKEN=' "${ENV_FILE}" 2>/dev/null; then
	note "To use the Cloudflare DNS module, set your API token:"
	note "  1. Edit ${ENV_FILE} and set CF_API_TOKEN=<your-token>"
	note "  2. Or re-run: ./caddy-installer.run --cf-api-key <your-token>"
fi

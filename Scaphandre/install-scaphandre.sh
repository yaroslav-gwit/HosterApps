#!/usr/bin/env bash

set -euo pipefail

# Installs or updates Scaphandre from an extracted .run payload. Re-running the
# installer replaces the binary and service unit with the bundled versions.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly PAYLOAD_DIR="${1:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}"
shift || true

readonly INSTALL_DIR="/opt/hoster/scaphandre"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly SERVICE_NAME="scaphandre.service"

C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RESET='\033[0m'

note() { printf "${C_GREEN}[%s]${C_RESET} %s\n" "${SCRIPT_NAME}" "$*"; }
warn() { printf "${C_YELLOW}[%s] Warning:${C_RESET} %s\n" "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

NO_START=false
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--no-start)
		NO_START=true
		shift
		;;
	*)
		die "Unknown argument: ${1}"
		;;
	esac
done

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root"
[[ -f "${PAYLOAD_DIR}/build-info.txt" ]] || die "build-info.txt not found in ${PAYLOAD_DIR}"
[[ -x "${PAYLOAD_DIR}/bin/scaphandre" ]] || die "scaphandre binary not found in ${PAYLOAD_DIR}/bin"
[[ -f "${PAYLOAD_DIR}/scaphandre.service" ]] || die "scaphandre.service not found in ${PAYLOAD_DIR}"
if [[ "${NO_START}" == false ]]; then
	command -v systemctl >/dev/null 2>&1 || die "systemctl is required unless --no-start is used"
fi

# shellcheck source=/dev/null
source "${PAYLOAD_DIR}/build-info.txt"

note "Installing Scaphandre ${SCAPHANDRE_VERSION} (built ${BUILD_DATE})"

SERVICE_WAS_ACTIVE=false
if [[ "${NO_START}" == false ]] && systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
	SERVICE_WAS_ACTIVE=true
	note "Stopping running ${SERVICE_NAME} for upgrade"
	systemctl stop "${SERVICE_NAME}"
fi

mkdir -p "${INSTALL_DIR}/bin"
install -m 0755 "${PAYLOAD_DIR}/bin/scaphandre" "${INSTALL_DIR}/bin/scaphandre"
install -m 0644 "${PAYLOAD_DIR}/build-info.txt" "${INSTALL_DIR}/build-info.txt"
ln -sf "${INSTALL_DIR}/bin/scaphandre" /usr/local/bin/scaphandre

note "Installed binary: ${INSTALL_DIR}/bin/scaphandre"
note "Symlinked: /usr/local/bin/scaphandre"
"${INSTALL_DIR}/bin/scaphandre" --version || die "Scaphandre binary failed to execute"

note "Installing systemd service"
install -m 0644 "${PAYLOAD_DIR}/scaphandre.service" "${SYSTEMD_DIR}/${SERVICE_NAME}"

if [[ "${NO_START}" == true ]]; then
	warn "Service was not enabled, started, or reloaded (--no-start)"
note "Run 'systemctl daemon-reload' before managing the service"
elif [[ "${SERVICE_WAS_ACTIVE}" == true ]]; then
	systemctl daemon-reload
	note "Enabling and restarting ${SERVICE_NAME}"
	systemctl enable "${SERVICE_NAME}" --quiet
	systemctl start "${SERVICE_NAME}"
else
	systemctl daemon-reload
	note "Enabling and starting ${SERVICE_NAME}"
	systemctl enable --now "${SERVICE_NAME}" --quiet
fi

if [[ "${NO_START}" == false ]]; then
	if systemctl is-active --quiet "${SERVICE_NAME}"; then
		note "Service is running"
	else
		warn "Service failed to start — check: journalctl -u ${SERVICE_NAME}"
	fi
fi

printf '\n'
note "Installation complete!"
note ""
note "  Binary:     ${INSTALL_DIR}/bin/scaphandre"
note "  Symlink:    /usr/local/bin/scaphandre"
note "  Build info: ${INSTALL_DIR}/build-info.txt"
note "  Service:    ${SYSTEMD_DIR}/${SERVICE_NAME}"
note "  Metrics:    http://localhost:1920/metrics"
note ""
note "Useful commands:"
note "  systemctl status scaphandre"
note "  journalctl -u scaphandre -f"

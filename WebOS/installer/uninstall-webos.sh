#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly CONFIG_DIR="/etc/hoster/webos"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} [--keep-config]

Stops WebOS and removes project-owned releases, systemd units and state.
The selected user's home and all container images/data are always preserved.
Installed distribution packages are not removed.

Options:
  --keep-config  Preserve /etc/hoster/webos for a later reinstall.
  -h, --help     Show this help.
USAGE
}

KEEP_CONFIG=false
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--keep-config) KEEP_CONFIG=true; shift ;;
	-h|--help) usage; exit 0 ;;
	*) die "Unknown option: ${1}" ;;
	esac
done

[[ "${EUID}" -eq 0 ]] || die "Run this uninstaller as root"

shopt -s nullglob
for user_config in "${CONFIG_DIR}"/users/*.env; do
	desktop_user="$(basename "${user_config}" .env)"
	service_instance="$(systemd-escape --template=webos@.service "${desktop_user}")"
	systemctl disable --now "${service_instance}" 2>/dev/null || true
done
shopt -u nullglob
# Upgrade compatibility for the original singleton configuration.
if [[ -r "${CONFIG_DIR}/webos.env" ]]; then
	desktop_user="$(sed -n 's/^WEBOS_USER=//p' "${CONFIG_DIR}/webos.env" | tail -n 1)"
	if [[ -n "${desktop_user}" ]]; then
		service_instance="$(systemd-escape --template=webos@.service "${desktop_user}")"
		systemctl disable --now "${service_instance}" 2>/dev/null || true
	fi
fi

rm -f \
	/etc/systemd/system/webos@.service \
	/usr/local/bin/webos \
	/usr/local/bin/webOS \
	/usr/local/sbin/webos-uninstall \
	/usr/share/bash-completion/completions/webos \
	/usr/share/bash-completion/completions/webOS \
	/usr/share/zsh/site-functions/_webos \
	/usr/share/zsh/site-functions/_webOS \
	/usr/share/fish/vendor_completions.d/webos.fish \
	/usr/share/fish/vendor_completions.d/webOS.fish \
	/etc/fonts/conf.d/69-hoster-webos-emoji.conf
rm -rf /opt/hoster/webos /var/lib/hoster/webos /var/log/hoster/webos
if [[ "${KEEP_CONFIG}" != true ]]; then
	rm -rf "${CONFIG_DIR}"
fi
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

note "Removed WebOS project files and all registered services"
note "User homes, sudo policy, distro packages, and container data were preserved"
if [[ "${KEEP_CONFIG}" == true ]]; then
	note "Preserved /etc/hoster/webos"
fi

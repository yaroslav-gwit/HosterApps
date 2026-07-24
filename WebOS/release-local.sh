#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME PROJECT_DIR
readonly DIST_DIR="${PROJECT_DIR}/dist"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

usage() {
	cat <<USAGE
Usage: ./${SCRIPT_NAME} [--engine docker|podman] [--version VERSION]

Builds and validates all three WebOS installers locally, then writes
dist/SHA256SUMS and dist/RELEASE_NOTES.md. Nothing is uploaded anywhere.
USAGE
}

VERSION="$(tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
ENGINE_ARGS=()
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--engine)
		[[ -n "${2:-}" ]] || die "--engine requires a value"
		ENGINE_ARGS=(--engine "${2}")
		shift 2
		;;
	--version)
		[[ -n "${2:-}" ]] || die "--version requires a value"
		VERSION="${2}"
		shift 2
		;;
	-h|--help)
		usage
		exit 0
		;;
	*) die "Unknown option: ${1}" ;;
	esac
done

"${PROJECT_DIR}/build.sh" --target all --version "${VERSION}" "${ENGINE_ARGS[@]}"

installers=(
	"${DIST_DIR}/webos-v${VERSION}-ubuntu-24.04-amd64.run"
	"${DIST_DIR}/webos-v${VERSION}-ubuntu-26.04-amd64.run"
	"${DIST_DIR}/webos-v${VERSION}-fedora-44-amd64.run"
)
for installer in "${installers[@]}"; do
	"${PROJECT_DIR}/tests/validate-installer.sh" "${installer}" "${VERSION}"
done

(
	cd "${DIST_DIR}"
	sha256sum "${installers[@]##*/}" > SHA256SUMS
)

{
	printf '# WebOS %s\n\n' "${VERSION}"
	printf 'WebOS turns a supported Linux VM into a persistent, browser-accessible '
	printf 'XFCE desktop. The streamed session runs as a real local user with its '
	printf 'normal home directory, sudo policy, systemd access, development tools, '
	printf 'and host Docker runtime.\n\n'
	printf 'This first WebOS release provides:\n\n'
	printf -- '- Native Selkies, Labwc, Xwayland, and XFCE sessions managed by systemd.\n'
	printf -- '- Self-contained installers for Ubuntu 24.04, Ubuntu 26.04, and Fedora 44.\n'
	printf -- '- Per-user HTTPS endpoints with self-signed certificates and browser authentication.\n'
	printf -- '- Multi-user service management through the `webos` operator utility.\n'
	printf -- '- A consistent Arc-Dark desktop, Papirus icons, Breeze cursors, polished XFCE panel, and WebOS branding.\n'
	printf -- '- Chrome, Firefox, VS Code, LibreOffice, GIMP, gThumb, VLC, gedit, Git, curl, and jq.\n'
	printf -- '- Pinned, containerized builds with offline Selkies Python payloads and native distro dependencies.\n\n'
	printf 'The implementation adapts Selkies and LinuxServer Wayland integration '
	printf 'patterns into a native host installation rather than running the user '
	printf 'desktop in a general-purpose container. Installers are idempotent, '
	printf 'preserve user data and administrator configuration, and were validated '
	printf 'on clean VMs for every supported platform.\n\n'
	printf '## Installers\n\n'
	for installer in "${installers[@]}"; do
		printf -- "- \`%s\`\n" "$(basename "${installer}")"
	done
	printf '\n## SHA-256\n\n```text\n'
	cat "${DIST_DIR}/SHA256SUMS"
	printf '```\n'
} > "${DIST_DIR}/RELEASE_NOTES.md"

note "Local release bundle is ready in ${DIST_DIR}"
note "No network release or upload action was performed"

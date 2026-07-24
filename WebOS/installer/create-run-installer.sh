#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly PAYLOAD_DIR="${PAYLOAD_DIR:-/build/payload}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-/build/out/webos-installer.run}"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -r "${PAYLOAD_DIR}/build-info.txt" ]] || die "Missing ${PAYLOAD_DIR}/build-info.txt"
[[ -x "${PAYLOAD_DIR}/install-webos.sh" ]] || die "Missing install-webos.sh"
[[ -x "${PAYLOAD_DIR}/uninstall-webos.sh" ]] || die "Missing uninstall-webos.sh"

WEBOS_VERSION="$(
	awk -F= '$1 == "WEBOS_VERSION" {
		sub(/^[^=]*=/, "")
		print
		exit
	}' "${PAYLOAD_DIR}/build-info.txt"
)"
[[ "${WEBOS_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] ||
	die "Invalid WEBOS_VERSION in build-info.txt"

work_dir="$(mktemp -d)"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

mkdir -p "$(dirname "${OUTPUT_FILE}")"
archive="${work_dir}/payload.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner \
	--mtime="@${SOURCE_DATE_EPOCH:-0}" -C "${PAYLOAD_DIR}" -cf - . |
	gzip -n -9 > "${archive}"

stub="${work_dir}/stub.sh"
cat > "${stub}" <<'STUB'
#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly WEBOS_VERSION="__WEBOS_VERSION__"
readonly ARCHIVE_LINE=__ARCHIVE_LINE__

usage() {
	cat <<USAGE
WebOS ${WEBOS_VERSION} installer

Usage: ./${SCRIPT_NAME} [OPTIONS]

Options:
  --help, -h          Show this help.
  --version           Print the embedded WebOS version.
  --extract DIR       Extract the payload without installing.
  --user USER         Select an existing non-root desktop user.
  --listen ADDRESS    Bind Selkies to ADDRESS (default: 127.0.0.1).
  --port PORT         Bind Selkies to PORT (default: first free port from 8081).
  --uninstall         Remove WebOS without deleting user/container data.
  --keep-config       With --uninstall, preserve /etc/hoster/webos.

Every session uses HTTPS with its own self-signed certificate. Installation
and uninstallation require root. Extraction does not.
USAGE
}

die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

extract_payload() {
	local destination="${1}"
	mkdir -p "${destination}"
	tail -n +"${ARCHIVE_LINE}" "$0" | tar -xzf - -C "${destination}"
}

case "${1:-}" in
-h|--help) usage; exit 0 ;;
--version) printf '%s\n' "${WEBOS_VERSION}"; exit 0 ;;
--extract)
	[[ -n "${2:-}" ]] || die "--extract requires a destination"
	extract_payload "${2}"
	printf '[%s] Extracted payload to %s\n' "${SCRIPT_NAME}" "${2}"
	exit 0
	;;
esac

[[ "${EUID}" -eq 0 ]] || die "Run as root, or use --extract to inspect the payload"

temporary="$(mktemp -d)"
cleanup() { rm -rf "${temporary}"; }
trap cleanup EXIT
extract_payload "${temporary}"

if [[ "${1:-}" == "--uninstall" ]]; then
	shift
	"${temporary}/uninstall-webos.sh" "$@"
	exit
fi
"${temporary}/install-webos.sh" "${temporary}" "$@"
exit 0
STUB

sed -i "s/__WEBOS_VERSION__/${WEBOS_VERSION}/g" "${stub}"
archive_line="$(( $(wc -l < "${stub}") + 1 ))"
sed "s/__ARCHIVE_LINE__/${archive_line}/" "${stub}" > "${OUTPUT_FILE}"
cat "${archive}" >> "${OUTPUT_FILE}"
chmod 0755 "${OUTPUT_FILE}"
note "Created ${OUTPUT_FILE}"

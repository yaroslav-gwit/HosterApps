#!/usr/bin/env bash

set -euo pipefail

# Creates a self-extracting .run installer from a pre-built Caddy binary.
# The resulting file can be copied to another Linux host and run as root to
# install Caddy with Cloudflare DNS and SSH modules.

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly CADDY_BINARY="${CADDY_BINARY:-/build/caddy}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-/build/_packages/caddy-installer.run}"
readonly OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -x "${CADDY_BINARY}" ]] || die "Caddy binary not found: ${CADDY_BINARY}"

# Detect version from the binary itself
CADDY_VERSION="$("${CADDY_BINARY}" version | awk '{print $1}')"
BUILD_DATE="$(date +%Y-%m-%d)"

note "Caddy version: ${CADDY_VERSION}"
note "Build date:    ${BUILD_DATE}"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

PAYLOAD_DIR="${WORK_DIR}/payload"
mkdir -p "${PAYLOAD_DIR}/bin" "${OUTPUT_DIR}"

# Copy the static binary
install -m 0755 "${CADDY_BINARY}" "${PAYLOAD_DIR}/bin/caddy"

# Embed version metadata
cat > "${PAYLOAD_DIR}/build-info.txt" <<EOF
CADDY_VERSION=${CADDY_VERSION}
BUILD_DATE=${BUILD_DATE}
EOF

# Copy the installer script into the payload
install -m 0755 "$(dirname "${BASH_SOURCE[0]}")/install-caddy.sh" "${PAYLOAD_DIR}/install-caddy.sh"

note "Creating compressed payload archive"
ARCHIVE_PATH="${WORK_DIR}/payload.tar.gz"
(cd "${PAYLOAD_DIR}" && tar -czf "${ARCHIVE_PATH}" .)

# Build the self-extracting stub
STUB_PATH="${WORK_DIR}/stub.sh"
cat > "${STUB_PATH}" <<'STUB'
#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly ARCHIVE_LINE=__ARCHIVE_LINE__

usage() {
	cat <<USAGE
Usage: ./${SCRIPT_NAME} [OPTIONS]

Options:
  --cf-api-key KEY   Set the Cloudflare API token in /etc/caddy/caddy.env.
  --extract DIR      Unpack the payload without installing it.
  -h, --help         Show this help text.

Without --extract, the archive installs Caddy into /opt/hoster/caddy/ and
therefore must be run as root.

The installer is idempotent:
  - First run:  installs binary, creates config, env file, and systemd service.
  - Next runs:  updates binary and service file; preserves Caddyfile and env.
USAGE
}

die() {
	printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2
	exit 1
}

extract_payload() {
	local destination="${1}"
	mkdir -p "${destination}"
	tail -n +"${ARCHIVE_LINE}" "$0" | tar -xzf - -C "${destination}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

if [[ "${1:-}" == "--extract" ]]; then
	[[ -n "${2:-}" ]] || die "--extract requires a destination directory"
	extract_payload "${2}"
	printf '[%s] Extracted payload to %s\n' "${SCRIPT_NAME}" "${2}"
	exit 0
fi

# Collect installer arguments (pass through to install-caddy.sh)
INSTALLER_ARGS=()
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--cf-api-key)
		[[ -n "${2:-}" ]] || die "--cf-api-key requires a value"
		INSTALLER_ARGS+=("--cf-api-key" "${2}")
		shift 2
		;;
	*)
		die "Unknown argument: ${1}"
		;;
	esac
done

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root, or use --extract to inspect it"

TMPDIR_PATH="$(mktemp -d)"
cleanup() { rm -rf "${TMPDIR_PATH}"; }
trap cleanup EXIT

extract_payload "${TMPDIR_PATH}"
"${TMPDIR_PATH}/install-caddy.sh" "${TMPDIR_PATH}" "${INSTALLER_ARGS[@]}"
exit 0
STUB

ARCHIVE_LINE="$(( $(wc -l < "${STUB_PATH}") + 1 ))"
sed "s/__ARCHIVE_LINE__/${ARCHIVE_LINE}/" "${STUB_PATH}" > "${OUTPUT_FILE}"
cat "${ARCHIVE_PATH}" >> "${OUTPUT_FILE}"
chmod +x "${OUTPUT_FILE}"

note "Created self-extracting installer: ${OUTPUT_FILE}"

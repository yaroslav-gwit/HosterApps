#!/usr/bin/env bash

set -euo pipefail

# Creates a self-extracting .run installer from the compiled QEMU tree at
# /opt/qemu. The resulting file can be copied to another Linux host and run
# as root to install QEMU into /opt/hoster/qemu/<version>_<date>/.

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly QEMU_PREFIX="${QEMU_PREFIX:-/opt/qemu}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-${QEMU_PREFIX}/_packages/qemu-installer.run}"
readonly OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -d "${QEMU_PREFIX}/bin" ]] || die "QEMU prefix not found: ${QEMU_PREFIX}/bin"
[[ -x "${QEMU_PREFIX}/bin/qemu-system-x86_64" ]] || die "qemu-system-x86_64 not found"

# Detect version from the binary itself
QEMU_RAW_VERSION="$("${QEMU_PREFIX}/bin/qemu-system-x86_64" --version | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')"
BUILD_DATE="$(date +%Y-%m-%d)"

note "QEMU version: ${QEMU_RAW_VERSION}"
note "Build date:   ${BUILD_DATE}"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

PAYLOAD_DIR="${WORK_DIR}/payload"
mkdir -p "${PAYLOAD_DIR}" "${OUTPUT_DIR}"

# Copy the entire QEMU installation tree into the payload
cp -a "${QEMU_PREFIX}/bin"       "${PAYLOAD_DIR}/bin"
cp -a "${QEMU_PREFIX}/firmware"  "${PAYLOAD_DIR}/firmware"

# Copy share dir (keymaps, QEMU device ROMs, etc.) if it exists
if [[ -d "${QEMU_PREFIX}/share" ]]; then
	cp -a "${QEMU_PREFIX}/share" "${PAYLOAD_DIR}/share"
fi

# Copy bundled libraries
if [[ -d "${QEMU_PREFIX}/lib" ]]; then
	cp -a "${QEMU_PREFIX}/lib" "${PAYLOAD_DIR}/lib"
fi

# Copy libexec (QEMU helper binaries like qemu-bridge-helper)
if [[ -d "${QEMU_PREFIX}/libexec" ]]; then
	cp -a "${QEMU_PREFIX}/libexec" "${PAYLOAD_DIR}/libexec"
fi

# Embed version metadata
cat > "${PAYLOAD_DIR}/build-info.txt" <<EOF
QEMU_VERSION=${QEMU_RAW_VERSION}
BUILD_DATE=${BUILD_DATE}
INSTALL_DIR_NAME=${QEMU_RAW_VERSION}_${BUILD_DATE}
EOF

# Copy the installer script into the payload
install -m 0755 "$(dirname "${BASH_SOURCE[0]}")/install-qemu.sh" "${PAYLOAD_DIR}/install-qemu.sh"

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
Usage: ./${SCRIPT_NAME} [--extract DIR]

Options:
  --extract DIR   Unpack the payload without installing it.
  -h, --help      Show this help text.

Without --extract, the archive installs QEMU into
/opt/hoster/qemu/<version>_<build-date>/ and therefore must be run as root.
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

[[ $# -eq 0 ]] || die "Unknown arguments: $*"
[[ "${EUID}" -eq 0 ]] || die "Run this installer as root, or use --extract to inspect it"

TMPDIR_PATH="$(mktemp -d)"
cleanup() { rm -rf "${TMPDIR_PATH}"; }
trap cleanup EXIT

extract_payload "${TMPDIR_PATH}"
"${TMPDIR_PATH}/install-qemu.sh" "${TMPDIR_PATH}"
exit 0
STUB

ARCHIVE_LINE="$(( $(wc -l < "${STUB_PATH}") + 1 ))"
sed "s/__ARCHIVE_LINE__/${ARCHIVE_LINE}/" "${STUB_PATH}" > "${OUTPUT_FILE}"
cat "${ARCHIVE_PATH}" >> "${OUTPUT_FILE}"
chmod +x "${OUTPUT_FILE}"

note "Created self-extracting installer: ${OUTPUT_FILE}"
note "Install directory will be: /opt/hoster/qemu/${QEMU_RAW_VERSION}_${BUILD_DATE}/"

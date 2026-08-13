#!/usr/bin/env bash

set -euo pipefail

# Creates a self-extracting .run installer from a compiled Scaphandre binary.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
readonly SCRIPT_DIR
readonly SCAPHANDRE_BINARY="${SCAPHANDRE_BINARY:-/build/scaphandre/target/release/scaphandre}"
readonly SCAPHANDRE_VERSION="${SCAPHANDRE_VERSION:-v1.0.3}"
readonly SCAPHANDRE_COMMIT="${SCAPHANDRE_COMMIT:-unknown}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-/build/_packages/scaphandre-installer.run}"
OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
readonly OUTPUT_DIR

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -x "${SCAPHANDRE_BINARY}" ]] || die "Scaphandre binary not found: ${SCAPHANDRE_BINARY}"
[[ -x "${SCRIPT_DIR}/install-scaphandre.sh" ]] || die "Installer script not found"
[[ -f "${SCRIPT_DIR}/scaphandre.service" ]] || die "Systemd service not found"

BINARY_VERSION="$("${SCAPHANDRE_BINARY}" --version | awk '{print $2}')"
RELEASE_VERSION="${SCAPHANDRE_VERSION#v}"
[[ "${BINARY_VERSION}" == "${RELEASE_VERSION}" ]] || \
	die "Binary version ${BINARY_VERSION} does not match ${RELEASE_VERSION}"
BUILD_DATE="$(date -u +%Y-%m-%d)"

note "Scaphandre version: ${RELEASE_VERSION}"
note "Upstream commit:    ${SCAPHANDRE_COMMIT}"
note "Build date:         ${BUILD_DATE}"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

PAYLOAD_DIR="${WORK_DIR}/payload"
mkdir -p "${PAYLOAD_DIR}/bin" "${OUTPUT_DIR}"

install -m 0755 "${SCAPHANDRE_BINARY}" "${PAYLOAD_DIR}/bin/scaphandre"
install -m 0755 "${SCRIPT_DIR}/install-scaphandre.sh" "${PAYLOAD_DIR}/install-scaphandre.sh"
install -m 0644 "${SCRIPT_DIR}/scaphandre.service" "${PAYLOAD_DIR}/scaphandre.service"

cat > "${PAYLOAD_DIR}/build-info.txt" <<EOF
SCAPHANDRE_VERSION=${RELEASE_VERSION}
SCAPHANDRE_UPSTREAM_TAG=${SCAPHANDRE_VERSION}
SCAPHANDRE_COMMIT=${SCAPHANDRE_COMMIT}
BUILD_DATE=${BUILD_DATE}
TARGET=x86_64-unknown-linux-musl
EOF

note "Creating compressed payload archive"
ARCHIVE_PATH="${WORK_DIR}/payload.tar.gz"
(cd "${PAYLOAD_DIR}" && tar -czf "${ARCHIVE_PATH}" .)

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
  --no-start     Install files without enabling or starting the systemd service.
  --extract DIR  Unpack the payload without installing it.
  -h, --help     Show this help text.

Without --extract, the archive installs Scaphandre into
/opt/hoster/scaphandre/ and must be run as root. Re-running it updates the
binary and service unit.
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
	[[ $# -eq 2 ]] || die "--extract cannot be combined with other arguments"
	extract_payload "${2}"
	printf '[%s] Extracted payload to %s\n' "${SCRIPT_NAME}" "${2}"
	exit 0
fi

INSTALLER_ARGS=()
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--no-start)
		INSTALLER_ARGS+=("--no-start")
		shift
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
"${TMPDIR_PATH}/install-scaphandre.sh" "${TMPDIR_PATH}" "${INSTALLER_ARGS[@]}"
exit 0
STUB

ARCHIVE_LINE="$(( $(wc -l < "${STUB_PATH}") + 1 ))"
sed "s/__ARCHIVE_LINE__/${ARCHIVE_LINE}/" "${STUB_PATH}" > "${OUTPUT_FILE}"
cat "${ARCHIVE_PATH}" >> "${OUTPUT_FILE}"
chmod +x "${OUTPUT_FILE}"

note "Created self-extracting installer: ${OUTPUT_FILE}"

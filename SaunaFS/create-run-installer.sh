#!/usr/bin/env bash

set -euo pipefail

# This helper turns a completed SaunaFS build tree into a self-extracting .run
# installer. The resulting file can be copied to another Linux host and run as
# root there; the embedded installer will unpack the staged filesystem tree and
# perform the same system-level setup as install-system.sh.

readonly SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "${SELF_PATH}")"
readonly SCRIPT_NAME="$(basename "${SELF_PATH}")"

usage() {
	cat <<EOF
Usage: ./${SCRIPT_NAME}

Optional environment variables:
  PROJECT_DIR=/path/to/saunafs-source
  BUILD_DIR=/path/to/build-tree
  OUTPUT_FILE=/path/to/saunafs-installer.run

The build tree must already exist and must have been configured with:
  -DCMAKE_INSTALL_PREFIX=/
EOF
}

note() {
	printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

die() {
	printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2
	exit 1
}

require_command() {
	command -v "${1}" >/dev/null 2>&1 || die "Required command not found: ${1}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

require_command cmake
require_command cp
require_command file
require_command ldd
require_command mktemp
require_command readlink
require_command sed
require_command tar
require_command wc

RAW_BUILD_DIR="${BUILD_DIR:-}"
if [[ -z "${RAW_BUILD_DIR}" ]]; then
	if [[ -d "${SCRIPT_DIR}/build" ]]; then
		RAW_BUILD_DIR="${SCRIPT_DIR}/build"
	elif [[ -d "${SCRIPT_DIR}/saunafs/build" ]]; then
		RAW_BUILD_DIR="${SCRIPT_DIR}/saunafs/build"
	else
		RAW_BUILD_DIR="${SCRIPT_DIR}/build"
	fi
fi
readonly BUILD_DIR="$(readlink -m "${RAW_BUILD_DIR}")"

[[ -d "${BUILD_DIR}" ]] || die "Build directory not found: ${BUILD_DIR}"
[[ -f "${BUILD_DIR}/cmake_install.cmake" ]] || die \
	"Missing ${BUILD_DIR}/cmake_install.cmake. Point BUILD_DIR at a finished CMake build tree."
[[ -f "${BUILD_DIR}/CMakeCache.txt" ]] || die \
	"Missing ${BUILD_DIR}/CMakeCache.txt. The build tree looks incomplete."

BUILD_SOURCE_DIR="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${BUILD_DIR}/CMakeCache.txt" | head -n1)"
BUILD_INSTALL_PREFIX="$(sed -n 's/^CMAKE_INSTALL_PREFIX:PATH=//p' "${BUILD_DIR}/CMakeCache.txt" | head -n1)"
[[ -n "${BUILD_INSTALL_PREFIX}" ]] || die \
	"Could not read CMAKE_INSTALL_PREFIX from ${BUILD_DIR}/CMakeCache.txt"
if [[ "${BUILD_INSTALL_PREFIX}" != "/" ]]; then
	die "This build tree uses CMAKE_INSTALL_PREFIX=${BUILD_INSTALL_PREFIX}. Rebuild it with -DCMAKE_INSTALL_PREFIX=/ before packaging a .run installer."
fi

RAW_PROJECT_DIR="${PROJECT_DIR:-${BUILD_SOURCE_DIR:-}}"
if [[ -z "${RAW_PROJECT_DIR}" ]]; then
	if [[ -d "${SCRIPT_DIR}/rpm/service-files" ]]; then
		RAW_PROJECT_DIR="${SCRIPT_DIR}"
	elif [[ -d "${SCRIPT_DIR}/saunafs/rpm/service-files" ]]; then
		RAW_PROJECT_DIR="${SCRIPT_DIR}/saunafs"
	else
		die "Could not determine the SaunaFS source directory. Set PROJECT_DIR=/path/to/saunafs-source."
	fi
fi
readonly PROJECT_DIR="$(readlink -f "${RAW_PROJECT_DIR}")"
readonly OUTPUT_FILE="$(readlink -m "${OUTPUT_FILE:-${PROJECT_DIR}/_packages/saunafs-installer.run}")"
readonly OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
readonly SERVICE_FILES_DIR="${PROJECT_DIR}/rpm/service-files"

[[ -d "${SERVICE_FILES_DIR}" ]] || die "Service files directory not found: ${SERVICE_FILES_DIR}"

WORK_DIR="$(mktemp -d)"
cleanup() {
	rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

PAYLOAD_DIR="${WORK_DIR}/payload"
STAGED_ROOT="${PAYLOAD_DIR}/rootfs"
SUPPORT_DIR="${PAYLOAD_DIR}/support"
ARCHIVE_PATH="${WORK_DIR}/payload.tar.gz"
STUB_PATH="${WORK_DIR}/stub.sh"

mkdir -p "${STAGED_ROOT}" "${SUPPORT_DIR}/service-files"
mkdir -p "${OUTPUT_DIR}"

# Stage the already-built installation tree under a temporary DESTDIR so the
# final .run file contains ready-to-copy /usr, /etc, and /var content.
note "Staging installed files from ${BUILD_DIR}"
DESTDIR="${STAGED_ROOT}" cmake --install "${BUILD_DIR}"

# ---------------------------------------------------------------------------
# Bundle shared library dependencies that may not exist (or may exist with
# incompatible versions) on target distros such as Rocky Linux.  We scan every
# ELF binary/library we just staged, collect their resolved shared-lib paths
# from the *build* host, and copy everything that is not part of glibc or the
# Linux dynamic linker into the payload.  Bundled libraries are kept private
# to SaunaFS via LD_LIBRARY_PATH wrapper scripts — no global ldconfig changes.
# ---------------------------------------------------------------------------
readonly BUNDLE_LIB_DIR="${STAGED_ROOT}/usr/lib/saunafs/bundled"
readonly LIBEXEC_DIR="${STAGED_ROOT}/usr/lib/saunafs/libexec"

is_glibc_or_system_lib() {
	case "${1}" in
	# glibc core
	*/libc.so*|*/libm.so*|*/libdl.so*|*/librt.so*|*/libpthread.so*|\
	*/libutil.so*|*/libresolv.so*|*/libnss_*.so*|*/libnsl.so*|\
	*/libmvec.so*|*/libBrokenLocale.so*|*/libanl.so*|*/libcrypt.so*)
		return 0 ;;
	# dynamic linker
	*/ld-linux*) return 0 ;;
	# kernel virtual DSO
	linux-vdso.so*) return 0 ;;
	# PAM and authentication — bundling these from the build host breaks
	# login on the target (e.g. Rocky) because PAM modules load them too.
	*/libpam.so*|*/libpam_misc.so*|*/libaudit.so*|*/libcap.so*|\
	*/libcap-ng.so*)
		return 0 ;;
	# systemd, SELinux, and core security libraries — same risk as PAM:
	# the target's own modules expect the distro-native copies.
	*/libsystemd.so*|*/libselinux.so*|*/libsepol.so*|\
	*/libgcrypt.so*|*/libgpg-error.so*|*/libkeyutils.so*|\
	*/libkrb5.so*|*/libgssapi_krb5.so*|*/libk5crypto.so*|\
	*/libcom_err.so*|*/libkrb5support.so*)
		return 0 ;;
	# TLS/crypto — mismatched OpenSSL breaks every TLS consumer on the host.
	*/libssl.so*|*/libcrypto.so*)
		return 0 ;;
	# Compression and low-level utilities commonly present on every distro.
	*/libz.so*|*/liblzma.so*|*/liblz4.so*|*/libzstd.so*|\
	*/libbz2.so*|*/libpcre*.so*|*/libexpat.so*|\
	*/libblkid.so*|*/libmount.so*|*/libuuid.so*)
		return 0 ;;
	esac
	return 1
}

bundle_shared_libraries() {
	local -A lib_paths=()
	local binary="" lib_line="" lib_path=""

	# Collect every ELF executable and shared object from the staged tree.
	while IFS= read -r binary; do
		[[ -f "${binary}" ]] || continue
		# Skip non-ELF files quickly.
		file -b "${binary}" | grep -q 'ELF' || continue

		while IFS= read -r lib_line; do
			# ldd output lines look like:
			#   libfoo.so.1 => /usr/lib/x86_64-linux-gnu/libfoo.so.1 (0x...)
			lib_path="$(printf '%s' "${lib_line}" | sed -n 's/^.*=> \(\/[^ ]*\) (.*/\1/p')"
			[[ -n "${lib_path}" ]] || continue
			is_glibc_or_system_lib "${lib_path}" && continue
			lib_paths["${lib_path}"]=1
		done < <(ldd "${binary}" 2>/dev/null || true)
	done < <(find "${STAGED_ROOT}" -type f \( -executable -o -name '*.so' -o -name '*.so.*' \))

	if [[ ${#lib_paths[@]} -eq 0 ]]; then
		note "No extra shared libraries to bundle"
		return
	fi

	mkdir -p "${BUNDLE_LIB_DIR}"
	for lib_path in "${!lib_paths[@]}"; do
		# Resolve symlinks so we copy the actual file, then recreate the
		# symlink structure the linker expects (libfoo.so.1 -> libfoo.so.1.2.3).
		local real_path
		real_path="$(readlink -f "${lib_path}")"
		local base_name
		base_name="$(basename "${lib_path}")"
		local real_name
		real_name="$(basename "${real_path}")"

		if [[ ! -e "${BUNDLE_LIB_DIR}/${real_name}" ]]; then
			cp -L "${real_path}" "${BUNDLE_LIB_DIR}/${real_name}"
			chmod 0755 "${BUNDLE_LIB_DIR}/${real_name}"
		fi
		if [[ "${base_name}" != "${real_name}" && ! -e "${BUNDLE_LIB_DIR}/${base_name}" ]]; then
			ln -sf "${real_name}" "${BUNDLE_LIB_DIR}/${base_name}"
		fi
	done

	note "Bundled $(find "${BUNDLE_LIB_DIR}" -type f | wc -l) shared libraries into the payload"
}

# ---------------------------------------------------------------------------
# Replace staged ELF binaries in usr/bin/ and usr/sbin/ with thin wrapper
# scripts that set LD_LIBRARY_PATH to the bundled directory before exec'ing
# the real binary from usr/lib/saunafs/libexec/.  This keeps bundled
# libraries private to SaunaFS processes — identical to the QEMU approach.
# ---------------------------------------------------------------------------
relocate_binaries_and_create_wrappers() {
	local dir="" binary="" bin_name=""
	local -a staged_dirs=(
		"${STAGED_ROOT}/usr/bin"
		"${STAGED_ROOT}/usr/sbin"
	)

	mkdir -p "${LIBEXEC_DIR}"

	for dir in "${staged_dirs[@]}"; do
		[[ -d "${dir}" ]] || continue

		for binary in "${dir}/"*; do
			[[ -f "${binary}" ]] || continue
			# Only wrap actual ELF executables; skip scripts and other files.
			file -b "${binary}" | grep -q 'ELF' || continue

			bin_name="$(basename "${binary}")"
			mv "${binary}" "${LIBEXEC_DIR}/${bin_name}"

			cat > "${binary}" <<'WRAPPER'
#!/usr/bin/env bash
_SAUNAFS_BUNDLED="/usr/lib/saunafs/bundled"
if [ -d "$_SAUNAFS_BUNDLED" ]; then
    export LD_LIBRARY_PATH="${_SAUNAFS_BUNDLED}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
exec /usr/lib/saunafs/libexec/__BIN_NAME__ "$@"
WRAPPER
			sed -i "s/__BIN_NAME__/${bin_name}/" "${binary}"
			chmod +x "${binary}"
		done
	done

	note "Relocated ELF binaries to libexec/ and created LD_LIBRARY_PATH wrappers"
}

bundle_shared_libraries
relocate_binaries_and_create_wrappers

install -m 0755 "${SCRIPT_DIR}/install-bundle.sh" "${SUPPORT_DIR}/install-bundle.sh"
install -m 0644 "${SCRIPT_DIR}/install-layout-common.sh" "${SUPPORT_DIR}/install-layout-common.sh"

# Preserve the full service-files directory contents, including the helper
# symlink shipped by the upstream package layout.
cp -a "${SERVICE_FILES_DIR}/." "${SUPPORT_DIR}/service-files/"

cat > "${SUPPORT_DIR}/build-info.txt" <<EOF
BUILD_DIR=${BUILD_DIR}
CMAKE_INSTALL_PREFIX=${BUILD_INSTALL_PREFIX}
OUTPUT_FILE=${OUTPUT_FILE}
EOF

note "Creating compressed payload archive"
(
	cd "${PAYLOAD_DIR}"
	tar -czf "${ARCHIVE_PATH}" .
)

cat > "${STUB_PATH}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

# Self-extracting SaunaFS installer archive.

readonly SCRIPT_NAME="$(basename "$0")"
readonly ARCHIVE_LINE=__ARCHIVE_LINE__

usage() {
	cat <<USAGE
Usage: ./${SCRIPT_NAME} [--extract DIR]

Options:
  --extract DIR   Unpack the payload without installing it.
  -h, --help      Show this help text.

Without --extract, the archive installs SaunaFS into / and therefore must be
run as root.
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
cleanup() {
	rm -rf "${TMPDIR_PATH}"
}
trap cleanup EXIT

extract_payload "${TMPDIR_PATH}"
"${TMPDIR_PATH}/support/install-bundle.sh" "${TMPDIR_PATH}"
exit 0
EOF

ARCHIVE_LINE="$(( $(wc -l < "${STUB_PATH}") + 1 ))"
sed "s/__ARCHIVE_LINE__/${ARCHIVE_LINE}/" "${STUB_PATH}" > "${OUTPUT_FILE}"
cat "${ARCHIVE_PATH}" >> "${OUTPUT_FILE}"
chmod +x "${OUTPUT_FILE}"

note "Created self-extracting installer: ${OUTPUT_FILE}"

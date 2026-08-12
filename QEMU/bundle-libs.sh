#!/usr/bin/env bash

set -euo pipefail

# Scans all ELF binaries under a given prefix and bundles their non-glibc
# shared library dependencies into <prefix>/lib/bundled/.

readonly PREFIX="${1:?Usage: bundle-libs.sh /opt/qemu}"
readonly BUNDLE_DIR="${PREFIX}/lib/bundled"
readonly LICENSE_DIR="${PREFIX}/licenses/system-libraries"
SEARCH_DIRS=("${PREFIX}/bin" "${PREFIX}/libexec" "${PREFIX}/lib")

iter_elf_files() {
	find "${SEARCH_DIRS[@]}" -type f \( -executable -o -name '*.so' -o -name '*.so.*' \) 2>/dev/null
}

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
	# PAM, authentication, and audit — should never be bundled across distros.
	*/libpam.so*|*/libpam_misc.so*|*/libaudit.so*|*/libcap.so*)
		return 0 ;;
	# systemd, SELinux, and core security libraries.
	*/libsystemd.so*|*/libselinux.so*|*/libsepol.so*|\
	*/libgcrypt.so*|*/libgpg-error.so*)
		return 0 ;;
	# TLS/crypto — the target distro's own copies should be used.
	*/libssl.so*|*/libcrypto.so*)
		return 0 ;;
	# Compression and low-level utilities commonly present on Linux hosts.
	# Keep libbz2 bundled: some target systems do not install it by default.
	*/libz.so*|*/liblzma.so*|*/liblz4.so*|*/libzstd.so*|\
	*/libpcre*.so*|\
	*/libblkid.so*|*/libmount.so*|*/libuuid.so*)
		return 0 ;;
	esac
	return 1
}

declare -A lib_paths=()

while IFS= read -r binary; do
	[[ -f "${binary}" ]] || continue
	file -b "${binary}" | grep -q 'ELF' || continue

	while IFS= read -r lib_line; do
		lib_path="$(printf '%s' "${lib_line}" | sed -n 's/^.*=> \(\/[^ ]*\) (.*/\1/p')"
		[[ -n "${lib_path}" ]] || continue
		is_glibc_or_system_lib "${lib_path}" && continue
		lib_paths["${lib_path}"]=1
	done < <(ldd "${binary}" 2>/dev/null || true)
done < <(iter_elf_files)

if [[ ${#lib_paths[@]} -eq 0 ]]; then
	echo "[bundle-libs] No extra shared libraries to bundle"
	exit 0
fi

mkdir -p "${BUNDLE_DIR}"
mkdir -p "${LICENSE_DIR}"
for lib_path in "${!lib_paths[@]}"; do
	real_path="$(readlink -f "${lib_path}")"
	base_name="$(basename "${lib_path}")"
	real_name="$(basename "${real_path}")"

	if [[ ! -e "${BUNDLE_DIR}/${real_name}" ]]; then
		cp -L "${real_path}" "${BUNDLE_DIR}/${real_name}"
		chmod 0755 "${BUNDLE_DIR}/${real_name}"
	fi
	if [[ "${base_name}" != "${real_name}" && ! -e "${BUNDLE_DIR}/${base_name}" ]]; then
		ln -sf "${real_name}" "${BUNDLE_DIR}/${base_name}"
	fi

	# Preserve the distro copyright notice for every bundled system library.
	package_name="$({
		dpkg-query --search "${lib_path}" 2>/dev/null || \
			dpkg-query --search "*/${real_name}" 2>/dev/null || true
	} | sed -n '1s/:.*//p')"
	if [[ -n "${package_name}" && -f "/usr/share/doc/${package_name}/copyright" ]]; then
		cp "/usr/share/doc/${package_name}/copyright" \
			"${LICENSE_DIR}/${package_name}.copyright"
	fi
done

while IFS= read -r binary; do
	[[ -f "${binary}" ]] || continue
	file -b "${binary}" | grep -q 'ELF' || continue

	while IFS= read -r lib_line; do
		lib_path="$(printf '%s' "${lib_line}" | sed -n 's/^.*=> \(\/[^ ]*\) (.*/\1/p')"
		[[ -n "${lib_path}" ]] || continue
		is_glibc_or_system_lib "${lib_path}" && continue

		lib_name="$(basename "${lib_path}")"
		if [[ ! -e "${BUNDLE_DIR}/${lib_name}" ]]; then
			echo "[bundle-libs] Missing bundled dependency ${lib_name} required by ${binary}" >&2
			exit 1
		fi
	done < <(ldd "${binary}" 2>/dev/null || true)
done < <(iter_elf_files)

echo "[bundle-libs] Bundled $(find "${BUNDLE_DIR}" -type f | wc -l) shared libraries"

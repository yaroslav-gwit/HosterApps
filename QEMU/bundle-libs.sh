#!/usr/bin/env bash

set -euo pipefail

# Scans all ELF binaries under a given prefix and bundles their non-glibc
# shared library dependencies into <prefix>/lib/bundled/.

readonly PREFIX="${1:?Usage: bundle-libs.sh /opt/qemu}"
readonly BUNDLE_DIR="${PREFIX}/lib/bundled"

is_glibc_or_system_lib() {
	case "${1}" in
	*/libc.so*|*/libm.so*|*/libdl.so*|*/librt.so*|*/libpthread.so*|\
	*/libutil.so*|*/libresolv.so*|*/libnss_*.so*|*/libnsl.so*|\
	*/libmvec.so*|*/libBrokenLocale.so*|*/libanl.so*|*/libcrypt.so*)
		return 0 ;;
	*/ld-linux*) return 0 ;;
	linux-vdso.so*) return 0 ;;
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
done < <(find "${PREFIX}/bin" "${PREFIX}/lib" -type f \( -executable -o -name '*.so' -o -name '*.so.*' \) 2>/dev/null)

if [[ ${#lib_paths[@]} -eq 0 ]]; then
	echo "[bundle-libs] No extra shared libraries to bundle"
	exit 0
fi

mkdir -p "${BUNDLE_DIR}"
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
done

echo "[bundle-libs] Bundled $(find "${BUNDLE_DIR}" -type f | wc -l) shared libraries"

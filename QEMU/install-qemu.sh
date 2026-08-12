#!/usr/bin/env bash

set -euo pipefail

# Installs the extracted QEMU payload into /opt/hoster/qemu/<version>_<date>/.
# Called by the self-extracting .run stub, or can be run manually on an
# already-extracted payload directory.

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly PAYLOAD_DIR="${1:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}"
readonly HOSTER_QEMU_BASE="/opt/hoster/qemu"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
warn() { printf '[%s] Warning: %s\n' "${SCRIPT_NAME}" "$*"; }
die()  { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root"
[[ -f "${PAYLOAD_DIR}/build-info.txt" ]] || die "build-info.txt not found in ${PAYLOAD_DIR}"

# Read version metadata
# shellcheck source=/dev/null
source "${PAYLOAD_DIR}/build-info.txt"

readonly INSTALL_DIR="${HOSTER_QEMU_BASE}/${INSTALL_DIR_NAME}"

# Validate the complete payload before replacing an installation produced by
# another build on the same day.
for dir in bin libexec firmware share/qemu lib/bundled licenses; do
	[[ -d "${PAYLOAD_DIR}/${dir}" ]] || die "Missing payload directory: ${dir}"
done
for bin_name in qemu-system-x86_64 qemu-img qemu-nbd swtpm virtiofsd; do
	[[ -x "${PAYLOAD_DIR}/bin/${bin_name}" ]] || die "Missing payload wrapper: ${bin_name}"
	[[ -x "${PAYLOAD_DIR}/libexec/${bin_name}" ]] || die "Missing payload binary: ${bin_name}"
done
for fw_name in bios-256k.bin OVMF_CODE_4M.fd OVMF_CODE_4M.secboot.fd OVMF_VARS_4M.fd OVMF_VARS_4M.ms.fd; do
	[[ -f "${PAYLOAD_DIR}/firmware/${fw_name}" ]] || die "Missing payload firmware: ${fw_name}"
done

if [[ -d "${INSTALL_DIR}" ]]; then
	warn "Install directory already exists: ${INSTALL_DIR}"
	warn "Overwriting existing installation"
	rm -rf "${INSTALL_DIR}"
fi

note "Installing QEMU ${QEMU_VERSION} (built ${BUILD_DATE}) into ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# Copy all payload directories into the install target
for dir in bin libexec firmware share lib licenses; do
	if [[ -d "${PAYLOAD_DIR}/${dir}" ]]; then
		cp -a "${PAYLOAD_DIR}/${dir}" "${INSTALL_DIR}/${dir}"
	fi
done

# Copy build metadata
install -m 0644 "${PAYLOAD_DIR}/build-info.txt" "${INSTALL_DIR}/build-info.txt"

# ---------------------------------------------------------------------------
# Bundled libraries are kept private to QEMU binaries. The wrapper scripts
# in bin/ set LD_LIBRARY_PATH to lib/bundled/ before exec'ing the real
# binary from libexec/. No global ldconfig or ld.so.conf.d changes are made.
# ---------------------------------------------------------------------------

# Clean up any global linker config from previous installer versions
if [[ -f "/etc/ld.so.conf.d/hoster-qemu.conf" ]]; then
	note "Removing legacy /etc/ld.so.conf.d/hoster-qemu.conf"
	rm -f "/etc/ld.so.conf.d/hoster-qemu.conf"
	command -v ldconfig >/dev/null 2>&1 && ldconfig
fi

# ---------------------------------------------------------------------------
# Launchers in /opt/hoster/qemu/bin/ that always dispatch through the latest
# installed version's wrapper scripts.
# ---------------------------------------------------------------------------
readonly SYMLINK_BIN="${HOSTER_QEMU_BASE}/bin"
mkdir -p "${SYMLINK_BIN}"

# Switch the complete versioned tree through one symlink. Convenience launchers
# below deliberately execute through latest so rollback is atomic for binaries,
# libraries, firmware, and data files. Launchers are used instead of direct
# symlinks because wrappers shipped before 11.1.0 derived their library path
# from $0 and therefore failed when invoked through a differently located
# symlink.
ln -sfn "${INSTALL_DIR}" "${HOSTER_QEMU_BASE}/latest"

for wrapper in "${INSTALL_DIR}/bin/"*; do
	[[ -f "${wrapper}" && -x "${wrapper}" ]] || continue
	local_name="$(basename "${wrapper}")"
	rm -f "${SYMLINK_BIN}/${local_name}"
	cat > "${SYMLINK_BIN}/${local_name}" <<'WRAPPER'
#!/usr/bin/env bash
exec "/opt/hoster/qemu/latest/bin/__BIN_NAME__" "$@"
WRAPPER
	sed -i "s/__BIN_NAME__/${local_name}/" "${SYMLINK_BIN}/${local_name}"
	chmod 0755 "${SYMLINK_BIN}/${local_name}"
done

# ---------------------------------------------------------------------------
# Verify key binaries
# ---------------------------------------------------------------------------
note "Verifying installed binaries..."
for bin_name in qemu-system-x86_64 qemu-img qemu-nbd swtpm virtiofsd; do
	if [[ -x "${INSTALL_DIR}/libexec/${bin_name}" && -x "${INSTALL_DIR}/bin/${bin_name}" ]]; then
		note "  OK: ${bin_name}"
	else
		warn "  MISSING: ${bin_name}"
	fi
done

# Verify firmware files
note "Verifying firmware files..."
for fw_name in bios-256k.bin OVMF_CODE_4M.fd OVMF_CODE_4M.secboot.fd OVMF_VARS_4M.fd OVMF_VARS_4M.ms.fd; do
	if [[ -f "${INSTALL_DIR}/firmware/${fw_name}" ]]; then
		note "  OK: ${fw_name}"
	else
		warn "  MISSING: ${fw_name}"
	fi
done

printf '\n'
note "Installation complete: ${INSTALL_DIR}"
note ""
note "Directory layout:"
note "  ${INSTALL_DIR}/bin/              — wrapper scripts (set LD_LIBRARY_PATH privately)"
note "  ${INSTALL_DIR}/libexec/          — real QEMU, swtpm, virtiofsd binaries"
note "  ${INSTALL_DIR}/firmware/         — OVMF and SeaBIOS firmware files"
note "  ${INSTALL_DIR}/share/qemu/       — QEMU data files (keymaps, device ROMs)"
note "  ${INSTALL_DIR}/lib/bundled/      — bundled shared libraries (private to QEMU)"
note "  ${INSTALL_DIR}/licenses/         — source and bundled-library license notices"
note ""
note "Convenience paths:"
note "  ${HOSTER_QEMU_BASE}/latest/      — always points to the most recent install"
note "  ${HOSTER_QEMU_BASE}/bin/         — launchers for latest version's binaries"
note ""
note "To use with Hoster, update the binary/firmware lookup paths to:"
note "  Binary:   ${INSTALL_DIR}/bin/qemu-system-x86_64"
note "  Firmware: ${INSTALL_DIR}/firmware/"

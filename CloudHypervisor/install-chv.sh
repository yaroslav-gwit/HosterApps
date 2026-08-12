#!/usr/bin/env bash

set -euo pipefail

# Installs the extracted Cloud Hypervisor payload into
# /opt/hoster/cloud-hypervisor/<version>_<date>/.

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly PAYLOAD_DIR="${1:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}"
readonly HOSTER_CHV_BASE="/opt/hoster/cloud-hypervisor"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
warn() { printf '[%s] Warning: %s\n' "${SCRIPT_NAME}" "$*"; }
die()  { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root"
[[ -f "${PAYLOAD_DIR}/build-info.txt" ]] || die "build-info.txt not found in ${PAYLOAD_DIR}"

# Read version metadata
# shellcheck source=/dev/null
source "${PAYLOAD_DIR}/build-info.txt"

readonly INSTALL_DIR="${HOSTER_CHV_BASE}/${INSTALL_DIR_NAME}"

# Validate the complete payload before replacing an installation from another
# build made on the same day.
for bin_name in cloud-hypervisor ch-remote virtiofsd; do
	[[ -x "${PAYLOAD_DIR}/bin/${bin_name}" ]] || die "Missing payload binary: ${bin_name}"
done
for fw_name in CLOUDHV_EFI.fd CLOUDHV.fd; do
	[[ -f "${PAYLOAD_DIR}/firmware/${fw_name}" ]] || die "Missing payload firmware: ${fw_name}"
done
for library in libseccomp.so.2 libcap-ng.so.0 libgcc_s.so.1; do
	[[ -f "${PAYLOAD_DIR}/lib/${library}" ]] || die "Missing payload library: ${library}"
done
[[ -d "${PAYLOAD_DIR}/licenses" ]] || die "Missing payload license directory"

if [[ -d "${INSTALL_DIR}" ]]; then
	warn "Install directory already exists: ${INSTALL_DIR}"
	warn "Overwriting existing installation"
	rm -rf "${INSTALL_DIR}"
fi

note "Installing Cloud Hypervisor ${CHV_VERSION} (built ${BUILD_DATE}) into ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# Copy payload directories
for dir in bin firmware lib licenses; do
	if [[ -d "${PAYLOAD_DIR}/${dir}" ]]; then
		cp -a "${PAYLOAD_DIR}/${dir}" "${INSTALL_DIR}/${dir}"
	fi
done

# Copy build metadata
install -m 0644 "${PAYLOAD_DIR}/build-info.txt" "${INSTALL_DIR}/build-info.txt"

# ---------------------------------------------------------------------------
# Convenience symlinks
# ---------------------------------------------------------------------------
readonly SYMLINK_BIN="${HOSTER_CHV_BASE}/bin"
mkdir -p "${SYMLINK_BIN}"
for binary in "${INSTALL_DIR}/bin/"*; do
	[[ -f "${binary}" && -x "${binary}" ]] || continue
	local_name="$(basename "${binary}")"
	ln -sfn "../latest/bin/${local_name}" "${SYMLINK_BIN}/${local_name}"
done

# Symlink the "latest" directory
ln -sfn "${INSTALL_DIR}" "${HOSTER_CHV_BASE}/latest"

# Legacy firmware paths used by existing Hoster installations.
readonly LEGACY_FIRMWARE_DIR="/opt/hoster/firmware"
mkdir -p "${LEGACY_FIRMWARE_DIR}"
for fw_name in CLOUDHV_EFI.fd CLOUDHV.fd; do
	ln -sfn "${HOSTER_CHV_BASE}/latest/firmware/${fw_name}" \
		"${LEGACY_FIRMWARE_DIR}/${fw_name}"
done

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
note "Verifying installed binaries..."
for bin_name in cloud-hypervisor ch-remote virtiofsd; do
	if [[ -x "${INSTALL_DIR}/bin/${bin_name}" ]]; then
		note "  OK: ${bin_name}"
	else
		warn "  MISSING: ${bin_name}"
	fi
done

note "Verifying firmware files..."
for fw_name in CLOUDHV_EFI.fd CLOUDHV.fd; do
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
note "  ${INSTALL_DIR}/bin/              — cloud-hypervisor, ch-remote, virtiofsd"
note "  ${INSTALL_DIR}/lib/              — private virtiofsd shared libraries"
note "  ${INSTALL_DIR}/firmware/         — CLOUDHV_EFI.fd, CLOUDHV.fd"
note "  ${INSTALL_DIR}/licenses/         — bundled-library license notices"
note ""
note "Convenience symlinks:"
note "  ${HOSTER_CHV_BASE}/latest/       — always points to the most recent install"
note "  ${HOSTER_CHV_BASE}/bin/          — symlinks to latest version's binaries"
note "  /opt/hoster/firmware/            — firmware symlinks (backwards compatible)"

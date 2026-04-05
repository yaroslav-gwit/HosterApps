#!/usr/bin/env bash

set -euo pipefail

# This helper is meant to run from inside the extracted .run payload. It copies
# the staged filesystem tree into / and then performs the same system user,
# service-unit, and default-config setup as the build-tree installer.

readonly SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "${SELF_PATH}")"
readonly SCRIPT_NAME="$(basename "${SELF_PATH}")"
readonly PAYLOAD_DIR="${1:-$(readlink -f "${SCRIPT_DIR}/..")}"
readonly PAYLOAD_ROOT="${PAYLOAD_DIR}/rootfs"
readonly SYSTEMD_UNIT_DIR="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}"
readonly SERVICE_FILES_DIR="${PAYLOAD_DIR}/support/service-files"

source "${SCRIPT_DIR}/install-layout-common.sh"

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root"

require_command tar
[[ -d "${PAYLOAD_ROOT}" ]] || die "Payload root not found: ${PAYLOAD_ROOT}"

create_service_account

# Detect services that are currently running so we can safely stop them before
# overwriting binaries and restart them once the upgrade is complete.
detect_active_services
stop_active_services

# Use a tar pipe rather than cp so permissions, symlinks, and ownership from the
# staged install tree are preserved as faithfully as possible.
note "Copying the staged SaunaFS filesystem tree into /"
(
	cd "${PAYLOAD_ROOT}"
	tar -cpf - .
) | (
	cd /
	tar -xpf -
)

prepare_runtime_layout
refresh_dynamic_linker_cache
ensure_runtime_dependencies
install_service_units
seed_default_configs
seed_initial_metadata
reload_systemd_units
restart_previously_active_services
print_next_steps

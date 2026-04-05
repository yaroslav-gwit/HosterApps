#!/usr/bin/env bash

set -euo pipefail

# This helper installs SaunaFS from an already-prepared CMake build tree.
# It does not compile anything on the host. The intended flow is:
#   1. build SaunaFS in Docker
#   2. copy the build tree (and optionally the upstream source checkout) to the
#      target host
#   3. run this script as root on the target Linux/systemd host
#
# The build tree must have been configured with CMAKE_INSTALL_PREFIX=/ because
# SaunaFS binaries embed default config/data paths such as /etc/saunafs and
# /var/lib/saunafs at compile time.

readonly SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "${SELF_PATH}")"
readonly SCRIPT_NAME="$(basename "${SELF_PATH}")"
readonly SYSTEMD_UNIT_DIR="${SYSTEMD_UNIT_DIR:-/etc/systemd/system}"

usage() {
	cat <<EOF
Usage: sudo ./${SCRIPT_NAME}

Optional environment variables:
  PROJECT_DIR=/path/to/saunafs-source
  BUILD_DIR=/path/to/build-tree
  SYSTEMD_UNIT_DIR=/etc/systemd/system
  SAUNAFS_INSTALL_RUNTIME_DEPS=1

The script intentionally does not enable or start services automatically.
It installs the files and prints the next manual steps at the end.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

source "${SCRIPT_DIR}/install-layout-common.sh"

[[ "${EUID}" -eq 0 ]] || die "Run this script as root"

require_command cmake
require_command sed

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
	die "This build tree uses CMAKE_INSTALL_PREFIX=${BUILD_INSTALL_PREFIX}. Rebuild it with -DCMAKE_INSTALL_PREFIX=/ before running this installer."
fi

RAW_PROJECT_DIR="${PROJECT_DIR:-${BUILD_SOURCE_DIR:-}}"
if [[ -z "${RAW_PROJECT_DIR}" ]]; then
	die "Could not determine the SaunaFS source directory. Set PROJECT_DIR=/path/to/saunafs-source."
fi
readonly PROJECT_DIR="$(readlink -f "${RAW_PROJECT_DIR}")"
readonly SERVICE_FILES_DIR="${PROJECT_DIR}/rpm/service-files"

[[ -d "${SERVICE_FILES_DIR}" ]] || die "Service files directory not found: ${SERVICE_FILES_DIR}"

# Install from the existing build tree only. This is the main point of the
# helper: use artifacts produced elsewhere instead of compiling locally.
note "Installing SaunaFS from the existing build tree in ${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

create_service_account

detect_active_services
stop_active_services

prepare_runtime_layout
refresh_dynamic_linker_cache
ensure_runtime_dependencies
install_service_units
seed_default_configs
seed_initial_metadata
reload_systemd_units
restart_previously_active_services
print_next_steps

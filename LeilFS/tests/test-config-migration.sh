#!/usr/bin/env bash

set -euo pipefail

readonly TEST_DIR="$(mktemp -d)"
cleanup() {
	rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

export SAUNAFS_ETC_DIR="${TEST_DIR}/etc/saunafs"
export LEIL_CGI_COMPAT_PATH="${TEST_DIR}/usr/share/sfscgi"
export LEIL_CGI_BACKUP_PATH="${TEST_DIR}/usr/share/sfscgi.saunafs-pre-leilfs"
mkdir -p "${SAUNAFS_ETC_DIR}"

# shellcheck source=../install-layout-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../install-layout-common.sh"

printf 'legacy-master\n' > "${SAUNAFS_ETC_DIR}/sfsmaster.cfg"
printf 'legacy-chunkserver\n' > "${SAUNAFS_ETC_DIR}/sfschunkserver.cfg"
printf 'existing-leil\n' > "${SAUNAFS_ETC_DIR}/leil-chunkserver.cfg"

migrate_legacy_configs

[[ "$(<"${SAUNAFS_ETC_DIR}/leil-master.cfg")" == "legacy-master" ]]
[[ "$(<"${SAUNAFS_ETC_DIR}/leil-chunkserver.cfg")" == "existing-leil" ]]
[[ "$(<"${SAUNAFS_ETC_DIR}/sfsmaster.cfg")" == "legacy-master" ]]
[[ "$(<"${SAUNAFS_ETC_DIR}/sfschunkserver.cfg")" == "legacy-chunkserver" ]]

mkdir -p "${LEIL_CGI_COMPAT_PATH}"
printf 'custom-cgi\n' > "${LEIL_CGI_COMPAT_PATH}/custom.txt"
prepare_legacy_path_transitions
[[ ! -e "${LEIL_CGI_COMPAT_PATH}" ]]
[[ "$(<"${LEIL_CGI_BACKUP_PATH}/custom.txt")" == "custom-cgi" ]]

printf 'config migration test passed\n'

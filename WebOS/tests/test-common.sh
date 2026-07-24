#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
cleanup() { rm -rf "${temporary}"; }
trap cleanup EXIT

export WEBOS_CONFIG_DIR="${temporary}/etc"
# shellcheck source=/dev/null
source "${PROJECT_DIR}/runtime/webos-common"

install -d -m 0755 "${WEBOS_USERS_DIR}"
install -m 0600 "${PROJECT_DIR}/config/webos-user.env" \
	"${WEBOS_USERS_DIR}/alice.env"
install -m 0600 "${PROJECT_DIR}/config/webos-user.env" \
	"${WEBOS_USERS_DIR}/bob.env"
webos_config_set "${WEBOS_USERS_DIR}/alice.env" WEBOS_USER alice
webos_config_set "${WEBOS_USERS_DIR}/alice.env" WEBOS_PORT 8081
webos_config_set "${WEBOS_USERS_DIR}/alice.env" WEBOS_TITLE "WebOS Test Alice"
webos_config_set "${WEBOS_USERS_DIR}/bob.env" WEBOS_USER bob
webos_config_set "${WEBOS_USERS_DIR}/bob.env" WEBOS_PORT 8082

[[ "$(webos_config_get "${WEBOS_USERS_DIR}/alice.env" WEBOS_TITLE)" == \
	"WebOS Test Alice" ]]
[[ "$(webos_allocate_port)" == 8083 ]]
webos_port_available 8081 && exit 1
webos_port_available 8081 alice
webos_set_default_user bob
[[ "$(webos_default_user)" == bob ]]
mapfile -t users < <(webos_list_users)
[[ "${users[*]}" == "alice bob" ]]

printf '[test-common.sh] Multi-user registry helpers passed\n'

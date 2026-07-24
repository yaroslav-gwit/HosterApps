#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

scripts=(
	build.sh
	release-local.sh
	installer/create-run-installer.sh
	installer/install-webos.sh
	installer/uninstall-webos.sh
	build/fetch-xfce420-noble.sh
	runtime/webos-session
	runtime/webos-xfce-session
	runtime/webos-common
	runtime/webos
	tests/test-common.sh
	tests/test-packaging.sh
	tests/validate-installer.sh
	tests/validate-installed.sh
	tests/validate-multi-user.sh
)

for script in "${scripts[@]}"; do
	bash -n "${PROJECT_DIR}/${script}"
done

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck "${scripts[@]/#/${PROJECT_DIR}/}"
else
	printf '[validate.sh] shellcheck not installed; skipped lint\n'
fi

"${PROJECT_DIR}/tests/test-packaging.sh"
"${PROJECT_DIR}/tests/test-common.sh"

if command -v systemd-analyze >/dev/null 2>&1; then
	systemd-analyze verify "${PROJECT_DIR}/systemd/webos@.service"
fi

printf '[validate.sh] Static validation passed\n'

#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
readonly PROJECT_DIR VERSION

temporary="$(mktemp -d)"
cleanup() { rm -rf "${temporary}"; }
trap cleanup EXIT

payload="${temporary}/payload"
mkdir -p "${payload}/wheels" "${payload}/licenses" "${payload}/assets"
cp -a "${PROJECT_DIR}/config" "${payload}/config"
cp -a "${PROJECT_DIR}/completions" "${payload}/completions"
cp -a "${PROJECT_DIR}/runtime" "${payload}/runtime"
cp -a "${PROJECT_DIR}/systemd" "${payload}/systemd"
cp "${PROJECT_DIR}/assets/webos-wallpaper.jpg" "${payload}/assets/webos-wallpaper.jpg"
cp "${PROJECT_DIR}/assets/webos-whisker.png" "${payload}/assets/webos-whisker.png"
cp "${PROJECT_DIR}/installer/install-webos.sh" "${payload}/install-webos.sh"
cp "${PROJECT_DIR}/installer/uninstall-webos.sh" "${payload}/uninstall-webos.sh"
touch "${payload}/wheels/test-0-py3-none-any.whl"
printf '%s\n' \
	"WEBOS_VERSION=${VERSION}" \
	"TARGET_ID=ubuntu" \
	"TARGET_VERSION=24.04" \
	"TARGET_ARCH=amd64" \
	"SOURCE_DATE_EPOCH=0" > "${payload}/build-info.txt"
chmod 0755 \
	"${payload}/install-webos.sh" \
	"${payload}/uninstall-webos.sh" \
	"${payload}/runtime/webos" \
	"${payload}/runtime/webos-common" \
	"${payload}/runtime/webos-session" \
	"${payload}/runtime/webos-xfce-session"

PAYLOAD_DIR="${payload}" \
	OUTPUT_FILE="${temporary}/webos.run" \
	SOURCE_DATE_EPOCH=0 \
	"${PROJECT_DIR}/installer/create-run-installer.sh"

[[ "$("${temporary}/webos.run" --version)" == "${VERSION}" ]]
"${temporary}/webos.run" --help >/dev/null
"${temporary}/webos.run" --extract "${temporary}/extracted" >/dev/null
cmp "${payload}/build-info.txt" "${temporary}/extracted/build-info.txt"
printf '[test-packaging.sh] Packaging smoke test passed\n'

#!/usr/bin/env bash

set -euo pipefail

# Build the Caddy artifact image and extract the resulting self-extracting
# installer onto the host.

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly OUTPUT_FILE="$(readlink -m "${OUTPUT_FILE:-./dist/caddy-installer.run}")"
readonly OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
readonly IMAGE_NAME="${IMAGE_NAME:-caddy-installer}"

usage() {
	cat <<EOF
Usage: ./${SCRIPT_NAME}

Optional environment variables:
  IMAGE_NAME=caddy-installer
  OUTPUT_FILE=./dist/caddy-installer.run
EOF
}

note() {
	printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

die() {
	printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2
	exit 1
}

require_command() {
	command -v "${1}" >/dev/null 2>&1 || die "Required command not found: ${1}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

require_command docker
require_command readlink

mkdir -p "${OUTPUT_DIR}"

note "Building Docker image ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" .

container_id=""
cleanup() {
	if [[ -n "${container_id}" ]]; then
		docker rm -f "${container_id}" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

note "Creating temporary container to export the installer artifact"
container_id="$(docker create "${IMAGE_NAME}")"

note "Copying /caddy-installer.run to ${OUTPUT_FILE}"
docker cp "${container_id}:/caddy-installer.run" "${OUTPUT_FILE}"

note "Installer artifact is ready at ${OUTPUT_FILE}"

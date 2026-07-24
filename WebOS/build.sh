#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME PROJECT_DIR
readonly DIST_DIR="${PROJECT_DIR}/dist"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

usage() {
	cat <<USAGE
Usage: ./${SCRIPT_NAME} [OPTIONS]

Build WebOS self-extracting installers with Docker or Podman.

Options:
  --target TARGET             all, ubuntu, ubuntu-24.04, ubuntu-26.04,
                              fedora, or fedora-44 (default: all).
  --version VERSION           Product version (default: VERSION file).
  --engine docker|podman      Container engine (auto-detected by default).
  --help, -h                  Show this help.

Environment:
  SELKIES_REVISION, PIXELFLUX_VERSION, PCMFLUX_VERSION
  BUILD_DATE, SOURCE_COMMIT, SOURCE_DATE_EPOCH
USAGE
}

TARGET=all
WEBOS_VERSION="$(tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--target) [[ -n "${2:-}" ]] || die "--target requires a value"; TARGET="${2}"; shift 2 ;;
	--version) [[ -n "${2:-}" ]] || die "--version requires a value"; WEBOS_VERSION="${2}"; shift 2 ;;
	--engine) [[ -n "${2:-}" ]] || die "--engine requires a value"; CONTAINER_ENGINE="${2}"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) die "Unknown option: ${1}" ;;
	esac
done

[[ "${TARGET}" =~ ^(all|ubuntu|ubuntu-24\.04|ubuntu-26\.04|fedora|fedora-44)$ ]] ||
	die "Invalid target: ${TARGET}"
[[ "${WEBOS_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] ||
	die "Version must look like 0.2.0 or 0.2.0-alpha.1"

if [[ -z "${CONTAINER_ENGINE}" ]]; then
	if command -v docker >/dev/null 2>&1; then
		CONTAINER_ENGINE=docker
	elif command -v podman >/dev/null 2>&1; then
		CONTAINER_ENGINE=podman
	else
		die "Docker or Podman is required"
	fi
fi
command -v "${CONTAINER_ENGINE}" >/dev/null 2>&1 ||
	die "Container engine not found: ${CONTAINER_ENGINE}"

SELKIES_REVISION="${SELKIES_REVISION:-12f5033b43b5b44a68bdd1ad804a49985832566a}"
PIXELFLUX_VERSION="${PIXELFLUX_VERSION:-2.0.0}"
PCMFLUX_VERSION="${PCMFLUX_VERSION:-2.0.0}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
SOURCE_COMMIT="${SOURCE_COMMIT:-$(git -C "${PROJECT_DIR}" rev-parse HEAD 2>/dev/null || printf unknown)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${PROJECT_DIR}" show -s --format=%ct HEAD 2>/dev/null || printf 0)}"
[[ "${SOURCE_DATE_EPOCH}" =~ ^[0-9]+$ ]] ||
	die "SOURCE_DATE_EPOCH must be a non-negative integer"

mkdir -p "${DIST_DIR}"

build_target() {
	local target="${1}" build_definition distro_label output_file image_name container_id
	local -a platform_args=()
	case "${target}" in
	ubuntu-24.04)
		build_definition=ubuntu
		distro_label=ubuntu-24.04
		platform_args+=(--build-arg "UBUNTU_VERSION=24.04")
		output_file="${DIST_DIR}/webos-v${WEBOS_VERSION}-ubuntu-24.04-amd64.run"
		;;
	ubuntu-26.04)
		build_definition=ubuntu
		distro_label=ubuntu-26.04
		platform_args+=(--build-arg "UBUNTU_VERSION=26.04")
		output_file="${DIST_DIR}/webos-v${WEBOS_VERSION}-ubuntu-26.04-amd64.run"
		;;
	fedora-44)
		build_definition=fedora
		distro_label=fedora-44
		output_file="${DIST_DIR}/webos-v${WEBOS_VERSION}-fedora-44-amd64.run"
		;;
	esac
	image_name="webos-installer-${distro_label}:${WEBOS_VERSION}"
	note "Building ${distro_label} payload"
	"${CONTAINER_ENGINE}" build \
		--file "${PROJECT_DIR}/build/Containerfile.${build_definition}" \
		--tag "${image_name}" \
		"${platform_args[@]}" \
		--build-arg "WEBOS_VERSION=${WEBOS_VERSION}" \
		--build-arg "SELKIES_REVISION=${SELKIES_REVISION}" \
		--build-arg "PIXELFLUX_VERSION=${PIXELFLUX_VERSION}" \
		--build-arg "PCMFLUX_VERSION=${PCMFLUX_VERSION}" \
		--build-arg "BUILD_DATE=${BUILD_DATE}" \
		--build-arg "SOURCE_COMMIT=${SOURCE_COMMIT}" \
		--build-arg "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}" \
		"${PROJECT_DIR}"

	container_id="$("${CONTAINER_ENGINE}" create "${image_name}" \
		"/webos-v${WEBOS_VERSION}-${distro_label}-amd64.run" --version)"
	if ! "${CONTAINER_ENGINE}" cp \
		"${container_id}:/webos-v${WEBOS_VERSION}-${distro_label}-amd64.run" \
		"${output_file}"; then
		"${CONTAINER_ENGINE}" rm -f "${container_id}" >/dev/null 2>&1 || true
		die "Failed to export ${distro_label} artifact"
	fi
	"${CONTAINER_ENGINE}" rm -f "${container_id}" >/dev/null
	chmod 0755 "${output_file}"
	note "Exported ${output_file}"
}

if [[ "${TARGET}" == all || "${TARGET}" == ubuntu || "${TARGET}" == ubuntu-24.04 ]]; then
	build_target ubuntu-24.04
fi
if [[ "${TARGET}" == all || "${TARGET}" == ubuntu || "${TARGET}" == ubuntu-26.04 ]]; then
	build_target ubuntu-26.04
fi
if [[ "${TARGET}" == all || "${TARGET}" == fedora || "${TARGET}" == fedora-44 ]]; then
	build_target fedora-44
fi

note "Build complete"

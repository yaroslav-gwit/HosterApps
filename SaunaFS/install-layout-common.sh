#!/usr/bin/env bash

# Shared post-install helpers for SaunaFS host-side installers. The callers are
# expected to source this file after enabling "set -euo pipefail".

: "${SCRIPT_NAME:=saunafs-installer}"

: "${SAUNAFS_USER:=saunafs}"
: "${SAUNAFS_GROUP:=saunafs}"
: "${SAUNAFS_ETC_DIR:=/etc/saunafs}"
: "${SAUNAFS_DATA_DIR:=/var/lib/saunafs}"
: "${SAUNAFS_RUN_DIR:=/var/run/saunafs}"
: "${SAUNAFS_CHUNK_DIR:=${SAUNAFS_DATA_DIR}/chunks}"
: "${SAUNAFS_METADATA_FILE:=${SAUNAFS_DATA_DIR}/metadata.sfs}"
: "${SAUNAFS_METADATA_TEMPLATE:=${SAUNAFS_DATA_DIR}/metadata.sfs.empty}"
: "${SAUNAFS_INSTALL_RUNTIME_DEPS:=1}"
: "${LIMITS_CONF:=/etc/security/limits.d/10-saunafs.conf}"
: "${PAM_CONF:=/etc/pam.d/saunafs}"
: "${CGISERV_DEFAULTS_FILE:=/etc/default/saunafs-cgiserv}"
: "${SYSTEMD_UNIT_DIR:=/etc/systemd/system}"
: "${MASTER_EXAMPLES_DIR:=/usr/share/doc/saunafs-master/examples}"
: "${CHUNKSERVER_EXAMPLES_DIR:=/usr/share/doc/saunafs-chunkserver/examples}"
: "${METALOGGER_EXAMPLES_DIR:=/usr/share/doc/saunafs-metalogger/examples}"
: "${CLIENT_EXAMPLES_DIR:=/usr/share/doc/saunafs-client/examples}"
: "${URAFT_EXAMPLES_DIR:=/usr/share/doc/saunafs-uraft/examples}"

if [[ -t 1 ]]; then
	STDOUT_RESET=$'\033[0m'
	STDOUT_INFO=$'\033[1;34m'
	STDOUT_NOTE=$'\033[1;36m'
	STDOUT_WARN=$'\033[1;33m'
	STDOUT_VALUE=$'\033[0;32m'
else
	STDOUT_RESET=''
	STDOUT_INFO=''
	STDOUT_NOTE=''
	STDOUT_WARN=''
	STDOUT_VALUE=''
fi

if [[ -t 2 ]]; then
	STDERR_RESET=$'\033[0m'
	STDERR_ERROR=$'\033[1;31m'
else
	STDERR_RESET=''
	STDERR_ERROR=''
fi

log_stdout() {
	local level="${1}"
	local color="${2}"
	shift 2

	printf '%b[%s]%b [%s] %s\n' \
		"${color}" "${level}" "${STDOUT_RESET}" "${SCRIPT_NAME}" "$*"
}

log_stderr() {
	local level="${1}"
	local color="${2}"
	shift 2

	printf '%b[%s]%b [%s] %s\n' \
		"${color}" "${level}" "${STDERR_RESET}" "${SCRIPT_NAME}" "$*" >&2
}

info() {
	log_stdout "INFO" "${STDOUT_INFO}" "$*"
}

note() {
	log_stdout "NOTE" "${STDOUT_NOTE}" "$*"
}

warn() {
	log_stdout "WARN" "${STDOUT_WARN}" "$*"
}

die() {
	log_stderr "ERROR" "${STDERR_ERROR}" "$*"
	exit 1
}

require_command() {
	command -v "${1}" >/dev/null 2>&1 || die "Required command not found: ${1}"
}

print_value() {
	printf '  %b%s%b\n' "${STDOUT_VALUE}" "${1}" "${STDOUT_RESET}"
}

detect_saunafs_lib_dir() {
	local -a candidates=()
	local -a matching_libs=()
	local candidate

	shopt -s nullglob
	candidates=(
		/usr/lib*/saunafs
		/usr/lib/*/saunafs
		/usr/local/lib*/saunafs
		/usr/local/lib/*/saunafs
	)
	shopt -u nullglob

	for candidate in "${candidates[@]}"; do
		shopt -s nullglob
		matching_libs=("${candidate}"/libsaunafs*.so* "${candidate}"/libsaunafsmount*.so*)
		shopt -u nullglob

		if [[ ${#matching_libs[@]} -gt 0 ]]; then
			printf '%s\n' "${candidate}"
			return 0
		fi
	done

	if [[ ${#candidates[@]} -gt 0 ]]; then
		printf '%s\n' "${candidates[0]}"
	else
		printf '%s\n' "/usr/lib/saunafs"
	fi
}

copy_if_missing() {
	local source="${1}"
	local destination="${2}"

	[[ -f "${source}" ]] || die "Expected file not found: ${source}"
	if [[ -e "${destination}" ]]; then
		note "Keeping existing ${destination}"
		return
	fi

	install -D -m 0644 "${source}" "${destination}"
}

install_or_update() {
	local source="${1}"
	local destination="${2}"

	[[ -f "${source}" ]] || die "Expected file not found: ${source}"
	install -D -m 0644 "${source}" "${destination}"
}

create_service_account() {
	require_command getent
	require_command groupadd
	require_command useradd

	if ! getent group "${SAUNAFS_GROUP}" >/dev/null 2>&1; then
		note "Creating system group ${SAUNAFS_GROUP}"
		groupadd --system "${SAUNAFS_GROUP}"
	fi

	if ! getent passwd "${SAUNAFS_USER}" >/dev/null 2>&1; then
		local nologin_bin
		nologin_bin="$(command -v nologin || true)"
		if [[ -z "${nologin_bin}" ]]; then
			nologin_bin="/bin/false"
		fi

		note "Creating system user ${SAUNAFS_USER}"
		useradd \
			--system \
			--gid "${SAUNAFS_GROUP}" \
			--home-dir "${SAUNAFS_DATA_DIR}" \
			--no-create-home \
			--shell "${nologin_bin}" \
			"${SAUNAFS_USER}"
	fi
}

prepare_runtime_layout() {
	local saunafs_lib_dir

	saunafs_lib_dir="$(detect_saunafs_lib_dir)"
	install -d -m 0755 -o root -g root \
		"${SAUNAFS_ETC_DIR}" \
		"${SYSTEMD_UNIT_DIR}" \
		"${saunafs_lib_dir}/plugins/chunkserver" \
		/etc/default
	install -d -m 0755 -o "${SAUNAFS_USER}" -g "${SAUNAFS_GROUP}" \
		"${SAUNAFS_DATA_DIR}" "${SAUNAFS_RUN_DIR}" "${SAUNAFS_CHUNK_DIR}"

	cat > "${LIMITS_CONF}" <<EOF
${SAUNAFS_USER} soft nofile 131072
${SAUNAFS_USER} hard nofile 131072
EOF
	chmod 0644 "${LIMITS_CONF}"

	cat > "${PAM_CONF}" <<'EOF'
session	required	pam_limits.so
EOF
	chmod 0644 "${PAM_CONF}"

	# Match the package scripts, which chown the data directory after install.
	chown -R "${SAUNAFS_USER}:${SAUNAFS_GROUP}" "${SAUNAFS_DATA_DIR}" "${SAUNAFS_RUN_DIR}"
}

is_debian_like_host() {
	[[ -r /etc/os-release ]] || return 1

	local os_id=""
	local os_id_like=""

	os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n1)"
	os_id_like="$(sed -n 's/^ID_LIKE=//p' /etc/os-release | tr -d '"' | head -n1)"

	[[ "${os_id}" == "debian" || "${os_id}" == "ubuntu" || " ${os_id_like} " == *" debian "* ]]
}

is_rhel_like_host() {
	[[ -r /etc/os-release ]] || return 1

	local os_id=""
	local os_id_like=""

	os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n1)"
	os_id_like="$(sed -n 's/^ID_LIKE=//p' /etc/os-release | tr -d '"' | head -n1)"

	[[ "${os_id}" == "rhel" || "${os_id}" == "rocky" || "${os_id}" == "centos" \
		|| "${os_id}" == "fedora" || "${os_id}" == "almalinux" \
		|| " ${os_id_like} " == *" rhel "* || " ${os_id_like} " == *" fedora "* ]]
}

resolve_debian_runtime_package() {
	local library_name="${1}"
	local candidate=""

	case "${library_name}" in
	libcrcutil.so.*)
		for candidate in libcrcutil0t64 libcrcutil0; do
			if apt-cache show "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libJudy.so.*)
		for candidate in libjudydebian1; do
			if apt-cache show "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libyaml-cpp.so.*)
		for candidate in libyaml-cpp0.8 libyaml-cpp0.7; do
			if apt-cache show "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libisal.so.*)
		for candidate in libisal2; do
			if apt-cache show "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libfuse3.so.*)
		for candidate in libfuse3-3; do
			if apt-cache show "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	esac

	return 1
}

resolve_rhel_runtime_package() {
	local library_name="${1}"
	local candidate=""

	case "${library_name}" in
	libJudy.so.*)
		for candidate in Judy; do
			if dnf info "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libyaml-cpp.so.*)
		for candidate in yaml-cpp; do
			if dnf info "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libisal.so.*)
		for candidate in libisal isa-l; do
			if dnf info "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libfuse3.so.*)
		for candidate in fuse3-libs fuse3; do
			if dnf info "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libboost_system.so.*|libboost_filesystem.so.*|libboost_iostreams.so.*|libboost_program_options.so.*)
		for candidate in boost-filesystem boost-iostreams boost-program-options boost-system; do
			if dnf info "${candidate}" >/dev/null 2>&1; then
				printf '%s\n' "${candidate}"
				return 0
			fi
		done
		;;
	libcrcutil.so.*)
		# crcutil is not typically available in RHEL/Rocky base repos;
		# the binary may still work if it was statically linked at build time.
		;;
	esac

	return 1
}

collect_missing_shared_libraries() {
	local binary=""
	local missing_library=""
	local -A missing_libraries=()
	local -a binaries=(
		/usr/bin/saunafs
		/usr/bin/sfsmount
		/usr/sbin/saunafs-cgiserver
		/usr/sbin/saunafs-uraft
		/usr/sbin/sfschunkserver
		/usr/sbin/sfsmaster
		/usr/sbin/sfsmetalogger
	)

	require_command ldd

	for binary in "${binaries[@]}"; do
		[[ -x "${binary}" ]] || continue

		while IFS= read -r missing_library; do
			[[ -n "${missing_library}" ]] || continue
			missing_libraries["${missing_library}"]=1
		done < <(
			ldd "${binary}" 2>/dev/null | sed -n \
				's/^[[:space:]]*\([^[:space:]]\+\)[[:space:]]*=>[[:space:]]*not found$/\1/p'
		)
	done

	if [[ ${#missing_libraries[@]} -gt 0 ]]; then
		printf '%s\n' "${!missing_libraries[@]}"
	fi
}

seed_initial_metadata() {
	if [[ -e "${SAUNAFS_METADATA_FILE}" ]]; then
		note "Keeping existing ${SAUNAFS_METADATA_FILE}"
		return
	fi

	if [[ ! -f "${SAUNAFS_METADATA_TEMPLATE}" ]]; then
		warn "Metadata template not found: ${SAUNAFS_METADATA_TEMPLATE}"
		return
	fi

	note "Initializing ${SAUNAFS_METADATA_FILE} from ${SAUNAFS_METADATA_TEMPLATE}"
	install -m 0644 -o "${SAUNAFS_USER}" -g "${SAUNAFS_GROUP}" \
		"${SAUNAFS_METADATA_TEMPLATE}" "${SAUNAFS_METADATA_FILE}"
}

ensure_runtime_dependencies() {
	local library_name=""
	local package_name=""
	local package_status=""
	local -a missing_libraries=()
	local -a unresolved_libraries=()
	local -a still_missing_libraries=()
	local -a packages_to_install=()
	local -A seen_packages=()

	if ! command -v ldd >/dev/null 2>&1; then
		warn "ldd not found; skipping runtime dependency verification"
		return
	fi

	mapfile -t missing_libraries < <(collect_missing_shared_libraries)
	if [[ ${#missing_libraries[@]} -eq 0 ]]; then
		return
	fi

	warn "Missing shared libraries were detected on this host:"
	for library_name in "${missing_libraries[@]}"; do
		print_value "${library_name}"
	done

	if [[ "${SAUNAFS_INSTALL_RUNTIME_DEPS}" != "1" ]]; then
		die "Install the required runtime libraries and rerun the installer, or leave SAUNAFS_INSTALL_RUNTIME_DEPS=1 so it can resolve them automatically."
	fi

	if is_debian_like_host; then
		require_command apt-cache
		require_command apt-get
		require_command dpkg-query

		info "Refreshing apt metadata for runtime dependency resolution"
		DEBIAN_FRONTEND=noninteractive apt-get update

		for library_name in "${missing_libraries[@]}"; do
			if ! package_name="$(resolve_debian_runtime_package "${library_name}")"; then
				unresolved_libraries+=("${library_name}")
				continue
			fi

			package_status="$(dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null || true)"
			if [[ "${package_status}" != "install ok installed" && -z "${seen_packages[${package_name}]:-}" ]]; then
				packages_to_install+=("${package_name}")
				seen_packages["${package_name}"]=1
			fi
		done

		if [[ ${#unresolved_libraries[@]} -gt 0 ]]; then
			warn "No built-in Debian/Ubuntu package mapping is available for:"
			for library_name in "${unresolved_libraries[@]}"; do
				print_value "${library_name}"
			done
		fi

		if [[ ${#packages_to_install[@]} -gt 0 ]]; then
			info "Installing missing runtime packages: ${packages_to_install[*]}"
			DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
				"${packages_to_install[@]}"
		fi
	elif is_rhel_like_host; then
		require_command dnf
		require_command rpm

		for library_name in "${missing_libraries[@]}"; do
			if ! package_name="$(resolve_rhel_runtime_package "${library_name}")"; then
				unresolved_libraries+=("${library_name}")
				continue
			fi

			if ! rpm -q "${package_name}" >/dev/null 2>&1 && [[ -z "${seen_packages[${package_name}]:-}" ]]; then
				packages_to_install+=("${package_name}")
				seen_packages["${package_name}"]=1
			fi
		done

		if [[ ${#unresolved_libraries[@]} -gt 0 ]]; then
			warn "No built-in RHEL/Rocky package mapping is available for:"
			for library_name in "${unresolved_libraries[@]}"; do
				print_value "${library_name}"
			done
		fi

		if [[ ${#packages_to_install[@]} -gt 0 ]]; then
			info "Installing missing runtime packages: ${packages_to_install[*]}"
			dnf install --assumeyes "${packages_to_install[@]}"
		fi
	else
		die "Automatic runtime dependency installation is only supported on Debian/Ubuntu and RHEL/Rocky/Fedora hosts."
	fi

	refresh_dynamic_linker_cache
	mapfile -t still_missing_libraries < <(collect_missing_shared_libraries)
	if [[ ${#still_missing_libraries[@]} -gt 0 ]]; then
		die "Shared libraries are still missing after dependency installation: ${still_missing_libraries[*]}"
	fi
}

install_service_if_present() {
	local binary_path="${1}"
	local service_name="${2}"
	local source_path="${SERVICE_FILES_DIR}/${service_name}"
	local destination_path="${SYSTEMD_UNIT_DIR}/${service_name}"

	[[ -d "${SERVICE_FILES_DIR}" ]] || die "Service files directory not found: ${SERVICE_FILES_DIR}"
	if [[ ! -x "${binary_path}" ]]; then
		note "Skipping ${service_name} because ${binary_path} is not installed"
		return
	fi

	# Service units are part of the packaged application surface, so refresh them
	# on updates instead of preserving older copies in place.
	install_or_update "${source_path}" "${destination_path}"
}

install_service_units() {
	install_service_if_present "/usr/sbin/sfsmaster" "saunafs-master.service"
	install_service_if_present "/usr/sbin/sfschunkserver" "saunafs-chunkserver.service"
	install_service_if_present "/usr/sbin/sfsmetalogger" "saunafs-metalogger.service"
	install_service_if_present "/usr/sbin/saunafs-cgiserver" "saunafs-cgiserv.service"

	if [[ -x "/usr/sbin/sfsmaster" && -x "/usr/sbin/saunafs-uraft" ]]; then
		install_or_update "${SERVICE_FILES_DIR}/saunafs-ha-master.service" \
			"${SYSTEMD_UNIT_DIR}/saunafs-ha-master.service"
		install_or_update "${SERVICE_FILES_DIR}/saunafs-uraft.service" \
			"${SYSTEMD_UNIT_DIR}/saunafs-uraft.service"
	elif [[ -x "/usr/sbin/saunafs-uraft" ]]; then
		note "Skipping saunafs-uraft.service because it requires sfsmaster as well"
	fi
}

seed_default_configs() {
	if [[ ! -e "${SAUNAFS_ETC_DIR}/sfsmaster.cfg" ]]; then
		copy_if_missing "${MASTER_EXAMPLES_DIR}/sfsmaster.cfg" "${SAUNAFS_ETC_DIR}/sfsmaster.cfg"
		cat >> "${SAUNAFS_ETC_DIR}/sfsmaster.cfg" <<'EOF'

# Installed by the SaunaFS helper to make the default role explicit.
PERSONALITY = master
EOF
	fi

	if [[ ! -e "${SAUNAFS_ETC_DIR}/sfschunkserver.cfg" ]]; then
		copy_if_missing "${CHUNKSERVER_EXAMPLES_DIR}/sfschunkserver.cfg" "${SAUNAFS_ETC_DIR}/sfschunkserver.cfg"
		cat >> "${SAUNAFS_ETC_DIR}/sfschunkserver.cfg" <<'EOF'

# Installed by the SaunaFS helper for a simple single-host deployment.
MASTER_HOST = 127.0.0.1
EOF
	fi

	if [[ ! -e "${SAUNAFS_ETC_DIR}/sfsmetalogger.cfg" ]]; then
		copy_if_missing "${METALOGGER_EXAMPLES_DIR}/sfsmetalogger.cfg" "${SAUNAFS_ETC_DIR}/sfsmetalogger.cfg"
		cat >> "${SAUNAFS_ETC_DIR}/sfsmetalogger.cfg" <<'EOF'

# Installed by the SaunaFS helper for a simple single-host deployment.
MASTER_HOST = 127.0.0.1
EOF
	fi

	if [[ ! -e "${SAUNAFS_ETC_DIR}/sfsmount.cfg" ]]; then
		cat > "${SAUNAFS_ETC_DIR}/sfsmount.cfg" <<'EOF'
# Default client-side mount settings for a local single-node deployment.
sfsmaster=127.0.0.1
sfsport=9421
EOF
		chmod 0644 "${SAUNAFS_ETC_DIR}/sfsmount.cfg"
	fi

	if [[ ! -e "${SAUNAFS_ETC_DIR}/sfshdd.cfg" ]]; then
		cat > "${SAUNAFS_ETC_DIR}/sfshdd.cfg" <<EOF
# Default single-node chunk storage created by the SaunaFS helper.
# Replace this path with dedicated storage before using the host in production.
${SAUNAFS_CHUNK_DIR}
EOF
		chmod 0644 "${SAUNAFS_ETC_DIR}/sfshdd.cfg"
	fi

	if [[ ! -e "${SAUNAFS_ETC_DIR}/sfsexports.cfg" ]]; then
		cat > "${SAUNAFS_ETC_DIR}/sfsexports.cfg" <<'EOF'
# Safer default export than the upstream example: only localhost can mount it.
# Expand this file deliberately once you know which clients should connect.
127.0.0.1               /       rw,alldirs,maproot=0
127.0.0.1               .       rw
EOF
		chmod 0644 "${SAUNAFS_ETC_DIR}/sfsexports.cfg"
	fi

	copy_if_missing "${MASTER_EXAMPLES_DIR}/sfsgoals.cfg" "${SAUNAFS_ETC_DIR}/sfsgoals.cfg"
	copy_if_missing "${MASTER_EXAMPLES_DIR}/sfstopology.cfg" "${SAUNAFS_ETC_DIR}/sfstopology.cfg"
	copy_if_missing "${MASTER_EXAMPLES_DIR}/sfsglobaliolimits.cfg" "${SAUNAFS_ETC_DIR}/sfsglobaliolimits.cfg"
	copy_if_missing "${CLIENT_EXAMPLES_DIR}/sfsiolimits.cfg" "${SAUNAFS_ETC_DIR}/sfsiolimits.cfg"
	copy_if_missing "${CLIENT_EXAMPLES_DIR}/sfstls.cfg" "${SAUNAFS_ETC_DIR}/sfstls.cfg"

	if [[ -f "${URAFT_EXAMPLES_DIR}/saunafs-uraft.cfg" ]]; then
		copy_if_missing "${URAFT_EXAMPLES_DIR}/saunafs-uraft.cfg" "${SAUNAFS_ETC_DIR}/saunafs-uraft.cfg"
	fi

	if [[ -x "/usr/sbin/saunafs-cgiserver" && ! -e "${CGISERV_DEFAULTS_FILE}" ]]; then
		cat > "${CGISERV_DEFAULTS_FILE}" <<'EOF'
# Optional overrides for saunafs-cgiserv.service.
# Uncomment any value you want to override locally.
# BIND_HOST=0.0.0.0
# BIND_PORT=9425
# ROOT_PATH=/usr/share/sfscgi
EOF
		chmod 0644 "${CGISERV_DEFAULTS_FILE}"
	fi
}

# ---------------------------------------------------------------------------
# Service lifecycle helpers for safe upgrades.  The caller records which
# services were active before the upgrade, stops them, performs the file
# overlay, and then restarts only the ones that were previously running.
# ---------------------------------------------------------------------------

readonly SAUNAFS_SERVICE_UNITS=(
	saunafs-master.service
	saunafs-chunkserver.service
	saunafs-metalogger.service
	saunafs-cgiserv.service
	saunafs-uraft.service
	saunafs-ha-master.service
)

# Populates the global SAUNAFS_ACTIVE_SERVICES array with the names of
# SaunaFS systemd units that are currently in the "active" state.
detect_active_services() {
	SAUNAFS_ACTIVE_SERVICES=()

	if ! command -v systemctl >/dev/null 2>&1; then
		return
	fi

	local unit=""
	for unit in "${SAUNAFS_SERVICE_UNITS[@]}"; do
		if systemctl is-active --quiet "${unit}" 2>/dev/null; then
			SAUNAFS_ACTIVE_SERVICES+=("${unit}")
		fi
	done
}

stop_active_services() {
	if [[ ${#SAUNAFS_ACTIVE_SERVICES[@]} -eq 0 ]]; then
		return
	fi

	warn "Stopping running SaunaFS services before upgrade:"
	local unit=""
	for unit in "${SAUNAFS_ACTIVE_SERVICES[@]}"; do
		print_value "${unit}"
		systemctl stop "${unit}" || warn "Failed to stop ${unit}; continuing anyway"
	done
}

restart_previously_active_services() {
	if [[ ${#SAUNAFS_ACTIVE_SERVICES[@]} -eq 0 ]]; then
		return
	fi

	info "Restarting SaunaFS services that were active before the upgrade:"
	local unit=""
	for unit in "${SAUNAFS_ACTIVE_SERVICES[@]}"; do
		print_value "${unit}"
		if ! systemctl start "${unit}"; then
			warn "Failed to start ${unit}; check 'journalctl -u ${unit}' for details"
		fi
	done
}

refresh_dynamic_linker_cache() {
	if command -v ldconfig >/dev/null 2>&1; then
		ldconfig
	fi
}

reload_systemd_units() {
	if command -v systemctl >/dev/null 2>&1; then
		if ! systemctl daemon-reload; then
			warn "systemctl daemon-reload failed; reload systemd manually if needed"
		fi
	else
		warn "systemctl not found; skipping daemon-reload"
	fi
}

print_next_steps() {
	printf '\n'
	info "SaunaFS was installed into the packaged layout."
	printf '\n'

	note "Review these files before starting services:"
	print_value "${SAUNAFS_ETC_DIR}/sfsmaster.cfg"
	print_value "${SAUNAFS_ETC_DIR}/sfschunkserver.cfg"
	print_value "${SAUNAFS_ETC_DIR}/sfsmetalogger.cfg"
	print_value "${SAUNAFS_ETC_DIR}/sfshdd.cfg"
	print_value "${SAUNAFS_ETC_DIR}/sfsexports.cfg"
	printf '\n'

	note "Suggested next steps:"
	print_value "systemctl enable saunafs-master.service"
	print_value "systemctl enable saunafs-chunkserver.service"
	print_value "systemctl enable saunafs-metalogger.service"
	print_value "systemctl start saunafs-master.service"
	print_value "systemctl start saunafs-chunkserver.service"
	print_value "systemctl start saunafs-metalogger.service"
	printf '\n'

	note "Optional services:"
	print_value "${SYSTEMD_UNIT_DIR}/saunafs-cgiserv.service"
	print_value "${SYSTEMD_UNIT_DIR}/saunafs-uraft.service"
	print_value "${SYSTEMD_UNIT_DIR}/saunafs-ha-master.service"
}

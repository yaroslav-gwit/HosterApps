#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly CONFIG_DIR="/etc/hoster/webos"
readonly USERS_DIR="${CONFIG_DIR}/users"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} USER_A USER_B

Validate two simultaneous WebOS sessions, their independent HTTPS endpoints,
runtime directories, credentials, generated titles, and shared-VM localhost
connectivity. The test starts a temporary HTTP server as USER_A and connects
to it as USER_B; user homes and WebOS configuration are not modified.
USAGE
}

value_from() {
	local file="${1}" key="${2}"
	python3 - "${file}" "${key}" <<'PY'
import pathlib
import shlex
import sys

raw = ""
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if line.startswith(f"{sys.argv[2]}="):
        raw = line.split("=", 1)[1].strip()
if not raw:
    print("")
else:
    lexer = shlex.shlex(raw, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    print(" ".join(lexer))
PY
}

[[ "${1:-}" != -h && "${1:-}" != --help ]] || { usage; exit 0; }
[[ $# -eq 2 ]] || die "Expected two registered users"
[[ "${EUID}" -eq 0 ]] || die "Run this validation as root"
user_a="${1}"
user_b="${2}"
[[ "${user_a}" != "${user_b}" ]] || die "The two users must be different"

declare -A ports pids
for user in "${user_a}" "${user_b}"; do
	config="${USERS_DIR}/${user}.env"
	[[ -r "${config}" ]] || die "Missing ${config}"
	getent passwd "${user}" >/dev/null || die "Unknown Linux user: ${user}"
	service="$(systemd-escape --template=webos@.service "${user}")"
	systemctl is-enabled --quiet "${service}" || die "${service} is not enabled"
	systemctl is-active --quiet "${service}" || die "${service} is not active"
	port="$(value_from "${config}" WEBOS_PORT)"
	listen="$(value_from "${config}" WEBOS_LISTEN)"
	auth_user="$(value_from "${config}" WEBOS_AUTH_USER)"
	auth_password="$(value_from "${config}" WEBOS_AUTH_PASSWORD)"
	cert="$(value_from "${config}" WEBOS_HTTPS_CERT)"
	[[ -n "${port}" && -n "${auth_user}" && -n "${auth_password}" ]] ||
		die "Incomplete configuration for ${user}"
	[[ -r "${cert}" ]] || die "Missing TLS certificate for ${user}"
	health_address="${listen}"
	case "${listen}" in
	0.0.0.0) health_address=127.0.0.1 ;;
	::) health_address='[::1]' ;;
	*:*) health_address="[${listen}]" ;;
	esac
	curl --insecure --fail --silent --show-error \
		--user "${auth_user}:${auth_password}" \
		--max-time 5 "https://${health_address}:${port}/" >/dev/null ||
		die "HTTPS health check failed for ${user}"
	runtime="/run/hoster-webos-${user}"
	[[ -S "${runtime}/wayland-0" && -S "${runtime}/wayland-1" ]] ||
		die "Independent Wayland sockets are missing for ${user}"
	pid="$(pgrep -u "$(id -u "${user}")" -f '/venv/bin/python -m selkies' | head -n 1)"
	[[ -n "${pid}" ]] || die "Selkies process is missing for ${user}"
	command="$(tr '\0' ' ' < "/proc/${pid}/cmdline")"
	[[ "${command}" == *"--ui-title WebOS-$(hostname)-${user}"* ]] ||
		die "Generated browser title is incorrect for ${user}"
	[[ "${command}" == *"--ui-sidebar-show-apps false"* ]] ||
		die "Apps sidebar is visible for ${user}"
	ports["${user}"]="${port}"
	pids["${user}"]="${pid}"
done

[[ "${ports[${user_a}]}" != "${ports[${user_b}]}" ]] ||
	die "The two sessions use the same TCP port"
[[ "${pids[${user_a}]}" != "${pids[${user_b}]}" ]] ||
	die "The two sessions use the same Selkies process"

probe_dir="$(mktemp -d /var/tmp/webos-localhost-probe.XXXXXX)"
probe_port=""
probe_pid=""
cleanup() {
	[[ -z "${probe_pid}" ]] || kill "${probe_pid}" 2>/dev/null || true
	rm -rf "${probe_dir}"
}
trap cleanup EXIT
printf 'WebOS shared localhost probe\n' > "${probe_dir}/index.html"
chmod 0755 "${probe_dir}"
chmod 0644 "${probe_dir}/index.html"
for candidate in $(seq 19081 19180); do
	if ! ss -H -ltn | awk '{print $4}' | grep -Eq ":${candidate}$"; then
		probe_port="${candidate}"
		break
	fi
done
[[ -n "${probe_port}" ]] || die "No free localhost probe port"
runuser -u "${user_a}" -- \
	python3 -m http.server "${probe_port}" --bind 127.0.0.1 \
	--directory "${probe_dir}" >/dev/null 2>&1 &
probe_pid=$!
for _ in $(seq 1 50); do
	if curl --fail --silent "http://127.0.0.1:${probe_port}/" >/dev/null 2>&1; then
		break
	fi
	sleep 0.1
done
runuser -u "${user_b}" -- \
	curl --fail --silent --show-error "http://127.0.0.1:${probe_port}/" |
	grep -qx 'WebOS shared localhost probe' ||
	die "${user_b} could not reach ${user_a}'s localhost application"

user_list="$(/usr/local/bin/webos user list)"
grep -q "${user_a}" <<< "${user_list}" ||
	die "webos user list omitted ${user_a}"
grep -q "${user_b}" <<< "${user_list}" ||
	die "webos user list omitted ${user_b}"

note "Validated simultaneous HTTPS sessions for ${user_a} and ${user_b}"
note "Validated ${user_b} -> localhost:${probe_port} application access owned by ${user_a}"

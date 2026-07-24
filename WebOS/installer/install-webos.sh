#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly PAYLOAD_DIR="${1:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}"
shift || true

readonly INSTALL_ROOT="/opt/hoster/webos"
readonly RELEASES_DIR="${INSTALL_ROOT}/releases"
readonly CURRENT_LINK="${INSTALL_ROOT}/current"
readonly CONFIG_DIR="/etc/hoster/webos"
readonly LEGACY_ENV_FILE="${CONFIG_DIR}/webos.env"
readonly DEFAULTS_FILE="${CONFIG_DIR}/defaults.env"
readonly USERS_DIR="${CONFIG_DIR}/users"
readonly CERTS_DIR="${CONFIG_DIR}/certs"
readonly DESKTOP_DIR="${CONFIG_DIR}/desktop"
readonly STATE_DIR="/var/lib/hoster/webos"
readonly LOG_DIR="/var/log/hoster/webos"
readonly UNIT_FILE="/etc/systemd/system/webos@.service"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
warn() { printf '[%s] Warning: %s\n' "${SCRIPT_NAME}" "$*" >&2; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -r "${PAYLOAD_DIR}/runtime/webos-common" ]] ||
	die "Missing WebOS helper library"
# shellcheck source=/dev/null
source "${PAYLOAD_DIR}/runtime/webos-common"

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} PAYLOAD_DIR [OPTIONS]

Options:
  --user USER       Existing non-root account that owns the desktop session.
  --listen ADDRESS  Selkies bind address (default: 127.0.0.1).
  --port PORT       Selkies TCP port (default: first free port from 8081).
  -h, --help        Show this help.
USAGE
}

require_value() {
	[[ -n "${2:-}" ]] || die "${1} requires a value"
}

validate_user() {
	local candidate="${1}" uid shell home
	getent passwd "${candidate}" >/dev/null || die "User does not exist: ${candidate}"
	uid="$(id -u "${candidate}")"
	[[ "${uid}" -ne 0 ]] || die "The desktop user must not be root"
	IFS=: read -r _ _ _ _ _ home shell < <(getent passwd "${candidate}")
	case "${shell}" in
	*/nologin|*/false) die "User ${candidate} does not have an interactive shell" ;;
	esac
	[[ -d "${home}" ]] || die "Home directory does not exist for ${candidate}: ${home}"
	runuser -u "${candidate}" -- test -x "${home}" ||
		die "Home directory is not accessible to ${candidate}: ${home}"
	runuser -u "${candidate}" -- test -w "${home}" ||
		die "Home directory is not writable by ${candidate}: ${home}"
}

select_user() {
	local requested="${1:-}" candidate
	local -a candidates=()
	if [[ -n "${requested}" ]]; then
		validate_user "${requested}"
		printf '%s\n' "${requested}"
		return
	fi
	if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
		validate_user "${SUDO_USER}"
		printf '%s\n' "${SUDO_USER}"
		return
	fi
	while IFS=: read -r candidate _ uid _ _ home shell; do
		if [[ "${uid}" -ge 1000 && "${uid}" -lt 65534 && -d "${home}" ]]; then
			case "${shell}" in
			*/nologin|*/false) continue ;;
			esac
			candidates+=("${candidate}")
		fi
	done < /etc/passwd
	if [[ "${#candidates[@]}" -eq 1 ]]; then
		printf '%s\n' "${candidates[0]}"
		return
	fi
	if [[ "${#candidates[@]}" -eq 0 ]]; then
		die "No existing non-root desktop user found; pass --user USER"
	fi
	die "Several desktop users are available (${candidates[*]}); pass --user USER"
}

validate_platform() {
	local expected_id="${TARGET_ID}" expected_version="${TARGET_VERSION}"
	local machine
	# shellcheck source=/dev/null
	source /etc/os-release
	machine="$(uname -m)"
	[[ "${machine}" == "x86_64" ]] ||
		die "Unsupported architecture ${machine}; this installer requires x86_64/amd64"
	[[ "${ID:-}" == "${expected_id}" && "${VERSION_ID:-}" == "${expected_version}" ]] ||
		die "This installer targets ${expected_id} ${expected_version}; detected ${ID:-unknown} ${VERSION_ID:-unknown}"
}

validate_listen() {
	local address="${1}"
	[[ "${address}" =~ ^[A-Za-z0-9:._-]+$ ]] ||
		die "Invalid listen address: ${address}"
}

validate_port() {
	local port="${1}"
	[[ "${port}" =~ ^[0-9]+$ ]] || die "Port must be numeric: ${port}"
	(( port >= 1 && port <= 65535 )) || die "Port must be between 1 and 65535"
}

metadata_value() {
	local key="${1}"
	awk -F= -v key="${key}" '
		$1 == key {
			sub(/^[^=]*=/, "")
			print
			exit
		}
	' "${PAYLOAD_DIR}/build-info.txt"
}

configure_ubuntu_workstation_repositories() {
	local temporary mozilla_fingerprint
	temporary="$(mktemp -d)"

	note "Configuring official Chrome, Firefox, and VS Code repositories"
	install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d

	curl --fail --silent --show-error --location \
		https://packages.mozilla.org/apt/repo-signing-key.gpg \
		-o "${temporary}/packages.mozilla.org.asc"
	mozilla_fingerprint="$(
		gpg --batch --show-keys --with-colons "${temporary}/packages.mozilla.org.asc" |
			awk -F: '$1 == "fpr" { print $10; exit }'
	)"
	[[ "${mozilla_fingerprint}" == "35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3" ]] ||
		die "Mozilla repository signing-key fingerprint verification failed"
	install -m 0644 "${temporary}/packages.mozilla.org.asc" \
		/etc/apt/keyrings/packages.mozilla.org.asc

	curl --fail --silent --show-error --location \
		https://packages.microsoft.com/keys/microsoft.asc \
		-o "${temporary}/microsoft.asc"
	gpg --batch --yes --dearmor \
		--output /etc/apt/keyrings/microsoft.gpg "${temporary}/microsoft.asc"
	chmod 0644 /etc/apt/keyrings/microsoft.gpg

	curl --fail --silent --show-error --location \
		https://dl.google.com/linux/linux_signing_key.pub \
		-o "${temporary}/google.asc"
	gpg --batch --yes --dearmor \
		--output /etc/apt/keyrings/google-chrome.gpg "${temporary}/google.asc"
	chmod 0644 /etc/apt/keyrings/google-chrome.gpg

	{
		printf '%s\n' \
			'Types: deb' \
			'URIs: https://packages.mozilla.org/apt' \
			'Suites: mozilla' \
			'Components: main' \
			'Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc' \
			'' \
			'Types: deb' \
			'URIs: https://packages.microsoft.com/repos/code' \
			'Suites: stable' \
			'Components: main' \
			'Architectures: amd64' \
			'Signed-By: /etc/apt/keyrings/microsoft.gpg' \
			'' \
			'Types: deb' \
			'URIs: https://dl.google.com/linux/chrome/deb/' \
			'Suites: stable' \
			'Components: main' \
			'Architectures: amd64' \
			'Signed-By: /etc/apt/keyrings/google-chrome.gpg'
	} > "${temporary}/hoster-webos-workstation.sources"
	install -m 0644 "${temporary}/hoster-webos-workstation.sources" \
		/etc/apt/sources.list.d/hoster-webos-workstation.sources

	printf '%s\n' \
		'Package: *' \
		'Pin: origin packages.mozilla.org' \
		'Pin-Priority: 1000' \
		> "${temporary}/hoster-webos-mozilla"
	install -m 0644 "${temporary}/hoster-webos-mozilla" \
		/etc/apt/preferences.d/hoster-webos-mozilla

	rm -rf "${temporary}"
}

configure_fedora_workstation_repositories() {
	local temporary
	temporary="$(mktemp -d)"

	note "Configuring official Chrome and VS Code repositories"
	install -d -m 0755 /etc/yum.repos.d
	rpm --import https://dl.google.com/linux/linux_signing_key.pub
	rpm --import https://packages.microsoft.com/keys/microsoft.asc

	{
		printf '%s\n' \
			'[google-chrome]' \
			'name=Google Chrome' \
			'baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64' \
			'enabled=1' \
			'gpgcheck=1' \
			'repo_gpgcheck=0' \
			'gpgkey=https://dl.google.com/linux/linux_signing_key.pub' \
			'' \
			'[code]' \
			'name=Visual Studio Code' \
			'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
			'enabled=1' \
			'autorefresh=1' \
			'type=rpm-md' \
			'gpgcheck=1' \
			'repo_gpgcheck=0' \
			'gpgkey=https://packages.microsoft.com/keys/microsoft.asc'
	} > "${temporary}/hoster-webos-workstation.repo"
	install -m 0644 "${temporary}/hoster-webos-workstation.repo" \
		/etc/yum.repos.d/hoster-webos-workstation.repo

	rm -rf "${temporary}"
}

install_ubuntu_24_wayland_desktop() {
	local packages_dir
	local -a packages=()

	[[ "${TARGET_ID}" == ubuntu && "${TARGET_VERSION}" == 24.04 ]] || return 0
	packages_dir="${PAYLOAD_DIR}/native-packages/ubuntu-24.04"
	[[ -d "${packages_dir}" ]] ||
		die "Ubuntu 24.04 XFCE 4.20 package payload is missing"
	mapfile -t packages < <(
		find "${packages_dir}" -maxdepth 1 -type f -name '*.deb' -print | sort
	)
	[[ "${#packages[@]}" -eq 13 ]] ||
		die "Ubuntu 24.04 XFCE 4.20 package payload is incomplete"

	note "Installing the pinned XFCE 4.20 Wayland desktop backport"
	apt-get install --no-install-recommends -y "${packages[@]}"
}

install_packages() {
	if [[ "${TARGET_ID}" == "ubuntu" ]]; then
		local -a packages=(
			ca-certificates curl dbus-user-session dbus-x11 docker.io
			fonts-noto-color-emoji fonts-noto-mono gnupg
			gsettings-desktop-schemas
			labwc libdrm2 libgbm1 libice6 libopus0 libpixman-1-0
			libpulse0 libsm6 libva-drm2 libva-x11-2 libva2
			libwayland-client0 libwayland-server0 libxkbcommon0
			libx11-6 libxext6
			mesa-va-drivers openssl python3 python3-venv sudo
			wl-clipboard wlr-randr xdg-utils xfce4 xfce4-terminal xwayland
			xfce4-whiskermenu-plugin
		)
		note "Installing Ubuntu runtime packages"
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get install --no-install-recommends -y "${packages[@]}"
		install_ubuntu_24_wayland_desktop
		configure_ubuntu_workstation_repositories
		apt-get update
		apt-get install -y \
			adwaita-icon-theme-full arc-theme code firefox gedit gimp git gthumb \
			breeze-cursor-theme gnome-themes-extra google-chrome-stable jq \
			papirus-icon-theme \
			libreoffice-calc libreoffice-impress libreoffice-writer vlc
	else
		local -a packages=(
			adwaita-cursor-theme adwaita-icon-theme adwaita-icon-theme-legacy
			arc-theme breeze-cursor-theme
			ca-certificates containerd curl dbus-daemon firefox gedit gimp git gthumb jq
			google-noto-color-emoji-fonts google-noto-sans-mono-fonts
			labwc libdrm libICE libSM
			libva libX11 libXext
			libwayland-client libwayland-server libxkbcommon mesa-dri-drivers
			mesa-libgbm openssl opus pixman pulseaudio-libs python3 sudo
			runc
			libreoffice-calc libreoffice-impress libreoffice-writer vlc
			papirus-icon-theme
			thunar wl-clipboard wlr-randr xdg-utils xfce4-appfinder
			xfce4-panel xfce4-session xfce4-settings xfce4-terminal
			xfce4-whiskermenu-plugin xfdesktop xfwm4
			xorg-x11-server-Xwayland
		)
		if systemctl cat docker.service >/dev/null 2>&1; then
			note "Preserving the existing Docker runtime"
		else
			if rpm -q podman-docker >/dev/null 2>&1; then
				note "Removing the Podman Docker-command shim before installing Docker"
				dnf remove -y podman-docker
			fi
			packages+=(docker-cli moby-engine)
		fi
		note "Installing Fedora runtime packages"
		configure_fedora_workstation_repositories
		packages+=(code google-chrome-stable)
		dnf install -y "${packages[@]}"
	fi
}

USER_ARG=""
LISTEN_ARG=""
PORT_ARG=""
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--user)
		require_value "${1}" "${2:-}"
		USER_ARG="${2}"
		shift 2
		;;
	--listen)
		require_value "${1}" "${2:-}"
		LISTEN_ARG="${2}"
		shift 2
		;;
	--port)
		require_value "${1}" "${2:-}"
		PORT_ARG="${2}"
		shift 2
		;;
	-h|--help)
		usage
		exit 0
		;;
	*) die "Unknown option: ${1}" ;;
	esac
done

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root"
[[ -r "${PAYLOAD_DIR}/build-info.txt" ]] || die "Missing payload build-info.txt"
[[ -d "${PAYLOAD_DIR}/wheels" ]] || die "Missing payload wheelhouse"
[[ -x "${PAYLOAD_DIR}/runtime/webos-session" ]] || die "Missing WebOS session launcher"

WEBOS_VERSION="$(metadata_value WEBOS_VERSION)"
TARGET_ID="$(metadata_value TARGET_ID)"
TARGET_VERSION="$(metadata_value TARGET_VERSION)"
TARGET_ARCH="$(metadata_value TARGET_ARCH)"
[[ "${WEBOS_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] ||
	die "Invalid WEBOS_VERSION in build-info.txt"
[[ "${TARGET_ID}" == ubuntu || "${TARGET_ID}" == fedora ]] ||
	die "Invalid TARGET_ID in build-info.txt"
[[ "${TARGET_VERSION}" =~ ^[0-9]+\.[0-9]+$ || "${TARGET_VERSION}" =~ ^[0-9]+$ ]] ||
	die "Invalid TARGET_VERSION in build-info.txt"
[[ "${TARGET_ARCH}" == amd64 || "${TARGET_ARCH}" == x86_64 ]] ||
	die "Invalid TARGET_ARCH in build-info.txt"

validate_platform
DESKTOP_USER="$(select_user "${USER_ARG}")"
validate_user "${DESKTOP_USER}"

LISTEN_ADDRESS="${LISTEN_ARG:-127.0.0.1}"
validate_listen "${LISTEN_ADDRESS}"
if [[ -n "${PORT_ARG}" ]]; then
	validate_port "${PORT_ARG}"
fi

note "Installing WebOS ${WEBOS_VERSION} for ${DESKTOP_USER}"
install_packages
install -m 0644 \
	"${PAYLOAD_DIR}/config/fontconfig/69-hoster-webos-emoji.conf" \
	/etc/fonts/conf.d/69-hoster-webos-emoji.conf
fc-cache -f

release_dir="${RELEASES_DIR}/${WEBOS_VERSION}"
staging_dir="${RELEASES_DIR}/.${WEBOS_VERSION}.new.$$"
previous_target=""
rollback_target=""
replaced_release_backup=""
if [[ -L "${CURRENT_LINK}" ]]; then
	previous_target="$(readlink -f "${CURRENT_LINK}")"
	rollback_target="${previous_target}"
fi

rm -rf "${staging_dir}"
install -d -m 0755 \
	"${staging_dir}/bin" \
	"${staging_dir}/share" \
	"${staging_dir}/share/backgrounds" \
	"${staging_dir}/share/icons"
install -m 0755 "${PAYLOAD_DIR}/runtime/webos" "${staging_dir}/bin/webos"
install -m 0755 "${PAYLOAD_DIR}/runtime/webos-common" "${staging_dir}/bin/webos-common"
install -m 0755 "${PAYLOAD_DIR}/runtime/webos-session" "${staging_dir}/bin/webos-session"
install -m 0755 "${PAYLOAD_DIR}/runtime/webos-xfce-session" "${staging_dir}/bin/webos-xfce-session"
install -m 0600 "${PAYLOAD_DIR}/config/webos-user.env" \
	"${staging_dir}/share/webos-user.env"
install -m 0644 "${PAYLOAD_DIR}/build-info.txt" "${staging_dir}/build-info.txt"
install -m 0644 "${PAYLOAD_DIR}/assets/webos-wallpaper.jpg" \
	"${staging_dir}/share/backgrounds/webos-wallpaper.jpg"
install -m 0644 "${PAYLOAD_DIR}/assets/webos-whisker.png" \
	"${staging_dir}/share/icons/webos-whisker.png"
cp -a "${PAYLOAD_DIR}/licenses" "${staging_dir}/share/licenses"

note "Creating the offline Python environment"
python3 -m venv --copies "${staging_dir}/venv"
"${staging_dir}/venv/bin/python" -m pip install \
	--no-index --no-cache-dir --find-links "${PAYLOAD_DIR}/wheels" selkies
"${staging_dir}/venv/bin/python" -c \
	'import pcmflux, pixelflux, selkies; print("Selkies Python payload verified")'

install -d -m 0755 "${RELEASES_DIR}"
if [[ -d "${release_dir}" ]]; then
	replaced_release_backup="${RELEASES_DIR}/.${WEBOS_VERSION}.replaced.$$"
	mv "${release_dir}" "${replaced_release_backup}"
	if [[ "${previous_target}" == "${release_dir}" ]]; then
		rollback_target="${replaced_release_backup}"
	fi
fi
mv "${staging_dir}" "${release_dir}"
ln -sfn "${release_dir}" "${CURRENT_LINK}.new"
mv -Tf "${CURRENT_LINK}.new" "${CURRENT_LINK}"
install -m 0644 "${PAYLOAD_DIR}/build-info.txt" "${INSTALL_ROOT}/build-info.txt"

install -d -m 0755 \
	"${CONFIG_DIR}" "${USERS_DIR}" "${CERTS_DIR}" "${STATE_DIR}" "${LOG_DIR}"
if [[ ! -f "${DEFAULTS_FILE}" ]]; then
	install -m 0644 "${PAYLOAD_DIR}/config/webos.env" "${DEFAULTS_FILE}"
	note "Created ${DEFAULTS_FILE}"
else
	note "Preserved ${DEFAULTS_FILE}"
fi
# The plain CPU H.264 path can produce a connected black canvas on current
# Ubuntu pixelflux builds. The striped H.264 path is compatible across all
# three supported targets and remains substantially leaner than JPEG.
if [[ "$(webos_config_get "${DEFAULTS_FILE}" WEBOS_ENCODER)" == h264enc ]]; then
	webos_config_set "${DEFAULTS_FILE}" WEBOS_ENCODER h264enc-striped
	note "Migrated the WebOS encoder default to h264enc-striped"
fi

ENV_FILE="$(webos_user_config "${DESKTOP_USER}")"
NEW_USER_CONFIG=false
if [[ ! -f "${ENV_FILE}" ]]; then
	install -m 0600 "${PAYLOAD_DIR}/config/webos-user.env" "${ENV_FILE}"
	NEW_USER_CONFIG=true
	note "Created per-user configuration ${ENV_FILE}"
	if [[ -r "${LEGACY_ENV_FILE}" &&
		"$(webos_config_get "${LEGACY_ENV_FILE}" WEBOS_USER)" == "${DESKTOP_USER}" ]]; then
		for key in \
			WEBOS_LISTEN WEBOS_PORT WEBOS_AUTH_USER WEBOS_AUTH_PASSWORD \
			WEBOS_TITLE WEBOS_ENCODER WEBOS_USE_CPU WEBOS_INITIAL_WIDTH \
			WEBOS_INITIAL_HEIGHT WEBOS_DEBUG; do
			value="$(webos_config_get "${LEGACY_ENV_FILE}" "${key}")"
			[[ -z "${value}" ]] ||
				webos_config_set "${ENV_FILE}" "${key}" "${value}"
		done
		note "Migrated the legacy single-user configuration for ${DESKTOP_USER}"
	fi
else
	note "Preserved ${ENV_FILE}"
fi

webos_config_set "${ENV_FILE}" WEBOS_USER "${DESKTOP_USER}"
if [[ -n "${LISTEN_ARG}" || -z "$(webos_config_get "${ENV_FILE}" WEBOS_LISTEN)" ]]; then
	webos_config_set "${ENV_FILE}" WEBOS_LISTEN "${LISTEN_ADDRESS}"
else
	LISTEN_ADDRESS="$(webos_config_get "${ENV_FILE}" WEBOS_LISTEN)"
fi
if [[ -n "${PORT_ARG}" ]]; then
	LISTEN_PORT="${PORT_ARG}"
elif [[ -n "$(webos_config_get "${ENV_FILE}" WEBOS_PORT)" ]]; then
	LISTEN_PORT="$(webos_config_get "${ENV_FILE}" WEBOS_PORT)"
else
	LISTEN_PORT="$(webos_allocate_port "${DESKTOP_USER}")" ||
		die "No free WebOS port in 8081-8999"
fi
validate_port "${LISTEN_PORT}"
webos_port_available "${LISTEN_PORT}" "${DESKTOP_USER}" ||
	die "Port ${LISTEN_PORT} is already assigned to another WebOS user"
webos_config_set "${ENV_FILE}" WEBOS_PORT "${LISTEN_PORT}"
if [[ -z "$(webos_config_get "${ENV_FILE}" WEBOS_AUTH_USER)" ]]; then
	webos_config_set "${ENV_FILE}" WEBOS_AUTH_USER "${DESKTOP_USER}"
fi
grep -q '^WEBOS_TITLE=' "${ENV_FILE}" ||
	webos_config_set "${ENV_FILE}" WEBOS_TITLE ""

AUTH_WAS_GENERATED=false
AUTH_PASSWORD="$(webos_config_get "${ENV_FILE}" WEBOS_AUTH_PASSWORD)"
if [[ -z "${AUTH_PASSWORD}" ]]; then
	AUTH_PASSWORD="$(webos_random_password)"
	webos_config_set "${ENV_FILE}" WEBOS_AUTH_PASSWORD "${AUTH_PASSWORD}"
	AUTH_WAS_GENERATED=true
fi
mapfile -t certificate_paths < <(webos_certificate_paths "${DESKTOP_USER}")
TLS_CERT="${certificate_paths[0]}"
TLS_KEY="${certificate_paths[1]}"
webos_generate_certificate "${DESKTOP_USER}" false
webos_config_set "${ENV_FILE}" WEBOS_HTTPS_CERT "${TLS_CERT}"
webos_config_set "${ENV_FILE}" WEBOS_HTTPS_KEY "${TLS_KEY}"
if ! webos_default_user >/dev/null 2>&1; then
	webos_set_default_user "${DESKTOP_USER}"
fi

if [[ ! -d "${DESKTOP_DIR}" ]]; then
	cp -a "${PAYLOAD_DIR}/config/desktop" "${DESKTOP_DIR}"
	chown -R root:root "${DESKTOP_DIR}"
	note "Created administrator-editable desktop defaults in ${DESKTOP_DIR}"
else
	note "Preserved administrator-edited desktop configuration in ${DESKTOP_DIR}"
fi
# Migrate the exact one-workspace alpha default while leaving any other
# administrator-selected workspace count untouched.
if grep -Fqx '  <desktops number="1" />' "${DESKTOP_DIR}/rc.xml"; then
	sed -i \
		's#^  <desktops number="1" />$#  <desktops number="4" popupTime="800" />#' \
		"${DESKTOP_DIR}/rc.xml"
	note "Migrated the WebOS Labwc default from one workspace to four"
fi
if ! grep -q 'action name="GoToDesktop"' "${DESKTOP_DIR}/rc.xml"; then
	sed -i '/    <keybind key="A-F4">/i\
    <keybind key="C-A-Left">\
      <action name="GoToDesktop" to="left" wrap="yes" />\
    </keybind>\
    <keybind key="C-A-Right">\
      <action name="GoToDesktop" to="right" wrap="yes" />\
    </keybind>\
    <keybind key="C-A-S-Left">\
      <action name="SendToDesktop" to="left" wrap="yes" />\
    </keybind>\
    <keybind key="C-A-S-Right">\
      <action name="SendToDesktop" to="right" wrap="yes" />\
    </keybind>' "${DESKTOP_DIR}/rc.xml"
	note "Added the WebOS Labwc workspace shortcuts"
fi
if grep -Fqx 'XCURSOR_THEME=Adwaita' "${DESKTOP_DIR}/environment"; then
	sed -i \
		's/^XCURSOR_THEME=Adwaita$/XCURSOR_THEME=breeze_cursors/' \
		"${DESKTOP_DIR}/environment"
	note "Migrated the WebOS cursor default to Breeze"
fi
if grep -Fqx 'GDK_BACKEND=x11,wayland' "${DESKTOP_DIR}/environment"; then
	sed -i \
		's/^GDK_BACKEND=x11,wayland$/GDK_BACKEND=wayland,x11/' \
		"${DESKTOP_DIR}/environment"
	note "Migrated GTK applications to prefer native Wayland"
fi
if [[ ! -e "${DESKTOP_DIR}/themerc-override" ]]; then
	install -m 0644 "${PAYLOAD_DIR}/config/desktop/themerc-override" \
		"${DESKTOP_DIR}/themerc-override"
	note "Installed the WebOS dark Labwc decoration defaults"
fi

install -m 0644 "${PAYLOAD_DIR}/systemd/webos@.service" "${UNIT_FILE}"
rm -f \
	/usr/local/bin/webOS \
	/usr/share/bash-completion/completions/webOS \
	/usr/share/zsh/site-functions/_webOS \
	/usr/share/fish/vendor_completions.d/webOS.fish
install -m 0755 "${PAYLOAD_DIR}/runtime/webos" /usr/local/bin/webos
install -m 0755 "${PAYLOAD_DIR}/uninstall-webos.sh" /usr/local/sbin/webos-uninstall
install -d -m 0755 \
	/usr/share/bash-completion/completions \
	/usr/share/zsh/site-functions \
	/usr/share/fish/vendor_completions.d
install -m 0644 "${PAYLOAD_DIR}/completions/webos.bash" \
	/usr/share/bash-completion/completions/webos
install -m 0644 "${PAYLOAD_DIR}/completions/_webos" \
	/usr/share/zsh/site-functions/_webos
install -m 0644 "${PAYLOAD_DIR}/completions/webos.fish" \
	/usr/share/fish/vendor_completions.d/webos.fish

if systemctl cat docker.service >/dev/null 2>&1; then
	systemctl enable --now docker.service
	if getent group docker >/dev/null && ! id -nG "${DESKTOP_USER}" | tr ' ' '\n' | grep -qx docker; then
		usermod -aG docker "${DESKTOP_USER}"
		warn "Added ${DESKTOP_USER} to the docker group; Docker daemon access is root-equivalent"
	fi
fi

service_instance="$(systemd-escape --template=webos@.service "${DESKTOP_USER}")"

systemctl daemon-reload
systemctl enable "${service_instance}" --quiet
mapfile -t registered_users < <(webos_list_users)
for registered_user in "${registered_users[@]}"; do
	registered_env="$(webos_user_config "${registered_user}")"
	if [[ "$(webos_config_get "${registered_env}" WEBOS_ENCODER)" == h264enc ]]; then
		webos_config_set "${registered_env}" WEBOS_ENCODER h264enc-striped
		note "Migrated ${registered_user}'s encoder override to h264enc-striped"
	fi
done
healthy=true
failed_user=""
for registered_user in "${registered_users[@]}"; do
	registered_instance="$(webos_service_instance "${registered_user}")"
	if systemctl is-enabled --quiet "${registered_instance}" 2>/dev/null; then
		note "Restarting ${registered_instance}"
		if ! systemctl restart "${registered_instance}" ||
			! webos_wait_for_health "${registered_user}" 45; then
			healthy=false
			failed_user="${registered_user}"
			break
		fi
	fi
done

if [[ "${healthy}" != true ]]; then
	failed_instance="$(webos_service_instance "${failed_user}")"
	warn "HTTPS health check failed; inspect: journalctl -u ${failed_instance} -n 200"
	if [[ -n "${rollback_target}" && -d "${rollback_target}" ]]; then
		warn "Restoring previous release: ${rollback_target}"
		ln -sfn "${rollback_target}" "${CURRENT_LINK}.rollback"
		mv -Tf "${CURRENT_LINK}.rollback" "${CURRENT_LINK}"
		for registered_user in "${registered_users[@]}"; do
			systemctl restart "$(webos_service_instance "${registered_user}")" 2>/dev/null || true
		done
	fi
	exit 1
fi

if [[ -n "${replaced_release_backup}" ]]; then
	rm -rf "${replaced_release_backup}"
fi

printf '\n'
note "WebOS ${WEBOS_VERSION} is running"
note "  URL:          https://${LISTEN_ADDRESS}:${LISTEN_PORT}/"
note "  Desktop user: ${DESKTOP_USER}"
note "  Service:     ${service_instance}"
note "  Config:      ${ENV_FILE}"
note "  Certificate: ${TLS_CERT}"
note "  Operator CLI: sudo webos"
note "  Status:      systemctl status ${service_instance}"
note "  Logs:        journalctl -u ${service_instance} -f"
if [[ "${AUTH_WAS_GENERATED}" == true ]]; then
	note "  Browser user: ${DESKTOP_USER}"
	note "  Browser password (shown once): ${AUTH_PASSWORD}"
else
	note "  Browser credentials are preserved in root-only ${ENV_FILE}"
fi
if [[ -r "${LEGACY_ENV_FILE}" ]]; then
	note "  Legacy single-user config is preserved but no longer used: ${LEGACY_ENV_FILE}"
fi
note "  Uninstall:   sudo webos-uninstall"

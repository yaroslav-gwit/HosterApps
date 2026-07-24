#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly CONFIG_DIR="/etc/hoster/webos"
readonly USERS_DIR="${CONFIG_DIR}/users"
readonly DEFAULT_USER_FILE="${CONFIG_DIR}/default-user"
readonly BUILD_INFO="/opt/hoster/webos/build-info.txt"
readonly COMMON_LIB="/opt/hoster/webos/current/bin/webos-common"

note() { printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"; }
die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} [--user USER] [--container-test] [--sudo-test]

Validate an installed WebOS service on a target VM. The optional container
test downloads and runs the standard hello-world image through the host
runtime. The optional sudo test requires the selected user's existing sudo
policy to permit a non-interactive command. This script does not automate
visual/browser validation.
USAGE
}

value_from() {
	local file="${1}" key="${2}"
	python3 - "${file}" "${key}" <<'PY'
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
raw = ""
for line in path.read_text().splitlines():
    if line.startswith(f"{key}="):
        raw = line.split("=", 1)[1].strip()
if not raw:
    print("")
elif raw[0] in "\"'" or "\\" in raw:
    lexer = shlex.shlex(raw, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    print(" ".join(list(lexer)))
else:
    print(raw)
PY
}

desktop_user=""
container_test=false
sudo_test=false
while [[ $# -gt 0 ]]; do
	case "${1}" in
	--user)
		[[ -n "${2:-}" ]] || die "--user requires a value"
		desktop_user="${2}"
		shift 2
		;;
	--container-test) container_test=true; shift ;;
	--sudo-test) sudo_test=true; shift ;;
	-h|--help) usage; exit 0 ;;
	*) die "Unknown option: ${1}" ;;
	esac
done

[[ "${EUID}" -eq 0 ]] || die "Run this validation as root"
os_id="$(. /etc/os-release; printf '%s' "${ID:-}")"
case "${os_id}" in
ubuntu|fedora) ;;
*) die "Unsupported installed-system validation target: ${os_id}" ;;
esac
[[ -r "${CONFIG_DIR}/defaults.env" ]] || die "Missing ${CONFIG_DIR}/defaults.env"
[[ -r "${DEFAULT_USER_FILE}" ]] || die "Missing ${DEFAULT_USER_FILE}"
[[ -r "${BUILD_INFO}" ]] || die "Missing ${BUILD_INFO}"
[[ -r "${COMMON_LIB}" ]] || die "Missing ${COMMON_LIB}"
# shellcheck source=/dev/null
source "${COMMON_LIB}"
[[ -x /usr/local/bin/webos ]] || die "Missing installed webos operator command"
[[ -r /usr/share/bash-completion/completions/webos ]] ||
	die "Missing webos Bash completion"
[[ -r /usr/share/zsh/site-functions/_webos ]] ||
	die "Missing webos Zsh completion"
[[ -r /usr/share/fish/vendor_completions.d/webos.fish ]] ||
	die "Missing webos Fish completion"
[[ ! -e /usr/local/bin/webOS ]] ||
	die "Legacy mixed-case webOS operator command is still installed"
[[ -r /opt/hoster/webos/current/share/backgrounds/webos-wallpaper.jpg ]] ||
	die "Missing installed WebOS wallpaper"
[[ -r /opt/hoster/webos/current/share/icons/webos-whisker.png ]] ||
	die "Missing installed WebOS Whisker Menu icon"
for command_name in \
	google-chrome-stable code firefox libreoffice gedit gimp git gthumb vlc \
	curl jq; do
	command -v "${command_name}" >/dev/null ||
		die "Required workstation command is missing: ${command_name}"
done
find /usr/lib /usr/lib64 -path '*/xfce4/panel/plugins/libwhiskermenu.so' \
	-print -quit 2>/dev/null | grep -q . ||
	die "XFCE Whisker Menu plugin is not installed"
command -v fc-match >/dev/null ||
	die "fontconfig utilities are not installed"
[[ -r /etc/fonts/conf.d/69-hoster-webos-emoji.conf ]] ||
	die "WebOS terminal emoji fallback is not configured"
fc-match --format '%{family}\n' "Noto Sans Mono" | head -n 1 |
	grep -q "Noto Sans Mono" ||
	die "Noto Sans Mono is not installed"
fc-match --format '%{family}\n' "Noto Color Emoji" | head -n 1 |
	grep -q "Noto Color Emoji" ||
	die "Noto Color Emoji is not installed"
fc-match --format '%{family}\n' "Noto Sans Mono:charset=1f600" | head -n 1 |
	grep -q "Noto Color Emoji" ||
	die "Noto Sans Mono does not fall back to Noto Color Emoji"

desktop_user="${desktop_user:-$(tr -d '[:space:]' < "${DEFAULT_USER_FILE}")}"
getent passwd "${desktop_user}" >/dev/null || die "Unknown desktop user: ${desktop_user}"
ENV_FILE="${USERS_DIR}/${desktop_user}.env"
[[ -r "${ENV_FILE}" ]] || die "Missing per-user configuration: ${ENV_FILE}"
[[ "$(value_from "${ENV_FILE}" WEBOS_USER)" == "${desktop_user}" ]] ||
	die "Per-user configuration identity does not match ${desktop_user}"
listen_address="$(value_from "${ENV_FILE}" WEBOS_LISTEN)"
listen_port="$(value_from "${ENV_FILE}" WEBOS_PORT)"
auth_user="$(value_from "${ENV_FILE}" WEBOS_AUTH_USER)"
auth_password="$(value_from "${ENV_FILE}" WEBOS_AUTH_PASSWORD)"
https_cert="$(value_from "${ENV_FILE}" WEBOS_HTTPS_CERT)"
https_key="$(value_from "${ENV_FILE}" WEBOS_HTTPS_KEY)"
target_id="$(value_from "${BUILD_INFO}" TARGET_ID)"
target_version="$(value_from "${BUILD_INFO}" TARGET_VERSION)"
expected_gtk_theme="Arc-Dark"
if [[ "${target_id}" == fedora ]]; then
	rpm -q arc-theme >/dev/null ||
		die "Selectable Arc GTK theme is not installed"
else
	dpkg-query -W -f='${Status}' arc-theme 2>/dev/null |
		grep -qx 'install ok installed' ||
		die "Selectable Arc GTK theme is not installed"
fi

# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == "${target_id}" && "${VERSION_ID:-}" == "${target_version}" ]] ||
	die "Installed payload target does not match this VM"
if [[ "${target_id}" == ubuntu && "${target_version}" == 24.04 ]]; then
	for package_version in \
		"xfce4-panel=4.20.3-1~bpo24.04" \
		"libxfce4windowing-0-0:amd64=4.20.2-1~bpo24.04" \
		"libxfce4ui-2-0:amd64=4.20.0-1~bpo24.04" \
		"libxfce4ui-common=4.20.0-1~bpo24.04" \
		"xfce4-helpers=4.20.1-1ubuntu1~bpo24.04" \
		"xfce4-settings=4.20.1-1ubuntu1~bpo24.04" \
		"xfce4-whiskermenu-plugin=2.9.2-1~bpo24.04" \
		"xfdesktop4=4.20.1-1ubuntu1~bpo24.04" \
		"xfconf=4.20.0-1~bpo24.04"; do
		package="${package_version%%=*}"
		expected_version="${package_version#*=}"
		[[ "$(dpkg-query -W -f='${Version}' "${package}")" == "${expected_version}" ]] ||
			die "${package} is not the pinned Ubuntu 24.04 Wayland backport"
	done
fi

service_instance="$(systemd-escape --template=webos@.service "${desktop_user}")"
systemctl is-enabled --quiet "${service_instance}" ||
	die "${service_instance} is not enabled"
systemctl is-active --quiet "${service_instance}" ||
	die "${service_instance} is not active"

health_address="${listen_address}"
case "${listen_address}" in
0.0.0.0) health_address=127.0.0.1 ;;
::) health_address='[::1]' ;;
*:* ) health_address="[${listen_address}]" ;;
esac
temporary="$(mktemp -d)"
cleanup() { rm -rf "${temporary}"; }
trap cleanup EXIT
curl --insecure --fail --silent --show-error \
	--user "${auth_user}:${auth_password}" \
	--max-time 5 "https://${health_address}:${listen_port}/" \
	>"${temporary}/index.html" ||
	die "Authenticated HTTPS health check failed"
grep -q '<title>WebOS</title>' "${temporary}/index.html" ||
	die "Served dashboard is missing the WebOS base title"
curl --insecure --fail --silent --show-error \
	--user "${auth_user}:${auth_password}" \
	--max-time 5 "https://${health_address}:${listen_port}/icon.png" \
	>"${temporary}/icon.png" ||
	die "WebOS favicon request failed"
python3 - "${temporary}/icon.png" <<'PY'
import pathlib
import sys

icon = pathlib.Path(sys.argv[1]).read_bytes()
if not icon.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("Served WebOS favicon is not a PNG")
PY

/usr/local/bin/webos --user "${desktop_user}" status >/dev/null ||
	die "webos operator status command failed"
source /usr/share/bash-completion/completions/webos
COMP_WORDS=(webos config "")
COMP_CWORD=2
_webos
printf '%s\n' "${COMPREPLY[@]}" | grep -qx set ||
	die "webos Bash completion did not offer the config set action"

desktop_uid="$(id -u "${desktop_user}")"
pgrep -u "${desktop_uid}" -x labwc >/dev/null ||
	die "Labwc is not running as ${desktop_user}"
pgrep -u "${desktop_uid}" -x xfce4-panel >/dev/null ||
	die "XFCE panel is not running as ${desktop_user}"
panel_pid="$(pgrep -u "${desktop_uid}" -x xfce4-panel | head -n 1)"
panel_backend="$(
	tr '\0' '\n' < "/proc/${panel_pid}/environ" |
		sed -n 's/^GDK_BACKEND=//p'
)"
[[ "${panel_backend}" == wayland ]] ||
	die "XFCE panel is not using its native Wayland backend"
settings_pid="$(pgrep -u "${desktop_uid}" -x xfsettingsd | head -n 1)"
settings_backend="$(
	tr '\0' '\n' < "/proc/${settings_pid}/environ" |
	sed -n 's/^GDK_BACKEND=//p'
)"
[[ "${settings_backend}" == wayland,x11 ]] ||
	die "XFCE settings daemon does not prefer its native Wayland backend"
pgrep -u "${desktop_uid}" -x xfdesktop >/dev/null ||
	die "XFCE desktop is not running as ${desktop_user}"
desktop_pid="$(pgrep -u "${desktop_uid}" -x xfdesktop | head -n 1)"
desktop_backend="$(
	tr '\0' '\n' < "/proc/${desktop_pid}/environ" |
		sed -n 's/^GDK_BACKEND=//p'
)"
case "${desktop_backend}" in
wayland | x11) ;;
*) die "XFCE desktop is not using its explicit Wayland/Xwayland backend" ;;
esac
command -v xfce4-terminal >/dev/null ||
	die "XFCE Terminal is not installed"
pgrep -u "${desktop_uid}" -x xfce4-terminal >/dev/null ||
	die "XFCE Terminal is not running as ${desktop_user}"
[[ -r "${https_cert}" && -r "${https_key}" ]] ||
	die "Per-user TLS certificate or key is missing"
openssl x509 -in "${https_cert}" -noout -checkend 0 >/dev/null ||
	die "Per-user TLS certificate is invalid or expired"
cert_subject="$(openssl x509 -in "${https_cert}" -noout -subject)"
cert_issuer="$(openssl x509 -in "${https_cert}" -noout -issuer)"
[[ "${cert_subject#subject=}" == "${cert_issuer#issuer=}" ]] ||
	die "WebOS certificate is not self-signed"
selkies_command="$(pgrep -a -u "${desktop_uid}" -f '/venv/bin/python -m selkies' | head -n 1)"
[[ "${selkies_command}" == *"--enable-https true"* ]] ||
	die "Selkies HTTPS is not enabled"
[[ "${selkies_command}" == *"--ui-sidebar-show-apps false"* ]] ||
	die "Selkies Apps sidebar functionality is not hidden"
[[ "${selkies_command}" == *"--use-browser-cursors false"* ]] ||
	die "Selkies stable canvas cursor mode is not enabled"
configured_title="$(value_from "${ENV_FILE}" WEBOS_TITLE)"
expected_title="${configured_title:-WebOS-$(hostname)-${desktop_user}}"
[[ "${selkies_command}" == *"--ui-title ${expected_title}"* ]] ||
	die "Selkies browser title does not match ${expected_title}"

selkies_pid_before="$(pgrep -u "${desktop_uid}" -f '/venv/bin/python -m selkies' | head -n 1)"
systemctl restart "${service_instance}"
webos_wait_for_health "${desktop_user}" 45 ||
	die "Full desktop health check failed after service restart"
selkies_pid_after="$(pgrep -u "${desktop_uid}" -f '/venv/bin/python -m selkies' | head -n 1)"
[[ "${selkies_pid_before}" != "${selkies_pid_after}" ]] ||
	die "Service restart did not replace the Selkies process"
[[ "$(pgrep -u "${desktop_uid}" -fc '/venv/bin/python -m selkies')" -eq 1 ]] ||
	die "Service restart left more than one Selkies process"
note "Service restart replaced the complete desktop process tree"

desktop_home="$(getent passwd "${desktop_user}" | cut -d: -f6)"
appearance_marker="${desktop_home}/.config/hoster-webos/appearance-v4"
desktop_profile_marker="${desktop_home}/.config/hoster-webos/desktop-profile-v3"
desktop_profile_v2_marker="${desktop_home}/.config/hoster-webos/desktop-profile-v5"
panel_profile_marker="${desktop_home}/.config/hoster-webos/panel-profile-v6"
whisker_profile_marker="${desktop_home}/.config/hoster-webos/whisker-profile-v7"
terminal_profile_marker="${desktop_home}/.config/hoster-webos/terminal-profile-v8"
interaction_profile_marker="${desktop_home}/.config/hoster-webos/interaction-profile-v9"
native_appearance_marker="${desktop_home}/.config/hoster-webos/native-appearance-v10"
arc_theme_marker="${desktop_home}/.config/hoster-webos/arc-theme-v12"
dark_preference_marker="${desktop_home}/.config/hoster-webos/dark-preference-v13"
terminal_background_marker="${desktop_home}/.config/hoster-webos/terminal-background-v14"
xsettings_xml="${desktop_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
desktop_xml="${desktop_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
panel_xml="${desktop_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
terminal_xml="${desktop_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml"
gtk_settings_ini="${desktop_home}/.config/gtk-3.0/settings.ini"
[[ -e "${appearance_marker}" ]] ||
	die "WebOS appearance defaults were not initialized"
[[ -e "${desktop_profile_marker}" ]] ||
	die "WebOS desktop profile defaults were not initialized"
[[ -e "${desktop_profile_v2_marker}" ]] ||
	die "WebOS streamlined desktop profile was not initialized"
[[ -e "${panel_profile_marker}" ]] ||
	die "WebOS polished panel profile was not initialized"
[[ -e "${whisker_profile_marker}" ]] ||
	die "WebOS Whisker Menu profile was not initialized"
[[ -e "${terminal_profile_marker}" ]] ||
	die "WebOS terminal profile was not initialized"
[[ -e "${interaction_profile_marker}" ]] ||
	die "WebOS interaction profile was not initialized"
[[ -e "${native_appearance_marker}" ]] ||
	die "WebOS native Wayland appearance profile was not initialized"
[[ -e "${arc_theme_marker}" ]] ||
	die "WebOS universal selectable theme migration was not initialized"
[[ -e "${dark_preference_marker}" ]] ||
	die "WebOS modern GTK dark preference was not initialized"
[[ -e "${terminal_background_marker}" ]] ||
	die "WebOS terminal background profile was not initialized"
grep -q "^gtk-theme-name=${expected_gtk_theme}$" "${gtk_settings_ini}" ||
	die "GTK dark first-frame settings were not initialized"
grep -q "value=\"${expected_gtk_theme}\"" "${xsettings_xml}" ||
	die "XFCE dark theme is not active"
grep -q 'value="Papirus-Dark"' "${xsettings_xml}" ||
	die "Papirus Dark icon theme is not active"
grep -q 'name="CursorThemeName" type="string" value="breeze_cursors"' "${xsettings_xml}" ||
	die "Breeze cursor theme is not active"
[[ -r /usr/share/icons/breeze_cursors/index.theme ]] ||
	die "Breeze cursor theme is not installed"
grep -q '/opt/hoster/webos/current/share/backgrounds/webos-wallpaper.jpg' "${desktop_xml}" ||
	die "WebOS desktop wallpaper is not active"
grep -q 'name="monitorWL-1"' "${desktop_xml}" ||
	die "WebOS wallpaper is not configured for the native Labwc output"
grep -q 'name="include-all-workspaces" type="bool" value="true"' "${panel_xml}" ||
	die "XFCE tasklist does not include all workspaces"
grep -q 'name="monitors-to-include" type="string" value="all"' "${panel_xml}" ||
	die "XFCE tasklist does not include all monitors"
grep -q 'name="font-use-system" type="bool" value="false"' "${terminal_xml}" ||
	die "XFCE Terminal is still using the system font"
grep -q 'name="font-name" type="string" value="Noto Sans Mono 10.5"' "${terminal_xml}" ||
	die "XFCE Terminal does not use Noto Sans Mono at 10.5pt"
grep -q 'name="misc-default-geometry" type="string" value="180x35"' "${terminal_xml}" ||
	die "XFCE Terminal does not use the 180x35 default geometry"
grep -q 'name="background-mode" type="string" value="TERMINAL_BACKGROUND_TRANSPARENT"' "${terminal_xml}" ||
	die "XFCE Terminal does not use the transparent background mode"
case "${os_id}" in
ubuntu) expected_terminal_darkness="0.930000" ;;
fedora) expected_terminal_darkness="0.920000" ;;
esac
grep -q "name=\"background-darkness\" type=\"double\" value=\"${expected_terminal_darkness}\"" "${terminal_xml}" ||
	die "XFCE Terminal does not use the distro-matched background opacity"
python3 - "${panel_xml}" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
panels = root.find("./property[@name='panels']")
if panels is None:
    raise SystemExit("XFCE panel layout is missing")
panel_ids = [value.get("value") for value in panels.findall("./value")]
if panel_ids != ["1"]:
    raise SystemExit(f"unexpected XFCE panel layout: {panel_ids}")
panel = panels.find("./property[@name='panel-1']")
if panel is None:
    raise SystemExit("XFCE top panel is missing")
size = panel.find("./property[@name='size']")
icon_size = panel.find("./property[@name='icon-size']")
if size is None or size.get("value") != "27":
    raise SystemExit("XFCE panel height is not 27px")
if icon_size is None or icon_size.get("value") != "25":
    raise SystemExit("XFCE panel icon size is not 25px")
plugin_ids_property = panel.find("./property[@name='plugin-ids']")
if plugin_ids_property is None:
    raise SystemExit("XFCE top panel has no plugin list")
plugin_ids = [
    value.get("value")
    for value in plugin_ids_property.findall("./value")
]
plugins = root.find("./property[@name='plugins']")
if plugins is None:
    raise SystemExit("XFCE panel plugins are missing")
plugin_map = {
    plugin.get("name").removeprefix("plugin-"): plugin
    for plugin in plugins.findall("./property")
}
for plugin in plugin_map.values():
    if plugin.get("value") == "pager":
        raise SystemExit("XFCE pager plugin is still configured")
    if plugin.get("value") == "actions":
        raise SystemExit("XFCE Action Buttons plugin is still configured")
tasklists = [
    plugin for plugin in plugin_map.values()
    if plugin.get("value") == "tasklist"
]
if not tasklists:
    raise SystemExit("XFCE Window Buttons tasklist is missing")
for tasklist in tasklists:
    actual = {
        prop.get("name"): prop.get("value")
        for prop in tasklist.findall("./property")
    }
    expected = {
        "include-all-workspaces": "true",
        "include-all-monitors": "true",
        "monitors-to-include": "all",
        "grouping": "false",
        "sort-order": "4",
    }
    for name, value in expected.items():
        if actual.get(name) != value:
            raise SystemExit(
                f"XFCE Window Buttons {name} is {actual.get(name)!r}, "
                f"expected {value!r}"
            )
menus = [
    plugin for plugin in plugin_map.values()
    if plugin.get("value") == "whiskermenu"
]
if not menus:
    raise SystemExit("XFCE Whisker Menu is missing")
for menu in menus:
    title = menu.find("./property[@name='show-button-title']")
    if title is None or title.get("value") != "true":
        raise SystemExit("XFCE Whisker Menu button title is not enabled")
    title_text = menu.find("./property[@name='button-title']")
    if title_text is None or title_text.get("value") != "Apps":
        raise SystemExit("XFCE Whisker Menu button title is not Apps")
    icon = menu.find("./property[@name='button-icon']")
    if icon is None or icon.get("value") != "/opt/hoster/webos/current/share/icons/webos-whisker.png":
        raise SystemExit("XFCE Whisker Menu icon is not configured")
    expected = {
        "launcher-show-name": "true",
        "launcher-icon-size": "1",
        "category-icon-size": "2",
        "menu-width": "550",
        "menu-height": "650",
        "menu-opacity": "95",
    }
    actual = {
        prop.get("name"): prop.get("value")
        for prop in menu.findall("./property")
    }
    for name, value in expected.items():
        if actual.get(name) != value:
            raise SystemExit(
                f"XFCE Whisker Menu {name} is {actual.get(name)!r}, expected {value!r}"
            )
ordered = [plugin_map[plugin_id] for plugin_id in plugin_ids]
clock_indexes = [
    index for index, plugin in enumerate(ordered)
    if plugin.get("value") == "clock"
]
if len(clock_indexes) != 2:
    raise SystemExit(f"expected two XFCE clocks, found {len(clock_indexes)}")
time_index, date_index = clock_indexes
if date_index != time_index + 2:
    raise SystemExit("XFCE time and date clocks are not separated by one plugin")
separator = ordered[time_index + 1]
if separator.get("value") != "separator":
    raise SystemExit("XFCE clocks do not have a separator between them")
style = separator.find("./property[@name='style']")
if style is None or style.get("value") != "0":
    raise SystemExit("XFCE clock separator is not transparent")
time_clock = ordered[time_index]
date_clock = ordered[date_index]
time_values = {
    prop.get("name"): prop.get("value")
    for prop in time_clock.findall("./property")
}
date_values = {
    prop.get("name"): prop.get("value")
    for prop in date_clock.findall("./property")
}
if time_values.get("mode") != "2" or time_values.get("digital-layout") != "3":
    raise SystemExit("XFCE time clock does not use the approved one-line layout")
if time_values.get("command") != "true":
    raise SystemExit("XFCE time clock calendar command is not disabled")
if date_values.get("digital-layout") != "2":
    raise SystemExit("XFCE date clock does not use the approved one-line layout")
PY
grep -q '<desktops number="4"' /etc/hoster/webos/desktop/rc.xml ||
	die "Labwc is not configured with four workspaces"
grep -q 'action name="GoToDesktop"' /etc/hoster/webos/desktop/rc.xml ||
	die "Labwc workspace switching shortcuts are missing"
if sed -n '/identifier="xfce4-panel"/,/windowRule>/p' \
	/etc/hoster/webos/desktop/rc.xml |
	grep -q 'ignoreFocusRequest="yes"'; then
	die "Labwc still suppresses Whisker Menu focus requests"
fi

probe_dir="${desktop_home}/.local/state/hoster-webos-validation"
runuser -u "${desktop_user}" -- mkdir -p "${probe_dir}"
if [[ -f "${probe_dir}/persistence-probe" ]]; then
	note "Existing home persistence probe found"
else
	runuser -u "${desktop_user}" -- touch "${probe_dir}/persistence-probe"
	note "Created persistence probe; rerun after reboot to verify it survives"
fi

if [[ "${container_test}" == true ]]; then
	runuser -u "${desktop_user}" -- docker run --rm hello-world
fi

if [[ "${sudo_test}" == true ]]; then
	runuser -u "${desktop_user}" -- sudo -n true ||
		die "${desktop_user} does not have non-interactive sudo access"
fi

note "Installed WebOS checks passed for ${service_instance}"
note "Manually confirm the streamed XFCE desktop through a browser or SSH tunnel"

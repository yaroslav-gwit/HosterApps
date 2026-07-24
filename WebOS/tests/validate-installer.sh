#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly INSTALLER="${1:-}"
readonly EXPECTED_VERSION="${2:-}"

die() { printf '[%s] Error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

[[ -n "${INSTALLER}" ]] || die "Usage: ${SCRIPT_NAME} INSTALLER [EXPECTED_VERSION]"
[[ -x "${INSTALLER}" ]] || die "Installer is missing or not executable: ${INSTALLER}"

actual_version="$("${INSTALLER}" --version)"
if [[ -n "${EXPECTED_VERSION}" && "${actual_version}" != "${EXPECTED_VERSION}" ]]; then
	die "Expected version ${EXPECTED_VERSION}, got ${actual_version}"
fi
"${INSTALLER}" --help >/dev/null

temporary="$(mktemp -d)"
cleanup() { rm -rf "${temporary}"; }
trap cleanup EXIT
"${INSTALLER}" --extract "${temporary}/payload" >/dev/null

required=(
	build-info.txt
	install-webos.sh
	uninstall-webos.sh
	runtime/webos-session
	runtime/webos-xfce-session
	runtime/webos-common
	runtime/webos
	systemd/webos@.service
	config/webos.env
	config/webos-user.env
	config/fontconfig/69-hoster-webos-emoji.conf
	completions/webos.bash
	completions/_webos
	completions/webos.fish
	assets/webos-wallpaper.jpg
	assets/webos-whisker.png
)
for path in "${required[@]}"; do
	[[ -e "${temporary}/payload/${path}" ]] || die "Missing payload path: ${path}"
done

bash -n \
	"${temporary}/payload/install-webos.sh" \
	"${temporary}/payload/uninstall-webos.sh" \
	"${temporary}/payload/runtime/webos" \
	"${temporary}/payload/runtime/webos-common" \
	"${temporary}/payload/runtime/webos-session" \
	"${temporary}/payload/runtime/webos-xfce-session"
find "${temporary}/payload/wheels" -maxdepth 1 -type f -name '*.whl' -print -quit |
	grep -q . || die "Payload wheelhouse is empty"

python3 - "${temporary}/payload" <<'PY'
import pathlib
import sys
import zipfile

payload = pathlib.Path(sys.argv[1])
defaults_text = (payload / "config/webos.env").read_text()
user_env_text = (payload / "config/webos-user.env").read_text()
session_text = (payload / "runtime/webos-session").read_text()
desktop_text = (payload / "runtime/webos-xfce-session").read_text()
desktop_environment_text = (payload / "config/desktop/environment").read_text()
installer_text = (payload / "install-webos.sh").read_text()
fontconfig_text = (
    payload / "config/fontconfig/69-hoster-webos-emoji.conf"
).read_text()
unit_text = (payload / "systemd/webos@.service").read_text()
if "WEBOS_ENABLE_HTTPS=true" not in defaults_text:
    raise SystemExit("Payload does not enable HTTPS by default")
if "WEBOS_ENCODER=h264enc-striped" not in defaults_text:
    raise SystemExit("Payload does not use the cross-distro striped H.264 default")
if "\nWEBOS_TITLE=\n" not in f"\n{user_env_text}":
    raise SystemExit("Per-user payload does not expose WEBOS_TITLE")
if "--enable-https true" not in session_text:
    raise SystemExit("Selkies HTTPS is not mandatory")
if "--ui-sidebar-show-apps false" not in session_text:
    raise SystemExit("Selkies Apps sidebar is not disabled")
if "--use-browser-cursors false" not in session_text:
    raise SystemExit("Selkies stable canvas cursor mode is not enabled")
if "WebOS-$(hostname)-${desktop_user}" not in session_text:
    raise SystemExit("Generated hostname/user title is missing")
if "GDK_BACKEND=wayland,x11" not in desktop_environment_text:
    raise SystemExit("GTK does not prefer its native Wayland backend")
if "export GTK_THEME=" in desktop_text:
    raise SystemExit("Desktop session still overrides user-selected GTK themes")
if "native-appearance-v10" not in desktop_text:
    raise SystemExit("Native Wayland appearance migration is missing")
if "gtk-theme-name=${WEBOS_DEFAULT_GTK_THEME}" not in desktop_text:
    raise SystemExit("GTK dark first-frame settings are missing")
if "arc-theme-v12" not in desktop_text or "Arc-Dark" not in desktop_text:
    raise SystemExit("Universal selectable dark-theme migration is missing")
if "dark-preference-v13" not in desktop_text or "color-scheme prefer-dark" not in desktop_text:
    raise SystemExit("Modern GTK dark color-scheme preference is missing")
if (
    "terminal-background-v14" not in desktop_text
    or "TERMINAL_BACKGROUND_TRANSPARENT" not in desktop_text
    or 'darkness="0.930000"' not in desktop_text
    or 'darkness="0.920000"' not in desktop_text
):
    raise SystemExit("Distro-matched transparent terminal background is missing")
if "arc-theme" not in installer_text:
    raise SystemExit("Selectable GTK theme package is missing")
if '[[ ! -e "${settings_file}" ]]' not in desktop_text:
    raise SystemExit("GTK startup settings do not preserve an existing user file")
if "xfce4-whiskermenu-plugin" not in installer_text:
    raise SystemExit("Installer does not install XFCE Whisker Menu")
if "gsettings-desktop-schemas" not in installer_text:
    raise SystemExit("Ubuntu GTK settings schema package is missing")
for font_package in (
    "fonts-noto-color-emoji",
    "fonts-noto-mono",
    "google-noto-color-emoji-fonts",
    "google-noto-sans-mono-fonts",
):
    if font_package not in installer_text:
        raise SystemExit(f"Installer does not include font package: {font_package}")
for workstation_package in ("gedit", "gthumb", "vlc"):
    if workstation_package not in installer_text:
        raise SystemExit(
            f"Installer does not include workstation package: {workstation_package}"
        )
if "Noto Sans Mono" not in fontconfig_text or "Noto Color Emoji" not in fontconfig_text:
    raise SystemExit("Payload does not configure the Noto terminal emoji fallback")
if '"${property}" string whiskermenu' not in desktop_text:
    raise SystemExit("Desktop profile does not enable XFCE Whisker Menu")
for required_panel_setting in (
    "panel-profile-v6",
    "/panels/panel-1/size uint 27",
    "/panels/panel-1/icon-size uint 25",
    "/share/icons/webos-whisker.png",
    "whisker-profile-v7",
    '/launcher-show-name" bool true',
    '/launcher-icon-size" int 1',
    '/category-icon-size" int 2',
    '/menu-width" int 550',
    '/menu-height" int 650',
    '/menu-opacity" int 95',
    '"${property}/command" string true',
    "interaction-profile-v9",
    '/grouping" bool false',
    '/sort-order" uint 4',
):
    if required_panel_setting not in desktop_text:
        raise SystemExit(
            f"Desktop profile is missing panel setting: {required_panel_setting}"
        )
for terminal_setting in (
    "terminal-profile-v8",
    'xfce4-terminal /font-use-system bool false',
    'xfce4-terminal /font-name string "Noto Sans Mono 10.5"',
    'xfce4-terminal /misc-default-geometry string "180x35"',
):
    if terminal_setting not in desktop_text:
        raise SystemExit(
            f"Desktop profile is missing terminal setting: {terminal_setting}"
        )
if "GDK_BACKEND=wayland xfce4-panel" not in desktop_text:
    raise SystemExit("XFCE panel launch does not enforce native Wayland")
if (
    "GDK_BACKEND=wayland xfdesktop" not in desktop_text
    or "GDK_BACKEND=x11 xfdesktop" not in desktop_text
):
    raise SystemExit("XFCE desktop launch does not provide its Wayland/Xwayland fallback")
if "EnvironmentFile=/etc/hoster/webos/users/%i.env" not in unit_text:
    raise SystemExit("Systemd unit is not per-user configured")

build_info = {}
for line in (payload / "build-info.txt").read_text().splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        build_info[key] = value
native_packages = payload / "native-packages/ubuntu-24.04"
native_sources = payload / "licenses/sources/xubuntu-xfce-4.20-noble"
if build_info.get("TARGET_ID") == "ubuntu" and build_info.get("TARGET_VERSION") == "24.04":
    if build_info.get("XFCE_PANEL_BUILD") != "4.20.3-1~bpo24.04":
        raise SystemExit("Ubuntu 24.04 XFCE panel build metadata is missing")
    if build_info.get("XFCE_SETTINGS_BUILD") != "4.20.1-1ubuntu1~bpo24.04":
        raise SystemExit("Ubuntu 24.04 XFCE settings build metadata is missing")
    if len(list(native_packages.glob("*.deb"))) != 13:
        raise SystemExit("Ubuntu 24.04 XFCE backport payload is incomplete")
    if len(list(native_sources.iterdir())) != 21:
        raise SystemExit("Ubuntu 24.04 XFCE corresponding source payload is incomplete")
elif native_packages.exists():
    raise SystemExit("Non-Noble payload unexpectedly contains XFCE backports")

wallpaper = payload / "assets/webos-wallpaper.jpg"
if not wallpaper.read_bytes().startswith(b"\xff\xd8\xff"):
    raise SystemExit("Payload WebOS wallpaper is not a JPEG")
whisker_icon = payload / "assets/webos-whisker.png"
if not whisker_icon.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("Payload WebOS Whisker icon is not a PNG")

selkies_wheels = sorted((payload / "wheels").glob("selkies-*.whl"))
if len(selkies_wheels) != 1:
    raise SystemExit(f"Expected one Selkies wheel, found {len(selkies_wheels)}")

with zipfile.ZipFile(selkies_wheels[0]) as wheel:
    names = wheel.namelist()
    index_name = next(
        (name for name in names if name.endswith("selkies/selkies_web/index.html")),
        None,
    )
    icon_name = next(
        (name for name in names if name.endswith("selkies/selkies_web/icon.png")),
        None,
    )
    if not index_name or b"<title>WebOS</title>" not in wheel.read(index_name):
        raise SystemExit("Selkies dashboard does not contain the WebOS title")
    if not icon_name or not wheel.read(icon_name).startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit("Selkies dashboard does not contain the WebOS favicon")
    scripts = (
        wheel.read(name)
        for name in names
        if name.endswith(".js") and "selkies/selkies_web/" in name
    )
    if not any(b"document.title=" in script for script in scripts):
        raise SystemExit("Selkies dashboard does not apply the dynamic tab title")
    scripts = (
        wheel.read(name)
        for name in names
        if name.endswith(".js") and "selkies/selkies_web/" in name
    )
    if not any(b"sidebar-brand-row" in script and b"WebOS" in script for script in scripts):
        raise SystemExit("Selkies dashboard does not contain the compact WebOS sidebar brand")
PY

printf '[%s] Validated %s (%s)\n' "${SCRIPT_NAME}" "${INSTALLER}" "${actual_version}"

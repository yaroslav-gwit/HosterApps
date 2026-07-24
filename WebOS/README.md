# WebOS native XFCE/Selkies installers

WebOS is a native browser desktop for a real Linux VM user. It
builds self-extracting installers for:

| Target | Artifact |
| --- | --- |
| Ubuntu 24.04 amd64 | `webos-v0.2.0-ubuntu-24.04-amd64.run` |
| Ubuntu 26.04 amd64 | `webos-v0.2.0-ubuntu-26.04-amd64.run` |
| Fedora 44 x86_64 | `webos-v0.2.0-fedora-44-amd64.run` |

All builds and release files are produced locally. This project deliberately
contains no GitHub Actions workflow and uploads nothing.

## What it installs

The visible desktop is XFCE on every target: XFCE panel, desktop, settings
daemon, terminal, application finder, and Thunar. Labwc is used only as the
hidden nested Wayland compositor/window manager. The XFCE panel uses native
Wayland windowing integration; graphical applications without native Wayland
support run through Labwc-managed Xwayland.

The workstation application set includes Google Chrome, Firefox, Visual Studio
Code, LibreOffice Writer/Calc/Impress, GIMP, gThumb, VLC, gedit, Git, curl, and
jq. Chrome, Firefox, and VS Code use their official vendor repositories where
applicable, so they continue receiving normal system-package updates after
installation.

```text
Browser
  -> Selkies (HTTPS + secure WebSocket, basic auth)
  -> pixelflux outer capture compositor + software encoding
  -> nested Labwc Wayland compositor
  -> Xwayland
  -> XFCE desktop as the selected real VM user
```

This is not a Webtop container. The session has the user's normal home,
filesystem, processes, sudo policy, and host container runtime. CPU rendering
and encoding are the defaults; GPU passthrough is not required.

Audio, microphone forwarding, gamepads, multiple displays, and WebRTC transport
are disabled in this release. The default single-port WebSocket transport is
simpler to proxy and validate. The pinned Selkies/pixelflux combination also
logs non-fatal errors for optional Wayland clipboard and output-enumeration
hooks that pixelflux 2.0.0 does not expose; desktop streaming and input work,
but browser/desktop clipboard synchronization is not supported in this release.
The Selkies Apps sidebar section is explicitly disabled. Users install and
launch software through the native XFCE desktop, terminal, package manager, or
their own repositories.

## Build locally

Docker or Podman is the only host build dependency. The target VM does not need
a compiler.

```bash
cd WebOS
./validate.sh
./build.sh
```

`./build.sh` builds all three installers into `dist/`. Select a subset with:

```bash
./build.sh --target ubuntu-24.04
./build.sh --target ubuntu-26.04
./build.sh --target fedora-44
./build.sh --target ubuntu       # both Ubuntu releases
```

Choose an engine explicitly when required:

```bash
./build.sh --engine podman
```

To build, validate, checksum, and prepare local release notes in one command:

```bash
./release-local.sh --engine podman
```

That command creates `dist/SHA256SUMS` and `dist/RELEASE_NOTES.md`. It does not
publish or upload anything.

The builders pin:

- Selkies source revision
  `12f5033b43b5b44a68bdd1ad804a49985832566a`;
- `pixelflux==2.0.0`;
- `pcmflux==2.0.0`;
- LinuxServer reference revision
  `9d7047537c30f978f3b9a5f0d82ba397fe510257`.

The full Python runtime dependency set is pinned in
`build/python-constraints.txt`.

Each distro builder compiles or downloads Python wheels in its own container.
The complete wheelhouse is embedded in the `.run`; installation uses
`pip --no-index`, so target provisioning does not contact PyPI and requires no
development toolchain. The target VM does need outbound access to its
distribution repositories and the official Google, Microsoft, and Mozilla
package repositories while the workstation applications are installed.

Build metadata records the WebOS version, target, pins, UTC build date, source
commit, and source epoch in the payload and installed release.

## Install

Run the artifact that exactly matches the VM:

```bash
sudo ./webos-v0.2.0-ubuntu-24.04-amd64.run
sudo ./webos-v0.2.0-ubuntu-26.04-amd64.run
sudo ./webos-v0.2.0-fedora-44-amd64.run
```

The installer validates distribution, release, and x86_64 architecture before
installing packages. It selects `SUDO_USER` when possible. On machines with
several normal accounts, be explicit:

```bash
sudo ./webos-v0.2.0-ubuntu-26.04-amd64.run \
  --user researcher \
  --listen 127.0.0.1 \
  --port 8081
```

The first install generates a browser basic-auth password and prints it once.
It remains in the root-only per-user file
`/etc/hoster/webos/users/<username>.env`. It also generates a distinct
self-signed HTTPS certificate and private key for that session. The first user
receives port 8081; subsequent users receive the first unassigned port above it
unless `--port` is supplied.

### Multi-user sessions

WebOS supports multiple simultaneous real Linux users on one VM. Each user has
an independent Selkies, Wayland, Labwc, Xwayland, and XFCE process tree with
their own home, browser credentials, certificate, runtime directory, and TCP
port. The application payload and administrator-managed desktop defaults are
shared.

WebOS only registers existing accounts; it never creates Linux users or grants
sudo. Create accounts using the distribution's normal policy, then register
them:

```bash
sudo useradd --create-home --shell /bin/bash alice
sudo useradd --create-home --shell /bin/bash bob

sudo webos user add alice
sudo webos user add bob
```

The resulting layout normally resembles:

```text
alice -> webos@alice.service -> https://127.0.0.1:8081
bob   -> webos@bob.service   -> https://127.0.0.1:8082
```

List sessions and retrieve the generated credentials:

```bash
sudo webos user list
sudo webos user credentials alice
sudo webos user credentials bob
```

Choose which session the short forms such as `webos status` control:

```bash
sudo webos user set-default alice
sudo webos status
sudo webos --user bob status
sudo webos user restart bob
```

To remove one WebOS session without deleting the Linux account or home:

```bash
sudo webos user remove bob
```

Users share the VM network namespace. If Alice starts a development server on
`127.0.0.1:3000`, Bob can open `https://localhost:3000` or
`http://localhost:3000`, as appropriate for that application, from his own
desktop. No WebOS proxying is required. Normal Unix file permissions still
apply to source trees; use separate clones or an explicitly managed shared
group/directory.

This is intended for cooperating users. A user with sudo or Docker daemon
access can become root and inspect or modify every session. Use separate VMs
for mutually untrusted users. Users also share TCP port space and the VM's
finite CPU/RAM; each software-encoded active desktop adds resource usage.

### Desktop appearance

Every target uses the bundled 1920×1080 WebOS plexus wallpaper and the
distro-packaged `Arc-Dark` XFCE theme by default. The Arc family is installed
on Ubuntu and Fedora so XFCE Appearance exposes real selectable styles while
the fleet retains the same Arc-Dark baseline. WebOS also seeds the standard
`prefer-dark` color-scheme preference once for modern GTK4 applications such
as gedit; users may change it afterward.
Dark Labwc window decorations are also installed. The complete `Papirus-Dark` icon theme and
the modern Breeze cursor theme are selected on Ubuntu and Fedora so the same
application, file, and pointer artwork is available on all supported systems.
GTK applications prefer their native Wayland backend, and XFCE's settings
daemon mirrors Appearance choices into GTK at runtime. WebOS does not export a
hard-coded `GTK_THEME`, so choosing another theme in Appearance takes effect
normally. The remote pointer uses Selkies' canvas renderer, with ordered cursor
decoding, to avoid a stale hand or text cursor winning a rapid surface change.
The panel and settings daemon remain native Wayland clients. `xfdesktop` is
probed separately because Fedora 44's package is built without Wayland support;
only that wallpaper process falls back to rootless Xwayland on Fedora.

WebOS provides four native Labwc workspaces. Use `Ctrl+Alt+Left` and
`Ctrl+Alt+Right` to move between them, and move the focused window with
`Ctrl+Alt+Shift+Left` or `Ctrl+Alt+Shift+Right`. Labwc does not publish the X11
EWMH desktop properties that XFCE's pager expects through Xwayland, so pager
clicks are not relied on in this release. The Window Buttons tasklist shows
windows from every workspace and every monitor by default. The unsupported
pager is omitted from the top panel, and the redundant bottom launcher panel is
removed. The searchable XFCE Whisker Menu replaces the basic Applications Menu
on every distribution. Its `Apps` button uses the bundled WebOS launcher icon
with both icon and title visible. Whisker uses specific application names
instead of generic desktop-entry descriptions, small application and category
icons, a 550×650-pixel menu, and 95% background opacity. Labwc permits the
panel menu to accept focus so its categories and launchers remain clickable
when the menu overlaps another window. The single top panel is 27px high with
25px icons. Action Buttons are omitted; the right side uses separate one-line
time and date clocks with a transparent separator, and the time-only clock
does not open a calendar.

XFCE Terminal defaults to `Noto Sans Mono` at 10.5pt and a `180x35` initial
geometry. The distro-native Noto Color Emoji font is installed as its emoji
fallback, so terminal applications can display emoji without replacing the
readable monospace font used for normal text. These are one-time per-user
defaults and remain user-editable afterward.

Window Buttons runs through XFCE's native Wayland windowing integration on
every supported platform. Buttons include all workspaces and monitors, retain
window creation order (`Sorting order: None`), and never group windows by
application. Clicking an active button minimizes its window; clicking it again
restores the window. Ubuntu 24.04's distro XFCE 4.18 tasklist cannot provide
these semantics under Labwc, so that installer carries a checksum-pinned
minimal XFCE 4.20 backport set built for Noble. That set includes the matching
4.20 settings manager and `libxfce4ui`, because Noble's 4.18 control-panel host
uses an X11-only `GtkSocket` and crashes when embedded in a native Wayland
session. No PPA is left configured.

Appearance initialization is deliberately one-time per real user. WebOS writes
`~/.config/hoster-webos/appearance-v4` after applying the defaults, so later
wallpaper or theme choices made by the user are not reset during service
restarts or upgrades. To intentionally reapply the WebOS defaults:

```bash
rm ~/.config/hoster-webos/appearance-v4
sudo webos restart
```

Icon and tasklist defaults use a one-time marker so existing users receive the
cross-distribution profile without losing later choices. Panel, menu, and
cursor cleanup uses its own versioned marker. To intentionally reapply both:

```bash
rm ~/.config/hoster-webos/desktop-profile-v3
rm ~/.config/hoster-webos/desktop-profile-v5
rm ~/.config/hoster-webos/panel-profile-v6
rm ~/.config/hoster-webos/whisker-profile-v7
rm ~/.config/hoster-webos/terminal-profile-v8
rm ~/.config/hoster-webos/interaction-profile-v9
rm ~/.config/hoster-webos/native-appearance-v10
rm ~/.config/hoster-webos/arc-theme-v12
rm ~/.config/hoster-webos/dark-preference-v13
rm ~/.config/hoster-webos/terminal-background-v14
sudo webos restart
```

WebOS initializes XFCE Terminal with a lightly transparent background. Ubuntu
uses `0.93` background darkness and Fedora uses `0.92`; this small
distribution-specific adjustment produces the same apparent opacity across
their different XFCE Terminal builds. The versioned marker applies the default
once, so users remain free to change it afterward.

### Browser identity

The browser tab defaults to `WebOS-<hostname>-<selected username>`. The compact
Selkies sidebar header always says `WebOS` on its own row, with its controls on
a second row, so long per-session names cannot distort the dashboard.
The bundled WebOS favicon identifies the session when several desktops are
open. To set a custom title, edit the root-only environment file:

```bash
sudoedit /etc/hoster/webos/users/researcher.env
```

Set, for example:

```text
WEBOS_TITLE="WebOS-Cryogenics-Lab"
```

An empty `WEBOS_TITLE=` restores the per-user default. Apply the change with:

```bash
sudo systemctl restart webos@researcher.service
```

The installed operator command provides the same operation with validation,
automatic restart, an authenticated health check, and rollback:

```bash
sudo webos --user researcher config set title "WebOS-Cryogenics-Lab"
sudo webos --user researcher config reset title
```

Other installer operations:

```bash
./webos-v0.2.0-ubuntu-26.04-amd64.run --help
./webos-v0.2.0-ubuntu-26.04-amd64.run --version
./webos-v0.2.0-ubuntu-26.04-amd64.run --extract /tmp/webos-payload
sudo ./webos-v0.2.0-ubuntu-26.04-amd64.run --uninstall
sudo ./webos-v0.2.0-ubuntu-26.04-amd64.run --uninstall --keep-config
```

## Connect safely

Every Selkies service uses HTTPS with a unique self-signed certificate. Selkies
still binds to loopback by default, preserving the least-exposure behavior. For
temporary access, use an SSH tunnel:

```bash
ssh -L 8081:127.0.0.1:8081 researcher@vm.example
```

Then open `https://127.0.0.1:8081/` and accept the internal certificate, or add
the generated certificate to the administrator workstation's trust store.

For persistent remote access, place Caddy or another authenticated reverse
proxy in front of each loopback port. The proxy may either trust the generated
certificate or explicitly disable upstream certificate verification for this
internal hop. Basic authentication remains enabled per session.

For direct internal-VM access without a tunnel, explicitly bind a session to
the VM network:

```bash
sudo webos --user researcher config set listen 0.0.0.0
sudo webos --user researcher url
```

Open `https://VM_ADDRESS:PORT/`. The certificate includes localhost, the
hostname, and the VM addresses present when it is generated, but remains
self-signed and therefore untrusted until accepted or imported. Regenerate it
after changing the VM hostname or addresses:

```bash
sudo webos user renew-certificate researcher
```

Binding `0.0.0.0` exposes that authenticated session on every VM interface and
is an explicit administrator decision.

## Host access and privileges

The selected account is not replaced or recreated. WebOS does not change its
sudo policy and does not grant sudo access.

On Ubuntu, the installer installs the distro Docker package and adds the user
to the `docker` group. Docker daemon access is effectively root-equivalent, and
the installer prints a warning when it makes this change.

On Fedora, it installs Fedora's Moby/Docker packages. If a working Docker
service is already installed, WebOS preserves and starts it. A conflicting
`podman-docker` command shim is removed when Docker must be installed; unrelated
Podman data is not deleted. The selected user is added to the `docker` group,
and the installer warns that daemon access is root-equivalent.

WebOS does not add audio, video, or device-group memberships and does not
enable systemd lingering. It is a full trusted user session, not a security
boundary between mutually untrusted users. The VM is the isolation boundary.

## Layout and upgrades

```text
/opt/hoster/webos/
├── current -> releases/<version>/
├── releases/<version>/
│   ├── bin/
│   ├── venv/
│   ├── share/backgrounds/webos-wallpaper.jpg
│   ├── share/licenses/
│   └── build-info.txt
└── build-info.txt

/etc/hoster/webos/
├── defaults.env
├── default-user
├── users/
│   ├── alice.env
│   └── bob.env
├── certs/
│   ├── alice.crt
│   ├── alice.key
│   ├── bob.crt
│   └── bob.key
└── desktop/

/var/lib/hoster/webos/
/var/log/hoster/webos/
/etc/systemd/system/webos@.service
```

Reinstalling replaces project-owned runtime assets and the systemd unit,
preserves every per-user environment and certificate, preserves
administrator-edited desktop configuration, atomically moves `current`,
restarts every enabled registered service, and performs authenticated local
HTTPS health checks. If a check fails after an upgrade, the installer restores
the previous `current` target when available. Upgrading the original
single-user installation migrates `/etc/hoster/webos/webos.env` into the selected
user's registry entry and leaves the old file untouched as an unused backup.

The installer never copies defaults over the user's home. XFCE may naturally
create or update that user's own XFCE preferences while the desktop is used.

## Operations and diagnostics

The operator utility is named lowercase `webos` everywhere. It is installed in
`/usr/local/bin` with Bash, Zsh, and Fish completions; the former mixed-case
`webOS` command and completions are removed during upgrade. Run `webos` without
arguments for a safe configuration summary and full command help:

```bash
sudo webos
sudo webos user list
sudo webos user add reviewer
sudo webos user credentials reviewer
sudo webos --user reviewer status
sudo webos status
sudo webos diagnostics
sudo webos logs --follow
sudo webos restart
```

Commands without `--user` operate on `/etc/hoster/webos/default-user`.
Operators can manage browser identity, credentials, listener, encoder, and
initial resolution independently for every registered user:

The default `h264enc-striped` CPU encoder is used on every supported platform.
It avoids the black-canvas behaviour observed with the plain `h264enc` path on
Ubuntu while retaining H.264 efficiency. Operators can still select another
supported encoder explicitly.

```bash
sudo webos --user researcher config show
sudo webos --user researcher config show --show-secrets
sudo webos --user researcher config set browser-user lab-browser
sudo webos --user researcher config set browser-password
sudo webos --user researcher config rotate-password
sudo webos --user researcher config set listen 127.0.0.1
sudo webos --user researcher config set port 8081
sudo webos --user researcher config set encoder h264enc-striped
sudo webos --user researcher config set cpu true
sudo webos --user researcher config set resolution 1920x1080
sudo webos --user researcher config edit
```

`browser-password` prompts twice without placing the secret in shell history.
`rotate-password` generates, applies, and prints a new password once. Mutating
commands preserve the previous environment file and restore it automatically
if the restarted service fails its authenticated health check. Start a new
shell or source the relevant completion file to activate completion in an
already-open shell.

For user `researcher`:

```bash
systemctl status webos@researcher.service
journalctl -u webos@researcher.service -f
sudo systemctl restart webos@researcher.service
sudo ss -ltnp | grep ':8081'
sudo cat /opt/hoster/webos/build-info.txt
sudoedit /etc/hoster/webos/users/researcher.env
```

After editing a user environment or `/etc/hoster/webos/desktop/`, restart the
affected service. Prefer the `webos config` commands because they validate,
health-check, and roll back unsafe changes.

To validate a built artifact without installing it:

```bash
./tests/validate-installer.sh \
  dist/webos-v0.2.0-ubuntu-26.04-amd64.run \
  0.2.0
```

Clean-VM functional validation should additionally check:

1. the authenticated HTTPS page and stream load directly or through a tunnel;
2. the WebOS favicon and `WebOS-<hostname>-<username>` title are present;
3. XFCE Terminal and Thunar start;
4. files in the real home survive service and VM restarts;
5. `sudo` follows the account's pre-existing policy;
6. `docker run --rm hello-world` succeeds;
7. only the configured address/port is listening;
8. reinstall and reboot preserve the session.
9. simultaneous users receive distinct ports, certificates, homes, and process
   trees;
10. one user's localhost development server is reachable from the other user's
    native browser;
11. the Selkies Apps sidebar section is absent.

After copying this source tree to the VM, most installed-state checks can be
run with:

```bash
sudo ./tests/validate-installed.sh --user researcher
sudo ./tests/validate-installed.sh --user researcher --container-test
sudo ./tests/validate-multi-user.sh researcher reviewer
```

The first invocation creates a small persistence probe under the selected
user's `.local/state/`; rerun it after reboot. Visual stream validation remains
manual.

## Uninstall

```bash
sudo webos-uninstall
```

Uninstall removes WebOS releases, unit, state, logs, and (unless
`--keep-config` is used) project configuration. It never deletes the selected
user's home, container images/data, unrelated system data, or installed
workstation applications. Vendor repository configuration is retained so
Chrome, Firefox, and VS Code keep receiving package-manager updates. Uninstall
does not remove the user's `docker` group membership, because that could disrupt
Docker access configured outside WebOS.

See [ATTRIBUTIONS.md](ATTRIBUTIONS.md) for upstream source and licence details
and [PRD.md](PRD.md) for scope and acceptance criteria.

# WebOS v0.2 product requirements

## Release

Working name: WebOS

Version: `0.2.0`

Tag convention: `webos-v0.2.0`

This is an explicitly early proof of concept. Release production is local or
self-hosted only; the repository must not contain GitHub-hosted build or
release workflows.

## Supported artifacts

One repository commit must produce:

```text
webos-v0.2.0-ubuntu-24.04-amd64.run
webos-v0.2.0-ubuntu-26.04-amd64.run
webos-v0.2.0-fedora-44-amd64.run
```

Each installer must reject a mismatched distribution, release, or architecture
before modifying the target.

## Product outcome

A system administrator runs one self-extracting installer on a normal VM. The
result is one or more persistent browser-accessible XFCE desktops, each running
as a selected, existing non-root Linux account.

The visible desktop environment must be XFCE on every platform. A minimal
headless Wayland compositor and Xwayland may support XFCE internally, but no
alternative user-facing shell should be installed or configured by WebOS.

The session operates on the real VM:

- normal home and filesystem;
- existing sudo policy;
- host systemd;
- host Docker on both Ubuntu and Fedora;
- normal development tools and graphical applications;
- persistent work across service/browser/VM restarts.

It must not use a general-purpose Webtop container or Docker-in-Docker as its
primary environment. The VM, not Selkies, is the isolation boundary.

## Runtime architecture

```text
Browser
  -> Selkies HTTPS on an independently configurable per-user TCP listener
  -> pixelflux outer capture compositor and CPU encoding
  -> nested Labwc Wayland compositor/window manager
  -> Xwayland compatibility
  -> native XFCE processes
  -> selected real VM user and persistent home
```

CPU rendering/encoding is the default. Audio, microphone, controllers,
multiple monitors, GPUs, SSO, public-certificate/DNS automation, and dynamic
login brokering are out of scope. Administratively registered simultaneous
users and per-session self-signed certificates are in scope.

## Installer contract

Required options:

```text
--help
--version
--extract <directory>
--user <username>
--listen <address>
--port <port>
--uninstall
```

Installation must:

1. require root;
2. validate the exact target;
3. select an existing real user, preferring `SUDO_USER`;
4. install distro packages;
5. install an embedded, offline Selkies Python payload;
6. install shared project configuration and a per-user systemd service;
7. run the desktop as the selected account;
8. enable and start it at boot;
9. perform an authenticated local HTTPS health check;
10. print URL, service, config, and diagnostics.

Default listener: `127.0.0.1`, with the first free port from 8081. Every
session must retain browser authentication and use a distinct self-signed
certificate even when an administrator explicitly chooses another address.
Production access may use an authenticated reverse proxy that trusts or
deliberately skips verification of the internal certificate.
The browser must use the WebOS favicon and default to
`WebOS-<hostname>-<selected username>` as its tab title. Administrators may
override that title through `WEBOS_TITLE` in the per-user environment. The
Selkies sidebar uses a compact `WebOS` brand row with its controls below it, and
its Apps functionality must be hidden.

Install a `webos` operator command with Bash, Zsh, and Fish completion. It must
provide help, status/log/service controls, safe configuration display, and
validated browser credential, title, listener, encoder, and resolution changes.
Configuration changes restart and health-check WebOS and restore the previous
file on failure. It must also add, list, inspect, remove, start, stop, and
restart registered users; retrieve their credentials; select a default user;
and renew their self-signed certificates. Removing WebOS for a user must not
delete that Linux account or home.

The operator command is lowercase-only. The default workstation includes
Chrome, Firefox, Visual Studio Code, LibreOffice Writer/Calc/Impress, GIMP, Git,
curl, and jq. All targets use the bundled WebOS wallpaper, Adwaita Dark, and
dark Labwc decorations on first launch while preserving subsequent per-user
appearance choices. The searchable XFCE Whisker Menu is the default application
launcher on every supported target.

## Privilege requirements

WebOS must not grant sudo. Docker group membership must be disclosed as
root-equivalent. A working Docker installation should be preserved; Fedora's
Moby/Docker packages are the default when Docker is absent. Any device-group
or systemd-lingering changes must be explicit; this release should avoid them.

## Idempotency

Use versioned releases and an atomic `current` symlink. Reinstallation updates
project runtime/unit files, preserves all per-user and administrator
configuration where practical, never overwrites files in user homes, restarts
all enabled registered services, and reruns health validation. Restore the
prior `current` release after a failed upgrade health check when one exists.

Uninstall must preserve user homes, unrelated container data, and unrelated
system configuration.

## Build and local release

Separate distro containers must build target-specific Python/native artifacts.
The VM must not require compilers. Pin important upstream versions/revisions
and record product version, target, architecture, Selkies revision, LinuxServer
reference revision, build time, and source commit.

`./build.sh` must populate all three artifacts in `dist/`.
`./release-local.sh` must validate them and generate SHA-256 checksums and local
release notes without any upload or external release mutation.

Generated `.run` files remain ignored by Git.

## Alpha acceptance

- all three installers build from one commit;
- each installs on its stated clean VM;
- the browser displays a usable XFCE desktop;
- the browser displays the WebOS favicon and configured per-session title;
- two or more registered users can run simultaneous independent sessions;
- sessions have distinct credentials, certificates, ports, runtime directories,
  process trees, homes, and XFCE preferences;
- one user can reach another user's loopback-bound development service through
  the shared VM localhost;
- the Selkies Apps sidebar functionality is absent;
- terminal/filesystem actions occur on the real host account;
- home data persists after restart/reboot;
- existing sudo access works;
- host containers run;
- listener scope matches configuration;
- service starts after reboot;
- reinstall preserves user/admin data;
- local checksums and diagnostics are produced and documented.

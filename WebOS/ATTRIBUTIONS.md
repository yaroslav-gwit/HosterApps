# WebOS attribution and source information

WebOS project scripts are distributed under the repository's BSD 2-Clause
license.

The generated installers redistribute an unmodified build of Selkies and its
Python dependencies. Licence files shipped inside Python wheels remain in their
respective `.dist-info` directories after installation. The payload also
includes the Selkies MPL 2.0 licence text.

| Project | Use | Pinned version/revision | Licence |
| --- | --- | --- | --- |
| [Selkies](https://github.com/selkies-project/selkies) | Browser client, streaming server and input | `12f5033b43b5b44a68bdd1ad804a49985832566a` | MPL-2.0; bundled web components carry their upstream notices |
| [pixelflux](https://github.com/linuxserver/pixelflux) | Wayland capture, input and software encoding | PyPI `2.0.0` | MPL-2.0 |
| [pcmflux](https://github.com/linuxserver/pcmflux) | Selkies audio dependency; audio disabled in this release | PyPI `2.0.0` | MPL-2.0 |
| [docker-baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies) | Behavioural reference only | `9d7047537c30f978f3b9a5f0d82ba397fe510257` | GPL-3.0 |
| [docker-webtop](https://github.com/linuxserver/docker-webtop) | Desktop launch reference only | `f4211d28f085a8a1c9ee4c77ad747ee54ac2ff7c` | GPL-3.0 |
| [XFCE](https://gitlab.xfce.org/xfce) | User-facing desktop environment | Distribution packages; Ubuntu 24.04 uses checksum-pinned Xubuntu Noble backports of Panel 4.20.3, Settings 4.20.1, libxfce4ui 4.20.0, libxfce4windowing 4.20.2, xfdesktop 4.20.1, xfconf 4.20.0 and Whisker Menu 2.9.2 | GPL/LGPL components; distro notices retained |
| [Labwc](https://github.com/labwc/labwc) | Hidden host-installed nested Wayland compositor/window manager | Distribution package | GPL-2.0-only |

The WebOS wallpaper is derived from the administrator-supplied
`3d-render-network-communications-background-with-plexus-design.jpg`. The
project stores a resized and cropped copy only; the repository owner is
responsible for confirming the source image's redistribution rights.

The Whisker Menu button uses a resized copy of the administrator-supplied
`toppng.com-windows-vista-eps-vector-logo-download-free-400x400.png`. Windows
logo artwork and related trademarks belong to Microsoft; the repository owner
is responsible for confirming redistribution and trademark usage rights.

No LinuxServer container filesystem or general-purpose Webtop runtime is
copied into the host. LinuxServer sources informed process ordering and package
selection; the native systemd integration and installer code are original to
this project.

Distribution packages installed by WebOS retain their distribution-supplied
licence and copyright files under the normal system locations.
The Ubuntu 24.04 installer embeds the exact Xubuntu Developers QA Staging
binary packages needed for a native Wayland tasklist. Their complete
corresponding `.dsc`, upstream tarballs, and Debian packaging sources accompany
the binaries under `licenses/sources/xubuntu-xfce-4.20-noble/` in the installer
payload and installed WebOS release.
Google Chrome and Visual Studio Code are installed from their vendors'
repositories and remain subject to their respective vendor licence terms; their
packages are not embedded in the WebOS installer.

# LeilFS `.run` Builder

This repository is meant to be a tiny **build-only** wrapper around the [leil-io/leilfs](https://github.com/leil-io/leilfs) project.

Its job is simple:

- clone the upstream LeilFS source during `docker build`
- check out a fixed upstream version
- build LeilFS
- package the result into a portable self-extracting `.run` installer
- let us publish that installer as a release artifact

## Version

The bundled Docker build currently targets:

```text
v5.11.0
```

The version is pinned directly in `Dockerfile` via:

```dockerfile
ARG LEILFS_VERSION=v5.11.0
```

To build another tag without editing the file, pass
`--build-arg LEILFS_VERSION=vX.Y.Z` to `docker build`.

## Files to keep in this repo

The standalone builder only needs these files:

```text
Dockerfile
create-run-installer.sh
export-installer.sh
install-bundle.sh
install-layout-common.sh
install-system.sh
README.md
tests/test-config-migration.sh
```

## Build the installer artifact

### Preferred: use the wrapper script

The most reliable path is:

```bash
./export-installer.sh
```

By default it writes:

```text
./dist/leilfs-installer.run
```

If you want a different output path:

```bash
OUTPUT_FILE=./release/leilfs-installer.run ./export-installer.sh
```

### Alternative: export the final stage directly

If your Docker/BuildKit combination supports local exporters correctly, you can
also export the final artifact stage directly:

```bash
docker buildx build --target artifact --output type=local,dest=./dist .
```

## What the Docker build does

At a high level, the Dockerfile:

1. installs the minimal bootstrap tools needed to clone upstream LeilFS
2. clones `https://github.com/leil-io/leilfs.git`
3. clones the pinned `v5.11.0` tag with a shallow checkout
4. uses upstream's own dependency installer for Ubuntu 24.04
5. bootstraps `vcpkg`
6. configures LeilFS with `-DCMAKE_INSTALL_PREFIX=/` and
   `-DCMAKE_BUILD_TYPE=Release`
7. builds the tagged release with an empty `VERSION_SUFFIX` so binaries report
   exactly `5.11.0` rather than the upstream development suffix
8. stages stripped release binaries and runs `create-run-installer.sh`
9. emits a final image that contains only `/leilfs-installer.run`

## Install the generated artifact

Copy the `.run` file to a target host and run:

```bash
sudo ./leilfs-installer.run
```

On Debian/Ubuntu and RHEL/Rocky/Fedora hosts, the installer checks for missing
shared-library packages and installs the known runtime dependencies
automatically when needed. If your hosts are air-gapped, preinstall those
packages first. Once they are already present, you can skip the automatic
package installation step with:

```bash
sudo LEILFS_INSTALL_RUNTIME_DEPS=0 ./leilfs-installer.run
```

The CGI dashboard's pure-Python `chardet` dependency is bundled privately under
`/usr/lib/leilfs/python`; the installer does not use `pip` or require EPEL for
it. A system Python 3 interpreter is still required and is installed through
the host package manager when missing.

Enable the optional dashboard with `systemctl enable --now
saunafs-cgiserv`. It listens on port 9425 by default; bind, port, and document
root overrides belong in `/etc/sysconfig/saunafs-cgiserv`, matching the
upstream systemd unit.

If you want to inspect the contents without installing:

```bash
./leilfs-installer.run --extract /tmp/leilfs-installer
```

## Upgrade from SaunaFS

Run the LeilFS installer exactly as you would for a fresh installation:

```bash
sudo ./leilfs-installer.run
```

The installer treats LeilFS as an in-place continuation of SaunaFS. It:

1. records which `saunafs-*.service` units are active and stops them
2. installs the LeilFS binaries and upstream compatibility symlinks
3. copies legacy configuration files to their canonical `leil-*.cfg` names
   only when the corresponding LeilFS file does not already exist
4. preserves every legacy configuration file
5. preserves the existing metadata and chunk data
6. restarts only the units that were active before the upgrade

LeilFS changes `/usr/share/sfscgi` from a real directory into a compatibility
symlink to `/usr/share/leil-cgi`. During a SaunaFS upgrade, the installer moves
the old directory to `/usr/share/sfscgi.saunafs-pre-leilfs` before installing
the symlink. This keeps any locally customized CGI files available for review
or rollback. Re-running the installer does not create another backup once the
compatibility path is already a symlink.

The `/etc/saunafs` and `/var/lib/saunafs` directories, `saunafs` service
account, and current `saunafs-*.service` unit names are intentionally retained.
Those names are still part of the LeilFS v5.11.0 upstream compatibility and
packaging surface; renaming them locally would make upgrades less safe.

The automatic configuration mapping is:

```text
sfsmaster.cfg            -> leil-master.cfg
sfschunkserver.cfg       -> leil-chunkserver.cfg
sfsmetalogger.cfg        -> leil-metalogger.cfg
sfsmount.cfg             -> leil-mount.cfg
sfshdd.cfg               -> leil-hdd.cfg
sfsexports.cfg           -> leil-exports.cfg
sfsgoals.cfg             -> leil-goals.cfg
sfstopology.cfg          -> leil-topology.cfg
sfsglobaliolimits.cfg    -> leil-globaliolimits.cfg
sfsiolimits.cfg          -> leil-iolimits.cfg
sfstls.cfg               -> leil-tls.cfg
saunafs-uraft.cfg        -> leil-uraft.cfg
```

The validated migration matrix and checks are recorded in
[`MIGRATION-TESTS.md`](MIGRATION-TESTS.md).

Before changing the pinned upstream release, follow
[`MAINTENANCE.md`](MAINTENANCE.md). It documents the private `chardet` bundle,
Python interpreter handling, CGI service override path, and the dashboard
regression tests that must be repeated for each release.

## Notes

- The generated installer is intended for Linux/systemd hosts.
- The build uses `CMAKE_INSTALL_PREFIX=/` so LeilFS defaults line up with
  `/etc/saunafs`, `/usr/sbin`, and `/var/lib/saunafs`.
- Fresh installations seed canonical LeilFS configs. The installer initializes `metadata.sfs` from the
  packaged `metadata.sfs.empty` template when needed, and does **not**
  auto-start services.
- Publishing `leilfs-installer.run` as a GitHub Release asset should fit the
  "download from releases" workflow you described.

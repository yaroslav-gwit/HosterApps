# SaunaFS `.run` Builder

This repository is meant to be a tiny **build-only** wrapper around the [leil-io/saunafs](https://github.com/leil-io/saunafs) project.

Its job is simple:

- clone the upstream SaunaFS source during `docker build`
- check out a fixed upstream version
- build SaunaFS
- package the result into a portable self-extracting `.run` installer
- let us publish that installer as a release artifact

## Version

The bundled Docker build currently targets:

```text
v5.7.1
```

The version is pinned directly in `Dockerfile` via:

```dockerfile
ENV SAUNAFS_VERSION=v5.7.1
```

To bump versions later, update that line and rebuild.

## Files to keep in this repo

The standalone builder only needs these root-level files:

```text
Dockerfile
create-run-installer.sh
export-installer.sh
install-bundle.sh
install-layout-common.sh
install-system.sh
README.build-only.md
```

If you want this file to be the front page of your standalone repo, rename it
to `README.md` there.

## Build the installer artifact

### Preferred: use the wrapper script

The most reliable path is:

```bash
./export-installer.sh
```

By default it writes:

```text
./dist/saunafs-installer.run
```

If you want a different output path:

```bash
OUTPUT_FILE=./release/saunafs-installer.run ./export-installer.sh
```

### Alternative: export the final stage directly

If your Docker/BuildKit combination supports local exporters correctly, you can
also export the final artifact stage directly:

```bash
docker buildx build --target artifact --output type=local,dest=./dist .
```

## What the Docker build does

At a high level, the Dockerfile:

1. installs the minimal bootstrap tools needed to clone upstream SaunaFS
2. clones `https://github.com/leil-io/saunafs.git`
3. runs `git checkout v5.7.1`
4. uses upstream's own dependency installer for Ubuntu 24.04
5. bootstraps `vcpkg`
6. configures SaunaFS with `-DCMAKE_INSTALL_PREFIX=/`
7. builds the project
8. runs `create-run-installer.sh`
9. emits a final image that contains only `/saunafs-installer.run`

## Install the generated artifact

Copy the `.run` file to a target host and run:

```bash
sudo ./saunafs-installer.run
```

On Debian/Ubuntu and RHEL/Rocky/Fedora hosts, the installer checks for missing
shared-library packages and installs the known runtime dependencies
automatically when needed. If your hosts are air-gapped, preinstall those
packages first. Once they are already present, you can skip the automatic
package installation step with:

```bash
sudo SAUNAFS_INSTALL_RUNTIME_DEPS=0 ./saunafs-installer.run
```

If you want to inspect the contents without installing:

```bash
./saunafs-installer.run --extract /tmp/saunafs-installer
```

## Notes

- The generated installer is intended for Linux/systemd hosts.
- The build uses `CMAKE_INSTALL_PREFIX=/` so SaunaFS defaults line up with
  `/etc/saunafs`, `/usr/sbin`, and `/var/lib/saunafs`.
- The installer seeds safe default configs, initializes `metadata.sfs` from the
  packaged `metadata.sfs.empty` template when needed, and does **not**
  auto-start services.
- Publishing `saunafs-installer.run` as a GitHub Release asset should fit the
  "download from releases" workflow you described.

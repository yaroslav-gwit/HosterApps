# QEMU `.run` Builder

A Docker-based build wrapper that compiles QEMU, swtpm, virtiofsd, and collects
OVMF/SeaBIOS firmware into a single self-extracting `.run` installer. The
installer is portable across Ubuntu 24.04 and Rocky Linux 10 — all required
dynamic libraries are bundled.

This is the QEMU counterpart to the [SaunaFS builder](../SaunaFS/) in this
repository.

## Version

The bundled Docker build currently targets:

```text
QEMU       11.1.0
libtpms    v0.10.2
swtpm      v0.10.1
virtiofsd  v1.14.0
```

These are pinned in the `Dockerfile` as build arguments together with the QEMU
source SHA-256 and exact companion-project Git commits. Update the pins and
integrity values together when bumping versions.

## What gets built

| Component   | Source                                              | Purpose                    |
|-------------|-----------------------------------------------------|----------------------------|
| QEMU        | https://download.qemu.org/                          | VM hypervisor              |
| libtpms     | https://github.com/stefanberger/libtpms             | TPM 2.0 emulation library  |
| swtpm       | https://github.com/stefanberger/swtpm               | Software TPM daemon        |
| virtiofsd   | https://gitlab.com/virtio-fs/virtiofsd              | Virtio-FS vhost-user daemon|
| OVMF        | Ubuntu 24.04 `ovmf` package (pre-built EDK2)        | UEFI firmware for VMs      |
| SeaBIOS     | Built by QEMU's own build system                    | Legacy BIOS firmware       |

## Build the installer artifact

```bash
cd QEMU
./export-installer.sh
```

The output lands at:

```text
./dist/qemu-installer.run
```

Override with:

```bash
OUTPUT_FILE=./release/qemu-installer.run ./export-installer.sh
```

## Install on a target host

```bash
sudo ./qemu-installer.run
```

Or extract without installing:

```bash
./qemu-installer.run --extract /tmp/qemu-payload
```

---

## Installation directory layout

The installer places everything under a versioned directory:

```
/opt/hoster/qemu/<version>_<build-date>/
```

For example:

```
/opt/hoster/qemu/11.1.0_2026-08-12/
```

### Full tree

```
/opt/hoster/qemu/
├── 11.1.0_2026-08-12/              ← versioned install
│   ├── bin/                         ← wrapper scripts (entry points)
│   │   ├── qemu-system-x86_64      ← sets LD_LIBRARY_PATH, execs libexec/
│   │   ├── qemu-img
│   │   ├── qemu-nbd
│   │   ├── swtpm
│   │   ├── swtpm_setup
│   │   ├── swtpm_ioctl
│   │   └── virtiofsd
│   ├── libexec/                     ← real ELF binaries
│   │   ├── qemu-system-x86_64
│   │   ├── qemu-img
│   │   ├── qemu-nbd
│   │   ├── swtpm
│   │   ├── swtpm_setup
│   │   ├── swtpm_ioctl
│   │   └── virtiofsd
│   ├── firmware/
│   │   ├── OVMF_CODE_4M.fd         ← UEFI code (standard boot)
│   │   ├── OVMF_CODE_4M.secboot.fd ← UEFI code (Secure Boot)
│   │   ├── OVMF_VARS_4M.fd         ← UEFI variable store template
│   │   ├── OVMF_VARS_4M.ms.fd      ← UEFI vars with Microsoft keys
│   │   ├── OVMF_CODE.fd            ← UEFI code (2MB variant)
│   │   ├── OVMF.fd                 ← Combined UEFI image (code+vars)
│   │   ├── bios-256k.bin           ← SeaBIOS (legacy BIOS)
│   │   ├── bios.bin                ← SeaBIOS (legacy, 128K)
│   │   └── vgabios-*.bin           ← VGA BIOS ROMs (std, virtio, etc.)
│   ├── share/
│   │   └── qemu/                    ← QEMU data (keymaps, device ROMs, etc.)
│   ├── lib/
│   │   └── bundled/                 ← shared libraries (private to QEMU)
│   ├── licenses/                    ← source and bundled-library notices
│   └── build-info.txt               ← versions, commits, source hash + build date
├── latest -> 11.1.0_2026-08-12/    ← active complete installation tree
└── bin/                             ← launchers that dispatch through latest/
    ├── qemu-system-x86_64
    ├── qemu-img
    └── ...
```

### How wrapper scripts work

The `bin/` directory contains thin shell wrappers, not the real ELF binaries.
Each wrapper sets `LD_LIBRARY_PATH` to the bundled libs directory before
exec'ing the real binary from `libexec/`. This keeps bundled libraries
**completely private** to QEMU — they are never registered globally via
`ldconfig` or `ld.so.conf.d`, so they cannot interfere with unrelated host
binaries like curl, openssl, etc.

```bash
# Example: bin/qemu-system-x86_64
#!/usr/bin/env bash
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_DIR="$(cd "$(dirname "${SELF_PATH}")" && pwd)"
LIB_DIR="${SELF_DIR}/../lib/bundled"
if [[ -d "${LIB_DIR}" ]]; then
    export LD_LIBRARY_PATH="${LIB_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
exec "${SELF_DIR}/../libexec/qemu-system-x86_64" "$@"
```

### Convenience paths (always point to latest installed version)

| Path                                | Description                        |
|-------------------------------------|------------------------------------|
| `/opt/hoster/qemu/latest/`          | Symlink to newest version dir      |
| `/opt/hoster/qemu/bin/`             | Launchers for active version binaries|

---

## How to integrate with HosterCoreLinux

This section documents every location in HosterCoreLinux that needs updating to
use the self-contained QEMU build instead of system packages.

### 1. QEMU binary resolution

**Current code:** `HosterLib/vm_generate_qemu.go` lines 21–30

```go
qemuBinary := "qemu-system-" + systemArch
if !WhichIsBinaryExists(qemuBinary) {
    e = fmt.Errorf("qemu binary is not found")
    return
}
```

**New approach:** Resolve the binary from `/opt/hoster/qemu/` instead of `$PATH`.

```
# Preferred: use the installer-managed active-version symlink
/opt/hoster/qemu/latest/bin/qemu-system-x86_64

# Fallback: semver-sort directories matching <version>_<date>, then PATH
```

### 2. qemu-img resolution

**Current code:** `HosterLib/vm_config.go` — uses `qemu-img` from PATH.

**New approach:** Same resolution as above:
```
/opt/hoster/qemu/latest/bin/qemu-img
```

### 3. OVMF firmware paths (UEFI boot)

**Current code:** `HosterLib/vm_generate_qemu.go` lines 55–127

The code currently searches these system paths:

```go
// Standard UEFI
"/usr/share/ovmf/x64/OVMF.4m.fd"
"/usr/share/ovmf/OVMF.fd"

// Secure Boot — code
"/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
"/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd"

// Secure Boot — vars
"/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
"/usr/share/OVMF/x64/OVMF_VARS.4m.fd"
```

**New approach:** Prepend the Hoster QEMU firmware directory to each search list.
The firmware directory for the resolved QEMU version is:

```
<qemu-version-dir>/firmware/
```

New firmware file mapping:

| Use case              | Bundled file path (relative to firmware/)   |
|-----------------------|---------------------------------------------|
| Standard UEFI (`-bios`)    | `OVMF.fd` or `OVMF_CODE_4M.fd`       |
| Secure Boot — code    | `OVMF_CODE_4M.secboot.fd`                  |
| Secure Boot — vars    | `OVMF_VARS_4M.ms.fd`                       |
| Secure Boot — plain vars | `OVMF_VARS_4M.fd`                       |

Example updated search order for Secure Boot code file:

```go
files := []string{
    qemuDir + "/firmware/OVMF_CODE_4M.secboot.fd",   // bundled (preferred)
    "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd",       // Ubuntu system
    "/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd",   // Rocky system
}
```

### 4. SeaBIOS firmware (legacy BIOS boot)

**Current code:** `HosterLib/vm_generate_qemu.go` line 129 — just sets
`machine = " -machine pc"` with no explicit BIOS path (QEMU uses its built-in
default).

**New approach:** Since QEMU is no longer in a system location, it may not find
its own firmware. Explicitly pass the BIOS path:

```
-machine pc -bios <qemu-version-dir>/firmware/bios-256k.bin
```

Or set the QEMU data directory so it finds firmware automatically:

```
-L <qemu-version-dir>/share/qemu/
```

The `-L` flag tells QEMU where to find its data files (firmware, keymaps, etc.)
and is the cleanest single fix for all firmware lookups.

### 5. swtpm (TPM emulation)

**Current code:** `HosterLib/vm_generate_qemu.go` lines 318–385

```go
command := fmt.Sprintf("swtpm socket --tpmstate dir=%s --ctrl type=unixio,path=%s/%s --tpm2 --terminate", ...)
```

**New approach:** Use the absolute path to the bundled swtpm:

```
<qemu-version-dir>/bin/swtpm
```

### 6. virtiofsd (virtio-fs)

**Current code:** `HosterLib/vm_start.go` — starts `virtiofsd` before the VM.

**New approach:** Use the absolute path to the bundled virtiofsd:

```
<qemu-version-dir>/bin/virtiofsd
```

### 7. Package installation scripts (can be simplified/removed)

These scripts currently install QEMU and firmware via apt/dnf. With the bundled
build, these package lists can be trimmed:

| Script                                          | QEMU packages to remove                    |
|-------------------------------------------------|--------------------------------------------|
| `HosterOS/rootfs/provision_rootfs.sh`           | `qemu-system`, `qemu-block-extra`, `qemu-utils`, `ovmf`, `seabios`, `qemu-img`, `qemu-kvm` |
| `HosterScripts/node_bootstrap.sh`               | `qemu-block-extra`, `qemu-system`, `qemu-utils`, `seabios`, `ovmf` |
| `node_init_dev.sh`                              | All qemu-* packages, `seabios`             |

**Replace with:** Download the `.run` installer from the GitHub release and run it.

### 8. Suggested resolution for Go code

A single helper should resolve the installer's atomic `latest` symlink first.
Do not select version directories with a plain lexicographic sort: for example,
`9.2.0` sorts after `11.1.0`. If `latest` is absent, use a semantic-version
comparison before falling back to the system `PATH`.

```go
func FindLatestQemuDir() (string, error) {
    latest := "/opt/hoster/qemu/latest"
    target, err := filepath.EvalSymlinks(latest)
    if err != nil {
        return "", fmt.Errorf("cannot resolve %s: %w", latest, err)
    }
    return target, nil
}
```

Then derive all paths from the result:

```go
qemuDir, err := FindLatestQemuDir()
// ...
qemuBinary    := filepath.Join(qemuDir, "bin", "qemu-system-"+systemArch)
qemuImg       := filepath.Join(qemuDir, "bin", "qemu-img")
swtpmBinary   := filepath.Join(qemuDir, "bin", "swtpm")
virtiofsdBin  := filepath.Join(qemuDir, "bin", "virtiofsd")
firmwareDir   := filepath.Join(qemuDir, "firmware")
qemuShareDir  := filepath.Join(qemuDir, "share", "qemu")
```

### 9. QEMU command-line additions

When running QEMU from a non-standard prefix, add this flag to every invocation
so QEMU can find its own data files (keymaps, firmware, device option ROMs):

```
-L <qemuDir>/share/qemu/
```

This single flag replaces the need to individually specify firmware paths for
SeaBIOS and VGA BIOS ROMs. OVMF paths still need to be explicit (they are
passed via `-bios` or `-drive if=pflash`).

---

## Multiple versions side-by-side

The versioned directory scheme supports multiple installed versions:

```
/opt/hoster/qemu/
├── 9.2.0_2025-11-01/
├── 10.2.2_2026-04-05/
├── 11.1.0_2026-08-12/
└── latest -> 11.1.0_2026-08-12/
```

Rollback is as simple as:
```bash
ln -sfn /opt/hoster/qemu/9.2.0_2025-11-01 /opt/hoster/qemu/latest
```

The `/opt/hoster/qemu/bin/` launchers follow that switch, including when
rolling back to packages whose own wrappers predate the symlink-path fix.
Running VMs are unaffected; the selected binaries change for subsequent
commands and VM starts. Test guest compatibility before changing versions and
use an explicit versioned QEMU machine type for migration compatibility.

Old versions can be removed with `rm -rf /opt/hoster/qemu/<old-version>/`.

## Build it yourself

If you prefer to compile from source:

```bash
cd QEMU
./export-installer.sh
```

This runs a containerized Docker build. The Dockerfile fetches all sources,
compiles everything, bundles shared libraries, and emits a single `.run` file.

The QEMU release tarball is checked against its pinned SHA-256 before it is
extracted. Companion repositories are checked against pinned tag commits, and
the payload includes upstream source licenses plus Debian copyright notices for
the bundled system libraries. For release work, also verify the QEMU tarball's
detached signature against the official QEMU signing key before updating the
checksum pin.

## Notes

- The build targets only `x86_64-softmmu` (x86_64 VMs). Add other targets to
  `--target-list` in the Dockerfile if needed.
- SPICE and VirtGL support are enabled for remote display.
- The installer does **not** create systemd services — QEMU is invoked by
  Hoster, not run as a standalone daemon.
- Bundled shared libraries live under `<version>/lib/bundled/` and are loaded
  privately via `LD_LIBRARY_PATH` in the wrapper scripts. Nothing is registered
  globally — no `ldconfig`, no `ld.so.conf.d` files — so bundled libs cannot
  interfere with other host binaries.

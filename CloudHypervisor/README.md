# Cloud Hypervisor `.run` Builder

A Docker-based wrapper that packages [Cloud Hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor),
its custom [EDK2 firmware](https://github.com/cloud-hypervisor/edk2), and
[virtiofsd](https://gitlab.com/virtio-fs/virtiofsd) into a single
self-extracting `.run` installer. The installer is portable across Ubuntu 24.04
and Rocky Linux 10.

Unlike the [QEMU builder](../QEMU/) and [SaunaFS builder](../SaunaFS/), Cloud
Hypervisor provides pre-built static binaries, so the Docker build downloads
those directly rather than compiling from source. Only virtiofsd is compiled
from source (Rust).

## Version

The bundled Docker build currently targets:

```text
Cloud Hypervisor   v51.1
EDK2 firmware      ch-13b4963ec4  (rebased on edk2-stable202602)
virtiofsd          v1.12.0
```

These are pinned in the `Dockerfile` via `ENV` directives. To bump versions,
update those lines and rebuild.

## What gets packaged

| Component         | Source                                                    | Purpose                         |
|-------------------|-----------------------------------------------------------|---------------------------------|
| cloud-hypervisor  | Pre-built static binary from GitHub releases              | MicroVM hypervisor              |
| ch-remote         | Pre-built static binary from GitHub releases              | Remote API client for CHV       |
| CLOUDHV_EFI.fd    | Pre-built firmware from cloud-hypervisor/edk2 releases    | Full UEFI firmware for MicroVMs |
| CLOUDHV.fd        | Pre-built firmware from cloud-hypervisor/edk2 releases    | Minimal firmware variant        |
| virtiofsd         | Built from source (Rust)                                  | Virtio-FS vhost-user daemon     |

## Build the installer artifact

```bash
cd CloudHypervisor
./export-installer.sh
```

Output:

```text
./dist/cloud-hypervisor-installer.run
```

Override with:

```bash
OUTPUT_FILE=./release/chv-installer.run ./export-installer.sh
```

## Install on a target host

```bash
sudo ./cloud-hypervisor-installer.run
```

Or extract without installing:

```bash
./cloud-hypervisor-installer.run --extract /tmp/chv-payload
```

---

## Installation directory layout

The installer places everything under a versioned directory:

```
/opt/hoster/cloud-hypervisor/<version>_<build-date>/
```

For example:

```
/opt/hoster/cloud-hypervisor/51.1_2026-04-06/
```

### Full tree

```
/opt/hoster/cloud-hypervisor/
├── 51.1_2026-04-06/                    ← versioned install
│   ├── bin/
│   │   ├── cloud-hypervisor             ← MicroVM hypervisor (static binary)
│   │   ├── ch-remote                    ← Remote API client (static binary)
│   │   └── virtiofsd                    ← Virtio-FS vhost-user daemon
│   ├── firmware/
│   │   ├── CLOUDHV_EFI.fd              ← Full UEFI firmware (primary)
│   │   └── CLOUDHV.fd                  ← Minimal firmware variant
│   └── build-info.txt                  ← version + build date metadata
├── latest -> 51.1_2026-04-06/          ← symlink to most recent install
└── bin/                                 ← symlinks to latest version's binaries
    ├── cloud-hypervisor -> ../51.1_2026-04-06/bin/cloud-hypervisor
    ├── ch-remote -> ...
    └── virtiofsd -> ...
```

### Convenience paths (always point to latest installed version)

| Path                                           | Description                        |
|------------------------------------------------|------------------------------------|
| `/opt/hoster/cloud-hypervisor/latest/`         | Symlink to newest version dir      |
| `/opt/hoster/cloud-hypervisor/bin/`            | Symlinks to newest version binaries|

---

## How to integrate with HosterCoreLinux

This section documents every location in HosterCoreLinux that needs updating to
use the self-contained Cloud Hypervisor build.

### 1. Cloud Hypervisor binary resolution

**Current code:** `HosterLib/microvm.go` lines 239–254

The code currently searches for the binary in `$PATH` using candidates:
```go
"/usr/bin/cloud-hypervisor"
"/usr/local/bin/cloud-hypervisor"
"cloud-hypervisor"
"cloud-hypervisor-static"
```

**New approach:** Resolve from `/opt/hoster/cloud-hypervisor/` instead.

```
# Preferred: scan /opt/hoster/cloud-hypervisor/ for the latest version directory
#   1. List directories matching the pattern <version>_<date>
#   2. Sort lexicographically
#   3. Pick the last entry
#   4. Use <picked>/bin/cloud-hypervisor

# Fallback: use the convenience symlink
/opt/hoster/cloud-hypervisor/latest/bin/cloud-hypervisor

# Last resort: fall back to system PATH (current behavior)
```

### 2. ch-remote binary resolution

**Current code:** `HosterLib/microvm.go` — uses `ch-remote` from PATH for API
calls (VM shutdown, etc.).

**New approach:** Same resolution as above:
```
/opt/hoster/cloud-hypervisor/latest/bin/ch-remote
```

### 3. CLOUDHV_EFI.fd firmware path

**Current code:** `HosterLib/microvm.go` lines 47–53

```go
firmwareCandidates := []string{
    "/opt/hoster/firmware/CLOUDHV_EFI.fd",
    "/opt/hoster/firmware/CLOUDHV_EFI",
    "/usr/local/share/cloud-hypervisor/CLOUDHV_EFI.fd",
    "/usr/share/cloud-hypervisor/CLOUDHV_EFI.fd",
    "/opt/hoster/firmware/hypervisor-fw",
}
```

**New approach:** Prepend the versioned firmware directory:

```go
chvDir := resolvedChvVersionDir  // e.g. /opt/hoster/cloud-hypervisor/51.1_2026-04-06

firmwareCandidates := []string{
    filepath.Join(chvDir, "firmware", "CLOUDHV_EFI.fd"),  // bundled (preferred)
    "/opt/hoster/firmware/CLOUDHV_EFI.fd",                // legacy symlink
    "/opt/hoster/firmware/CLOUDHV_EFI",
    "/usr/local/share/cloud-hypervisor/CLOUDHV_EFI.fd",
    "/usr/share/cloud-hypervisor/CLOUDHV_EFI.fd",
    "/opt/hoster/firmware/hypervisor-fw",
}
```

### 4. virtiofsd resolution

**Current code:** `HosterLib/vm_virtiofsd.go` lines 28–46

```go
candidates := []string{
    "virtiofsd",
    "/usr/lib/qemu/virtiofsd",
    "/usr/libexec/virtiofsd",
    "/usr/lib/virtiofsd",
}
```

**New approach:** Prepend the bundled virtiofsd. Note that if both QEMU and CHV
installers are present, either one provides virtiofsd. Prefer the path from
whichever hypervisor is being used for the current VM/MicroVM:

```go
// For MicroVMs (Cloud Hypervisor):
chvDir + "/bin/virtiofsd"

// For VMs (QEMU):
qemuDir + "/bin/virtiofsd"

// Fallback to system PATH
```

### 5. Download/provisioning scripts (can be simplified)

These scripts currently download CHV and firmware from GitHub at runtime:

| Script                                          | What to simplify                          |
|-------------------------------------------------|-------------------------------------------|
| `HosterOS/rootfs/provision_rootfs.sh` (lines 74-99) | Remove GitHub API download logic; use `.run` installer instead |

**Replace with:** Download the `.run` installer from the GitHub release and run it.

### 6. Suggested helper function for Go code

```go
// FindLatestChvDir scans /opt/hoster/cloud-hypervisor/ for versioned
// directories and returns the path to the latest one.
func FindLatestChvDir() (string, error) {
    base := "/opt/hoster/cloud-hypervisor"
    entries, err := os.ReadDir(base)
    if err != nil {
        return "", fmt.Errorf("cannot read %s: %w", base, err)
    }

    var candidates []string
    for _, e := range entries {
        if !e.IsDir() {
            continue
        }
        name := e.Name()
        if len(name) > 0 && name[0] >= '0' && name[0] <= '9' && strings.Contains(name, "_") {
            candidates = append(candidates, name)
        }
    }
    if len(candidates) == 0 {
        return "", fmt.Errorf("no Cloud Hypervisor installation found in %s", base)
    }

    sort.Strings(candidates)
    return filepath.Join(base, candidates[len(candidates)-1]), nil
}
```

Then derive all paths:

```go
chvDir, err := FindLatestChvDir()
// ...
chvBinary     := filepath.Join(chvDir, "bin", "cloud-hypervisor")
chRemoteBin   := filepath.Join(chvDir, "bin", "ch-remote")
virtiofsdBin  := filepath.Join(chvDir, "bin", "virtiofsd")
firmwareDir   := filepath.Join(chvDir, "firmware")
```

---

## Multiple versions side-by-side

Same as the QEMU installer — multiple versions can coexist:

```
/opt/hoster/cloud-hypervisor/
├── 50.2_2025-12-01/
├── 51.1_2026-04-06/
└── latest -> 51.1_2026-04-06/
```

Rollback:
```bash
ln -sfn /opt/hoster/cloud-hypervisor/50.2_2025-12-01 /opt/hoster/cloud-hypervisor/latest
```

## Notes

- Cloud Hypervisor and ch-remote are **static binaries** — no shared library
  bundling is needed for them. Only virtiofsd has dynamic dependencies.
- The installer does **not** create systemd services — Cloud Hypervisor is
  invoked by Hoster via its API socket, not run as a standalone daemon.
- The `CLOUDHV.fd` firmware is a minimal variant; `CLOUDHV_EFI.fd` is the full
  UEFI firmware and is what HosterCoreLinux uses.

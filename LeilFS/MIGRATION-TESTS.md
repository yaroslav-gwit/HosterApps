# LeilFS installer and migration validation

Validation date: 2026-08-11

## Artifacts

- Published SaunaFS release: `saunafs-5.7.1`
- Published SaunaFS asset SHA-256:
  `26202a9477424280deeb935f9b2dd5878cf59d9c748b5bf12f4e53d60121445c`
- LeilFS upstream tag: `v5.11.0`
- LeilFS upstream commit: `6347c2fe0bc8039f5d64d7b1710b6174bb75b6f0`
- Final local LeilFS asset: `dist/leilfs-installer.run`
- Final LeilFS asset size: `30,023,877` bytes
- Final LeilFS asset SHA-256:
  `c03701c5952ea064119e2300968bdbd77135c8f9785017da93cd4bfac1539af0`

The LeilFS artifact was built with `CMAKE_BUILD_TYPE=Release`, staged with
`cmake --install --strip`, and contains build provenance in
`support/build-info.txt`. Both `leil-master` and the compatibility command
`sfsmaster` report version `5.11.0`.

The published SaunaFS 5.7.1 asset was verified against its GitHub digest. Its
binary reports `5.7.0-dev`, despite having been built from the v5.7.1 commit
`9f003e9b4c1310943b002d3bdc71be1b77ed958a`; this is an upstream
embedded-version issue in the old artifact, not a mismatch in the downloaded
asset.

## Docker validation

The final self-extracting installer passed these clean-container cases using
local Docker with root privileges:

| Base image | Fresh LeilFS install | SaunaFS-to-LeilFS config migration |
| --- | --- | --- |
| `ubuntu:24.04` | Pass | Pass |
| `almalinux:10` | Pass | Pass |

The checks covered installer exit status, canonical and compatibility command
versions, default canonical configs, bundled-library resolution without a
runtime package fallback, legacy config preservation, canonical config
migration, and the CGI directory-to-symlink transition.

The published SaunaFS installer assumes `/etc/security/limits.d` exists and
therefore required that directory to be created in the minimal Alma container.
The LeilFS installer now creates the parent directories itself and passes a
fresh install without that workaround.

## CGI dashboard validation

The upstream `leil.cgi` imports the third-party Python `chardet` module, but
upstream's RPM metadata declares only Python itself. This caused the dashboard
to return `ModuleNotFoundError: No module named 'chardet'` on AlmaLinux.

The final installer privately bundles `chardet` 5.2.0 and its license under
`/usr/lib/leilfs/python`, patches the installed CGI to use that private module,
and installs a system Python 3 interpreter through the distro package manager
only when one is absent. It does not use root-level `pip` or require EPEL.

Real `/leil.cgi` HTTP requests were tested after fresh and SaunaFS-migration
installs in `ubuntu:24.04` and `almalinux:10` containers. Both returned more
than 10 KB of dashboard HTML without a traceback. The configured fresh VMs
also returned HTTP 200 remotely over port 9425 on both target VMs.

The CGI service unit reads `/etc/sysconfig/saunafs-cgiserv`. The installer now
creates that effective path and migrates a previous
`/etc/default/saunafs-cgiserv` file when present, fixing an inherited mismatch
that caused bind and port overrides to be ignored.

## VM migration validation

| Target | Operating system | Result |
| --- | --- | --- |
| Ubuntu migration VM | Ubuntu 26.04 LTS | Pass |
| AlmaLinux migration VM | AlmaLinux 10.1 | Pass |

On each clean VM, the published SaunaFS installer was installed first. The
master, chunkserver, and metalogger services were enabled and started. A real
FUSE-mounted fixture was then created with a 2 MiB random file, a small text
file, a hardlink, and a symlink. `saunafs fileinfo` showed chunk ID 2 with one
copy on `127.0.0.1:9422` before migration.

The LeilFS installer then performed an in-place upgrade while all three
services were running. Validation confirmed:

- the installer stopped and restarted exactly the previously active services;
- master, chunkserver, and metalogger remained enabled and active;
- all 12 legacy configs were initially byte-identical to their canonical
  LeilFS copies, including a unique per-host marker;
- the recorded legacy config checksums remained unchanged;
- a second installer run preserved a deliberate canonical-only marker and did
  not create an additional CGI backup;
- existing metadata and chunk storage were retained;
- `leil-mount` remounted the filesystem and verified the original random-file
  SHA-256, hardlink, symlink, and chunkserver copy;
- a new file could be written and read after migration;
- both compatibility and canonical commands reported `5.11.0`;
- no error-priority journal entries appeared for the three services during the
  final tested install.

The fixture random-file hashes were:

- Ubuntu: `9d1ee120736b440f3f0131af17643c7969e8cd2dfe525b2144e9dea0e450d3e9`
- AlmaLinux: `c2ebe6130f47e209bc79aff849473a38ad5d85d020036428cc2782badf3f83b5`

## Issue found during migration testing

The first VM migration attempt exposed the upstream rename of
`/usr/share/sfscgi` from a directory to a symlink. The tar overlay stopped at
that conflict after stopping services, before config migration or service
restart. No configuration, metadata, or chunk data was removed. Both VMs were
restored by reapplying the verified published SaunaFS installer and restarting
the original services. The LeilFS installer was then changed to preserve the
old directory as `/usr/share/sfscgi.saunafs-pre-leilfs`; migration and repeated
installation subsequently passed on both hosts and in both container families.

The initially supplied AlmaLinux migration target was later corrected before
fresh-install validation. Both targets were isolated test systems, so no
non-test system was affected.

## Fresh-install VM validation

Fresh-install validation was completed on 2026-08-12 after snapshot rollback:

| Target | Operating system | Result |
| --- | --- | --- |
| Ubuntu fresh-install VM | Ubuntu 26.04 LTS | Pass |
| AlmaLinux fresh-install VM | AlmaLinux 10.1 | Pass |

Before installation, both hosts were verified to have no LeilFS or SaunaFS
commands, service account, configuration directory, data directory, or systemd
units. `/dev/fuse` was present on both.

The final checksum-verified installer was copied to each VM and run without
environment overrides. Validation confirmed:

- the installer created the `saunafs` compatibility account and group;
- exactly 12 canonical `leil-*.cfg` files and no legacy configs were created;
- the packaged defaults selected `/var/lib/saunafs/chunks` and localhost-only
  exports;
- metadata was initialized from the 8-byte empty template;
- canonical and compatibility commands both reported `5.11.0`;
- all private bundled libraries resolved without runtime-package fallback;
- service units were installed but correctly remained disabled and inactive
  until explicitly enabled by the operator;
- the fresh CGI compatibility symlink was installed without creating a
  migration backup.

The master, chunkserver, and metalogger were then enabled and started using the
unmodified packaged configuration. Ports 9419 through 9422 listened on both
hosts. A FUSE fixture containing 2 MiB of random data, a text file, hardlink,
and symlink was written and verified with `leil fileinfo`. Its hashes were:

- Ubuntu: `63b892ada393709cb3d7f60bdb864af9c79a6bc7dd3c59578102742f5236188b`
- AlmaLinux: `fd968c45773c5bde57203da0fa92e720c74118078c36c8111e63a5362baeb3dc`

An orderly stop/start of all three server services preserved the fixture and
link semantics. Re-running the installer while services were active preserved
a deliberate canonical-config marker, retained the filesystem data, restarted
the previously active units, created no legacy configs, and remained writable.

Finally, both VMs were rebooted. All three enabled services started
automatically, the filesystem remounted, both original checksums matched, the
chunk copy remained available on `127.0.0.1:9422`, and new post-reboot writes
succeeded. Each boot logged one transient chunkserver connection refusal while
the chunkserver and local master started in parallel; the chunkserver recovered
immediately and no unit failed.

## VM state after all testing

The fresh Ubuntu and AlmaLinux VMs were left with LeilFS installed. Master,
chunkserver, metalogger, and the CGI dashboard were enabled and active, and the
FUSE test mounts were unmounted. The final installer was present at
`/root/leilfs-installer.run`, with fresh-install evidence under `/root/`.

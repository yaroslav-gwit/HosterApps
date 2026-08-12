# LeilFS packaging maintenance

This file is the handoff checklist for updating the self-extracting installer
to a newer upstream LeilFS release. Read it before changing
`LEILFS_VERSION` in `Dockerfile`.

## Dashboard Python dependency

LeilFS v5.11.0's `usr/share/leil-cgi/leil.cgi` imports the third-party Python
module `chardet`, but the upstream RPM spec declares only `python3`. On a clean
AlmaLinux 10 installation this produced:

```text
ModuleNotFoundError: No module named 'chardet'
```

Do not assume this has been fixed merely because the dashboard works on an
Ubuntu build host. Ubuntu's upstream build dependencies install
`python3-chardet`, which can hide the missing target dependency.

The current packaging deliberately avoids root-level `pip` and an EPEL runtime
requirement:

1. `create-run-installer.sh` locates the build host's `chardet` module.
2. It copies the pure-Python package to `/usr/lib/leilfs/python/chardet` in the
   staged root.
3. It inserts `/usr/lib/leilfs/python` into the packaged `leil.cgi` search path
   before `import chardet` runs.
4. It copies the distro-provided `python3-chardet` copyright material to
   `/usr/share/doc/leilfs/bundled-python/chardet`.
5. `ensure_dashboard_runtime_dependencies` verifies the private module and
   installs only the system Python 3 interpreter when the target lacks it.

When upgrading upstream, inspect at least:

```bash
rg -n '^(import|from) ' /path/to/leilfs/src/cgi
rg -n 'chardet|python3' /path/to/leilfs/debian /path/to/leilfs/rpm
```

If upstream removes `chardet`, replaces it, or starts packaging all Python
dependencies portably, update the private bundle rather than retaining stale
code. If it still imports `chardet`, verify that the Docker build environment
provides `python3-chardet`; `create-run-installer.sh` intentionally fails if it
cannot locate the module instead of emitting a broken dashboard.

Do not validate this dependency with only:

```bash
python3 -c 'import chardet'
```

That tests global site packages and would fail intentionally on the validated
Alma VM. Test the private bundle directly:

```bash
PYTHONPATH=/usr/lib/leilfs/python python3 -c \
  'import chardet; print(chardet.__version__)'
```

Most importantly, start a master and CGI server and make a real request:

```bash
systemctl enable --now saunafs-master saunafs-cgiserv
curl --fail --location http://127.0.0.1:9425/leil.cgi > /tmp/leil-dashboard.html
! grep -q 'Traceback\|ModuleNotFoundError' /tmp/leil-dashboard.html
test "$(stat -c %s /tmp/leil-dashboard.html)" -gt 1000
```

Repeat the real HTTP test in clean Ubuntu and Alma/Rocky containers and on the
supported VMs. Repeat it for both a fresh installation and a SaunaFS migration.

## CGI service overrides

The upstream systemd unit is still named `saunafs-cgiserv.service` and reads:

```text
/etc/sysconfig/saunafs-cgiserv
```

An earlier installer wrote `/etc/default/saunafs-cgiserv`, which systemd never
read. The current installer creates the effective `/etc/sysconfig` file and
copies the old `/etc/default` file there when upgrading. Preserve this
migration unless upstream changes the unit's `EnvironmentFile` path.

After changing an override, remember that the unit must be restarted:

```bash
systemctl restart saunafs-cgiserv
```

## Release update checklist

1. Confirm the new upstream tag and immutable commit.
2. Update `LEILFS_VERSION` in `Dockerfile` and the documented version.
3. Re-audit canonical and compatibility binaries, config names, data paths,
   users, and systemd units. The v5.11.0 release is only a partial rename.
4. Re-audit every Python CGI import and the `chardet` logic above.
5. Build the stripped Release artifact with `export-installer.sh`.
6. Extract it and verify `support/build-info.txt`, bundled libraries, private
   Python modules, licenses, wrappers, and reported binary versions.
7. Test fresh installation in clean Ubuntu and Alma/Rocky containers.
8. Test a published SaunaFS installer followed by the new LeilFS installer in
   both container families.
9. Fetch `/leil.cgi`; checking only the static `/` or `index.html` does not
   exercise Python imports.
10. Test fresh installation, active-service migration, idempotent reinstall,
    FUSE data persistence, service restart, and reboot on the target VMs.
11. Record the final artifact size, SHA-256, upstream commit, and results in
    `MIGRATION-TESTS.md` only after the exact final artifact passes.

The artifact checksum changes whenever an embedded installer script or bundled
dependency changes. Never publish a hash from an earlier intermediate build.

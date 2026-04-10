# Caddy `.run` Builder

A Docker-based build wrapper that compiles Caddy with the **Cloudflare DNS** and
**SSH** modules into a single self-extracting `.run` installer. The installer is
portable across Linux distributions — Caddy is a statically linked Go binary.

## Version

The bundled Docker build currently targets:

```text
Caddy      v2.9.1
xcaddy     v0.4.4
```

These are pinned in the `Dockerfile` via `ENV` directives. To bump versions,
update those lines and rebuild.

## What gets built

| Component         | Source                                        | Purpose                          |
|-------------------|-----------------------------------------------|----------------------------------|
| Caddy             | https://github.com/caddyserver/caddy          | Reverse proxy / web server       |
| caddy-dns/cloudflare | https://github.com/caddy-dns/cloudflare    | Cloudflare DNS-01 ACME challenge |
| caddy-ssh         | https://github.com/mohammed90/caddy-ssh       | SSH server module                |

## Build the installer artifact

```bash
cd Caddy
./export-installer.sh
```

The output lands at:

```text
./dist/caddy-installer.run
```

Override with:

```bash
OUTPUT_FILE=./release/caddy-installer.run ./export-installer.sh
```

## Install on a target host

```bash
# Basic install
sudo ./caddy-installer.run

# Install and set Cloudflare API token
sudo ./caddy-installer.run --cf-api-key "your-cloudflare-api-token"
```

Or extract without installing:

```bash
./caddy-installer.run --extract /tmp/caddy-payload
```

---

## Idempotent behaviour

The installer is designed to be run multiple times safely:

| Action                | First run          | Subsequent runs         |
|-----------------------|--------------------|-------------------------|
| Binary                | Installed          | Replaced (updated)      |
| Caddyfile             | Created (hello world) | **Preserved**        |
| Environment file      | Created (template) | **Preserved**           |
| `--cf-api-key` value  | Written to env     | Updated in env          |
| Systemd service file  | Created + enabled  | Updated + reloaded      |
| Service state         | Started            | Restarted (if was running) |

**Config files are never overwritten** — only the binary and service file are
updated on re-runs.

---

## Installation layout

```
/opt/hoster/caddy/
├── bin/
│   └── caddy                  ← static Go binary
└── build-info.txt             ← version + build date metadata

/etc/caddy/
├── Caddyfile                  ← site configuration (user-editable)
└── caddy.env                  ← environment variables (CF_API_TOKEN, etc.)

/usr/local/bin/caddy           ← symlink to /opt/hoster/caddy/bin/caddy
/var/lib/caddy/                ← runtime data (certificates, etc.)
```

## Systemd service

The installer creates and enables `caddy.service`. Key features:

- Runs as the dedicated `caddy` system user
- Validates config before starting (`ExecStartPre`)
- Supports graceful reload (`systemctl reload caddy`)
- Loads environment from `/etc/caddy/caddy.env`
- Hardened with `ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`, etc.

### Useful commands

```bash
systemctl status caddy          # check service status
systemctl reload caddy          # reload after config changes
journalctl -u caddy -f          # follow logs
caddy validate --config /etc/caddy/Caddyfile  # validate config
```

## Cloudflare DNS module

The Cloudflare module enables DNS-01 ACME challenges, allowing you to obtain
TLS certificates for hosts that are not directly reachable from the internet.

### 1. Set your API token

Either during install:

```bash
sudo ./caddy-installer.run --cf-api-key "your-token"
```

Or manually:

```bash
# Edit /etc/caddy/caddy.env
CF_API_TOKEN=your-cloudflare-api-token

# Restart to pick up the new token
systemctl restart caddy
```

Generate a token at https://dash.cloudflare.com/profile/api-tokens with the
permission **Zone / DNS / Edit**.

### 2. Use in your Caddyfile

```
example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy localhost:8080
}
```

## Notes

- Caddy is a static Go binary — no shared library bundling or `LD_LIBRARY_PATH`
  wrappers are needed.
- The installer does **not** version directories (unlike QEMU/CloudHypervisor)
  because Caddy runs as a managed service with a single active version.
- Re-running the installer with `--cf-api-key` on an existing install will
  update the token in-place without touching the Caddyfile.

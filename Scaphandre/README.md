# Scaphandre `.run` Builder

A Docker-based build wrapper that compiles Scaphandre from its upstream source
and packages it as a self-extracting `.run` installer. Upstream publishes source
releases without compiled release assets, so the binary is built and released
here instead of being committed to this repository.

## Version

The Docker build currently targets:

```text
Scaphandre             v1.0.3
Upstream commit        b64443c447e24f25947111ec8611449f213eb0a5
Rust builder           1.95 (musl)
Target                  x86_64 Linux
Features                prometheus, containers, qemu, json
```

Both the upstream tag and commit are pinned in `Dockerfile`. Scaphandre's
`v1.0.3` tag accidentally retains `1.0.2` as its Cargo package version; the
build corrects that metadata so the resulting binary reports `1.0.3`.

## Build the installer artifact

```bash
cd Scaphandre
./export-installer.sh
```

The output lands at:

```text
./dist/scaphandre-installer.run
```

Override the destination with:

```bash
OUTPUT_FILE=./release/scaphandre-installer.run ./export-installer.sh
```

## Install on a target host

```bash
sudo ./scaphandre-installer.run
```

Install the files without enabling or starting the service (useful in a
chroot or image build):

```bash
sudo ./scaphandre-installer.run --no-start
```

Or extract the payload without installing:

```bash
./scaphandre-installer.run --extract /tmp/scaphandre-payload
```

Re-running the installer updates the binary and systemd service. If the service
was active, it is stopped for the update and started again afterward.

## Installation layout

```text
/opt/hoster/scaphandre/
├── bin/
│   └── scaphandre
└── build-info.txt

/usr/local/bin/scaphandre -> /opt/hoster/scaphandre/bin/scaphandre
/etc/systemd/system/scaphandre.service
```

The binary is statically linked against musl, so the installer does not depend
on a target distribution's glibc or OpenSSL version.

## Service

The bundled service runs the Prometheus exporter as root because Scaphandre
needs access to RAPL data in `/sys/class/powercap` and process data in `/proc`.
It listens on all interfaces on port `1920` and enables QEMU and container
metrics.

Useful commands:

```bash
systemctl status scaphandre
journalctl -u scaphandre -f
curl http://localhost:1920/metrics
```

## Prometheus target

```yaml
- job_name: "scaphandre"
  fallback_scrape_protocol: PrometheusText0.0.4
  scrape_interval: 30s
  static_configs:
    - targets: ["localhost:1920"]
  relabel_configs:
    - source_labels: [__address__]
      target_label: instance
      replacement: "your_instance_name_here"
```

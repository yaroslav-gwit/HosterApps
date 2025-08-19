#!/usr/bin/env bash
#
#  etcd‑uninstall.sh
#
#  Completely removes the Etcd installation, its systemd unit, data,
#  and the dedicated system user/group.
#
#  Usage:
#      sudo ./etcd-uninstall.sh            # interactive confirmation
#      sudo ./etcd-uninstall.sh --force    # skip confirmation (e.g. CI)
#
#  Exit codes:
#      0 – success
#      1 – not run as root
#      2 – user aborted
#      3 – any other error
#

set -euo pipefail
trap 'error "An unexpected error occurred at line $LINENO." ; exit 3' ERR

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
error() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# --------------------------------------------------------------------------- #
# 1. Pre‑flight checks
# --------------------------------------------------------------------------- #
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

# --------------------------------------------------------------------------- #
# 2. Parse options
# --------------------------------------------------------------------------- #
FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force) FORCE=true ;;
        -h|--help)
            cat <<'HELP'
etcd-uninstall.sh  - Completely removes Etcd from the system.

Options:
  -f, --force    Skip the confirmation prompt (useful for scripts or CI).
  -h, --help     Show this help message.
HELP
            exit 0
            ;;
        *) error "Unknown option: $1"; exit 3 ;;
    esac
    shift
done

# --------------------------------------------------------------------------- #
# 3. Confirmation (unless forced)
# --------------------------------------------------------------------------- #
if ! $FORCE; then
    log "WARNING: This will permanently delete Etcd binaries, data and the system user."
    read -rp "Do you really want to continue? (y/N): " -n 1 REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled."
        exit 2
    fi
fi

# --------------------------------------------------------------------------- #
# 4. Stop and disable the service
# --------------------------------------------------------------------------- #
if systemctl is-active --quiet etcd; then
    log "Stopping the etcd service..."
    systemctl stop etcd
fi

if systemctl is-enabled --quiet etcd; then
    log "Disabling the etcd service..."
    systemctl disable etcd
fi

# --------------------------------------------------------------------------- #
# 5. Remove the unit file(s)
# --------------------------------------------------------------------------- #
for svc in "/etc/systemd/system/etcd.service" "/run/systemd/system/etcd.service"; do
    if [[ -f $svc ]]; then
        log "Removing systemd unit $svc ..."
        rm -f "$svc"
    fi
done

# Reload the daemon to pick up the removal
log "Reloading systemd daemon..."
systemctl daemon-reload

# --------------------------------------------------------------------------- #
# 6. Delete installation directory and data
# --------------------------------------------------------------------------- #
if [[ -d /opt/etcd ]]; then
    log "Removing /opt/etcd and all its contents..."
    rm -rf /opt/etcd
fi

# --------------------------------------------------------------------------- #
# 7. Delete the dedicated user & group
# --------------------------------------------------------------------------- #
if id -u etcd >/dev/null 2>&1; then
    log "Removing the 'etcd' system user ..."
    userdel etcd
fi

if getent group etcd >/dev/null 2>&1; then
    log "Removing the 'etcd' system group ..."
    groupdel etcd
fi

# --------------------------------------------------------------------------- #
# 8. Done
# --------------------------------------------------------------------------- #
log "Etcd has been completely removed."
log "All binaries, configuration, data and system user/group are gone."

#!/usr/bin/env bash
# ==============================================================================
# Gitea Backup Script
# Target: lake.dc.paradigm-works.com
# ==============================================================================

set -euo pipefail

# Configuration
BACKUP_DIR="/var/backups/gitea"
RETENTION_DAYS=14
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="gitea-backup-${TIMESTAMP}"
LOG_TAG="gitea-backup"
GITEA_BIN="/opt/gitea/bin/gitea"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "[-] Error: This script must be run as root." >&2
   exit 1
fi

# Logging helper
log() {
    echo "[+] $*"
    logger -t "$LOG_TAG" "$*"
}

error_exit() {
    echo "[-] Error: $*" >&2
    logger -t "$LOG_TAG" "ERROR: $*"
    [[ -n "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
    exit 1
}

cleanup() {
    [[ -n "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log "Starting Gitea backup process..."

# 1. Pre-flight checks
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

if [[ ! -x "$GITEA_BIN" ]]; then
    error_exit "Gitea binary not found or not executable at $GITEAr_BIN."
fi

# Create work directory as user 'git' so permissions match the dump process
WORK_DIR=$(sudo -u git mktemp -d) || error_exit "Failed to create temporary working directory."

# 2. Create Gitea native dump inside the secure work directory as user 'git'
log "Running gitea dump..."
if ! sudo -u git bash -c "cd '$WORK_DIR' && '$GITEA_BIN' dump -c /etc/gitea/app.ini --type tar.gz"; then
    error_exit "Gitea dump failed."
fi

# Find the generated dump archive
DUMP_ARCHIVE=$(find "$WORK_DIR" -maxdepth 1 -name "gitea-dump-*.tar.gz" | head -n 1)
if [[ -z "$DUMP_ARCHIVE" ]]; then
    error_exit "Gitea dump archive could not be located."
fi

# 3. Bundle configuration and SSL certificates (/etc/gitea contains app.ini and certs)[cite: 1]
log "Backing up /etc/gitea configuration and certificates..."
tar -czf "${WORK_DIR}/gitea-etc.tar.gz" -C /etc gitea

# 4. Finalize backup package
FINAL_ARCHIVE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
log "Assembling final backup package at ${FINAL_ARCHIVE}..."
tar -czf "$FINAL_ARCHIVE" -C "$WORK_DIR" "$(basename "$DUMP_ARCHIVE")" "gitea-etc.tar.gz"
chmod 600 "$FINAL_ARCHIVE"

# 5. Prune old backups
log "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "gitea-backup-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete

log "Gitea backup completed successfully: ${FINAL_ARCHIVE}"

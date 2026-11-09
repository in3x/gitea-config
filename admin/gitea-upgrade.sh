#!/usr/bin/env bash
# ==============================================================================
# Gitea Binary Upgrade Script
# Target: lake.dc.paradigm-works.com
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GITEA_BIN="/opt/gitea/bin/gitea"
BACKUP_SCRIPT="/opt/gitea/bin/gitea-backup.sh"

# Fall back to alternative locations if /opt/gitea/bin copy is not installed
if [[ ! -x "$BACKUP_SCRIPT" && -x "/usr/local/bin/gitea-backup.sh" ]]; then
    BACKUP_SCRIPT="/usr/local/bin/gitea-backup.sh"
elif [[ ! -x "$BACKUP_SCRIPT" && -x "$REPO_ROOT/scripts/gitea-backup.sh" ]]; then
    BACKUP_SCRIPT="$REPO_ROOT/scripts/gitea-backup.sh"
fi

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "[-] Error: This script must be run as root." >&2
   exit 1
fi

# 1. Run our established backup script first
if [[ -x "$BACKUP_SCRIPT" ]]; then
    echo "[+] Running pre-upgrade backup..."
    "$BACKUP_SCRIPT"
else
    echo "[-] Error: Backup script not found or not executable at $BACKUP_SCRIPT." >&2
    exit 1
fi

# 2. Fetch the latest release download URL via GitHub API (or specify a version tag)
echo "[+] Fetching latest Gitea release details..."
ARCH_ALIAS="$(detect_arch_alias 2>/dev/null || uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')"
LATEST_URL=$(curl -s https://api.github.com/repos/go-gitea/gitea/releases/latest \
    | grep -oE "https://[^\"]+linux-${ARCH_ALIAS}\"" \
    | grep -vE "\.(asc|sha256|xz|sigstore\.json)" \
    | tr -d '"' \
    | head -n 1)

if [[ -z "$LATEST_URL" ]]; then
    echo "[-] Error: Could not determine the latest Gitea release download URL." >&2
    exit 1
fi

echo "[+] Downloading latest binary from: $LATEST_URL"
TEMP_BIN="$(mktemp)"
curl -L -o "$TEMP_BIN" "$LATEST_URL"
chmod 700 "$TEMP_BIN"

# Verify the downloaded binary works
if ! "$TEMP_BIN" --version &>/dev/null; then
    echo "[-] Error: Downloaded binary failed verification." >&2
    rm -f "$TEMP_BIN"
    exit 1
fi

# 3. Stop Gitea service
echo "[+] Stopping gitea service..."
systemctl stop gitea

# 4. Replace binary
echo "[+] Replacing binary at $GITEA_BIN..."
mv "$TEMP_BIN" "$GITEA_BIN"
chown root:root "$GITEA_BIN"
chmod 755 "$GITEA_BIN"

# 5. Start Gitea service (triggers automatic DB migrations)
echo "[+] Starting gitea service..."
systemctl start gitea

# 6. Verify status
echo "[+] Verifying installation..."
sleep 2
systemctl --no-pager status gitea

echo "[+] Gitea upgrade completed successfully!"
"$GITEA_BIN" --version

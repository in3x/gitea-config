#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ALLOW_ROOT=false
QUIET_MODE=true
TARGET_SITE=""

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-root)
            ALLOW_ROOT=true
            shift
            ;;
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        -v|--verbose)
            QUIET_MODE=false
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [SITE] [OPTIONS]"
            echo ""
            echo "Stage 2 Deployment: Deploys site configuration and binaries to system targets."
            echo ""
            echo "Options:"
            echo "  SITE             Site profile name from site-conf/ (prompts menu if omitted)"
            echo "  -v, --verbose    Show unified diffs for mismatches"
            echo "  -q, --quiet      Suppress informational stdout"
            echo "      --allow-root Allow running directly as root without sudo"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        -*)
            echo "[-] Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$TARGET_SITE" ]]; then
                TARGET_SITE="$1"
            fi
            shift
            ;;
    esac
done

# Resolve real calling user and home directory
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
elif [[ $EUID -eq 0 ]]; then
    if [[ "$ALLOW_ROOT" == false ]]; then
        echo "[SAFETY ABORT] Running directly as root is disabled by default." >&2
        echo "               If running via sudo, \$HOME will resolve automatically." >&2
        echo "               To force execution as pure root, re-run with: $0 --allow-root" >&2
        logger -t deploy-gitea -p "user.err" "[SAFETY ABORT] Blocked direct root execution without --allow-root" 2>/dev/null || true
        exit 1
    fi
    REAL_USER="root"
    REAL_HOME="$HOME"
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

# Load shared dev-bootstrap library for site selection & platform detection
DEV_BOOTSTRAP_LIB="${HOME}/.local/lib/dev-bootstrap"
if [[ ! -f "$DEV_BOOTSTRAP_LIB/lib-common.sh" ]]; then
    echo "[-] Error: Shared platform library not found at $DEV_BOOTSTRAP_LIB" >&2
    echo "    Please run the host bootstrap to install it:" >&2
    echo "      bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only" >&2
    exit 1
fi
source "$DEV_BOOTSTRAP_LIB/lib-common.sh"

SITE="$(resolve_site "$TARGET_SITE" "$REPO_ROOT/site-conf")"
SITE_DIR="$REPO_ROOT/site-conf/$SITE"

GITEA_USER="git"
GITEA_GROUP="git"

TARGET_APP_INI="/etc/gitea/app.ini"
TARGET_SERVICE="/etc/systemd/system/gitea.service"
TARGET_BACKUP_SERVICE="/etc/systemd/system/gitea-backup.service"
TARGET_BACKUP_TIMER="/etc/systemd/system/gitea-backup.timer"
TARGET_BINARY="/opt/gitea/bin/gitea"
TARGET_BACKUP="/opt/gitea/bin/gitea-backup.sh"

SOURCE_APP_INI="$SITE_DIR/app.ini"
SOURCE_SERVICE="$REPO_ROOT/units/gitea.service"
SOURCE_BACKUP_SERVICE="$REPO_ROOT/units/gitea-backup.service"
SOURCE_BACKUP_TIMER="$REPO_ROOT/units/gitea-backup.timer"
SOURCE_BACKUP="$REPO_ROOT/scripts/gitea-backup.sh"

DIST_DIR="$REPO_ROOT/gitea-distribution"
LOCAL_BINARY="$DIST_DIR/gitea"

NEEDS_SYSTEMD_RELOAD=false
WAS_SERVICE_RUNNING=false

log_msg() {
    local level="$1"
    shift
    local msg="$*"
    
    logger -t deploy-gitea -p "user.$level" "$msg" 2>/dev/null || true
    
    if [[ "$QUIET_MODE" == false ]]; then
        echo "[$level] $msg"
    fi
}

check_binary_status() {
    local src="$1"
    local dst="$2"

    if [[ ! -f "$src" ]]; then
        echo "NO_LOCAL_BINARY"
        return
    fi

    if [[ ! -f "$dst" ]]; then
        echo "MISSING"
        return
    fi

    if ! cmp -s "$src" "$dst"; then
        echo "VERSION_MISMATCH"
        return
    fi

    local current_mode
    current_mode=$(stat -c "%a" "$dst")
    if [[ "$current_mode" != "755" ]]; then
        echo "MODE_MISMATCH ($current_mode vs 755)"
        return
    fi

    echo "OK"
}

check_file_status() {
    local src="$1"
    local dst="$2"
    local expected_owner="$3"
    local expected_mode="$4"

    if [[ ! -f "$dst" ]]; then
        echo "MISSING"
        return
    fi

    if ! cmp -s "$src" "$dst"; then
        echo "CONTENT_MISMATCH"
        return
    fi

    local current_owner
    current_owner=$(stat -c "%U:%G" "$dst")
    if [[ "$current_owner" != "$expected_owner" ]]; then
        echo "OWNER_MISMATCH ($current_owner vs $expected_owner)"
        return
    fi

    local current_mode
    current_mode=$(stat -c "%a" "$dst")
    if [[ "$current_mode" != "$expected_mode" ]]; then
        echo "MODE_MISMATCH ($current_mode vs $expected_mode)"
        return
    fi

    echo "OK"
}

check_dir_status() {
    local dir="$1"
    local expected_owner="$2"
    local expected_mode="$3"

    if [[ ! -d "$dir" ]]; then
        echo "MISSING"
        return
    fi

    local current_owner
    current_owner=$(stat -c "%U:%G" "$dir")
    if [[ "$current_owner" != "$expected_owner" ]]; then
        echo "OWNER_MISMATCH ($current_owner vs $expected_owner)"
        return
    fi

    local current_mode
    current_mode=$(stat -c "%a" "$dir")
    if [[ "$current_mode" != "$expected_mode" ]]; then
        echo "MODE_MISMATCH ($current_mode vs $expected_mode)"
        return
    fi

    echo "OK"
}

fetch_latest_gitea() {
    mkdir -p "$DIST_DIR"
    
    log_msg "info" "Checking GitHub for latest stable Gitea release..."
    
    LATEST_TAG=$(curl -sS https://api.github.com/repos/go-gitea/gitea/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_TAG" ]]; then
        log_msg "warn" "Could not determine latest Gitea release from GitHub API."
        return 1
    fi
    
    VERSION="${LATEST_TAG#v}"
    ARCH_ALIAS="$(detect_arch_alias 2>/dev/null || uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')"
    TARGET_FILENAME="gitea-${VERSION}-linux-${ARCH_ALIAS}"
    DOWNLOAD_URL="https://dl.gitea.com/gitea/${VERSION}/${TARGET_FILENAME}"
    DEST_FILE="$DIST_DIR/$TARGET_FILENAME"
    
    log_msg "info" "Latest production release found: $LATEST_TAG ($TARGET_FILENAME)"
    
    if [[ -f "$DEST_FILE" ]]; then
        log_msg "info" "Binary $TARGET_FILENAME is already present in $DIST_DIR."
    else
        read -rp "Download $TARGET_FILENAME from $DOWNLOAD_URL ? [y/N]: " CONFIRM_DL
        if [[ "$CONFIRM_DL" =~ ^[Yy]$ ]]; then
            log_msg "info" "Downloading $DOWNLOAD_URL..."
            curl -L "$DOWNLOAD_URL" -o "$DEST_FILE"
            chmod 755 "$DEST_FILE"
            log_msg "notice" "Successfully downloaded $TARGET_FILENAME"
        else
            log_msg "info" "Skipped binary download."
            return 0
        fi
    fi

    if [[ -f "$DEST_FILE" ]]; then
        ln -sf "$TARGET_FILENAME" "$LOCAL_BINARY"
        log_msg "info" "Symlinked $LOCAL_BINARY -> $TARGET_FILENAME"
    fi
}

prompt_and_apply_file() {
    local src="$1"
    local dst="$2"
    local owner="$3"
    local mode="$4"
    local status="$5"

    if [[ "$status" == "OK" ]]; then
        log_msg "info" "SKIP: $dst is already correct."
        return
    fi

    if [[ "$status" == "CONTENT_MISMATCH" && "$QUIET_MODE" == false ]]; then
        echo "---------------------------------------------------"
        echo "DIFF for $dst:"
        diff -u "$dst" "$src" || true
        echo "---------------------------------------------------"
    fi

    if [[ "$status" == "MISSING" ]]; then
        PROMPT_MSG="Target $dst is missing. Create it now? [y/N]: "
    else
        PROMPT_MSG="Target $dst exists but has differences ($status). Overwrite/update? [y/N]: "
    fi

    read -rp "$PROMPT_MSG" CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        sudo cp "$src" "$dst"
        sudo chown "$owner" "$dst"
        sudo chmod "$mode" "$dst"
        log_msg "notice" "UPDATED: $dst (Owner: $owner, Mode: $mode)"
        NEEDS_SYSTEMD_RELOAD=true
    else
        log_msg "info" "SKIPPED by user: Left $dst unchanged."
    fi
}

prompt_and_apply_dir() {
    local dir="$1"
    local owner="$2"
    local mode="$3"
    local status="$4"

    if [[ "$status" == "OK" ]]; then
        log_msg "info" "SKIP: Directory $dir is already correct."
        return
    fi

    if [[ "$status" == "MISSING" ]]; then
        PROMPT_MSG="Directory $dir is missing. Create it? [y/N]: "
    else
        PROMPT_MSG="Directory $dir exists but permissions differ ($status). Fix permissions? [y/N]: "
    fi

    read -rp "$PROMPT_MSG" CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        sudo mkdir -p "$dir"
        sudo chown "$owner" "$dir"
        sudo chmod "$mode" "$dir"
        log_msg "notice" "UPDATED: Directory $dir (Owner: $owner, Mode: $mode)"
    else
        log_msg "info" "SKIPPED by user: Left directory $dir unchanged."
    fi
}

# --- EXECUTION FLOW ---

echo "===================================================================="
echo " Gitea Deployment Target Configuration"
echo "===================================================================="
echo " Mode:          System (Root)"
echo " Site Profile:  $SITE"
echo " Source Config: $SOURCE_APP_INI"
echo " Target Binary: $TARGET_BINARY"
echo " Target Backup: $TARGET_BACKUP"
echo " Target Config: $TARGET_APP_INI"
echo " Target Unit:   $TARGET_SERVICE"
echo " Working Dir:   /var/lib/gitea"
echo "===================================================================="

# 1. Primary Safety Checks
if [[ ! -f "$SOURCE_APP_INI" ]]; then
    log_msg "err" "[ABORT] Site profile config not found: $SOURCE_APP_INI"
    echo "[-] Error: Run 'admin/site-profile.sh $SITE' to generate the profile first." >&2
    exit 1
fi

if [[ ! -f "$SOURCE_SERVICE" ]]; then
    log_msg "err" "[ABORT] Unit file missing: $SOURCE_SERVICE"
    exit 1
fi

if [[ ! -f "$SOURCE_BACKUP" ]]; then
    log_msg "err" "[ABORT] Backup script missing: $SOURCE_BACKUP"
    exit 1
fi

if [[ ! -f "$SOURCE_BACKUP_SERVICE" || ! -f "$SOURCE_BACKUP_TIMER" ]]; then
    log_msg "err" "[ABORT] Backup systemd units missing from units/"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    if ! sudo -v; then
        log_msg "err" "Sudo privileges required to check and deploy files."
        exit 1
    fi
fi

if ! getent group "$GITEA_GROUP" >/dev/null 2>&1; then
    log_msg "err" "Group '$GITEA_GROUP' does not exist."
    exit 1
fi

if ! id -u "$GITEA_USER" >/dev/null 2>&1; then
    log_msg "err" "User '$GITEA_USER' does not exist."
    log_msg "err" "Create it with: sudo adduser --system --group --disabled-password --home /usr/local/home/git $GITEA_USER"
    exit 1
fi

# Ensure local distribution files are owned by the non-root calling user
mkdir -p "$DIST_DIR"
chown -R "$REAL_USER:$REAL_USER" "$DIST_DIR" 2>/dev/null || true

# 2. Fetch / Download latest release binary
fetch_latest_gitea

# 3. Inspect target state against source files
log_msg "info" "Inspecting target state against $SITE_DIR source files..."

APP_INI_STATUS=$(check_file_status "$SOURCE_APP_INI" "$TARGET_APP_INI" "$GITEA_USER:$GITEA_GROUP" "640")
SERVICE_STATUS=$(check_file_status "$SOURCE_SERVICE" "$TARGET_SERVICE" "root:root" "644")
BACKUP_SERVICE_STATUS=$(check_file_status "$SOURCE_BACKUP_SERVICE" "$TARGET_BACKUP_SERVICE" "root:root" "644")
BACKUP_TIMER_STATUS=$(check_file_status "$SOURCE_BACKUP_TIMER" "$TARGET_BACKUP_TIMER" "root:root" "644")
BACKUP_STATUS=$(check_file_status "$SOURCE_BACKUP" "$TARGET_BACKUP" "root:root" "750")
DIR_ETC_STATUS=$(check_dir_status "/etc/gitea" "root:$GITEA_GROUP" "770")
DIR_VAR_STATUS=$(check_dir_status "/var/lib/gitea" "$GITEA_USER:$GITEA_GROUP" "750")
BINARY_STATUS=$(check_binary_status "$LOCAL_BINARY" "$TARGET_BINARY")

if [[ "$APP_INI_STATUS" == "OK" && "$SERVICE_STATUS" == "OK" && "$BACKUP_SERVICE_STATUS" == "OK" && "$BACKUP_TIMER_STATUS" == "OK" && "$BACKUP_STATUS" == "OK" && "$DIR_ETC_STATUS" == "OK" && "$DIR_VAR_STATUS" == "OK" && "$BINARY_STATUS" == "OK" ]]; then
    log_msg "info" "All target files, binaries, and directories are up to date with correct permissions. No changes required."
    exit 0
fi

# 4. Service shutdown prompt if changes are required
if systemctl is-active --quiet gitea.service 2>/dev/null; then
    WAS_SERVICE_RUNNING=true
    log_msg "notice" "gitea.service is currently RUNNING."
    read -rp "Stop gitea.service before applying changes? [y/N]: " STOP_CONFIRM
    if [[ ! "$STOP_CONFIRM" =~ ^[Yy]$ ]]; then
        log_msg "notice" "[ABORT] Deployment canceled by user. Service must be stopped to safely make changes."
        exit 0
    fi
    log_msg "info" "Stopping gitea.service..."
    sudo systemctl stop gitea.service
fi

# 5. Apply directories and files
prompt_and_apply_dir "/etc/gitea" "root:$GITEA_GROUP" "770" "$DIR_ETC_STATUS"
prompt_and_apply_dir "/var/lib/gitea" "$GITEA_USER:$GITEA_GROUP" "750" "$DIR_VAR_STATUS"

prompt_and_apply_file "$SOURCE_APP_INI" "$TARGET_APP_INI" "$GITEA_USER:$GITEA_GROUP" "640" "$APP_INI_STATUS"
prompt_and_apply_file "$SOURCE_SERVICE" "$TARGET_SERVICE" "root:root" "644" "$SERVICE_STATUS"
prompt_and_apply_file "$SOURCE_BACKUP_SERVICE" "$TARGET_BACKUP_SERVICE" "root:root" "644" "$BACKUP_SERVICE_STATUS"
prompt_and_apply_file "$SOURCE_BACKUP_TIMER" "$TARGET_BACKUP_TIMER" "root:root" "644" "$BACKUP_TIMER_STATUS"
prompt_and_apply_file "$SOURCE_BACKUP" "$TARGET_BACKUP" "root:root" "750" "$BACKUP_STATUS"

# 6. Apply binary update if required
if [[ "$BINARY_STATUS" != "OK" && "$BINARY_STATUS" != "NO_LOCAL_BINARY" ]]; then
    PROMPT_MSG="Target binary $TARGET_BINARY is $BINARY_STATUS. Update executable binary? [y/N]: "
    read -rp "$PROMPT_MSG" CONFIRM_UPDATE
    if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        sudo cp -L "$LOCAL_BINARY" "$TARGET_BINARY"
        sudo chown root:root "$TARGET_BINARY"
        sudo chmod 755 "$TARGET_BINARY"
        log_msg "notice" "UPDATED binary: $TARGET_BINARY"
    else
        log_msg "info" "SKIPPED by user: Left $TARGET_BINARY unchanged."
    fi
fi

# 7. Reload systemd daemon if service file changed
if $NEEDS_SYSTEMD_RELOAD; then
    log_msg "info" "Reloading systemd daemon..."
    sudo systemctl daemon-reload
fi

# 8. Restart service if previously running
if $WAS_SERVICE_RUNNING; then
    read -rp "gitea.service was stopped earlier. Restart it now? [Y/n]: " RESTART_CONFIRM
    RESTART_CONFIRM=${RESTART_CONFIRM:-Y}
    if [[ "$RESTART_CONFIRM" =~ ^[Yy]$ ]]; then
        log_msg "info" "Starting gitea.service..."
        sudo systemctl start gitea.service
    else
        log_msg "notice" "gitea.service was left STOPPED by user choice."
    fi
fi

log_msg "info" "Deployment execution finished."

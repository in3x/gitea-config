#!/usr/bin/env bash
# ==============================================================================
# Jujutsu (jj) Install & Upgrade Script
# Fetches the latest (or specified) release of Jujutsu from GitHub
# ==============================================================================

set -euo pipefail

REPO="jj-vcs/jj"
SPECIFIED_VERSION=""
FORCE=false
CUSTOM_DIR=""
INSTALL_MODE=""

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Downloads and installs or upgrades Jujutsu (jj) to the latest stable release.

Options:
  -v, --version <TAG>   Install a specific version (e.g., v0.47.1 or 0.47.1).
  -d, --dir <PATH>      Target directory for the jj executable.
      --user            Install to ~/.local/bin (default for non-root).
      --system          Install to /usr/local/bin (default for root).
  -f, --force           Force reinstall even if current version is up to date.
  -h, --help            Show this help message.

EOF
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            SPECIFIED_VERSION="$2"
            shift 2
            ;;
        -d|--dir)
            CUSTOM_DIR="$2"
            shift 2
            ;;
        --user)
            INSTALL_MODE="user"
            shift
            ;;
        --system)
            INSTALL_MODE="system"
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "[-] Error: Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Logging helpers
log() {
    echo "[+] $*"
}

error_exit() {
    echo "[-] Error: $*" >&2
    exit 1
}

# 1. Architecture detection
ARCH="$(uname -m)"
OS="$(uname -s)"

if [[ "$OS" != "Linux" ]]; then
    error_exit "This script currently only supports Linux (detected: $OS)."
fi

case "$ARCH" in
    x86_64|amd64)
        TARGET_ARCH="x86_64-unknown-linux-musl"
        ;;
    aarch64|arm64)
        TARGET_ARCH="aarch64-unknown-linux-musl"
        ;;
    *)
        error_exit "Unsupported CPU architecture: $ARCH"
        ;;
esac

# 2. Determine target installation directory
if [[ -n "$CUSTOM_DIR" ]]; then
    TARGET_DIR="$CUSTOM_DIR"
elif [[ "$INSTALL_MODE" == "user" ]]; then
    TARGET_DIR="${HOME}/.local/bin"
elif [[ "$INSTALL_MODE" == "system" ]]; then
    TARGET_DIR="/usr/local/bin"
elif command -v jj >/dev/null 2>&1; then
    EXISTING_JJ="$(command -v jj)"
    TARGET_DIR="$(dirname "$EXISTING_JJ")"
elif [[ $EUID -eq 0 ]]; then
    TARGET_DIR="/usr/local/bin"
else
    TARGET_DIR="${HOME}/.local/bin"
fi

TARGET_BIN="${TARGET_DIR}/jj"

# 3. Resolve version to install
if [[ -n "$SPECIFIED_VERSION" ]]; then
    if [[ "$SPECIFIED_VERSION" =~ ^v ]]; then
        TARGET_TAG="$SPECIFIED_VERSION"
    else
        TARGET_TAG="v${SPECIFIED_VERSION}"
    fi
    log "Requested version: $TARGET_TAG"
else
    log "Checking GitHub for the latest stable Jujutsu release..."
    RELEASE_JSON=$(curl -sS "https://api.github.com/repos/${REPO}/releases/latest")
    LATEST_TAG=$(echo "$RELEASE_JSON" | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1)

    if [[ -z "$LATEST_TAG" ]]; then
        error_exit "Could not retrieve latest release tag from GitHub API."
    fi
    TARGET_TAG="$LATEST_TAG"
    log "Latest release found: $TARGET_TAG"
fi

TARGET_VER="${TARGET_TAG#v}"

# 4. Check currently installed version
if [[ -x "$TARGET_BIN" ]] && [[ "$FORCE" == false ]]; then
    CURRENT_RAW=$("$TARGET_BIN" --version 2>/dev/null || true)
    # Output is typically "jj 0.47.1-hash..."
    CURRENT_VER=$(echo "$CURRENT_RAW" | awk '{print $2}' | cut -d'-' -f1)
    if [[ "$CURRENT_VER" == "$TARGET_VER" ]]; then
        log "Jujutsu is already up to date ($CURRENT_RAW at $TARGET_BIN)."
        log "Use --force to reinstall."
        exit 0
    elif [[ -n "$CURRENT_VER" ]]; then
        log "Current installed version: $CURRENT_VER -> Target version: $TARGET_VER"
    fi
fi

# 5. Download and verify binary
DOWNLOAD_FILENAME="jj-${TARGET_TAG}-${TARGET_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TARGET_TAG}/${DOWNLOAD_FILENAME}"

WORK_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log "Downloading $DOWNLOAD_FILENAME from GitHub..."
if ! curl -fL --progress-bar -o "${WORK_DIR}/${DOWNLOAD_FILENAME}" "$DOWNLOAD_URL"; then
    error_exit "Failed to download $DOWNLOAD_URL"
fi

log "Extracting binary..."
tar -xzf "${WORK_DIR}/${DOWNLOAD_FILENAME}" -C "$WORK_DIR"

EXTRACTED_BIN="${WORK_DIR}/jj"
if [[ ! -f "$EXTRACTED_BIN" ]]; then
    error_exit "Archive did not contain 'jj' executable."
fi
chmod 755 "$EXTRACTED_BIN"

# Verify execution
NEW_VERSION_OUTPUT=$("$EXTRACTED_BIN" --version)
log "Extracted binary verified: $NEW_VERSION_OUTPUT"

# 6. Install to target directory
# Determine if sudo is required for write permissions
NEED_SUDO=false
if [[ ! -d "$TARGET_DIR" ]]; then
    if ! mkdir -p "$TARGET_DIR" 2>/dev/null; then
        NEED_SUDO=true
    fi
elif [[ ! -w "$TARGET_DIR" ]] || ([[ -e "$TARGET_BIN" ]] && [[ ! -w "$TARGET_BIN" ]]); then
    NEED_SUDO=true
fi

log "Installing executable to $TARGET_BIN..."
if [[ "$NEED_SUDO" == true ]]; then
    log "Sudo permissions required to install to $TARGET_DIR"
    sudo mkdir -p "$TARGET_DIR"
    sudo cp "$EXTRACTED_BIN" "$TARGET_BIN"
    sudo chmod 755 "$TARGET_BIN"
else
    mkdir -p "$TARGET_DIR"
    cp "$EXTRACTED_BIN" "$TARGET_BIN"
    chmod 755 "$TARGET_BIN"
fi

# 7. Final status confirmation
log "Jujutsu upgraded successfully!"
"$TARGET_BIN" --version
log "Binary installed at: $TARGET_BIN"

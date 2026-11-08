#!/usr/bin/env bash
# ==============================================================================
# Site Profile Management Tool (Stage 1 Lifecycle)
# Syncs canonical conf/app.ini templates into site-conf/<site>/app.ini
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE="$REPO_ROOT/conf/app.ini"
SITE_CONF_DIR="$REPO_ROOT/site-conf"

if [[ ! -f "$TEMPLATE" ]]; then
    echo "[-] Error: Canonical template not found at $TEMPLATE" >&2
    exit 1
fi

mkdir -p "$SITE_CONF_DIR"

# Deterministic site selection (CLI argument or interactive menu)
resolve_or_create_site() {
    local target_site="${1:-}"
    if [[ -n "$target_site" ]]; then
        echo "$target_site"
        return
    fi

    local sites=($(find "$SITE_CONF_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort))
    
    echo "Select a site profile to manage:" >&2
    local count=0
    for i in "${!sites[@]}"; do
        echo "  $((i+1))) ${sites[$i]}" >&2
        count=$((i+1))
    done
    echo "  $((count+1))) [Create new profile]" >&2

    read -rp "Selection [1-$((count+1))]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count + 1 )); then
        echo "[-] Invalid selection." >&2
        exit 1
    fi

    if (( choice == count + 1 )); then
        read -rp "Enter new site profile ID (e.g., lake, prod-east, lab): " new_id
        if [[ -z "$new_id" || ! "$new_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "[-] Error: Invalid site ID '$new_id'. Use alphanumeric, hyphen, or underscore." >&2
            exit 1
        fi
        echo "$new_id"
    else
        echo "${sites[$((choice-1))]}"
    fi
}

TARGET_SITE="$(resolve_or_create_site "${1:-}")"
TARGET_DIR="$SITE_CONF_DIR/$TARGET_SITE"
TARGET_CONFIG="$TARGET_DIR/app.ini"

# Stage 1: Initialization or Non-destructive Merge
if [[ ! -f "$TARGET_CONFIG" ]]; then
    echo "[+] Initializing new site profile: $TARGET_SITE"
    mkdir -p "$TARGET_DIR"

    read -rp "Domain FQDN (e.g. ${TARGET_SITE}.dc.paradigm-works.com): " DOMAIN
    DOMAIN="${DOMAIN:-${TARGET_SITE}.dc.paradigm-works.com}"

    # Generate cryptographically secure tokens
    LFS_SECRET=$(openssl rand -base64 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    INTERNAL_TOKEN=$(openssl rand -base64 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    JWT_SECRET=$(openssl rand -base64 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_urlsafe(32))")

    sed \
        -e "s|{{DOMAIN}}|$DOMAIN|g" \
        -e "s|{{LFS_JWT_SECRET}}|$LFS_SECRET|g" \
        -e "s|{{INTERNAL_TOKEN}}|$INTERNAL_TOKEN|g" \
        -e "s|{{JWT_SECRET}}|$JWT_SECRET|g" \
        "$TEMPLATE" > "$TARGET_CONFIG"

    chmod 600 "$TARGET_CONFIG"
    echo "[+] Successfully created site-conf/$TARGET_SITE/app.ini"
    echo "    Domain:         $DOMAIN"
    echo "    Generated keys: LFS_JWT_SECRET, INTERNAL_TOKEN, JWT_SECRET"
    echo "    Target:         $TARGET_CONFIG"
else
    echo "[+] Existing profile detected: site-conf/$TARGET_SITE/app.ini"
    echo "[+] Running non-destructive template sync (checking for missing sections & keys)..."

    python3 - <<EOF
from pathlib import Path

template_path = Path("$TEMPLATE")
target_path = Path("$TARGET_CONFIG")

t_lines = template_path.read_text(encoding="utf-8").splitlines()
s_lines = target_path.read_text(encoding="utf-8").splitlines()

def parse_ini(lines):
    top = []
    sec = {}
    cur = None
    for line in lines:
        s = line.strip()
        if not s or s.startswith(('#', ';')):
            continue
        if s.startswith('[') and s.endswith(']'):
            cur = s[1:-1].strip()
            if cur not in sec:
                sec[cur] = []
        elif '=' in s:
            k = s.split('=', 1)[0].strip()
            if cur is None:
                top.append(k)
            else:
                sec[cur].append(k)
    return top, sec

top_t, sec_t = parse_ini(t_lines)
top_s, sec_s = parse_ini(s_lines)

result_lines = list(s_lines)
added_keys = []
added_secs = []

# Check missing top-level keys
for k in top_t:
    if k not in top_s:
        for line in t_lines:
            if line.strip().startswith(k + ' ') or line.strip().startswith(k + '='):
                idx = 0
                for i, r in enumerate(result_lines):
                    if r.strip().startswith('['):
                        idx = i
                        break
                result_lines.insert(idx, line)
                added_keys.append(('(root)', k))
                break

# Check missing sections and keys within sections
for sec_name, keys in sec_t.items():
    if sec_name not in sec_s:
        block = []
        in_sec = False
        for line in t_lines:
            s = line.strip()
            if s.startswith('[') and s.endswith(']'):
                cur = s[1:-1].strip()
                if cur == sec_name:
                    in_sec = True
                elif in_sec:
                    break
            if in_sec:
                block.append(line)
        if result_lines and result_lines[-1].strip() != '':
            result_lines.append('')
        result_lines.extend(block)
        added_secs.append(sec_name)
    else:
        existing_keys = sec_s[sec_name]
        for k in keys:
            if k not in existing_keys:
                key_line = None
                in_sec = False
                for line in t_lines:
                    s = line.strip()
                    if s.startswith('[') and s.endswith(']'):
                        in_sec = (s[1:-1].strip() == sec_name)
                    elif in_sec and (s.startswith(k + ' ') or s.startswith(k + '=')):
                        key_line = line
                        break
                if key_line:
                    for idx, r in enumerate(result_lines):
                        if r.strip() == f'[{sec_name}]':
                            result_lines.insert(idx + 1, key_line)
                            added_keys.append((sec_name, k))
                            break

if added_secs or added_keys:
    target_path.write_text('\n'.join(result_lines) + '\n', encoding="utf-8")
    print(f"[+] Added {len(added_secs)} missing sections and {len(added_keys)} missing keys to {target_path}")
    for sec in added_secs:
        print(f"    + Section: [{sec}]")
    for sec, key in added_keys:
        print(f"    + Key: [{sec}] {key}")
else:
    print("[+] All template sections and keys are present. No additions needed.")
EOF
fi

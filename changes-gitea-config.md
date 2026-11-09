# Standards Evaluation & Proposed Changes: gitea-config

## 1. Executive Summary

`gitea-config` is currently the most standards-compliant repository in the workspace. It faithfully implements the standard directory scaffolding, separation of concerns, and two-stage configuration lifecycle. 

However, it contains **procedural duplication** that should be offloaded to the centralized developer platform library (`~/.local/lib/dev-bootstrap`), a few **architectural hardcodings**, and an **undeployed operational script**.

---

## 2. Standards Compliance Scorecard

| Standard | Status | Observations |
| :--- | :--- | :--- |
| **Directory Scaffolding** (`package-scaffolding`) | **Pass** | Clean separation of `admin/`, `conf/`, `site-conf/`, `scripts/`, `units/`, and `docs/`. |
| **Separation of Concerns** (`script-conventions`) | **Pass** | Clear separation between operational worker (`scripts/gitea-backup.sh`) and administrative deployment (`admin/gitea-deploy.sh`). |
| **Script Naming** (`script-conventions`) | **Minor Inconsistency** | Core scripts use `<app>-<function>.sh`. However, `admin/jj-install.sh` and `admin/jj-update.sh` duplicate external tooling. |
| **Two-Stage Config** (`site-conf-pattern`) | **Pass** | Stage 1 (`admin/site-profile.sh`) and Stage 2 (`admin/gitea-deploy.sh`) are properly separated. |
| **Deterministic Site Selection** | **Pass** | Respects `$1` with interactive numbered menu fallback. |
| **Target Hierarchy** | **Pass** | Uses `/opt/gitea/bin/` for binaries and `/etc/gitea/` for configs. |
| **Architecture Independence** | **Fail** | Hardcodes `linux-amd64` in binary fetch routines. |

---

## 3. Detailed Inconsistencies & Duplications

### A. Redundant Platform Tooling (`admin/jj-install.sh` & `admin/jj-update.sh`)
- **Problem**: `gitea-config/admin/jj-install.sh` (291 lines) and `admin/jj-update.sh` are local duplicates of the Jujutsu installer.
- **Why It Matters**: Developer tooling installation belongs to the host environment platform (`zed-standards` / `dev-bootstrap`), not inside an application service repository. When the upstream installer was improved (e.g. adding version comparison and upgrade logic), `gitea-config` remained stuck on an older version.
- **Fix**: Remove both files from `gitea-config`. Rely on the host's existing `jj` or the centralized library at `~/.local/lib/dev-bootstrap/jj-install.sh`.

### B. Duplicated Site Selection Logic
- **Problem**: `admin/site-profile.sh` (lines 20–59) and `admin/gitea-deploy.sh` (lines 72–101) each implement their own Bash loop to find directories in `site-conf/`, sort them, format a numbered menu, and validate integer input.
- **Why It Matters**: If menu handling or formatting changes, every script must be edited individually.
- **Fix**: Offload site resolution to the shared library:
  ```bash
  source "${HOME}/.local/lib/dev-bootstrap/lib-site.sh"
  SITE="$(resolve_site "${1:-}" "$REPO_ROOT/site-conf")"
  ```

### C. Hardcoded CPU Architecture
- **Problem**: Both `admin/gitea-deploy.sh` (line 234) and `admin/gitea-upgrade.sh` (line 28) explicitly hardcode `linux-amd64`:
  ```bash
  TARGET_FILENAME="gitea-${VERSION}-linux-amd64"
  ```
- **Why It Matters**: Prevents deploying or upgrading on ARM64 servers (`aarch64`) or virtual machines.
- **Fix**: Use architecture detection (or `~/.local/lib/dev-bootstrap/lib-platform.sh`):
  ```bash
  case "$(uname -m)" in
      x86_64|amd64) ARCH="linux-amd64" ;;
      aarch64|arm64) ARCH="linux-arm64" ;;
      *) echo "[-] Unsupported architecture" >&2; exit 1 ;;
  esac
  ```

### D. Undeployed Operational Script (`scripts/gitea-backup.sh`)
- **Problem**:
  - `scripts/gitea-backup.sh` exists in the repository.
  - `admin/gitea-upgrade.sh` checks for `/usr/local/bin/gitea-backup.sh` before upgrading.
  - However, `admin/gitea-deploy.sh` only installs `app.ini`, `gitea.service`, and the `gitea` binary; it never deploys `gitea-backup.sh` to `/opt/gitea/bin/gitea-backup.sh`.
- **Why It Matters**: The operational script is left sitting in the git checkout rather than running from the production binary directory.
- **Fix**:
  1. Add `TARGET_BACKUP="/opt/gitea/bin/gitea-backup.sh"` to `admin/gitea-deploy.sh`.
  2. Deploy it alongside the binary with ownership `root:root` and mode `0750`.
  3. Update `admin/gitea-upgrade.sh` to look in `/opt/gitea/bin/gitea-backup.sh`.

---

## 4. Migration Plan for `gitea-config`

```text
gitea-config/
├── admin/
│   ├── gitea-deploy.sh            # Updated: deploys backup script, sources lib-site & lib-platform
│   ├── gitea-upgrade.sh           # Updated: dynamic arch detection, checks /opt/gitea/bin/
│   ├── jj-install.sh              # [DELETE] (Handled by dev-bootstrap)
│   ├── jj-update.sh               # [DELETE] (Handled by dev-bootstrap)
│   └── site-profile.sh            # Updated: sources lib-site
├── scripts/
│   └── gitea-backup.sh            # Preserved as canonical operational worker
├── conf/
│   └── app.ini                    # Preserved
├── site-conf/
│   └── lake/app.ini               # Preserved
├── units/
    │   ├── gitea.service              # Preserved
    │   ├── gitea-backup.service       # Added: oneshot service executing /opt/gitea/bin/gitea-backup.sh
    │   └── gitea-backup.timer         # Added: systemd timer (default: daily at 02:00 AM)
```

### Action Items:
1. `rm /home/ubuntu/Projects/gitea-config/admin/jj-install.sh /home/ubuntu/Projects/gitea-config/admin/jj-update.sh`
2. Update `admin/gitea-deploy.sh` to deploy `scripts/gitea-backup.sh` to `/opt/gitea/bin/gitea-backup.sh`.
3. Add dynamic architecture resolution in `admin/gitea-deploy.sh` and `admin/gitea-upgrade.sh`.
4. Update `README.md` in `gitea-config` to remove references to `jj-install.sh`.

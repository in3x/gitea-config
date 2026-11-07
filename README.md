# Gitea Configuration & Server Management

This repository contains configuration files, systemd service definitions, and operational automation scripts for deploying, maintaining, backing up, and upgrading a production [Gitea](https://about.gitea.com/) instance on `lake.dc.paradigm-works.com`.

---

## Repository Structure

| File | Target Location | Description |
| :--- | :--- | :--- |
| `gitea-app.ini` | `/etc/gitea/app.ini` | Production Gitea configuration file (HTTPS, SQLite, SSH, LFS). |
| `gitea.service` | `/etc/systemd/system/gitea.service` | Systemd service definition for managing the Gitea daemon. |
| `deploy-gitea.sh` | Local repository utility | Interactive audit and deployment script to sync configs, permissions, and binaries. |
| `gitea-backup.sh` | `/usr/local/bin/gitea-backup.sh` | Automated backup script bundling `gitea dump`, `/etc/gitea` configs, and SSL certs. |
| `gitea-upgrade.sh` | Host utility / maintenance script | Automated binary upgrade script with mandatory pre-upgrade backup. |
| `install-jj.sh` | Local repository utility | Script to install or upgrade Jujutsu (`jj`) to the latest release. |
| `guides/jj_workflow_guide.md` | Documentation | Jujutsu (`jj`) version control workflow guide for working with this server. |

---

## Server Architecture & Target Environment

- **Target Host / Domain**: `lake.dc.paradigm-works.com`
- **Web UI & API Protocol**: HTTPS on port `3000` (`https://lake.dc.paradigm-works.com:3000/`)
- **TLS Certificates**: `/etc/gitea/lake.dc.paradigm-works.com_chain.pem` and `/etc/gitea/lake.dc.paradigm-works.com_private.pem`
- **SSH Service**: Built-in Gitea SSH server on port `20022`
- **System User & Group**: `git:git` (`/usr/local/home/git`)
- **Binary Path**: `/opt/gitea/bin/gitea`
- **Working & Data Directory**: `/var/lib/gitea/`
  - Repositories: `/var/lib/gitea/data/gitea-repositories`
  - Database: SQLite3 at `/var/lib/gitea/data/gitea.db`
  - Git LFS: `/var/lib/gitea/data/lfs`

---

## Operations & Scripts

### 1. Deployment and Configuration Sync (`deploy-gitea.sh`)

An interactive maintenance tool that checks the state of configuration files, directories, permissions, and binaries against this repository.

#### Key Features:
- **Safety checks**: Prevents accidental raw root execution (`--allow-root` required if not run via `sudo`).
- **Binary caching & update**: Queries GitHub for the latest stable binary and stores it in `gitea-distribution/` (symlinked as `gitea`).
- **Permission & diff verification**: Displays unified diffs when differences exist before prompting to update targets.
- **Service management**: Prompts to gracefully stop `gitea.service` prior to applying file/binary changes and restarts it upon completion.

#### Target Permissions Enforced:
| Target Path | Owner : Group | Permissions |
| :--- | :--- | :--- |
| `/etc/gitea` | `root:git` | `770` (`rwxrwx---`) |
| `/var/lib/gitea` | `git:git` | `750` (`rwxr-x---`) |
| `/etc/gitea/app.ini` | `git:git` | `640` (`rw-r-----`) |
| `/etc/systemd/system/gitea.service` | `root:root` | `644` (`rw-r--r--`) |
| `/opt/gitea/bin/gitea` | `root:root` | `755` (`rwxr-xr-x`) |

#### Usage:
```bash
# Run interactively (quiet by default, prompts for each mismatched change)
./deploy-gitea.sh

# Run with verbose output (shows full diffs for modified files)
./deploy-gitea.sh -v

# Force execution as pure root (bypassing sudo user resolution)
./deploy-gitea.sh --allow-root
```

---

### 2. Backups (`gitea-backup.sh`)

Creates a complete, timestamped archive containing:
1. Gitea native dump (`gitea dump` executed as the `git` user, backing up the SQLite database and repositories).
2. Configuration directory (`/etc/gitea`, preserving `app.ini` and SSL certificates).

#### Key Features:
- Saves archives to `/var/backups/gitea/gitea-backup-YYYYMMDD_HHMMSS.tar.gz` with `600` permissions.
- Automatically cleans up archives older than **14 days**.
- Logs events to `syslog` / `journald` under the tag `gitea-backup`.

#### Recommended Setup:
Install to `/usr/local/bin/gitea-backup.sh` and execute via a daily root cron job or systemd timer:
```bash
sudo cp gitea-backup.sh /usr/local/bin/gitea-backup.sh
sudo chmod 700 /usr/local/bin/gitea-backup.sh
```

---

### 3. Upgrading Gitea (`gitea-upgrade.sh`)

Automates production binary upgrades with zero data-loss risk:
1. **Pre-flight backup**: Automatically triggers `/usr/local/bin/gitea-backup.sh` before modifying any files.
2. **Download & verify**: Downloads the latest `linux-amd64` release binary from GitHub and verifies binary execution (`--version`).
3. **Atomic replacement**: Stops `gitea.service`, replaces `/opt/gitea/bin/gitea`, updates permissions, and restarts the service.
4. **Automatic migration**: Starting Gitea executes any pending database schema migrations automatically.

#### Usage:
```bash
sudo ./gitea-upgrade.sh
```

---

### 4. Installing & Upgrading Jujutsu (`install-jj.sh`)

Automates installing or updating the Jujutsu (`jj`) binary to the latest GitHub release.

#### Key Features:
- Detects host architecture (`x86_64` / `aarch64`).
- Intelligently targets the active `jj` installation directory (or `~/.local/bin` / `/usr/local/bin`).
- Idempotent: checks current version against latest release before downloading.
- Supports `--user`, `--system`, `--dir <PATH>`, `--version <TAG>`, and `--force`.
- Symlinked as `update-jj.sh`.

#### Usage:
```bash
# Update jj to the latest release
./update-jj.sh

# Force reinstall or install specific version
./install-jj.sh --version v0.47.1 --force
```

---

## Client Workflow with Jujutsu (`jj`)

Jujutsu (`jj`) is the standard version control tool used with this Gitea server. All repositories hosted here can be cloned, tracked, and pushed directly using `jj`'s Git backend.

### Quick Start with `jj`

```bash
# Clone an existing repository via Gitea's SSH interface
jj git clone ssh://git@lake.dc.paradigm-works.com:20022/<owner>/<repo>.git

# Or connect an existing local Jujutsu workspace to Gitea
jj git remote add origin ssh://git@lake.dc.paradigm-works.com:20022/<owner>/<repo>.git

# Track and advance local changes
jj status
jj diff
jj describe -m "feat: descriptive commit message"

# Advance the bookmark pointer to your completed revision (@-)
jj new
jj bookmark set main -r @-

# Push bookmark upstream to Gitea
jj git push --remote origin --bookmark main
```

For comprehensive details on daily branching, diverged bookmarks, merging upstream changes, and troubleshooting, see the full guide:
- [`guides/jj_workflow_guide.md`](guides/jj_workflow_guide.md)

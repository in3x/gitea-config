# Gitea Configuration & Server Management

This repository contains configuration templates, site profiles, systemd service definitions, and operational automation scripts for deploying, maintaining, backing up, and upgrading a production [Gitea](https://about.gitea.com/) instance according to standardized package scaffolding and site-profile conventions.

---

## Repository Structure

```text
gitea-config/
├── README.md
├── admin/                         # Management & administrative scripts (run interactively via sudo)
│   ├── gitea-deploy.sh            # Stage 2 deployment: syncs site-conf profile to system targets
│   ├── gitea-upgrade.sh           # Binary upgrade script with pre-upgrade backup
│   └── site-profile.sh            # Stage 1 lifecycle: initializes/merges conf/ into site-conf/
├── scripts/                       # Operational scripts (run unattended via cron/systemd)
│   └── gitea-backup.sh            # Automated backup script bundling gitea dump & /etc/gitea
├── conf/                          # Upstream canonical configuration templates
│   └── app.ini                    # Canonical template with placeholders and defaults
├── site-conf/                     # Concrete site profiles (gitignored)
│   ├── .gitignore                 # Prevents site configs/secrets from leaking to version control
│   └── lake/                      # Production profile for lake.dc.paradigm-works.com
│       └── app.ini
├── units/                         # Systemd unit files
│   └── gitea.service              # Systemd service unit for Gitea daemon
└── docs/                          # Architecture notes and operational guides
    └── jj_workflow_guide.md       # Jujutsu (jj) version control workflow guide
```

---

## Two-Stage Configuration Lifecycle

Configuration in this repository follows a strict two-stage lifecycle:

```text
Upstream Template (conf/app.ini)
        │
        ▼  Stage 1: admin/site-profile.sh [SITE]
Site Profile (site-conf/<site>/app.ini)
        │
        ▼  Stage 2: admin/gitea-deploy.sh [SITE]
System Target (/etc/gitea/app.ini)
```

1. **Stage 1 (`admin/site-profile.sh`)**:
   - Initializes a new site profile in `site-conf/<site>/app.ini` from `conf/app.ini`, substituting site domain and generating cryptographic tokens (`LFS_JWT_SECRET`, `INTERNAL_TOKEN`, `JWT_SECRET`).
   - On subsequent runs, performs a non-destructive merge of missing sections/keys from `conf/app.ini` without modifying customized site values.
2. **Stage 2 (`admin/gitea-deploy.sh`)**:
   - Takes a site name (CLI `$1` or interactive menu) and audits target paths against `site-conf/<site>/app.ini` and `units/gitea.service`.
   - Displays unified diffs and prompts before applying updates to `/etc/gitea/app.ini`, `/etc/systemd/system/gitea.service`, or `/opt/gitea/bin/gitea`.

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

### Target Permissions Enforced
| Target Path | Owner : Group | Permissions |
| :--- | :--- | :--- |
| `/etc/gitea` | `root:git` | `770` (`rwxrwx---`) |
| `/var/lib/gitea` | `git:git` | `750` (`rwxr-x---`) |
| `/etc/gitea/app.ini` | `git:git` | `640` (`rw-r-----`) |
| `/etc/systemd/system/gitea.service` | `root:root` | `644` (`rw-r--r--`) |
| `/opt/gitea/bin/gitea` | `root:root` | `755` (`rwxr-xr-x`) |

---

## Operations & Scripts

### 1. Site Profile Management (`admin/site-profile.sh`)

Initializes new site profiles or merges upstream template changes into existing profiles:

```bash
# Manage with interactive menu:
./admin/site-profile.sh

# Target specific profile:
./admin/site-profile.sh lake
```

### 2. Deployment and Configuration Sync (`admin/gitea-deploy.sh`)

Audits and deploys site configurations, service units, and binaries to system targets:

```bash
# Run interactively (prompts menu for site selection, checks target state):
./admin/gitea-deploy.sh

# Specify site profile directly (ideal for automation/scripts):
./admin/gitea-deploy.sh lake

# Run with verbose diff output:
./admin/gitea-deploy.sh lake -v
```

### 3. Automated Backups (`scripts/gitea-backup.sh`)

Creates a complete, timestamped archive containing:
1. Gitea native dump (`gitea dump` executed as the `git` user, backing up SQLite DB and repositories).
2. Configuration directory (`/etc/gitea`, preserving `app.ini` and SSL certificates).

Archives are saved to `/var/backups/gitea/gitea-backup-YYYYMMDD_HHMMSS.tar.gz` with `600` permissions. Backups older than 14 days are automatically pruned.

```bash
# Install to /usr/local/bin/gitea-backup.sh and run via cron:
sudo cp scripts/gitea-backup.sh /usr/local/bin/gitea-backup.sh
sudo chmod 700 /usr/local/bin/gitea-backup.sh
```

### 4. Upgrading Gitea Binary (`admin/gitea-upgrade.sh`)

Automates production binary upgrades with zero data-loss risk:
1. Pre-flight backup via `gitea-backup.sh`.
2. Fetches and validates the latest stable `linux-amd64` release binary from GitHub.
3. Gracefully stops `gitea.service`, atomically replaces `/opt/gitea/bin/gitea`, and restarts the service.

```bash
sudo ./admin/gitea-upgrade.sh
```

### 5. Installing & Upgrading Jujutsu (`admin/jj-install.sh`)

Installs or updates Jujutsu (`jj`) to the latest GitHub release. Supports transparent `~/.bashrc.d` drop-in configuration for user installs:

```bash
# Update jj to the latest release
./admin/jj-update.sh

# Install specific version
./admin/jj-install.sh --version v0.47.1 --force
```

---

## Client Workflow with Jujutsu (`jj`)

Jujutsu (`jj`) is the standard version control tool used with this Gitea server. See [`docs/jj_workflow_guide.md`](docs/jj_workflow_guide.md) for full branch, bookmark, and merge workflows.

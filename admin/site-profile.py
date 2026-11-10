#!/usr/bin/env python3
"""
Gitea Site Profile Management Tool (Stage 1 Lifecycle)
Python implementation provided alongside admin/site-profile.sh for A/B testing.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Resolve repository paths
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
TEMPLATE = REPO_ROOT / "conf" / "app.ini"
SITE_CONF = REPO_ROOT / "site-conf"

# Prefer shared dev-bootstrap library if available
DEV_BOOTSTRAP_LIB = Path.home() / ".local" / "lib" / "dev-bootstrap"
if (DEV_BOOTSTRAP_LIB / "site-profile.py").is_file():
    sys.path.insert(0, str(DEV_BOOTSTRAP_LIB))
    from site_profile import main as engine_main
else:
    # Fallback to local import if zed-standards is checked out alongside
    zed_lib = REPO_ROOT.parent / "zed-standards" / "lib"
    if (zed_lib / "site-profile.py").is_file():
        sys.path.insert(0, str(zed_lib))
        from site_profile import main as engine_main
    else:
        print("[-] Error: dev-bootstrap platform library not found.", file=sys.stderr)
        print("    Run: bash ~/Projects/zed-standards/admin/host-bootstrap.sh --lib-only", file=sys.stderr)
        sys.exit(1)


def main() -> int:
    args = ["-t", str(TEMPLATE), "-s", str(SITE_CONF)] + sys.argv[1:]
    return engine_main(args)


if __name__ == "__main__":
    sys.exit(main())

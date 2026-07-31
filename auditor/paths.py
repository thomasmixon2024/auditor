"""
Central location config for the auditor tool.

Previously every module hardcoded "/home/thomas/auditor-workspace/...",
which meant the tool only ran on one specific machine (and silently
crashed in CI, where that path doesn't exist / isn't writable).

Everything now resolves relative to the repo itself by default, and can
be overridden with environment variables for CI or multi-machine setups:

    AUDITOR_HOME          - repo root (default: parent of this file's dir)
    AUDITOR_LOGS_DIR       - where reports/logs get written
    AUDITOR_TARGET_DIR     - default project(s) to scan
"""
import os
from pathlib import Path

REPO_ROOT = Path(os.environ.get("AUDITOR_HOME", Path(__file__).resolve().parent.parent))
LOGS_DIR = Path(os.environ.get("AUDITOR_LOGS_DIR", REPO_ROOT / "logs"))
TARGET_PROJECT_DIR = Path(os.environ.get("AUDITOR_TARGET_DIR", REPO_ROOT / "target_project"))
AUDIT_LOG_FILE = LOGS_DIR / "auditor.log"
LATEST_SARIF = LOGS_DIR / "latest.sarif"

# Make sure the logs dir exists wherever we land (repo checkout, CI runner, etc.)
LOGS_DIR.mkdir(parents=True, exist_ok=True)

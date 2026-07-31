import subprocess
import datetime
import json
import os

from auditor.paths import AUDIT_LOG_FILE, REPO_ROOT

SEVERITY_ORDER = ["low", "medium", "high"]


def log(msg):
    ts = datetime.datetime.now().isoformat()
    with open(AUDIT_LOG_FILE, "a") as f:
        f.write(f"[{ts}] {msg}\n")


def _run(cmd, **kwargs):
    """subprocess.run wrapper that never raises on a missing binary -
    the old code let FileNotFoundError kill the whole audit if e.g.
    semgrep wasn't installed on a given machine."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    except FileNotFoundError:
        msg = f"[auditor] '{cmd[0]}' is not installed or not on PATH - skipping."
        log(msg)
        return subprocess.CompletedProcess(cmd, returncode=127, stdout="", stderr=msg)


def detect_project_type(path):
    """Look at what's actually in the project instead of assuming Python.
    This is the fix for the tool reporting 'Total lines of code: 0' against
    Link2MP4 - it was only ever running Python linters on a PowerShell repo."""
    types = set()
    for root, _dirs, files in os.walk(path):
        for fname in files:
            lower = fname.lower()
            if lower.endswith(".py"):
                types.add("python")
            elif lower.endswith((".ps1", ".psm1", ".psd1")):
                types.add("powershell")
    return types


# ---------------------------------------------------------------- Python ---

def run_ruff(path):
    log(f"Running ruff on {path}")
    result = _run(["ruff", "check", path])
    log("Ruff completed")
    return result.stdout or result.stderr


def run_ruff_fix(path):
    log(f"Running ruff --fix on {path}")
    result = _run(["ruff", "check", path, "--fix"])
    log("Ruff --fix completed")
    return result.stdout or result.stderr


def run_bandit(path, severity):
    """Runs bandit's text report for the human-readable output, and
    separately counts findings via -f json so severity filtering/CI
    decisions don't depend on grepping formatted text."""
    log(f"Running bandit on {path} with severity={severity}")
    text_result = _run(["bandit", "-r", path])
    output = text_result.stdout or text_result.stderr

    counts = count_bandit_findings(path)
    if severity != "all":
        output += f"\n[auditor] severity filter '{severity}' -> {counts.get(severity, 0)} matching finding(s)"

    log("Bandit completed")
    return output


def count_bandit_findings(path):
    """Returns {'low': n, 'medium': n, 'high': n} using bandit's own JSON
    output, which is far more reliable than substring-matching its text
    report (the previous approach broke silently on any format change)."""
    result = _run(["bandit", "-r", path, "-f", "json"])
    counts = {"low": 0, "medium": 0, "high": 0}
    try:
        data = json.loads(result.stdout) if result.stdout else {}
    except json.JSONDecodeError:
        return counts
    for finding in data.get("results", []):
        sev = finding.get("issue_severity", "").lower()
        if sev in counts:
            counts[sev] += 1
    return counts


def run_semgrep(path, severity):
    log(f"Running semgrep on {path} with severity={severity}")
    result = _run(["semgrep", "--config=auto", path])
    output = result.stdout or result.stderr

    counts = count_semgrep_findings(path)
    if severity != "all":
        output += f"\n[auditor] severity filter '{severity}' -> {counts.get(severity, 0)} matching finding(s)"

    log("Semgrep completed")
    return output


def count_semgrep_findings(path):
    """Same idea as count_bandit_findings: parse --json instead of text."""
    result = _run(["semgrep", "--config=auto", "--json", path])
    counts = {"low": 0, "medium": 0, "high": 0}
    severity_map = {"INFO": "low", "WARNING": "medium", "ERROR": "high"}
    try:
        data = json.loads(result.stdout) if result.stdout else {}
    except json.JSONDecodeError:
        return counts
    for finding in data.get("results", []):
        raw_sev = finding.get("extra", {}).get("severity", "").upper()
        sev = severity_map.get(raw_sev)
        if sev:
            counts[sev] += 1
    return counts


def run_semgrep_fix(path):
    log(f"Running semgrep --autofix on {path}")
    result = _run(["semgrep", "--config=auto", "--autofix", path])
    log("Semgrep --autofix completed")
    return result.stdout or result.stderr


# ------------------------------------------------------------- PowerShell --

def run_psscriptanalyzer(path):
    """PowerShell equivalent of run_ruff/run_bandit. Requires PSScriptAnalyzer
    (Install-Module PSScriptAnalyzer) and pwsh on PATH. Degrades gracefully
    with a clear message rather than pretending the scan happened, if either
    is missing - which is what the tool used to do (silently)."""
    log(f"Running PSScriptAnalyzer on {path}")
    cmd = [
        "pwsh", "-NoProfile", "-Command",
        f"Invoke-ScriptAnalyzer -Path '{path}' -Recurse | ConvertTo-Json -Depth 5"
    ]
    result = _run(cmd)
    if result.returncode == 127:
        return ("[auditor] pwsh/PSScriptAnalyzer not available on this machine - "
                "PowerShell files were NOT scanned. Install PowerShell 7+ and run "
                "'Install-Module PSScriptAnalyzer' to enable this check.")
    log("PSScriptAnalyzer completed")
    return result.stdout or result.stderr or "No issues identified."


def count_psscriptanalyzer_findings(path):
    cmd = [
        "pwsh", "-NoProfile", "-Command",
        f"Invoke-ScriptAnalyzer -Path '{path}' -Recurse | ConvertTo-Json -Depth 5"
    ]
    result = _run(cmd)
    counts = {"low": 0, "medium": 0, "high": 0}
    severity_map = {"Information": "low", "Warning": "medium", "Error": "high"}
    if not result.stdout:
        return counts
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return counts
    if isinstance(data, dict):
        data = [data]
    for finding in data or []:
        sev = severity_map.get(finding.get("Severity"))
        if sev:
            counts[sev] += 1
    return counts


def run_custom_fixers(path):
    """Wires up ps_fixer.ps1 against PowerShell projects instead of the old
    hardcoded 'placeholder' stub. No-op (clearly labeled as such) for
    projects with no PowerShell files, or if pwsh isn't installed."""
    if "powershell" not in detect_project_type(path):
        return "No PowerShell files in this project - custom fixers skipped."

    log(f"Running ps_fixer.ps1 custom fixers on {path}")
    fixer_script = REPO_ROOT / "auditor" / "ps_fixer.ps1"
    cmd = [
        "pwsh", "-NoProfile", "-Command",
        f". '{fixer_script}'; Fix-PowerShellModule -Folder '{path}'"
    ]
    result = _run(cmd)
    if result.returncode == 127:
        return "[auditor] pwsh not available - PowerShell custom fixers were NOT applied."
    log("Custom fixers completed")
    return result.stdout or result.stderr or "Custom fixers applied."


def discover_projects(base_path):
    log(f"Discovering projects in {base_path}")
    projects = []
    if not os.path.isdir(base_path):
        log(f"Base path does not exist: {base_path}")
        return projects
    for entry in os.listdir(base_path):
        full = os.path.join(base_path, entry)
        if os.path.isdir(full):
            projects.append(full)
    log(f"Found projects: {projects}")
    return projects

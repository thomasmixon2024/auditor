"""
Recomputes finding totals (low/medium/high) for a target path, using the
exact same scanner functions run_all.py uses. Called twice by
run_full_audit.ps1 - once against the original target, once against the
fixed copy - so the two numbers are guaranteed to be comparable.

Usage:
    python scripts/verify_findings.py --path <dir>

Prints a single line of JSON: {"low": N, "medium": N, "high": N}
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from auditor.scanner import (
    detect_project_type,
    discover_projects,
    count_bandit_findings,
    count_semgrep_findings,
    count_psscriptanalyzer_findings,
)


def totals_for_path(path):
    totals = {"low": 0, "medium": 0, "high": 0}

    # Mirror run_all.py's own discovery: it treats each subdirectory of
    # `path` as a project. If there are no subdirectories, fall back to
    # treating `path` itself as the project so pointing --path directly
    # at a single project (e.g. target_project\Link2MP4) still works.
    projects = discover_projects(path)
    if not projects:
        projects = [path]

    for project in projects:
        types = detect_project_type(project)

        if "python" in types or not types:
            for sev, n in count_bandit_findings(project).items():
                totals[sev] += n
            for sev, n in count_semgrep_findings(project).items():
                totals[sev] += n

        if "powershell" in types:
            for sev, n in count_psscriptanalyzer_findings(project).items():
                totals[sev] += n

    return totals


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", required=True)
    args = parser.parse_args()
    print(json.dumps(totals_for_path(args.path)))


if __name__ == "__main__":
    main()

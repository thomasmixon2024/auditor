import argparse
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from auditor.scanner import (
    run_ruff,
    run_bandit,
    run_semgrep,
    run_ruff_fix,
    run_semgrep_fix,
    run_psscriptanalyzer,
    run_custom_fixers,
    discover_projects,
    detect_project_type,
    count_bandit_findings,
    count_semgrep_findings,
    count_psscriptanalyzer_findings,
    SEVERITY_ORDER,
    log,
)
from auditor.report import generate_report
from auditor.report_html import generate_html_report
from auditor.report_json import generate_json_report
from auditor.report_sarif import generate_sarif_report
from auditor.dashboard_html import generate_dashboard
from auditor.paths import LOGS_DIR, TARGET_PROJECT_DIR


def severity_at_or_above(counts, threshold):
    """counts is {'low': n, 'medium': n, 'high': n}. Returns the total
    number of findings at or above the given threshold ('all' == 'low')."""
    threshold = "low" if threshold == "all" else threshold
    if threshold not in SEVERITY_ORDER:
        threshold = "low"
    start = SEVERITY_ORDER.index(threshold)
    return sum(counts.get(sev, 0) for sev in SEVERITY_ORDER[start:])


def audit(base_path, severity="all", ci_mode=False, fix_mode=False):
    ts = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    bundle_path = LOGS_DIR / f"audit_{ts}"
    os.makedirs(bundle_path, exist_ok=True)

    log(f"Audit started: bundle={bundle_path}, base_path={base_path}, "
        f"severity={severity}, ci_mode={ci_mode}, fix_mode={fix_mode}")

    projects = discover_projects(base_path)
    results = {}
    fix_report_lines = []
    total_breaching_findings = 0

    for project in projects:
        log(f"Scanning project: {project}")
        project_types = detect_project_type(project)
        project_results = {}
        project_counts = {"low": 0, "medium": 0, "high": 0}

        # Only run tools relevant to what's actually in the project -
        # previously this ran Python-only tools (ruff/bandit) against
        # every project regardless of language, so PowerShell projects
        # like Link2MP4 always came back with "0 lines of code".
        if "python" in project_types or not project_types:
            project_results["ruff"] = run_ruff(project)
            project_results["bandit"] = run_bandit(project, severity)
            project_results["semgrep"] = run_semgrep(project, severity)
            for sev, n in count_bandit_findings(project).items():
                project_counts[sev] += n
            for sev, n in count_semgrep_findings(project).items():
                project_counts[sev] += n

        if "powershell" in project_types:
            project_results["psscriptanalyzer"] = run_psscriptanalyzer(project)
            for sev, n in count_psscriptanalyzer_findings(project).items():
                project_counts[sev] += n

        results[project] = project_results
        total_breaching_findings += severity_at_or_above(project_counts, severity)

        if fix_mode:
            log(f"Auto-fix mode enabled for {project}")
            fix_report_lines.append(f"PROJECT: {project}")
            if "python" in project_types or not project_types:
                fix_report_lines.append("Ruff --fix output:")
                fix_report_lines.append(run_ruff_fix(project))
                fix_report_lines.append("Semgrep --autofix output:")
                fix_report_lines.append(run_semgrep_fix(project))
            fix_report_lines.append("Custom fixers output:")
            fix_report_lines.append(run_custom_fixers(project))
            fix_report_lines.append("")

    if fix_mode:
        fix_path = os.path.join(bundle_path, "fix_report.txt")
        with open(fix_path, "w") as f:
            f.write("=== AUTO-FIX REPORT ===\n\n")
            f.write("\n".join(fix_report_lines))
        print(f"Auto-fix report saved to: {fix_path}")

    generate_json_report(results, bundle_path)
    generate_sarif_report(results, bundle_path)

    if not ci_mode:
        generate_report(results, bundle_path)
        generate_html_report(results, bundle_path)
        generate_dashboard(results, bundle_path)

    if ci_mode:
        if total_breaching_findings > 0:
            print(f"AUDIT FAILED: {total_breaching_findings} finding(s) at or above "
                  f"severity '{severity}'. See {bundle_path} for details.")
            sys.exit(1)
        print(f"Audit passed: no findings at or above severity '{severity}'.")
        sys.exit(0)


def parse_args():
    parser = argparse.ArgumentParser(description="Run ruff/bandit/semgrep/PSScriptAnalyzer over target project(s).")
    parser.add_argument("--path", default=str(TARGET_PROJECT_DIR),
                         help="Directory containing project(s) to scan (default: %(default)s)")
    parser.add_argument("--severity", default="all", choices=["all", "low", "medium", "high"],
                         help="Minimum severity to report/fail on in --ci mode.")
    parser.add_argument("--ci", action="store_true", help="CI mode: JSON+SARIF only, exit non-zero on findings.")
    parser.add_argument("--fix", action="store_true", help="Run auto-fixers (ruff --fix, semgrep --autofix, ps_fixer.ps1).")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    audit(args.path, args.severity, args.ci, args.fix)

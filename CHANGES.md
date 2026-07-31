# Fixes applied (audit follow-up)

## 1. CI gate always passed, regardless of findings
`scripts/run_all.py` called `sys.exit(0)` unconditionally in `--ci` mode.
Now `count_bandit_findings()` / `count_semgrep_findings()` /
`count_psscriptanalyzer_findings()` parse each tool's JSON output, and
`audit()` exits `1` if anything at or above `--severity` was found, `0`
otherwise. Tested against a deliberately vulnerable file (hardcoded
password + `shell=True` + unsanitized input) — confirmed exit code 1 at
`--severity high` and `--severity all`; confirmed exit code 0 against
clean code.

## 2. Hardcoded `/home/thomas/auditor-workspace/...` paths everywhere
New `auditor/paths.py` resolves everything relative to the repo itself
(overridable via `AUDITOR_HOME` / `AUDITOR_LOGS_DIR` / `AUDITOR_TARGET_DIR`
env vars). This is also what makes the GitHub Actions workflow actually
runnable — it previously tried to write to a path that doesn't exist on
a hosted runner.

## 3. Stored XSS in report.html / dashboard.html
Tool output and project paths were dropped into HTML with no escaping.
Fixed with `html.escape()` everywhere content is interpolated, plus
`json.dumps(...).replace("</", "<\\/")` for the Chart.js data (json.dumps
alone escapes for JS syntax but not for the surrounding `<script>` tag —
verified this specific `</script>` breakout with a live payload before
and after the fix).

## 4. Hardcoded API secret in `api.py`
Token now comes from `AUDITOR_API_TOKEN` (required env var, process exits
with a clear message if unset — no more silent `"super-secret-token"`
default). Comparison uses `hmac.compare_digest` instead of `!=` to avoid
a timing side-channel. Token now travels via `X-Auditor-Token` header
instead of a URL query parameter (query params get logged everywhere).

## 5. `server.py` ran Flask with `debug=True` on `0.0.0.0`
Default is now `127.0.0.1` with debug off. Both are overridable via
`AUDITOR_SERVER_HOST` / `AUDITOR_SERVER_DEBUG` for anyone who deliberately
wants LAN access — but it's opt-in now, not the default. Added the same
token-header auth as `api.py`. Also fixed an unhandled `IndexError` when
`logs/` has no audit bundles yet (`/latest/*` routes now return a 404
JSON error instead of crashing).

## 6. Tool never actually scanned its own target project
`ruff`/`bandit` are Python-only; `target_project/Link2MP4` is 100%
PowerShell, so every real run in the original `logs/` produced "0 lines
of code". Added `detect_project_type()` (extension-based), and
`run_psscriptanalyzer()` / `count_psscriptanalyzer_findings()` as the
PowerShell-side equivalent of the bandit functions. `run_all.py` now
picks the right tool(s) per project instead of always running the Python
linters. `run_custom_fixers()` also now actually invokes `ps_fixer.ps1`
against PowerShell projects (`Fix-PowerShellModule`) instead of returning
a hardcoded placeholder string.

Note: this sandbox doesn't have `pwsh`, so PowerShell scanning degrades
to a clear "not available" message here rather than a silent 0-findings
result — on your actual machine (which has PowerShell, since it's
running Link2MP4) this should do a real scan. Worth a first real run to
confirm PSScriptAnalyzer output parses the way I expect.

---

## Not yet addressed (flagged as moderate in the original audit, still open)

- SARIF output still dumps each tool's raw stdout as one big `message.text`
  per run instead of individual findings with `physicalLocation`/line
  numbers — GitHub Code Scanning will ingest it but can't show inline
  annotations.
- No `requirements.txt` / `pyproject.toml` — dependencies
  (fastapi, pydantic, flask, ruff, bandit, semgrep) still aren't pinned
  anywhere.
- `configs/` directory is still empty/unused.
- `--fix` mode still applies `ruff --fix` / `semgrep --autofix` directly
  with no dry-run or diff preview before writing.

Happy to take these on next if useful.

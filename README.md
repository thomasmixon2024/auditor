# Auditor Tool

This repository contains a lightweight audit tool for scanning one or more target projects using security and style tools.

## What it does

- Discovers target projects under `target_project/` by directory
- Runs language-appropriate scanners
  - Python: `ruff`, `bandit`, `semgrep`
  - PowerShell: `PSScriptAnalyzer`
- Generates reports in:
  - plain text
  - HTML
  - JSON
  - SARIF
- Includes a sample target project at `target_project/Link2MP4`
- Provides a REST API wrapper (`api.py`) and a report server (`server.py`)

## Quick start

If you want the simplest field workflow, use the helper script from the repository root:

```powershell
.\run_audit.ps1
```

This will create a local `.venv`, install the required dependencies, and run the audit on `target_project/`.

To start the built-in report server after an audit has run:

```powershell
.\run_server.ps1
```

Then open the latest dashboard at `http://127.0.0.1:5000/latest/dashboard`.

## Requirements

This tool requires Python 3.11+ and the dependencies listed in `requirements.txt`.

It also optionally uses the following external tools if you want full scanning coverage:

- `ruff`
- `bandit`
- `semgrep`
- `pwsh` (PowerShell Core) with the `PSScriptAnalyzer` module installed

> PowerShell scanning and custom fixes will only work when `pwsh` and `PSScriptAnalyzer` are available.

## Setup

1. Install Python 3.11+.
2. Open a terminal in this repository root.
3. The helper script `run_audit.ps1` can create a local virtual environment and install dependencies automatically when you run it.

If you prefer manual setup, you can also do this:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

4. If you plan to scan PowerShell code, install PowerShell and the analyzer:

```powershell
pwsh -NoProfile -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
```

## Using the audit CLI

Run the main audit command:

```powershell
python scripts/run_all.py
```

By default, it scans `target_project/` and writes results into `logs/`.

### Common options

- `--path PATH` — scan a different directory instead of `target_project/`
- `--severity {all,low,medium,high}` — minimum severity to fail on in CI mode
- `--ci` — CI mode: generate JSON and SARIF only and exit with `1` if findings are present
- `--fix` — run auto-fixers (`ruff --fix`, `semgrep --autofix`, and `ps_fixer.ps1`)

Example:

```powershell
python scripts/run_all.py --path target_project --ci --severity high
```

## Running the audit API

The `api.py` script exposes a simple HTTP endpoint to trigger audits.

1. Set a token first:

```powershell
$env:AUDITOR_API_TOKEN = [System.Guid]::NewGuid().ToString()
```

2. Start the API with Uvicorn:

```powershell
python -m uvicorn api:app --host 127.0.0.1 --port 8000
```

3. Call the API with the token:

```powershell
curl -X POST http://127.0.0.1:8000/audit \
  -H "X-Auditor-Token: $env:AUDITOR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"severity":"all","ci":true}'
```

## Running the report server

`server.py` serves the latest generated audit bundle from `logs/`.

1. Set the API token:

```powershell
$env:AUDITOR_API_TOKEN = [System.Guid]::NewGuid().ToString()
```

2. Start the server:

```powershell
python server.py
```

3. Open the dashboard in your browser:

- `http://127.0.0.1:5000/latest/dashboard`
- `http://127.0.0.1:5000/latest/json`
- `http://127.0.0.1:5000/latest/sarif`

## Environment variables

| Variable | Purpose |
|---|---|
| `AUDITOR_HOME` | Override repository root path |
| `AUDITOR_LOGS_DIR` | Override the report/log output directory |
| `AUDITOR_TARGET_DIR` | Override the default target project directory |
| `AUDITOR_API_TOKEN` | Required auth token for `api.py` and `server.py` |
| `AUDITOR_SERVER_HOST` | Host for `server.py` (default `127.0.0.1`) |
| `AUDITOR_SERVER_DEBUG` | Set to `true` to enable Flask debug mode in `server.py` |

## .txt file support

`run_preview.ps1`, `run_interactive.ps1`, and `scripts/preview_fix.py` now support text files (`.txt` and `.md`) by analyzing the file contents and guessing whether the source is PowerShell or Python.

If a format is detected, the tool will preview and optionally apply fixes as if the file were named `.ps1` or `.py`.

If the format cannot be inferred, interactive mode will help you choose the correct script type.

## Interactive preview mode

Use `run_interactive.ps1` to start the auditor in a guided interactive session. It prompts for the file path, shows a preview diff, and asks whether you want to apply the fix.

```powershell
.\run_interactive.ps1
```

You can also pass a file path directly:

```powershell
.\run_interactive.ps1 -File "C:\path\to\script.txt"
```

## Help document

New users can open `HELP.md` for a friendly command reference and examples of how each helper script works.

## Notes for first-time users

- `target_project/Link2MP4` is an example PowerShell project included for testing.
- If a scanner binary is missing, the tool logs a message and skips that scanner instead of crashing.
- The `--fix` mode may alter project files. Use it carefully and review changes.
- `report.sarif` is generated for compatibility, but the SARIF output is currently basic and may not include line-level findings.

## Recommended next steps

- Install the required Python dependencies.
- Run `python scripts/run_all.py --path target_project --ci --severity high` to verify the audit flow.
- Check `logs/` for generated bundles and report files.
- If needed, add `requirements.txt` pinned versions or convert the project to `pyproject.toml` later.

# Auditor Project Help

This file is a friendly reference for new users. It explains the key commands, what each helper script does, and how to work with `.txt` files.

## What this project does

The auditor project is built to inspect small source files and project directories for style and PowerShell/Python issues. It includes:

- `run_audit.ps1` - run the full project audit using a local Python virtual environment
- `run_preview.ps1` - preview fixes for a single file and optionally apply them
- `scripts/preview_fix.py` - the script behind the single-file preview workflow
- `run_server.ps1` and `server.py` - launch the report server to view audit results

## Key commands

### 1. Run the full audit

Use this command from the repository root:

```powershell
.un_audit.ps1
```

What it does:

- Creates `.venv` if it does not already exist
- Installs dependencies from `requirements.txt`
- Runs the audit on `target_project/`
- Writes scan output into `logs/`

### 2. Preview a single file

Use this command for one file at a time:

```powershell
.un_preview.ps1 -File "C:\path\to\file.ps1"
```

What it does:

- Runs `scripts/preview_fix.py` against the target file
- Copies the file to a temporary working location
- Runs syntax checks and auto-fixers where available
- Prints a unified diff of proposed changes
- Lets you decide whether to apply safe whitespace-only fixes

### 3. Interactive file preview

If you want a guided, step-by-step audit session, use the interactive launcher:

```powershell
.\run_interactive.ps1
```

This will prompt you for:

- The file to audit
- Whether to treat a `.txt` file as PowerShell or Python if the format is unclear
- Whether to apply whitespace-only or full fixes after previewing the diff

You can also pass a file directly:

```powershell
.\run_interactive.ps1 -File "C:\path\to\script.txt"
```

### 4. Preview a `.txt` file

This project now supports `.txt` files by inferring the likely source format from the file contents.

For example:

```powershell
.un_preview.ps1 -File "C:\Users\Thomas\Desktop\Performance Report Command.txt"
```

If the file contains PowerShell code, it will be treated like a `.ps1` file. If it contains Python code, it will be treated like a `.py` file.

If the tool cannot guess the format, it will ask you to rename the file to the correct extension and try again.

### 4. Apply whitespace-only fixes automatically

Use this command to run preview and apply only whitespace-related changes:

```powershell
.un_preview.ps1 -File "C:\path\to\file.ps1" -ApplyIfWhitespaceOnly
```

### 5. Apply fixes including non-whitespace changes

Use this command when you are sure you want to apply the proposed fixes and create a backup first:

```powershell
.un_preview.ps1 -File "C:\path\to\file.ps1" -Apply -Force
```

This is more aggressive because it can apply semantic or formatting fix changes. The tool creates a `.bak` backup before writing changes.

### 6. View help on the Python preview script

You can run the Python script directly if you want to see its usage and flags:

```powershell
python .\scripts\preview_fix.py --help
```

The available options are:

- `--apply-if-whitespace-only` - apply changes only when they are whitespace-only
- `--apply` - apply all changes non-interactively
- `--force` - allow non-whitespace changes when used with `--apply`
- `-y` / `--yes` - assume yes to interactive prompts

## What each helper script does

### `run_audit.ps1`

- Ensures Python is installed
- Creates `.venv` if missing
- Installs Python dependencies
- Runs the full audit flow via `scripts/run_all.py`

### `run_preview.ps1`

- Ensures Python is installed
- Creates `.venv` if missing
- Installs Python dependencies
- Runs `scripts/preview_fix.py` on one file
- Passes any additional switches to `preview_fix.py`

### `scripts/preview_fix.py`

- Copies the target file to a temporary directory
- Infers format for `.txt` and `.md` files
- Runs safe whitespace normalization
- Runs `ruff --fix` and `semgrep --autofix` for Python (when available)
- Runs `ps_fixer.ps1` and PowerShell syntax checking for PowerShell files
- Prints a unified diff showing what would change
- Applies changes only when requested by flags or interactive approval

### `run_server.ps1` and `server.py`

- Start a local web server to view audit results
- `server.py` serves the latest report bundle from `logs/`

## Where logs are written

- `logs/preview_fix.log` - log for the single-file preview workflow
- `logs/` - general audit output and report bundles

## Recommended workflow for a new user

1. Open PowerShell as Administrator if you plan to audit or fix system-level scripts.
2. Run `.un_audit.ps1` first to verify the main audit path.
3. Use `.un_preview.ps1 -File <file>` to inspect a single file before applying fixes.
4. If the file is saved as `.txt`, the tool will try to detect whether it is PowerShell or Python.
5. If you want to apply only whitespace cleanup, use `-ApplyIfWhitespaceOnly`.
6. Keep the `.bak` backup files created by `-Apply -Force` until you are satisfied with the result.

## Troubleshooting

- If `pwsh` is missing, PowerShell scanning and fixers will be skipped.
- If `ruff` or `semgrep` are missing, Python fixers will be skipped.
- If a `.txt` file cannot be identified, rename it to `.ps1` or `.py` and run preview again.
- If a command fails, check `logs/preview_fix.log` for details.

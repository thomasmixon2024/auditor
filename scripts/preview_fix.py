#!/usr/bin/env python3
"""
preview_fix.py

Given a single source file, run the applicable auto-fixers in a temporary copy
and print a unified diff showing what would change. This lets you quickly
preview fixes before applying them to the real file.

Supported fixers (if installed):
 - Python: ruff --fix
 - Python: semgrep --autofix (optional)
 - PowerShell: runs auditor/ps_fixer.ps1 against a temp copy (requires pwsh)

Usage:
    python scripts/preview_fix.py path/to/file

Returns:
 - exit code 0 if preview generated (may be empty if no changes)
 - exit code 2 if file not found or unsupported
 - exit code 3 on internal error
"""

import datetime
import difflib
import py_compile
import shutil
import subprocess  # nosec: B404 - subprocess usage is intentional here
import sys
import tempfile
from abc import ABC, abstractmethod
from pathlib import Path


class str(str, ABC):
    """A small string subclass with useful helpers for prompt and path handling."""

    def is_blank(self) -> bool:
        return not self.strip()

    def as_path(self) -> Path:
        return Path(self)

    def normalize_whitespace(self) -> "str":
        text = self.replace("\r\n", "\n").replace("\r", "\n")
        lines = [line.rstrip() for line in text.split("\n")]
        text = "\n".join(lines)
        if not text.endswith("\n") and text:
            text += "\n"
        return str.__new__(self.__class__, text)


REPO_ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = REPO_ROOT / 'logs'
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / 'preview_fix.log'


def append_log(level: str, msg: str):
    ts = datetime.datetime.now(tz=datetime.timezone.utc).isoformat()
    entry = f"[{ts}] [{level}] {msg}\n"
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(entry)


def log(msg):
    print(f"[preview_fix] {msg}")
    append_log('INFO', msg)


def run_cmd(cmd, cwd=None):
    try:
        # subprocess.run is intentionally used here with external commands.
        # The command list should be validated by callers; suppress bandit B603.
        res = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, check=False)  # nosec: B603
        append_log('DEBUG', f"Command: {cmd} exit={res.returncode}")
        if res.stdout:
            append_log('DEBUG', f"stdout: {res.stdout.strip()}")
        if res.stderr:
            append_log('DEBUG', f"stderr: {res.stderr.strip()}")
        return res.returncode, res.stdout, res.stderr
    except FileNotFoundError:
        append_log('WARN', f"Command not found: {cmd[0]}")
        return 127, "", f"Command not found: {cmd[0]}"


def prompt_input(prompt: str, default: str | None = None) -> str:
    if default:
        prompt = f"{prompt} [{default}]: "
    else:
        prompt = f"{prompt}: "
    try:
        response = input(prompt).strip()
    except EOFError:
        return default or ""
    return response if response else (default or "")


def prompt_choice(prompt: str, choices: dict, default=None) -> str:
    options = ", ".join([f"{key}:{value}" for key, value in choices.items()])
    normalized_values = {value.lower(): key for key, value in choices.items()}
    while True:
        response = prompt_input(f"{prompt} ({options})", default)
        if not response:
            return default
        response = response.strip().lower()
        if response in choices:
            return response
        if response in normalized_values:
            return normalized_values[response]
        print(f"Please choose one of: {', '.join(choices.values())}")


def prompt_yes_no(prompt: str, default: str = 'n') -> bool:
    response = prompt_input(prompt, default).strip().lower()
    return response in ('y', 'yes')


def prompt_file_path(default: str = None) -> str:
    while True:
        path = prompt_input('Enter the path to the file to audit', default)
        if not path:
            print('No file path provided. Exiting.')
            return ''
        candidate = Path(path).expanduser().resolve()
        if candidate.exists() and candidate.is_file():
            return str(candidate)
        print(f'File not found: {candidate}')


def normalize_whitespace_inplace(path: Path) -> bool:
    """Apply simple, safe whitespace normalizations in-place and return
    True if the file changed."""
    changed = False
    text = path.read_text(encoding='utf-8', errors='surrogateescape')
    original = text

    # Normalize CRLF -> LF
    text = text.replace('\r\n', '\n')
    # Replace tabs with 4 spaces
    text = text.replace('\t', '    ')
    # Remove trailing whitespace on each line
    lines = [line.rstrip() for line in text.split('\n')]
    # Ensure single trailing newline
    text = '\n'.join(lines)
    if not text.endswith('\n'):
        text += '\n'

    if text != original:
        path.write_text(text, encoding='utf-8', errors='surrogateescape')
        changed = True
    return changed


def infer_format_from_text(text: str):
    """Infer whether a text file contains PowerShell or Python source."""
    normalized = text.lower()
    python_tokens = [
        "import ", "def ", "print(", "if __name__ == '__main__'", "elif ", "except ", "with ", "class ", "self", "async ", "await ", "from ", "raise "
    ]
    powershell_tokens = [
        "write-host", "get-counter", "get-ciminstance", "get-netadapter", "set-strictmode", "ipconfig", "netsh", "function ", "cmdletbinding", "new-object system.windows.forms", "get-service", "get-process"
    ]

    py_score = sum(normalized.count(token) for token in python_tokens)
    ps_score = sum(normalized.count(token) for token in powershell_tokens)

    if normalized.startswith("#!") and "python" in normalized.splitlines()[0]:
        return 'py'
    if normalized.startswith("#!") and "pwsh" in normalized.splitlines()[0]:
        return 'ps1'

    if ps_score > py_score and ps_score > 0:
        return 'ps1'
    if py_score > ps_score and py_score > 0:
        return 'py'
    return None


def preview_python(file_path: Path, tmp_file: Path):
    stdout_acc = []

    # Quick syntax check on the original file
    try:
        py_compile.compile(str(file_path), doraise=True)
    except py_compile.PyCompileError as e:
        log(f"Python syntax error in original file: {e.msg}")
        return False, [(2, '', f"SyntaxError: {e.msg}")]

    # Apply simple whitespace normalization before fixers
    ws_changed = normalize_whitespace_inplace(tmp_file)
    if ws_changed:
        log("Applied whitespace normalization to temporary file.")

    # Try ruff --fix
    rc, out, err = run_cmd(["ruff", "check", str(tmp_file), "--fix"])  # ruff modifies in-place
    stdout_acc.append((rc, out, err))
    if rc == 127:
        log("ruff not found; skipping ruff fixes")

    # Try semgrep --autofix (optional)
    rc2, out2, err2 = run_cmd(["semgrep", "--config=auto", "--autofix", str(tmp_file)])
    stdout_acc.append((rc2, out2, err2))
    if rc2 == 127:
        log("semgrep not found or not applicable; skipping semgrep autofix")

    return True, stdout_acc


def preview_powershell(file_path: Path, tmp_file: Path):
    # Use the included ps_fixer.ps1
    fixer = REPO_ROOT / "auditor" / "ps_fixer.ps1"
    if not fixer.exists():
        log("ps_fixer.ps1 not found in repo; skipping PowerShell fixes")
        return False, (127, "", "ps_fixer not present")

    # Basic syntax check using pwsh parser if available
    # Apply whitespace normalization first
    ws_changed = normalize_whitespace_inplace(tmp_file)
    if ws_changed:
        log("Applied whitespace normalization to temporary PowerShell file.")

    # Prepare a small pwsh command to parse the file
    escaped = str(tmp_file).replace("'", "''")
    parse_cmd = ["pwsh", "-NoProfile", "-Command", f"try {{ [void][System.Management.Automation.Language.Parser]::ParseFile('{escaped}', [ref]$null, [ref]$null); Write-Output 'OK' }} catch {{ Write-Error $_.Exception.Message; exit 2 }}"]
    rcp, outp, errp = run_cmd(parse_cmd)
    if rcp == 127:
        log("pwsh not found; skipping PowerShell syntax check")
    elif rcp != 0:
        log(f"PowerShell syntax error: {errp.strip()}" )
        return False, [(2, '', errp)]

    # Call pwsh to run Fix-PowerShellModule on the directory containing the file
    cmd = ["pwsh", "-NoProfile", "-Command", f". '{fixer}'; Fix-PowerShellModule -Folder '{tmp_file.parent}'"]
    rc, out, err = run_cmd(cmd)
    if rc == 127:
        log("pwsh not found; skipping PowerShell fixes")
    return (rc == 0), (rc, out, err)


def unified_diff_text(original: str, modified: str, fromfile: str, tofile: str) -> str:
    orig_lines = original.splitlines(keepends=True)
    mod_lines = modified.splitlines(keepends=True)
    diff = difflib.unified_diff(orig_lines, mod_lines, fromfile=fromfile, tofile=tofile)
    return ''.join(diff)


def is_whitespace_only_change(orig: str, new: str) -> bool:
    # Remove all whitespace characters and compare
    import re
    o = re.sub(r"\s+", "", orig)
    n = re.sub(r"\s+", "", new)
    return o == n


import argparse


def main(argv=None):
    parser = argparse.ArgumentParser(description='Preview and optionally apply auto-fixes for a single file')
    parser.add_argument('path', nargs='?', help='Path to the file to preview (optional in interactive mode)')
    parser.add_argument('-i', '--interactive', action='store_true', dest='interactive',
                        help='Run in interactive mode and prompt for a file path and actions')
    parser.add_argument('--apply-if-whitespace-only', action='store_true', dest='apply_ws_only',
                        help='If the changes are whitespace-only, apply them non-interactively')
    parser.add_argument('--apply', action='store_true', dest='apply_all',
                        help='Apply changes non-interactively (requires --force to apply non-whitespace changes)')
    parser.add_argument('--force', action='store_true', dest='force',
                        help='When used with --apply, allow applying non-whitespace changes (creates backup)')
    parser.add_argument('-y', '--yes', action='store_true', dest='yes',
                        help='Assume yes to any interactive prompts')

    args = parser.parse_args(argv[1:] if argv else None)

    if args.interactive and not args.path:
        selected_path = prompt_file_path()
        if not selected_path:
            return 
        target = Path(selected_path).resolve()
    elif not args.path:
        parser.error('the following arguments are required: path (unless --interactive is used)')
    else:
        target = Path(args.path).resolve()

    if not target.exists() or not target.is_file():
        msg = f"File not found: {target}"
        print(msg)
        append_log('ERROR', msg)
        return 2

    suffix = target.suffix.lower()
    guessed_format = None
    if suffix in ('.txt', '.md'):
        content = target.read_text(encoding='utf-8', errors='surrogateescape')
        guessed_format = infer_format_from_text(content)
        if guessed_format:
            msg = f"Detected likely format '{guessed_format}' for {target} based on file contents."
            print(msg)
            append_log('INFO', msg)
        elif args.interactive:
            choice = prompt_choice(
                'Could not determine the format automatically; choose the file type',
                {'1': 'PowerShell', '2': 'Python', 'c': 'Cancel'},
                default='c'
            )
            if choice in ('1', 'powershell', 'ps1'):
                guessed_format = 'ps1'
                print('Selected PowerShell format for preview.')
            elif choice in ('2', 'python', 'py'):
                guessed_format = 'py'
                print('Selected Python format for preview.')
            else:
                print('No file format selected. Exiting.')
                return 2
        else:
            msg = f"Could not determine the format of {target}. Rename to .ps1 or .py if this is PowerShell or Python source."
            print(msg)
            append_log('WARN', msg)
            return 2

    with tempfile.TemporaryDirectory() as td:
        tmp_dir = Path(td)
        if guessed_format:
            tmp_file = tmp_dir / f"{target.stem}.{guessed_format}"
        else:
            tmp_file = tmp_dir / target.name
        shutil.copy2(target, tmp_file)

        try:
            append_log('INFO', f"Starting preview for {target}")
            modified_working_file = tmp_file
            if suffix in ('.py',) or guessed_format == 'py':
                ok, logs = preview_python(target, tmp_file)
            elif suffix in ('.ps1', '.psm1') or guessed_format == 'ps1':
                # For PowerShell, copy into a small folder so ps_fixer can recurse
                ps_temp_folder = tmp_dir / 'psproj'
                ps_temp_folder.mkdir()
                ps_filename = tmp_file.name
                tmp_ps_file = ps_temp_folder / ps_filename
                shutil.copy2(tmp_file, tmp_ps_file)
                ok, logs = preview_powershell(target, tmp_ps_file)
                # The modified file for diff is inside the ps_temp_folder
                modified_working_file = tmp_ps_file
            else:
                msg = f"Unsupported file type for preview: {suffix}"
                print(msg)
                append_log('ERROR', msg)
                return 2

            # Read texts
            orig_text = target.read_text(encoding='utf-8', errors='surrogateescape')
            new_text = modified_working_file.read_text(encoding='utf-8', errors='surrogateescape') if modified_working_file.exists() else ''

            diff = unified_diff_text(orig_text, new_text, str(target), str(target) + ' (preview)')

            if not diff:
                print("No changes would be made by the configured fixers.")
                append_log('INFO', f"No changes for {target}")
                return 0

            # Print diff to user
            print(diff)
            append_log('INFO', f"Preview generated for {target}; changes present")

            # Determine if changes are whitespace-only
            whitespace_only = is_whitespace_only_change(orig_text, new_text)
            append_log('DEBUG', f"Whitespace-only change: {whitespace_only}")

            # Decide how to proceed based on flags and change type
            if whitespace_only:
                if args.apply_ws_only or args.apply_all:
                    # Non-interactive apply requested
                    backup = target.with_suffix(target.suffix + f'.bak.{datetime.datetime.now().strftime("%Y%m%d%H%M%S")}')
                    shutil.copy2(target, backup)
                    shutil.copy2(modified_working_file, target)
                    msg = f"Applied whitespace-only fixes to {target}. Backup saved to {backup}"
                    print(msg)
                    append_log('INFO', msg)
                    append_log('INFO', 'Applied diff:\n' + diff.replace('\n', '\n'))
                    return 0
                else:
                    if args.yes:
                        apply_changes = True
                    elif args.interactive:
                        apply_changes = prompt_yes_no('Apply whitespace-only fixes to the original file?', 'n')
                    else:
                        try:
                            answer = input('Apply whitespace-only fixes to the original file? [y/N]: ').strip().lower()
                        except EOFError:
                            answer = 'n'
                        apply_changes = answer in ('y', 'yes')

                    if apply_changes:
                        backup = target.with_suffix(target.suffix + f'.bak.{datetime.datetime.now().strftime("%Y%m%d%H%M%S")}')
                        shutil.copy2(target, backup)
                        shutil.copy2(modified_working_file, target)
                        msg = f"Applied whitespace-only fixes to {target}. Backup saved to {backup}"
                        print(msg)
                        append_log('INFO', msg)
                        append_log('INFO', 'Applied diff:\n' + diff.replace('\n', '\n'))
                        return 0
                    else:
                        print('No changes applied.')
                        append_log('INFO', f"User declined to apply fixes for {target}")
                        return 0
            else:
                # Non-whitespace changes
                if args.apply_all:
                    if not args.force:
                        msg = ('--apply requested but changes are not whitespace-only. '
                               'Refusing to apply without --force.')
                        print(msg)
                        append_log('WARN', msg)
                        return 4
                    apply_now = True
                elif args.yes:
                    apply_now = True
                elif args.interactive:
                    apply_now = prompt_yes_no('Non-whitespace changes detected. Apply fixes and create a backup?', 'n')
                else:
                    apply_now = False

                if apply_now:
                    backup = target.with_suffix(target.suffix + f'.bak.{datetime.datetime.now().strftime("%Y%m%d%H%M%S")}')
                    shutil.copy2(target, backup)
                    shutil.copy2(modified_working_file, target)
                    msg = f"Applied fixes (non-whitespace) to {target}. Backup saved to {backup}"
                    print(msg)
                    append_log('INFO', msg)
                    append_log('INFO', 'Applied diff:\n' + diff.replace('\n', '\n'))
                    return 0
                if args.apply_all:
                    return 0
                msg = 'Non-whitespace changes detected; automatic apply disabled. Review the diff above.'
                print(msg)
                append_log('WARN', f"{msg} for {target}")
                return 0

        except Exception as e:
            err_msg = f"Error during preview: {e}"
            print(err_msg)
            append_log('ERROR', err_msg)
            return 3


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))

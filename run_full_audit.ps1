<#
.SYNOPSIS
One command that audits, fixes, and verifies a target project, with a
backup and a fixed copy kept on disk at every stage.

.DESCRIPTION
Wraps scripts\run_all.py end-to-end so nothing ever runs the auto-fixers
directly against your real project, and nothing gets applied back unless
it's been verified.

Pipeline (each stage stops the whole run on failure - see .\logs\run_<ts>\run.log):

  1) venv + dependencies        (same bootstrap as run_audit.ps1)
  2) BACKUP     -> logs\run_<ts>\backup\   verbatim copy of the target
  3) BASELINE AUDIT -> logs\run_<ts>\before\  scan of the *original*, no fixers
  4) FIXED COPY -> logs\run_<ts>\fixed\    a working copy - fixers never
                                            touch the original directly
  5) FIX PASS   -> ruff --fix / semgrep --autofix / ps_fixer.ps1 run
                    against the working copy only
  6) POST-FIX AUDIT -> logs\run_<ts>\after\   scan of the working copy
  7) VERIFY:
       - every .ps1 / .psm1 / .psd1 in the working copy must still parse
         cleanly (PowerShell's own parser - no pwsh/PSScriptAnalyzer
         dependency for this check)
       - per-file function count must not have dropped
       - per-file line count must not have collapsed (>40% loss = flagged)
       - low/medium/high finding totals must not be worse after the fix
  8) FINALIZE:
       - verification FAILS   -> original is never touched; fixed\ and
                                  backup\ are left on disk for review;
                                  script exits non-zero
       - verification PASSES  -> working copy is applied back over the
                                  real target (unless -DryRun is given)

.PARAMETER Path
Target to audit, relative to the repo root or absolute. Default: target_project

.PARAMETER Severity
all | low | medium | high - passed straight through to run_all.py.

.PARAMETER DryRun
Run the full pipeline (including verification) but never write the fixed
copy back over the original, even if verification passes. Useful for
reviewing what would change first.

.PARAMETER SkipFix
Audit only. Runs the backup + baseline audit and stops there - no fixed
copy, no fix pass, no verification.

.EXAMPLE
.\run_full_audit.ps1
Backs up, audits, fixes, verifies, and (if clean) applies against target_project.

.EXAMPLE
.\run_full_audit.ps1 -DryRun
Same, but leaves target_project untouched no matter what - inspect
logs\run_<ts>\fixed\ yourself before deciding.

.EXAMPLE
.\run_full_audit.ps1 -Path 'target_project\Link2MP4' -Severity high

.EXAMPLE
.\run_full_audit.ps1 -SkipFix
Audit-only run, no fixers touched at all.
#>

[CmdletBinding()]
param(
    [string]$Path = 'target_project',

    [ValidateSet('all', 'low', 'medium', 'high')]
    [string]$Severity = 'all',

    [switch]$DryRun,
    [switch]$SkipFix
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptRoot

$timestamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$runDir      = Join-Path $scriptRoot "logs\run_$timestamp"
$backupDir   = Join-Path $runDir 'backup'
$fixedDir    = Join-Path $runDir 'fixed'
$beforeDir   = Join-Path $runDir 'before'
$afterDir    = Join-Path $runDir 'after'
$fixLogDir   = Join-Path $runDir 'fix'
$summaryFile = Join-Path $runDir 'SUMMARY.txt'
$transcript  = Join-Path $runDir 'run.log'

function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "    OK:   $Msg" -ForegroundColor Green }
function Write-Bad  { param([string]$Msg) Write-Host "    FAIL: $Msg" -ForegroundColor Red }

$summary = New-Object System.Collections.Generic.List[string]
function Add-Summary { param([string]$Msg) $summary.Add($Msg) | Out-Null; Write-Host $Msg }

function Invoke-Robocopy {
    param([string]$Source, [string]$Dest, [string]$FailMessage)
    robocopy $Source $Dest /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "$FailMessage (robocopy exit code $LASTEXITCODE)"
    }
}

$exitCode = 0
$verified = $false

try {
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    Start-Transcript -Path $transcript -Force | Out-Null

    Add-Summary "Auditor full run - $timestamp"
    Add-Summary "Target path: $Path"
    Add-Summary "Severity:    $Severity"
    Add-Summary "DryRun:      $($DryRun.IsPresent)"
    Add-Summary "SkipFix:     $($SkipFix.IsPresent)"
    Add-Summary ""

    # ------------------------------------------------------------ 1. venv --
    Write-Step "Setting up Python environment"
    $venvPath = Join-Path $scriptRoot '.venv'
    $bootstrapPython = $null
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $bootstrapPython = (Get-Command python).Source
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        $bootstrapPython = (Get-Command python3).Source
    }
    if (-not $bootstrapPython) {
        throw "Python 3 is not installed or not on PATH. Install Python 3.11+ and try again."
    }

    if (-not (Test-Path (Join-Path $venvPath 'Scripts\python.exe'))) {
        Write-Host "    Creating virtual environment..."
        & $bootstrapPython -m venv $venvPath
        if ($LASTEXITCODE -ne 0) { throw "Failed to create virtual environment." }
    }
    $python = Join-Path $venvPath 'Scripts\python.exe'
    if (-not (Test-Path $python)) { throw "venv exists but python.exe is missing at $python" }

    & $python -m pip install --upgrade pip *> $null
    & $python -m pip install -r (Join-Path $scriptRoot 'requirements.txt') *> $null
    if ($LASTEXITCODE -ne 0) { throw "pip install -r requirements.txt failed." }
    Write-Ok "venv ready: $python"

    $env:AUDITOR_HOME = $scriptRoot

    # Resolve and sanity-check the target BEFORE touching anything.
    $resolvedTarget = Join-Path $scriptRoot $Path
    if (-not (Test-Path $resolvedTarget)) {
        throw "Target path does not exist: $resolvedTarget"
    }
    $resolvedTarget = (Resolve-Path $resolvedTarget).Path
    Add-Summary "Resolved target: $resolvedTarget"

    # --------------------------------------------------------- 2. backup --
    Write-Step "Backing up target"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Invoke-Robocopy -Source $resolvedTarget -Dest $backupDir -FailMessage "Backup failed"

    $origCount   = (Get-ChildItem $resolvedTarget -Recurse -File).Count
    $backupCount = (Get-ChildItem $backupDir -Recurse -File).Count
    if ($backupCount -ne $origCount) {
        throw "Backup file count mismatch: original=$origCount backup=$backupCount - refusing to continue."
    }
    Write-Ok "Backed up $backupCount file(s) to $backupDir"

    # --------------------------------------------------- 3. baseline audit --
    Write-Step "Running baseline audit (no fixers) against the original"
    New-Item -ItemType Directory -Path $beforeDir -Force | Out-Null
    $env:AUDITOR_LOGS_DIR = $beforeDir
    & $python (Join-Path $scriptRoot 'scripts\run_all.py') --path $resolvedTarget --severity $Severity
    if ($LASTEXITCODE -ne 0) { throw "Baseline audit failed (exit $LASTEXITCODE)." }
    Write-Ok "Baseline audit complete: $beforeDir"

    if ($SkipFix) {
        Add-Summary "`n-SkipFix was set - stopping after the baseline audit. Nothing was fixed or applied."
        $summary | Set-Content -Path $summaryFile
        Stop-Transcript | Out-Null
        Write-Host "`nSummary: $summaryFile" -ForegroundColor Cyan
        exit 0
    }

    # ------------------------------------------------- 4. working copy --
    Write-Step "Creating a working copy to fix (original is never touched by fixers)"
    New-Item -ItemType Directory -Path $fixedDir -Force | Out-Null
    Invoke-Robocopy -Source $resolvedTarget -Dest $fixedDir -FailMessage "Copy-to-fix failed"
    Write-Ok "Working copy ready: $fixedDir"

    # ------------------------------------------------------- 5. fix pass --
    Write-Step "Running auto-fixers against the working copy"
    New-Item -ItemType Directory -Path $fixLogDir -Force | Out-Null
    $env:AUDITOR_LOGS_DIR = $fixLogDir
    & $python (Join-Path $scriptRoot 'scripts\run_all.py') --path $fixedDir --severity $Severity --fix
    if ($LASTEXITCODE -ne 0) { throw "Fix pass failed (exit $LASTEXITCODE)." }
    Write-Ok "Fix pass complete"

    # ---------------------------------------------------- 6. post-fix audit --
    Write-Step "Running post-fix audit against the working copy"
    New-Item -ItemType Directory -Path $afterDir -Force | Out-Null
    $env:AUDITOR_LOGS_DIR = $afterDir
    & $python (Join-Path $scriptRoot 'scripts\run_all.py') --path $fixedDir --severity $Severity
    if ($LASTEXITCODE -ne 0) { throw "Post-fix audit failed (exit $LASTEXITCODE)." }
    Write-Ok "Post-fix audit complete: $afterDir"

    # -------------------------------------------------------- 7. verify --
    Write-Step "Verifying the fix didn't break anything"
    $problems = New-Object System.Collections.Generic.List[string]

    # 7a. Every PowerShell file in the working copy must still parse cleanly.
    #     Uses PowerShell's own parser directly - no pwsh / PSScriptAnalyzer
    #     dependency for this specific check.
    $psFiles = Get-ChildItem $fixedDir -Recurse -Include *.ps1, *.psm1, *.psd1 -File
    foreach ($f in $psFiles) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $f.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            foreach ($e in $parseErrors) {
                $problems.Add("PARSE ERROR: $($f.FullName):$($e.Extent.StartLineNumber) - $($e.Message)")
            }
        }
    }
    if (($problems | Where-Object { $_ -like 'PARSE ERROR:*' }).Count -eq 0) {
        Write-Ok "All $($psFiles.Count) PowerShell file(s) still parse cleanly"
    } else {
        Write-Bad "Parse errors found in the fixed output (see summary)"
    }

    # 7b. Per-file sanity: the fixer should not have gutted function bodies
    #     or otherwise collapsed the file (this is exactly the failure mode
    #     from the earlier ps_fixer.ps1 regex bug).
    foreach ($f in $psFiles) {
        $relPath  = $f.FullName.Substring($fixedDir.Length).TrimStart('\')
        $origFile = Join-Path $backupDir $relPath
        if (-not (Test-Path $origFile)) { continue }

        try {
            $origContent  = Get-Content $origFile -Raw -ErrorAction Stop
            $fixedContent = Get-Content $f.FullName -Raw -ErrorAction Stop
        } catch {
            $problems.Add("UNREADABLE: could not compare $relPath - $($_.Exception.Message)")
            continue
        }
        if (-not $origContent)  { $origContent  = '' }
        if (-not $fixedContent) { $fixedContent = '' }

        $origLines  = (Get-Content $origFile).Count
        $fixedLines = (Get-Content $f.FullName).Count
        $origFuncs  = ([regex]::Matches($origContent, 'function\s+[\w-]+')).Count
        $fixedFuncs = ([regex]::Matches($fixedContent, 'function\s+[\w-]+')).Count

        if ($fixedFuncs -lt $origFuncs) {
            $problems.Add("FUNCTION LOSS: $relPath went from $origFuncs to $fixedFuncs function definition(s)")
        }
        if ($origLines -gt 0 -and ($fixedLines / [double]$origLines) -lt 0.6) {
            $pctLoss = [math]::Round((1 - ($fixedLines / [double]$origLines)) * 100)
            $problems.Add("CONTENT LOSS: $relPath dropped from $origLines to $fixedLines lines (-$pctLoss%)")
        }
    }

    # 7c. Finding totals before vs. after must not have gotten worse.
    $beforeCounts = & $python (Join-Path $scriptRoot 'scripts\verify_findings.py') --path $resolvedTarget | ConvertFrom-Json
    $afterCounts  = & $python (Join-Path $scriptRoot 'scripts\verify_findings.py') --path $fixedDir      | ConvertFrom-Json

    Add-Summary "`nFindings before -> after (low / medium / high):"
    Add-Summary "  low:    $($beforeCounts.low) -> $($afterCounts.low)"
    Add-Summary "  medium: $($beforeCounts.medium) -> $($afterCounts.medium)"
    Add-Summary "  high:   $($beforeCounts.high) -> $($afterCounts.high)"
    foreach ($sev in 'low', 'medium', 'high') {
        if ($afterCounts.$sev -gt $beforeCounts.$sev) {
            $problems.Add("REGRESSION: '$sev' findings increased ($($beforeCounts.$sev) -> $($afterCounts.$sev))")
        }
    }

    $verified = $problems.Count -eq 0
    Add-Summary ""
    if ($verified) {
        Add-Summary "VERIFICATION: PASSED"
    } else {
        Add-Summary "VERIFICATION: FAILED ($($problems.Count) issue(s))"
        foreach ($p in $problems) { Add-Summary "  - $p" }
    }

    # ------------------------------------------------------ 8. finalize --
    Write-Step "Finalizing"
    if (-not $verified) {
        Write-Bad "Verification failed - original target left untouched."
        Add-Summary "`nOriginal was NOT modified. Review the fixed copy manually:"
        Add-Summary "  $fixedDir"
        Add-Summary "Backup of the original (kept regardless of outcome):"
        Add-Summary "  $backupDir"
        $exitCode = 1
    }
    elseif ($DryRun) {
        Write-Ok "Verification passed. -DryRun was set, so the original was left untouched."
        Add-Summary "`nRun again without -DryRun to apply the verified fixed copy at:"
        Add-Summary "  $fixedDir"
    }
    else {
        Invoke-Robocopy -Source $fixedDir -Dest $resolvedTarget -FailMessage "Applying the fixed copy back to the target failed"
        Write-Ok "Applied verified fix to $resolvedTarget"
        Add-Summary "`nApplied. Original backup remains at:"
        Add-Summary "  $backupDir"
    }

    Add-Summary "`nReports:"
    Add-Summary "  Baseline (before): $beforeDir"
    Add-Summary "  Post-fix (after):  $afterDir"
    Add-Summary "  Fixed copy:        $fixedDir"
}
catch {
    $exitCode = 1
    Write-Bad $_.Exception.Message
    Add-Summary "`nERROR: $($_.Exception.Message)"
    Add-Summary "Original target was not modified by this run."
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    $summary | Set-Content -Path $summaryFile -ErrorAction SilentlyContinue
    Write-Host "`nSummary written to: $summaryFile" -ForegroundColor Cyan
}

exit $exitCode

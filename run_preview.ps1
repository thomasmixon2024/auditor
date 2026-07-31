<#
.SYNOPSIS
Preview auto-fixes for a single file using the local virtual environment.
.DESCRIPTION
Creates/uses the repo .venv, installs dependencies, and runs scripts/preview_fix.py
against a single file to print a unified diff of proposed changes.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$File,

    [switch]$ApplyIfWhitespaceOnly,
    [switch]$Apply,
    [switch]$Force,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptRoot

$venvPath = Join-Path $scriptRoot '.venv'
$pythonPath = $null

if (Test-Path (Join-Path $venvPath 'Scripts\python.exe')) {
    $pythonPath = Join-Path $venvPath 'Scripts\python.exe'
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonPath = (Get-Command python).Source
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $pythonPath = (Get-Command python3).Source
}

if (-not $pythonPath) {
    Write-Error 'Python 3 is not installed or not on PATH. Install Python 3.11+ and try again.'
    exit 1
}

if (-not (Test-Path $venvPath)) {
    Write-Host 'Creating virtual environment...'
    & $pythonPath -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to create virtual environment.'; exit $LASTEXITCODE }
}

$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
Write-Host 'Installing dependencies (if needed)...'
& $pythonPath -m pip install --upgrade pip | Out-Null
& $pythonPath -m pip install -r requirements.txt | Out-Null

$env:AUDITOR_HOME = $scriptRoot
$env:AUDITOR_LOGS_DIR = Join-Path $scriptRoot 'logs'

$script = Join-Path $scriptRoot 'scripts\preview_fix.py'

# Build argument list for the python script based on provided switches
$pyArgs = @($script, $File)
if ($ApplyIfWhitespaceOnly) { $pyArgs += '--apply-if-whitespace-only' }
if ($Apply) { $pyArgs += '--apply' }
if ($Force) { $pyArgs += '--force' }
if ($Yes) { $pyArgs += '--yes' }

Write-Host "Running: $pythonPath $($pyArgs -join ' ')"
& $pythonPath @pyArgs
exit $LASTEXITCODE

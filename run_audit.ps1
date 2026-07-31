<#
.SYNOPSIS
Runs the auditor tool with a local virtual environment and easy defaults.
.DESCRIPTION
This helper script creates a .venv in the repository root if needed,
installs Python dependencies from requirements.txt, and runs
scripts/run_all.py against the configured target project.
#>

param(
    [string]$Path = "target_project",
    [ValidateSet('all','low','medium','high')]
    [string]$Severity = 'all',
    [switch]$Ci,
    [switch]$Fix
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
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Failed to create virtual environment.'
        exit $LASTEXITCODE
    }
}

$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path $pythonPath)) {
    Write-Error 'Virtual environment was created but python.exe was not found.'
    exit 1
}

Write-Host 'Installing dependencies...'
& $pythonPath -m pip install --upgrade pip | Out-Null
& $pythonPath -m pip install -r requirements.txt | Out-Null

# Ensure the local audit tool can run without requiring extra approval or
# environment-specific setup for simple local usage.
$env:AUDITOR_HOME = $scriptRoot
$env:AUDITOR_LOGS_DIR = Join-Path $scriptRoot 'logs'
$env:AUDITOR_TARGET_DIR = Join-Path $scriptRoot 'target_project'

$script = Join-Path $scriptRoot 'scripts\run_all.py'

$args = @('--path', $Path, '--severity', $Severity)
if ($Ci) { $args += '--ci' }
if ($Fix) { $args += '--fix' }

Write-Host "Running audit on path: $Path (severity=$Severity)"
& $pythonPath $script @args
exit $LASTEXITCODE

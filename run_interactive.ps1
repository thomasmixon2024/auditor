<#!
.SYNOPSIS
Run the preview fixer in interactive mode for a single file.
.DESCRIPTION
Prompts for a file path when needed, previews proposed fixes, and asks whether to apply them.
#>

param(
    [string]$File,
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

$script = Join-Path $scriptRoot 'scripts\preview_fix.py'
$pyArgs = @($script, '--interactive')
if ($File) { $pyArgs += $File }
if ($Yes) { $pyArgs += '--yes' }

Write-Host "Running: $pythonPath $($pyArgs -join ' ')"
& $pythonPath @pyArgs
exit $LASTEXITCODE

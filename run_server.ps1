<#
.SYNOPSIS
Starts the audit report server using the local virtual environment.
.DESCRIPTION
This helper script creates a .venv if needed, installs dependencies, and starts
server.py on localhost. It requires AUDITOR_API_TOKEN to be set in the environment.
#>

param(
    [string]$Host = '127.0.0.1',
    [int]$Port = 5000,
    [switch]$Debug
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

if (-not $env:AUDITOR_API_TOKEN) {
    Write-Error 'AUDITOR_API_TOKEN is not set. Set it before starting the server.'
    exit 1
}

Write-Host "Starting report server on http://$Host:$Port"
$env:AUDITOR_SERVER_HOST = $Host
$env:AUDITOR_SERVER_DEBUG = if ($Debug) { 'true' } else { 'false' }
& $pythonPath (Join-Path $scriptRoot 'server.py')
exit $LASTEXITCODE

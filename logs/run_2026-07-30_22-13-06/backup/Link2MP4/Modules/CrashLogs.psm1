# CrashLogs.psm1 — Unified Logging Engine

if ($env:LOCALAPPDATA) {
    $script:CrashDir = Join-Path $env:LOCALAPPDATA "Link2MP4\Logs"
} else {
    $script:CrashDir = Join-Path $PSScriptRoot "..\CrashLogs"
}

if (-not (Test-Path $script:CrashDir)) {
    New-Item -ItemType Directory -Path $script:CrashDir -Force | Out-Null
}

$script:LastRotationDay = $null

function Rotate-Logs {
    $today = Get-Date -Format "yyyyMMdd"
    if ($script:LastRotationDay -eq $today) { return }

    $logs = Get-ChildItem -Path $script:CrashDir -Filter "log_*.txt" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($logs.Count -gt 50) {
        $logs | Select-Object -Skip 50 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $script:LastRotationDay = $today
}

function Write-Log {
    param([string]$Source, [string]$Message)
    Rotate-Logs
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $file = Join-Path $script:CrashDir ("log_" + (Get-Date -Format "yyyyMMdd") + ".txt")
    Add-Content -Path $file -Value "[$timestamp] [$Source] $Message"
}

function Get-CrashLogDirectory { return $script:CrashDir }

Export-ModuleMember -Function Write-Log, Get-CrashLogDirectory

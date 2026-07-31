Set-StrictMode -Version Latest
# DownloaderConfig.psm1 — Environment & Binary Validation

[CmdletBinding()]
function Get-YtDlpPath {
    $ytdlpCmd = Get-Command "yt-dlp.exe" -ErrorAction SilentlyContinue
    if ($null -ne $ytdlpCmd) { return $ytdlpCmd.Source }

    $localPath = Join-Path $PSScriptRoot "..\yt-dlp.exe"
    if (Test-Path $localPath) { return (Resolve-Path $localPath).Path }

    throw "yt-dlp.exe was not found in System PATH or project root."
}

[CmdletBinding()]
function Ensure-TargetDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Export-ModuleMember -Function Get-YtDlpPath, Ensure-TargetDirectory
Write-Log -Source "DownloaderConfig" -Message "DownloaderConfig module loaded."



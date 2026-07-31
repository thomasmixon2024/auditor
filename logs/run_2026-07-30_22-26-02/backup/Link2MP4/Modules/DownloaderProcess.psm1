# DownloaderProcess.psm1 — Subprocess Handle Engine (Progress Template Improved)

if (-not (Test-Path Variable:global:ActiveDownloadProcess)) {
    $global:ActiveDownloadProcess = $null
}

function New-YtDlpProcess {
    param([string]$BinaryPath, [string]$URL, [string]$TargetFolder)

    $outputTemplate = Join-Path $TargetFolder "%(title)s.%(ext)s"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $BinaryPath
    $escapedTemplate = $outputTemplate.Replace('"', '\"')
    $escapedUrl = $URL.Replace('"', '\"')

    $psi.Arguments = '-f "b[ext=mp4]/bv*[ext=mp4]+ba[ext=m4a]/b" -o "{0}" --no-playlist --newline --progress --progress-template "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress.eta_str)s" "{1}"' -f $escapedTemplate, $escapedUrl

    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    return $proc
}

function Stop-YtDlpProcess {
    if ($null -ne $global:ActiveDownloadProcess -and -not $global:ActiveDownloadProcess.HasExited) {
        try {
            Write-Log -Source "DownloaderProcess" -Message "Killing process PID $($global:ActiveDownloadProcess.Id)"
            $global:ActiveDownloadProcess.Kill()
            return $true
        } catch {
            Write-Log -Source "DownloaderProcess" -Message "Error stopping process: $($_.Exception.Message)"
            return $false
        }
    }
    return $false
}

Export-ModuleMember -Function New-YtDlpProcess, Stop-YtDlpProcess
Write-Log -Source "DownloaderProcess" -Message "DownloaderProcess module loaded."

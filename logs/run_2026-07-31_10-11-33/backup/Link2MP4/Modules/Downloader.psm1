# Downloader.psm1 — Unified Facade

Import-Module (Join-Path $PSScriptRoot "DownloaderConfig.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "DownloaderProcess.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "DownloaderWorker.psm1") -Force

function Set-DownloadState {
    param($UI, [bool]$IsDownloading)

    if ($null -eq $UI) { return }
    if ($UI.ContainsKey("Download")) { $UI["Download"].Enabled = -not $IsDownloading }
    if ($UI.ContainsKey("Cancel")) { $UI["Cancel"].Enabled = $IsDownloading }
}

function Start-Download {
    param($UI, [string]$URL, [string]$Folder, $Form)

    if ($null -eq $UI -or $null -eq $Form) { throw "UI and Form are required to start a download." }

    try {
        Ensure-TargetDirectory -Path $Folder
        $ytdlp = Get-YtDlpPath

        Update-UI $Form {
            if ($UI.ContainsKey("Status"))       { $UI["Status"].Text = "Preparing yt-dlp..." }
            if ($UI.ContainsKey("Progress"))     { $UI["Progress"].Value = 0 }
            if ($UI.ContainsKey("ProgressDetail")) { $UI["ProgressDetail"].Text = "Preparing yt-dlp..." }
        }

        Set-DownloadState -UI $UI -IsDownloading $true

        $proc = New-YtDlpProcess -BinaryPath $ytdlp -URL $URL -TargetFolder $Folder
        $downloadTask = [System.Threading.Tasks.Task]::Run({ Invoke-DownloadWorker -Process $proc -UI $UI })

        $downloadTask.ContinueWith({
            param($task)
            if ($task.IsFaulted) {
                $exception = $task.Exception.GetBaseException()
                Write-Log -Source "Downloader" -Message "Download exception: $($exception.ToString())"
                Update-UI $Form {
                    if ($UI.ContainsKey("Status"))       { $UI["Status"].Text = "Download failed." }
                    if ($UI.ContainsKey("ProgressDetail")) { $UI["ProgressDetail"].Text = "Download failed." }
                    Set-DownloadState -UI $UI -IsDownloading $false
                }
                [System.Windows.Forms.MessageBox]::Show("Download error:`n`n$($exception.Message)", "Download Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            $result = $task.Result
            Update-UI $Form {
                if ($result.ExitCode -eq 0) {
                    if ($UI.ContainsKey("Status"))       { $UI["Status"].Text = "Download Complete!" }
                    if ($UI.ContainsKey("Progress"))     { $UI["Progress"].Value = 100 }
                    if ($UI.ContainsKey("ProgressDetail")) { $UI["ProgressDetail"].Text = "100%  |  Download complete" }
                } else {
                    $err = if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) { $result.StdErr } else { $result.StdOut }
                    Write-Log -Source "Downloader" -Message "yt-dlp failed (Code $($result.ExitCode)): $err"
                    if ($UI.ContainsKey("Status"))       { $UI["Status"].Text = "Download Failed." }
                    if ($UI.ContainsKey("ProgressDetail")) { $UI["ProgressDetail"].Text = "Download failed." }
                    [System.Windows.Forms.MessageBox]::Show("yt-dlp Error:`n`n$err", "Download Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
                Set-DownloadState -UI $UI -IsDownloading $false
            }
        }) | Out-Null
    }
    catch {
        Write-Log -Source "Downloader" -Message "Download exception: $($_.Exception.ToString())"
        Update-UI $Form {
            if ($UI.ContainsKey("Status"))       { $UI["Status"].Text = "Error starting download." }
            if ($UI.ContainsKey("ProgressDetail")) { $UI["ProgressDetail"].Text = "Ready" }
        }
        Set-DownloadState -UI $UI -IsDownloading $false
    }
}

function Stop-DownloadProcess {
    param($UI)
    $stopped = Stop-YtDlpProcess
    if ($stopped) {
        if ($null -ne $UI -and $UI.ContainsKey("Status"))       { $UI["Status"].Text = "Download cancelled." }
        if ($null -ne $UI -and $UI.ContainsKey("ProgressDetail")) { $UI["ProgressDetail"].Text = "Cancelled" }
        if ($null -ne $UI -and $UI.ContainsKey("Progress"))     { $UI["Progress"].Value = 0 }
        if ($null -ne $UI) { Set-DownloadState -UI $UI -IsDownloading $false }
    }
}

Export-ModuleMember -Function Start-Download, Stop-DownloadProcess
Write-Log -Source "Downloader" -Message "Downloader wrapper ready."

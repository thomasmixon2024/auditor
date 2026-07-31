Set-StrictMode -Version Latest
# DownloaderWorker.psm1 — Non-Blocking Async Execution Pump (Progress-Bar Fixed)

[CmdletBinding()]
function Invoke-DownloadWorker {
    param([System.Diagnostics.Process]$Process, [hashtable]$UI)

    if ($null -eq $Process) { throw "Process object cannot be null." }
    if ($null -eq $UI) { throw "UI context cannot be null." }

    $global:ActiveDownloadProcess = $Process
    $output = New-Object System.Text.StringBuilder
    $errors = New-Object System.Text.StringBuilder
    $completion = [System.Threading.Tasks.TaskCompletionSource[object]]::new()

    $outputHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $event)
        if ($null -ne $event.Data) {
            [void]$output.AppendLine($event.Data)
            Update-DownloadProgress -UI $UI -Line $event.Data
        }
    }

    $errorHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $event)
        if ($null -ne $event.Data) {
            [void]$errors.AppendLine($event.Data)
            Update-DownloadProgress -UI $UI -Line $event.Data
        }
    }

    $exitHandler = [System.EventHandler]{
        param($sender, $event)
        $completion.TrySetResult($null) | Out-Null
    }

    try {
        $Process.EnableRaisingEvents = $true
        $Process.add_OutputDataReceived($outputHandler)
        $Process.add_ErrorDataReceived($errorHandler)
        $Process.add_Exited($exitHandler)

        [void]$Process.Start()
        [void]$Process.BeginOutputReadLine()
        [void]$Process.BeginErrorReadLine()

        $completion.Task.Wait()
        $Process.WaitForExit()

        return [PSCustomObject]@{
            ExitCode = $Process.ExitCode
            StdOut   = $output.ToString()
            StdErr   = $errors.ToString()
        }
    }
    finally {
        if ($global:ActiveDownloadProcess -eq $Process) { $global:ActiveDownloadProcess = $null }
        $Process.Dispose()
    }
}

[CmdletBinding()]
function Update-DownloadProgress {
    param($UI, [string]$Line)

    if ($null -eq $UI -or -not $UI.ContainsKey('Form')) { return }
    $form = $UI['Form']
    $cleanLine = $Line -replace "`e\[[0-9;]*m", ''

    $progressLine = $cleanLine
    Update-UI $form {
        $clean = $progressLine -replace "`e\[[0-9;]*m", ''

        if ($clean -match '^download:\s*(?<percent>[\d.]+)\s*%?\s*\|\s*(?<speed>[^|]+)\|\s*(?<eta>.+)$') {
            $percent = [math]::Max(0, [math]::Min(100, [int][math]::Round([double]$Matches.percent)))
            $speed   = $Matches.speed.Trim()
            $eta     = $Matches.eta.Trim()

            if ($UI.ContainsKey('Progress'))       { $UI['Progress'].Value = $percent }
            if ($UI.ContainsKey('ProgressDetail')) { $UI['ProgressDetail'].Text = "$percent%  |  $speed  |  ETA $eta" }
            if ($UI.ContainsKey('Status'))         { $UI['Status'].Text = "Downloading... $percent%" }
            return
        }

        if ($clean -match '(\d+(?:\.\d+)?)\s*%') {
            $percent = [math]::Max(0, [math]::Min(100, [int][math]::Round([double]$Matches[1])))
            if ($UI.ContainsKey('Progress')) { $UI['Progress'].Value = $percent }
            if ($UI.ContainsKey('ProgressDetail')) { $UI['ProgressDetail'].Text = "$percent%  |  $clean" }
            if ($UI.ContainsKey('Status')) { $UI['Status'].Text = "Downloading... $percent%" }
        }
    }
}

Export-ModuleMember -Function Invoke-DownloadWorker
Write-Log -Source "DownloaderWorker" -Message "DownloaderWorker module loaded (progress-bar fix applied)."



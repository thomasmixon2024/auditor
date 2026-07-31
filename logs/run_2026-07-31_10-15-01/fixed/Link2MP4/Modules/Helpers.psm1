Set-StrictMode -Version Latest
# Helpers.psm1 — Safe UI invocation + message box helper

[CmdletBinding()]
function Update-UI {
    param($Form, [scriptblock]$Action)
    if ($null -eq $Form -or $Form.IsDisposed) {
        Write-Log -Source "Helpers" -Message "Update-UI skipped: Form is null or disposed."
        return
    }
    if (-not $Form.IsHandleCreated) {
        Write-Log -Source "Helpers" -Message "Update-UI skipped: Form handle not created."
        return
    }
    try {
        if ($Form.InvokeRequired) { $Form.Invoke($Action) } else { & $Action }
    } catch {
        Write-Log -Source "Helpers" -Message "Update-UI failed: $($_.Exception.Message)"
    }
}

[CmdletBinding()]
function Show-UIMessage {
    param([string]$Text, [string]$Title = "Message")
    try {
        [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-Log -Source "Helpers" -Message "Show-UIMessage failed: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Update-UI, Show-UIMessage
Write-Log -Source 'Helpers' -Message 'Module loaded.'



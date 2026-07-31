# Events.psm1 — Robust Dynamic Hashtable Event Dispatcher

function Register-Link2MP4Events {
    param($UI, $Form)

    if ($null -eq $UI -or $null -eq $Form) { return }
    $script:CurrentUI = $UI
    $script:CurrentForm = $Form

    if ($UI.ContainsKey("Theme") -and $null -ne $UI["Theme"]) {
        $UI["Theme"].Add_Click({
            try {
                $next = if ((Get-Theme) -eq "Dark") { "Light" } else { "Dark" }
                Set-Theme $next
                Apply-Theme $script:CurrentForm $script:CurrentUI
            } catch {
                Write-Log -Source "Events" -Message "Theme error: $($_.Exception.Message)"
            }
        })
    }

    if ($UI.ContainsKey("Browse") -and $null -ne $UI["Browse"]) {
        $UI["Browse"].Add_Click({
            try {
                $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    if ($script:CurrentUI.ContainsKey("Folder") -and $null -ne $script:CurrentUI["Folder"]) {
                        $script:CurrentUI["Folder"].Text = $dialog.SelectedPath
                    }
                }
                $dialog.Dispose()
            } catch {
                Write-Log -Source "Events" -Message "Browse error: $($_.Exception.Message)"
            }
        })
    }

    if ($UI.ContainsKey("Download") -and $null -ne $UI["Download"]) {
        $UI["Download"].Add_Click({
            try {
                $urlBox = $script:CurrentUI["URL"]
                $folderBox = $script:CurrentUI["Folder"]
                if ($null -eq $urlBox -or $null -eq $folderBox) {
                    Write-Log -Source "Events" -Message "Input controls missing."
                    return
                }
                $url = "$($urlBox.Text)".Trim()
                $folder = "$($folderBox.Text)".Trim()
                if ([string]::IsNullOrWhiteSpace($url)) {
                    [System.Windows.Forms.MessageBox]::Show("Please enter a valid video URL.", "Input Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                Start-Download -UI $script:CurrentUI -URL $url -Folder $folder -Form $script:CurrentForm
            } catch {
                Write-Log -Source "Events" -Message "Download click failure: $($_.Exception.Message)"
            }
        })
    }

    if ($UI.ContainsKey("Cancel") -and $null -ne $UI["Cancel"]) {
        $UI["Cancel"].Add_Click({
            try { Stop-DownloadProcess -UI $script:CurrentUI }
            catch { Write-Log -Source "Events" -Message "Cancel click failure: $($_.Exception.Message)" }
        })
    }

    $Form.Add_FormClosing({
        try { Stop-DownloadProcess -UI $script:CurrentUI }
        catch { Write-Log -Source "Events" -Message "Form closing cancellation failed: $($_.Exception.Message)" }
    })
}

Export-ModuleMember -Function Register-Link2MP4Events
Write-Log -Source "Events" -Message "Events module loaded."

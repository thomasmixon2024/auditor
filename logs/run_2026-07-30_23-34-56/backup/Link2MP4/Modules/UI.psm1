# UI.psm1 — Explicit Scope & Control Mapping

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-Link2MP4UI {
    $UI = [hashtable]::Synchronized(@{})

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Link2MP4 Downloader"
    $Form.Size = New-Object System.Drawing.Size(550, 420)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedSingle"
    $Form.MaximizeBox = $false
    $UI["Form"] = $Form

    $Card = New-Object System.Windows.Forms.Panel
    $Card.Location = New-Object System.Drawing.Point(20, 20)
    $Card.Size = New-Object System.Drawing.Size(495, 330)
    $Card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $Form.Controls.Add($Card)
    $UI["Card"] = $Card

    $Title = New-Object System.Windows.Forms.Label
    $Title.Text = "Link2MP4"
    $Title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $Title.Location = New-Object System.Drawing.Point(15, 15)
    $Title.AutoSize = $true
    $Card.Controls.Add($Title)
    $UI["Title"] = $Title

    $BtnTheme = New-Object System.Windows.Forms.Button
    $BtnTheme.Text = "☀️ Theme"
    $BtnTheme.Location = New-Object System.Drawing.Point(370, 15)
    $BtnTheme.Size = New-Object System.Drawing.Size(110, 30)
    $BtnTheme.FlatStyle = "Flat"
    $Card.Controls.Add($BtnTheme)
    $UI["Theme"] = $BtnTheme

    $LblURL = New-Object System.Windows.Forms.Label
    $LblURL.Text = "Video URL:"
    $LblURL.Location = New-Object System.Drawing.Point(15, 65)
    $LblURL.AutoSize = $true
    $Card.Controls.Add($LblURL)

    $TxtURL = New-Object System.Windows.Forms.TextBox
    $TxtURL.Location = New-Object System.Drawing.Point(15, 85)
    $TxtURL.Size = New-Object System.Drawing.Size(465, 25)
    $Card.Controls.Add($TxtURL)
    $UI["URL"] = $TxtURL

    $LblFolder = New-Object System.Windows.Forms.Label
    $LblFolder.Text = "Save Directory:"
    $LblFolder.Location = New-Object System.Drawing.Point(15, 125)
    $LblFolder.AutoSize = $true
    $Card.Controls.Add($LblFolder)

    $TxtFolder = New-Object System.Windows.Forms.TextBox
    $TxtFolder.Location = New-Object System.Drawing.Point(15, 145)
    $TxtFolder.Size = New-Object System.Drawing.Size(370, 25)
    $TxtFolder.Text = [System.IO.Path]::Combine($env:USERPROFILE, "Downloads")
    $Card.Controls.Add($TxtFolder)
    $UI["Folder"] = $TxtFolder

    $BtnBrowse = New-Object System.Windows.Forms.Button
    $BtnBrowse.Text = "Browse"
    $BtnBrowse.Location = New-Object System.Drawing.Point(395, 143)
    $BtnBrowse.Size = New-Object System.Drawing.Size(85, 27)
    $BtnBrowse.FlatStyle = "Flat"
    $Card.Controls.Add($BtnBrowse)
    $UI["Browse"] = $BtnBrowse

    $BtnDownload = New-Object System.Windows.Forms.Button
    $BtnDownload.Text = "Download Video"
    $BtnDownload.Location = New-Object System.Drawing.Point(15, 195)
    $BtnDownload.Size = New-Object System.Drawing.Size(330, 35)
    $BtnDownload.FlatStyle = "Flat"
    $Card.Controls.Add($BtnDownload)
    $UI["Download"] = $BtnDownload

    $BtnCancel = New-Object System.Windows.Forms.Button
    $BtnCancel.Text = "Cancel"
    $BtnCancel.Location = New-Object System.Drawing.Point(355, 195)
    $BtnCancel.Size = New-Object System.Drawing.Size(125, 35)
    $BtnCancel.FlatStyle = "Flat"
    $BtnCancel.Enabled = $false
    $Card.Controls.Add($BtnCancel)
    $UI["Cancel"] = $BtnCancel

    $Progress = New-Object System.Windows.Forms.ProgressBar
    $Progress.Location = New-Object System.Drawing.Point(15, 245)
    $Progress.Size = New-Object System.Drawing.Size(465, 18)
    $Progress.Minimum = 0
    $Progress.Maximum = 100
    $Progress.Value = 0
    $Card.Controls.Add($Progress)
    $UI["Progress"] = $Progress

    $LblProgress = New-Object System.Windows.Forms.Label
    $LblProgress.Text = "Waiting to start download"
    $LblProgress.Location = New-Object System.Drawing.Point(15, 267)
    $LblProgress.Size = New-Object System.Drawing.Size(465, 20)
    $Card.Controls.Add($LblProgress)
    $UI["ProgressDetail"] = $LblProgress

    $LblStatus = New-Object System.Windows.Forms.Label
    $LblStatus.Text = "Ready"
    $LblStatus.Location = New-Object System.Drawing.Point(15, 292)
    $LblStatus.Size = New-Object System.Drawing.Size(465, 25)
    $Card.Controls.Add($LblStatus)
    $UI["Status"] = $LblStatus

    return $UI
}

Export-ModuleMember -Function New-Link2MP4UI
Write-Log -Source "UI" -Message "UI module loaded with synchronized control map."

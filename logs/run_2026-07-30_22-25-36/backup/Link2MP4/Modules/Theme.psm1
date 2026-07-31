# Theme.psm1 — Link2MP4 Theme Engine

if (-not (Test-Path Variable:global:CurrentTheme)) { $global:CurrentTheme = "Dark" }

function Get-Theme { return $global:CurrentTheme }
function Set-Theme { param([string]$ThemeName) $global:CurrentTheme = $ThemeName }

function Apply-Theme {
    param($Form, $UI)
    if ($null -eq $Form -or $null -eq $UI) { return }

    if ($global:CurrentTheme -eq "Dark") {
        $bgColor    = [System.Drawing.Color]::FromArgb(32, 32, 32)
        $cardColor  = [System.Drawing.Color]::FromArgb(45, 45, 48)
        $textColor  = [System.Drawing.Color]::White
        $inputBg    = [System.Drawing.Color]::FromArgb(28, 28, 28)
        $buttonBg   = [System.Drawing.Color]::FromArgb(0, 122, 204)
        $btnText    = [System.Drawing.Color]::White
        $toggleText = "☀️ Light Mode"
    } else {
        $bgColor    = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $cardColor  = [System.Drawing.Color]::White
        $textColor  = [System.Drawing.Color]::Black
        $inputBg    = [System.Drawing.Color]::White
        $buttonBg   = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $btnText    = [System.Drawing.Color]::White
        $toggleText = "🌙 Dark Mode"
    }

    $Form.BackColor = $bgColor

    foreach ($key in $UI.Keys) {
        $control = $UI[$key]
        if ($null -eq $control) { continue }

        if ($control -is [System.Windows.Forms.TextBox]) {
            $control.BackColor = $inputBg
            $control.ForeColor = $textColor
        }
        elseif ($control -is [System.Windows.Forms.Label]) {
            $control.ForeColor = $textColor
        }
        elseif ($control -is [System.Windows.Forms.Panel] -or $control -is [System.Windows.Forms.GroupBox]) {
            $control.BackColor = $cardColor
        }
        elseif ($control -is [System.Windows.Forms.Button]) {
            if ($key -eq "Theme") {
                $control.Text = $toggleText
                $control.BackColor = $cardColor
                $control.ForeColor = $textColor
            } else {
                $control.BackColor = $buttonBg
                $control.ForeColor = $btnText
            }
        }
    }
    $Form.Refresh()
}

Export-ModuleMember -Function Get-Theme, Set-Theme, Apply-Theme
Write-Log -Source "Theme" -Message "Theme engine loaded."

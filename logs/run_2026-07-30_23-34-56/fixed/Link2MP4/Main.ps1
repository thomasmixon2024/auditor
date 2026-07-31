Set-StrictMode -Version Latest
# Main.ps1 — Link2MP4 Application Entry Point

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
}

$ModuleDir = Join-Path $scriptDir "Modules"

if ($env:LINK2MP4_STA -ne "1") {
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $env:LINK2MP4_STA = "1"
        $arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $PSCommandPath
        $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Wait -PassThru
        $env:LINK2MP4_STA = $null
        exit $child.ExitCode
    }
}

$modules = @("CrashLogs.psm1", "Helpers.psm1", "Theme.psm1", "UI.psm1", "Downloader.psm1", "Events.psm1")

foreach ($mod in $modules) {
    $modPath = Join-Path $ModuleDir $mod
    if (Test-Path $modPath) {
        Import-Module $modPath -Force
    } else {
        Write-Warning "Module file not found: $modPath"
    }
}

try {
    Write-Log -Source "Main" -Message "Initializing Link2MP4 Application..."

    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

    if (Get-Command "New-Link2MP4UI" -ErrorAction SilentlyContinue) {
        $UI = New-Link2MP4UI
    } else {
        throw "UI constructor function (New-Link2MP4UI) not found in UI.psm1"
    }

    $Form = $UI.Form

    if (Get-Command "Apply-Theme" -ErrorAction SilentlyContinue) {
        Apply-Theme $Form $UI
    }

    if (Get-Command "Register-Link2MP4Events" -ErrorAction SilentlyContinue) {
        Register-Link2MP4Events -UI $UI -Form $Form
    }

    Write-Log -Source "Main" -Message "Displaying Form..."
    [void]$Form.ShowDialog()
}
catch {
    $err = $_.Exception.Message
    if (Get-Command "Write-Log" -ErrorAction SilentlyContinue) {
        Write-Log -Source "Main" -Message "Fatal Application Launch Error: $err"
    }
    [System.Windows.Forms.MessageBox]::Show("Fatal error starting Link2MP4:`n`n$err", "Launch Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
finally {
    if ($null -ne $Form) { $Form.Dispose() }
    $env:LINK2MP4_STA = $null
}



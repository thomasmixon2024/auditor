function Format-Script {
    param([string]$Path)

    $content = Get-Content $Path -Raw
    $content = $content -replace "`t", "    "

    if ($content -notmatch "Set-StrictMode") {
        $content = "Set-StrictMode -Version Latest`n" + $content
    }

    if ($content -notmatch "CmdletBinding") {
        $content = $content -replace "function\s+([A-Za-z0-9_-]+)\s*{",
            "[CmdletBinding()]`nfunction `$1 {"
    }

    Set-Content -Path $Path -Value $content
}

function Normalize-FunctionNames {
    param([string]$Path)

    $content = Get-Content $Path -Raw

    $content = $content -replace "function\s+([a-z]+)_([A-Za-z0-9]+)",
        { "function $($args[0].Groups[1].Value)-$($args[0].Groups[2].Value)" }

    Set-Content -Path $Path -Value $content
}

function Fix-PowerShellModule {
    param([string]$Folder)

    Get-ChildItem $Folder -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
        Format-Script $_.FullName
        Normalize-FunctionNames $_.FullName
    }

    "PowerShell fixes applied to $Folder"
}

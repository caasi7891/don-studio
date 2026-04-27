#Requires -Version 5.1
<#
    Creates a "녹화 시작.lnk" shortcut on the user's Desktop pointing
    at start-recording.ps1, with -ExecutionPolicy Bypass and -WindowStyle Hidden.
#>
$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop '녹화 시작.lnk'
$target = 'powershell.exe'
$argument = (
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ' +
    '-File "' + (Join-Path $PSScriptRoot 'start-recording.ps1') + '"'
)

$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($shortcutPath)
$sc.TargetPath       = $target
$sc.Arguments        = $argument
$sc.WorkingDirectory = $PSScriptRoot

$iconCandidate = Join-Path $PSScriptRoot 'assets\tray-icon.ico'
if (Test-Path -LiteralPath $iconCandidate) {
    $sc.IconLocation = $iconCandidate
}
$sc.Save()

Write-Host "Shortcut created: $shortcutPath" -ForegroundColor Green
exit 0

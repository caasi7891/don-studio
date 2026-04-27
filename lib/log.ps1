#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Get-LogDir {
    return (Resolve-Path -LiteralPath "$PSScriptRoot\..\logs").Path
}

function Write-Log {
    [CmdletBinding()]
    param(
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO',
        [Parameter(Mandatory)] [string]$Message
    )
    $logDir = Get-LogDir
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $log = Join-Path $logDir ("recorder-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

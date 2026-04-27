#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Read-Dotenv {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)
    $h = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $h }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.TrimStart([char]0xFEFF)
        if ($line -match '^\s*#') { return }
        if ($line -match '^\s*$') { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 0) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($val -match '^"(.*)"$') { $val = $matches[1] }
        $h[$key] = $val
    }
    return $h
}

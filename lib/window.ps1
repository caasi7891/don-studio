#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

if (-not ([System.Management.Automation.PSTypeName]'DonStudio.Win').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace DonStudio {
    public static class Win {
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
    }
}
"@
}

function Find-HtsWindow {
    [CmdletBinding()] param()

    if (-not (Get-Command Read-Dotenv -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'dotenv.ps1')
    }

    $envPath = "$PSScriptRoot\..\.env"
    $envMap = @{}
    if (Test-Path -LiteralPath $envPath) {
        $envMap = Read-Dotenv -Path (Resolve-Path -LiteralPath $envPath)
    }

    # Process-env override wins over .env so test harnesses (smoke-test.ps1)
    # can flip the target without mutating the on-disk .env.
    $override = if ($env:WINDOW_TITLE_OVERRIDE) { $env:WINDOW_TITLE_OVERRIDE }
                elseif ($envMap.WINDOW_TITLE_OVERRIDE) { $envMap.WINDOW_TITLE_OVERRIDE }
                else { $null }

    if ($override) {
        # Override matches when EITHER the process name OR the window title
        # contains the needle (case-insensitive). This makes "notepad" work on
        # Korean Windows where the real title is "제목 없음 - 메모장".
        $needle = $override
        return Get-Process |
            Where-Object {
                $_.MainWindowHandle -ne [IntPtr]::Zero -and (
                    $_.ProcessName -like "*$needle*" -or
                    $_.MainWindowTitle -like "*$needle*"
                )
            } |
            Select-Object -First 1
    }

    $byTitle = @(
        Get-Process |
            Where-Object {
                $_.MainWindowHandle -ne [IntPtr]::Zero -and
                $_.MainWindowTitle -match '영웅문|HEROES|Heroes'
            }
    )
    if ($byTitle.Count -eq 0) { return $null }
    if ($byTitle.Count -eq 1) { return $byTitle[0] }

    $disambig = $byTitle |
        Where-Object { $_.ProcessName -match 'kiwoom|hero|khmini|khministarter' } |
        Select-Object -First 1
    if ($disambig) { return $disambig }
    return $byTitle[0]
}

function Test-WindowVisible {
    [CmdletBinding()] param([Parameter(Mandatory)] [IntPtr]$Hwnd)
    if ($Hwnd -eq [IntPtr]::Zero) { return $false }
    return (
        [DonStudio.Win]::IsWindowVisible($Hwnd) -and
        -not [DonStudio.Win]::IsIconic($Hwnd)
    )
}

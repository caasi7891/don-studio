#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ----- WM_HOTKEY receiving NativeWindow (C1 fix) ---------------------------
if (-not ([System.Management.Automation.PSTypeName]'DonStudio.HotkeyWindow').Type) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DonStudio {
    public class HotkeyWindow : NativeWindow, IDisposable {
        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_ALT = 0x1;
        public const uint MOD_CONTROL = 0x2;
        public const uint MOD_SHIFT = 0x4;
        public const uint MOD_WIN = 0x8;

        public int HotkeyId = 1;
        public Action OnHotkey;

        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public HotkeyWindow() { CreateHandle(new CreateParams()); }

        public bool Register(uint mods, uint vk) {
            return RegisterHotKey(this.Handle, HotkeyId, mods, vk);
        }

        protected override void WndProc(ref Message m) {
            if (m.Msg == WM_HOTKEY && OnHotkey != null) {
                try { OnHotkey(); } catch { /* swallow to keep pump alive */ }
            }
            base.WndProc(ref m);
        }

        public void Dispose() {
            try { UnregisterHotKey(this.Handle, HotkeyId); } catch {}
            try { DestroyHandle(); } catch {}
        }
    }
}
"@
}

# ----- Tray UI factory ----------------------------------------------------
function New-TrayUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$OnStop,
        [string]$StopEventName = 'Global\don-studio-stop',
        [string]$IconPath
    )

    Add-Type -AssemblyName System.Windows.Forms,System.Drawing

    $tray = New-Object System.Windows.Forms.NotifyIcon
    if (-not $IconPath) { $IconPath = "$PSScriptRoot\..\assets\tray-icon.ico" }
    try {
        if (Test-Path -LiteralPath $IconPath) {
            $tray.Icon = New-Object System.Drawing.Icon $IconPath
        } else {
            $tray.Icon = [System.Drawing.SystemIcons]::Application
        }
    } catch {
        $tray.Icon = [System.Drawing.SystemIcons]::Application
    }
    $tray.Visible = $true
    $tray.Text = 'don-studio recording'

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $stopItem = $menu.Items.Add('정지 (Ctrl+Alt+S)')
    $stopItem.add_Click({
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log -Message '[tray] menu Stop clicked' }
        & $OnStop
    }.GetNewClosure())

    $logItem = $menu.Items.Add('로그 폴더 열기')
    $logItem.add_Click({
        $p = (Resolve-Path -LiteralPath "$PSScriptRoot\..\logs").Path
        Start-Process explorer.exe -ArgumentList $p
    })

    $recItem = $menu.Items.Add('녹화 폴더 열기')
    $recItem.add_Click({
        $p = (Resolve-Path -LiteralPath "$PSScriptRoot\..\recordings").Path
        Start-Process explorer.exe -ArgumentList $p
    })

    $tray.ContextMenuStrip = $menu

    # Hotkey registration with explicit success check (m-6)
    $hot = New-Object DonStudio.HotkeyWindow
    $hot.OnHotkey = {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log -Message '[tray] hotkey fired' }
        & $OnStop
    }.GetNewClosure()
    $vkS = 0x53
    $mods = ([DonStudio.HotkeyWindow]::MOD_CONTROL -bor [DonStudio.HotkeyWindow]::MOD_ALT)
    $registered = $hot.Register($mods, $vkS)

    if (-not $registered) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Level WARN -Message 'RegisterHotKey failed: Ctrl+Alt+S already in use. Use tray menu to stop.'
        }
        try {
            $tray.ShowBalloonTip(
                3000,
                'don-studio',
                'Ctrl+Alt+S가 이미 다른 프로그램에 등록됨. 트레이 메뉴 "정지"로 정지하세요.',
                [System.Windows.Forms.ToolTipIcon]::Warning
            )
        } catch {}
    }

    # smoke-test stop signal: 500 ms timer polling EventWaitHandle (M-NEW-3)
    $stopEvt = New-Object System.Threading.EventWaitHandle(
        $false,
        [System.Threading.EventResetMode]::AutoReset,
        $StopEventName
    )
    $stopTimer = New-Object System.Windows.Forms.Timer
    $stopTimer.Interval = 500
    # .GetNewClosure() snapshots $stopEvt and $OnStop so the Tick handler
    # keeps resolving them correctly even if the enclosing scope changes.
    $stopTimer.add_Tick({
        if ($stopEvt.WaitOne(0)) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log -Message '[tray] EventWaitHandle signaled' }
            & $OnStop
        }
    }.GetNewClosure())
    $stopTimer.Start()

    return [pscustomobject]@{
        Tray      = $tray
        Hotkey    = $hot
        StopEvent = $stopEvt
        StopTimer = $stopTimer
    }
}

function Dispose-TrayUI {
    [CmdletBinding()] param([Parameter(Mandatory)] $Ui)

    if ($Ui.StopTimer) {
        try { $Ui.StopTimer.Stop() } catch {}
        try { $Ui.StopTimer.Dispose() } catch {}
    }
    if ($Ui.StopEvent) {
        try { $Ui.StopEvent.Dispose() } catch {}
    }
    if ($Ui.Hotkey) {
        try { $Ui.Hotkey.Dispose() } catch {}
    }
    if ($Ui.Tray) {
        try { $Ui.Tray.Visible = $false } catch {}
        try { $Ui.Tray.Dispose() } catch {}
    }
}

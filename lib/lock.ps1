#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$script:DonStudioMutex = $null
$script:DonStudioMutexHeld = $false

function Acquire-SingleInstanceLock {
    [CmdletBinding()]
    param([string]$Name = 'Global\don-studio-recording')
    if ($script:DonStudioMutexHeld) { return $true }
    $script:DonStudioMutex = New-Object System.Threading.Mutex($false, $Name)
    try {
        $acquired = $script:DonStudioMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        # Previous owner crashed without releasing; we now own it.
        $acquired = $true
    }
    $script:DonStudioMutexHeld = $acquired
    return $acquired
}

function Release-SingleInstanceLock {
    [CmdletBinding()] param()
    if ($script:DonStudioMutex) {
        if ($script:DonStudioMutexHeld) {
            try { $script:DonStudioMutex.ReleaseMutex() } catch {}
            $script:DonStudioMutexHeld = $false
        }
        try { $script:DonStudioMutex.Dispose() } catch {}
        $script:DonStudioMutex = $null
    }
}

#Requires -Version 5.1
<#
    don-studio: detached uploader.

    1. Drains failed-uploads/ first (FIFO) so retries happen before today's file.
    2. Uploads $MediaPath (if still present).
    3. On success: deletes local mp4. On failure: moves to failed-uploads/.
    4. Hidden window — surface fatal errors via balloon toast.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$MediaPath
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'lib\dotenv.ps1')
. (Join-Path $PSScriptRoot 'lib\log.ps1')
. (Join-Path $PSScriptRoot 'lib\oauth.ps1')
. (Join-Path $PSScriptRoot 'lib\upload-core.ps1')

Add-Type -AssemblyName System.Windows.Forms,System.Drawing

function Show-UploadToast {
    param([string]$Title, [string]$Body, [System.Windows.Forms.ToolTipIcon]$Kind = 'Info')
    try {
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.Visible = $true
        $n.ShowBalloonTip(5000, $Title, $Body, $Kind)
        Start-Sleep -Seconds 5
        $n.Visible = $false
        $n.Dispose()
    } catch {}
}

function Build-Metadata {
    param([Parameter(Mandatory)] [string]$Path)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($stem -match '^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})') {
        $title = "{0}-{1}-{2} {3}:{4}" -f $matches[1],$matches[2],$matches[3],$matches[4],$matches[5]
    } else {
        $title = Get-Date -Format 'yyyy-MM-dd HH:mm'
    }
    return @{
        snippet = @{ title = $title; description = '' }
        status  = @{ privacyStatus = 'private' }
    }
}

function Try-Upload {
    [CmdletBinding()] param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $meta = Build-Metadata -Path $Path
    try {
        $videoId = Invoke-ResumableUpload -FilePath $Path -Metadata $meta
        Write-Log -Message "[upload] success videoId=$videoId path=$Path"
        Remove-Item -LiteralPath $Path -Force
        return $true
    } catch {
        $err = $_.Exception.Message
        Write-Log -Level ERROR -Message "[upload] failed path=$Path err=$err"
        $failedDir = Join-Path $PSScriptRoot 'failed-uploads'
        if (-not (Test-Path -LiteralPath $failedDir)) {
            New-Item -ItemType Directory -Path $failedDir -Force | Out-Null
        }
        $dest = Join-Path $failedDir (Split-Path -Leaf $Path)
        # Avoid clobbering an existing failed file with the same name.
        if (Test-Path -LiteralPath $dest) {
            $dest = Join-Path $failedDir (("{0}.{1}{2}" -f
                [System.IO.Path]::GetFileNameWithoutExtension($Path),
                (Get-Date -Format 'yyyyMMddHHmmss'),
                [System.IO.Path]::GetExtension($Path)))
        }
        Move-Item -LiteralPath $Path -Destination $dest -Force
        Show-UploadToast `
            -Title 'don-studio 업로드 실패' `
            -Body '원본은 failed-uploads/에 보존됨. 다음 실행 시 재시도.' `
            -Kind Warning
        return $false
    }
}

# 1) Drain failed-uploads/ queue
$failedDir = Join-Path $PSScriptRoot 'failed-uploads'
if (Test-Path -LiteralPath $failedDir) {
    Get-ChildItem -LiteralPath $failedDir -Filter '*.mp4' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime |
        ForEach-Object {
            $null = Try-Upload -Path $_.FullName
        }
}

# 2) Upload this session's file
if ($MediaPath -and (Test-Path -LiteralPath $MediaPath)) {
    $null = Try-Upload -Path $MediaPath
}

exit 0

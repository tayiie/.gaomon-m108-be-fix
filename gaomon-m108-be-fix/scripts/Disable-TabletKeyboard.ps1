<#
.SYNOPSIS
    Stop stray B/E keystrokes from a GAOMON / HUION pen tablet by disabling its
    keyboard HID collections at the device level.

.DESCRIPTION
    Some GAOMON tablets expose a HID keyboard collection for their pen side
    buttons / express keys. When the official driver is not running, that
    collection can emit B and E (Photoshop brush/eraser shortcuts) into the
    focused window.

    The official driver injects those keys with PostMessage/SendMessage, which
    bypasses user-mode keyboard hooks. The reliable user-mode fix is to disable
    the tablet's keyboard HID collections. The pen digitizer, mouse collection
    and pressure data are separate collections and keep working.

    This script writes ConfigFlags=1 directly (Windows refuses
    "pnputil /disable-device" for keyboard-class devices) and restarts the
    device. Use -Undo to restore ConfigFlags=0.

.PARAMETER Match
    Substrings of HID collection instance IDs to target. The defaults cover the
    GAOMON M108 (VID_256C/PID_0064) and the GAOMON virtual keyboard driver.
    For another model, pass its VID/PID or a collection name.

.PARAMETER Undo
    Re-enable the matching keyboard collections instead of disabling them.

.PARAMETER NoElevate
    Do not self-elevate. Use this only when the current shell is already
    elevated (or together with -WhatIf for discovery).

.EXAMPLE
    .\Disable-TabletKeyboard.ps1

.EXAMPLE
    .\Disable-TabletKeyboard.ps1 -Undo

.EXAMPLE
    .\Disable-TabletKeyboard.ps1 -WhatIf -NoElevate

.NOTES
    Tested on GAOMON M108 (GM001_T208). Requires Windows 10/11 and
    administrator rights for the actual change.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Match = @('VID_256C&PID_0064', 'bigmax_hid_drv'),
    [switch]$Undo,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

# Allow "-Match a,b" to arrive as a single string when re-launched elevated.
if ($Match.Count -eq 1 -and $Match[0] -match ',') {
    $Match = $Match[0] -split ','
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-Admin

if (-not $isAdmin -and -not $NoElevate) {
    $argList = @(
        '-NoProfile',
        '-NoExit',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"')
    )
    if ($Undo) { $argList += '-Undo' }
    if ($Match) { $argList += @('-Match', ($Match -join ',')) }

    Write-Host 'Requesting administrator rights (UAC prompt)...' -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Host ('Could not elevate: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Right-click the .cmd file and choose "Run as administrator".'
    }
    return
}

$scriptDir = Split-Path -Parent $PSCommandPath
$logDir = Join-Path $scriptDir '..\logs'
[System.IO.Directory]::CreateDirectory($logDir) | Out-Null
$logFile = Join-Path $logDir ('fix-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
$logEncoding = New-Object System.Text.UTF8Encoding($false)

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, $logEncoding)
    Write-Host $Message
}

$mode = if ($Undo) { 'ENABLE' } else { 'DISABLE' }
Write-Log ('=== GAOMON tablet keyboard fix: ' + $mode + ' ===')
Write-Log ('admin=' + $isAdmin + '  match=' + ($Match -join ', '))

# Enumerate HID collections from the registry. Using the registry (instead of
# Get-PnpDevice) also works on systems where the PnpDevice cmdlets are
# restricted, and it gives us ConfigFlags directly.
$enumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID'
$targets = @()

Get-ChildItem -Path $enumRoot -ErrorAction SilentlyContinue | ForEach-Object {
    $collection = $_.PSChildName
    Get-ChildItem -Path $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
        $instance = $_.PSChildName
        $fullId = 'HID\{0}\{1}' -f $collection, $instance
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $props) { return }

        $service = [string]$props.Service
        $desc = [string]$props.DeviceDesc
        $isKeyboard = ($service -eq 'kbdhid') -or ($desc -match 'Keyboard')
        if (-not $isKeyboard) { return }

        $hit = $false
        foreach ($pattern in $Match) {
            if ($collection -like ('*' + $pattern + '*') -or $fullId -like ('*' + $pattern + '*')) {
                $hit = $true
                break
            }
        }
        if (-not $hit) { return }

        $targets += [pscustomobject]@{
            InstanceId  = $fullId
            KeyPath     = $_.PSPath
            ConfigFlags = [int]$props.ConfigFlags
            Service     = $service
            Desc        = $desc
        }
    }
}

if ($targets.Count -eq 0) {
    Write-Log 'No matching keyboard HID collections found.'
    Write-Log 'Is the tablet connected? For another model, pass its VID/PID with -Match.'
    exit 1
}

$wantDisabled = -not $Undo
$changed = 0

foreach ($target in $targets) {
    Write-Log ('target: ' + $target.InstanceId)
    Write-Log ('  ConfigFlags=' + $target.ConfigFlags + '  service=' + $target.Service + '  desc=' + $target.Desc)

    $isDisabled = (($target.ConfigFlags -band 1) -eq 1)
    if ($isDisabled -eq $wantDisabled) {
        Write-Log '  already in the desired state, skipping'
        continue
    }

    # Preserve other ConfigFlags bits; only toggle CONFIGFLAG_DISABLED (bit 0).
    $newValue = if ($Undo) { $target.ConfigFlags -band (-bnot 1) } else { $target.ConfigFlags -bor 1 }

    if (-not $PSCmdlet.ShouldProcess($target.InstanceId, ('Set ConfigFlags=' + $newValue))) {
        continue
    }

    try {
        Set-ItemProperty -Path $target.KeyPath -Name ConfigFlags -Value $newValue -Type DWord -ErrorAction Stop
        Write-Log ('  ConfigFlags -> ' + $newValue)
    } catch {
        Write-Log ('  failed to set ConfigFlags: ' + $_.Exception.Message)
        Write-Log '  If access is denied, run this script from an elevated PowerShell window.'
        continue
    }

    $restartOutput = & pnputil.exe /restart-device $target.InstanceId 2>&1
    Write-Log ('  pnputil /restart-device: ' + ($restartOutput -join ' | '))

    Start-Sleep -Milliseconds 600
    $now = (Get-ItemProperty -Path $target.KeyPath -Name ConfigFlags -ErrorAction SilentlyContinue).ConfigFlags
    Write-Log ('  ConfigFlags now: ' + $now)
    $changed++
}

Write-Log ('=== done, changed ' + $changed + ' device(s) ===')

if (-not $Undo -and $changed -gt 0) {
    Write-Host ''
    Write-Host 'Done. Test the pen side button now: no B/E should appear.' -ForegroundColor Green
    Write-Host 'The express keys / lock-screen / screenshot keys use the same keyboard'
    Write-Host 'interface and will stop working. The pen, pressure, mouse buttons and'
    Write-Host 'the volume keys are unaffected.'
    Write-Host 'To restore, run enable-tablet-keyboard.cmd as administrator.'
}
elseif ($Undo -and $changed -gt 0) {
    Write-Host ''
    Write-Host 'Restored. If a device does not come back, unplug/replug the tablet or reboot.' -ForegroundColor Green
}

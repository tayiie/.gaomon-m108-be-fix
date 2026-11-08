<#
.SYNOPSIS
    Show the state of the tablet's keyboard HID collections (read-only).

.DESCRIPTION
    Prints the matching HID collections, their ConfigFlags and whether they are
    disabled. Use this to check whether Disable-TabletKeyboard.ps1 took effect
    or to find the VID/PID of another tablet model.

.PARAMETER Match
    Substrings of HID collection instance IDs to match.
#>
[CmdletBinding()]
param(
    [string[]]$Match = @('VID_256C&PID_0064', 'bigmax_hid_drv')
)

$enumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID'
$rows = @()

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

        $flags = [int]$props.ConfigFlags
        $rows += [pscustomobject]@{
            State       = if (($flags -band 1) -eq 1) { 'Disabled' } else { 'Enabled' }
            ConfigFlags = $flags
            Service     = $service
            InstanceId  = $fullId
        }
    }
}

if ($rows.Count -eq 0) {
    Write-Host 'No matching keyboard HID collections found.' -ForegroundColor Yellow
    Write-Host 'Is the tablet connected? For another model, pass -Match <VID/PID>.'
    exit 1
}

$rows | Format-Table State, ConfigFlags, Service, InstanceId -AutoSize

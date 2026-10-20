<#
.SYNOPSIS
    Catch the short ADB window that opens while a SONOFF NSPanel Pro / Pro 120 boots.

.DESCRIPTION
    On units that boot into the Chinese factory-test screen (工厂模式), adbd is only
    reachable for roughly 15-20 seconds during boot. Polling this by hand is nearly
    impossible, so this script watches `adb devices` every 300 ms and acts the moment
    the panel appears.

    Relevant build properties on such a unit:

        ro.debuggable=1
        ro.adb.secure=0     <- no "Allow USB debugging" prompt, it shows up as "device"

.PARAMETER Serial
    USB serial of the panel. Optional; without it the first non-TCP device is used.

.PARAMETER Fix
    Also disable the factory test app (com.eWeLinkNSPro.dev) and bring the eWeLink
    panel app (com.eWeLinkControlPanel) to the front.

.PARAMETER Minutes
    How long to keep watching. Default: 10.

.PARAMETER Adb
    Path to adb.exe. Default: "adb" (must be on PATH).

.EXAMPLE
    .\find-adb-window.ps1

.EXAMPLE
    .\find-adb-window.ps1 -Serial H082012302031505935 -Fix -Minutes 15
#>
[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$Fix,
    [int]$Minutes = 10,
    [string]$Adb = 'adb'
)

$ErrorActionPreference = 'Continue'
$logFile = Join-Path $PSScriptRoot 'adb-window.log'

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Invoke-Adb {
    param([string[]]$Arguments)
    & $Adb @Arguments 2>&1
}

if (-not (Get-Command $Adb -ErrorAction SilentlyContinue) -and -not (Test-Path $Adb)) {
    throw "adb not found. Pass -Adb C:\path\to\adb.exe or add platform-tools to PATH."
}

Write-Log "watching for the NSPanel Pro boot window ($Minutes min)..."

$deadline = (Get-Date).AddMinutes($Minutes)
$handled = $false

while ((Get-Date) -lt $deadline) {
    $deviceLines = Invoke-Adb -Arguments @('devices')
    foreach ($line in $deviceLines) {
        if ($line -match '^(?<id>\S+)\s+(?<state>device|recovery|sideload|unauthorized)\s*$') {
            $id = $Matches['id']
            $state = $Matches['state']

            # Ignore TCP transports (192.168.x.x:5555) and only handle our serial, if given.
            if ($id -like '*:*') { continue }
            if ($Serial -and $id -ne $Serial) { continue }

            Write-Log "found $id  [$state]"
            if ($state -ne 'device') {
                Write-Log "not authorised - accept the RSA prompt on the panel if it is visible"
                $handled = $true
                break
            }

            # Root is available on userdebug builds; not strictly required for the fix.
            Invoke-Adb @('-s', $id, 'root') | Out-Null
            Start-Sleep -Seconds 2
            Invoke-Adb @('-s', $id, 'wait-for-device') | Out-Null

            Write-Log ('id            : ' + ((Invoke-Adb @('-s', $id, 'shell', 'id')) -join ' '))
            Write-Log ('build         : ' + ((Invoke-Adb @('-s', $id, 'shell', 'getprop ro.build.display.id')) -join ' '))
            Write-Log ('packages      : ' + ((Invoke-Adb @('-s', $id, 'shell', 'pm list packages | grep -i -e ewelink -e smatek')) -join ' | '))
            Write-Log ('home activity : ' + ((Invoke-Adb @('-s', $id, 'shell', 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME')) -join ' '))

            if ($Fix) {
                Write-Log 'disabling factory app...'
                Write-Log ('  ' + ((Invoke-Adb @('-s', $id, 'shell', 'pm disable-user --user 0 com.eWeLinkNSPro.dev')) -join ' '))
                Write-Log ('  ' + ((Invoke-Adb @('-s', $id, 'shell', 'am force-stop com.eWeLinkNSPro.dev')) -join ' '))
                Write-Log ('  ' + ((Invoke-Adb @('-s', $id, 'shell', 'pm disable-user --user 0 com.smatek.test')) -join ' '))
                Write-Log ('disabled now  : ' + ((Invoke-Adb @('-s', $id, 'shell', 'pm list packages -d')) -join ' | '))

                Invoke-Adb @('-s', $id, 'shell', 'input keyevent 3') | Out-Null
                Start-Sleep -Seconds 3
                Write-Log ('foreground    : ' + ((Invoke-Adb @('-s', $id, 'shell', 'dumpsys activity activities | grep mResumedActivity')) -join ' '))
                Write-Log 'Pick "eWeLinkControlPanel" and choose "Always" on the panel if a Home chooser appears.'
            }

            $handled = $true
            break
        }
    }
    if ($handled) { break }
    Start-Sleep -Milliseconds 300
}

if (-not $handled) {
    Write-Log 'no device appeared. Power-cycle the panel (normal reboot, no 5x reset) and run again.'
}

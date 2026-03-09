<#
.SYNOPSIS
    Disables the touch screen device if it is enabled.
.DESCRIPTION
    This script checks for touch screen devices on the system. If a touch screen device is found and it is enabled, the script disables it.
.NOTES 
    Filename: Disable-TouchScreen.ps1
    Created: 2026-03-09
    Version: 2.0
.VERSION HISTORY
    1.0 - Only based on HIDClass and FriendlyName checks, which could lead to false positives/negatives.
    2.0 - Added hardware ID check for more reliable detection and combined logic for better accuracy.
.ROLE
    System Administrator
    This can be deployed via Group Policy / Intune or run manually on individual machines.
    Dependency: Requires administrative privileges to run.
    Deploy in system context and 64-bit architecture.
.AUTHOR
    Burhan Vejalpurwala
#>

######
# ===========================================
# Disable Internal Touchscreen (Combined Logic)
# ===========================================

$LogPath = "C:\ProgramData\Disable-InternalTouch.log"
Start-Transcript -Path $LogPath -Append -ErrorAction SilentlyContinue

$DisabledDevices = @()
$SkippedDevices  = @()

$HIDDevices = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue

if (-not $HIDDevices) {
    Write-Output "No HID devices found"
    Stop-Transcript
    exit 0
}

foreach ($Device in $HIDDevices) {

    $IsDigitizer = $false
    $IsNameMatch = $false
    $IsUSB       = $Device.InstanceId -match "^USB"

    # --- Hardware ID check (Authoritative) ---
    try {
        $HWIDs = (Get-PnpDeviceProperty -InstanceId $Device.InstanceId `
                    -KeyName 'DEVPKEY_Device_HardwareIds' `
                    -ErrorAction Stop).Data

        if ($HWIDs -match "HID_DEVICE_UP:000D_U:0004") {
            $IsDigitizer = $true
        }
    }
    catch {}

    # --- FriendlyName check (Supplementary only) ---
    if ($Device.FriendlyName -match "Touch|Tactile") {
        $IsNameMatch = $true
    }

    # --- Final decision ---
    if ((($IsDigitizer -or $IsNameMatch)) -and -not $IsUSB) {

        if ($Device.Status -ne "Disabled") {
            Disable-PnpDevice -InstanceId $Device.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            $DisabledDevices += $Device.InstanceId
        }
        else {
            $SkippedDevices += "$($Device.InstanceId) (Already Disabled)"
        }
    }
}

if ($DisabledDevices.Count -gt 0) {
    Write-Output "Internal Touchscreen Disabled: $($DisabledDevices -join ', ')"
}
elseif ($SkippedDevices.Count -gt 0) {
    Write-Output "Internal Touchscreen Already Disabled"
}
else {
    Write-Output "No Internal Touchscreen Detected"
}

Stop-Transcript
exit 0

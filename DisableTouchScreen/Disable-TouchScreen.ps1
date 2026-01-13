<#
.SYNOPSIS
    Disables the touch screen device if it is enabled.
.DESCRIPTION
    This script checks for touch screen devices on the system. If a touch screen device is found and it is enabled, the script disables it.
.NOTES 
    Filename: Disable-TouchScreen.ps1
    Created: 2024-06-15
    Version: 1.0
.ROLE
    System Administrator
    This can be deployed via Group Policy / Intune or run manually on individual machines.
    Dependency: Requires administrative privileges to run.
    Deploy in system context and 64-bit architecture.
.AUTHOR
    Burhan Vejalpurwala
#>


$TouchDevices = Get-PnpDevice -Class HIDClass | Where-Object {
    $_.FriendlyName -match "HID.*Touch"
}

if (-not $TouchDevices) {
    Write-Output "No touch screen device detected"
    exit 0
}

foreach ($Device in $TouchDevices) {
    if ($Device.Status -ne "Disabled") {
        Disable-PnpDevice -InstanceId $Device.InstanceId -Confirm:$false
        Write-Output "Touch screen detected and disabled"
    }
    else {
        Write-Output "Touch screen already disabled"
    }
}

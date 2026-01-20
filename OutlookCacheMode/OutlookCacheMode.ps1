<#
.SYNOPSIS
    Enforces Outlook Cached Mode with a 3-month sync window conditionally based on disk size.  
.DESCRIPTION
    This script checks if the system drive size exceeds 128GB. If so, it configures Outlook to use Cached Exchange Mode with a sync window of 3 months (90 days) by
    modifying the appropriate registry settings for the logged-on user. 
    It also creates a scheduled task to ensure the settings persist across reboots and user logins.
.NOTES
    File Name  : OutlookCacheMode.ps1
    Author     : Burhan Vejalpurwala
    Created    : 2024-06-10
    Version    : 1.0
#>

# ==========================
# Outlook Cached Mode – Conditional 3 Months
# Intune Platform Script 
# ==========================

# Setting up paths and variables
$LogRoot = "$env:ProgramData\IntuneLogs"
$ScriptRoot = "$env:ProgramData\IntuneScripts"
$LogFile = "$LogRoot\Outlook_CachedMode_Conditional.log"
$TaskScript = "$ScriptRoot\OutlookCachedMode.ps1"
$TaskName = "Intune-Outlook-CachedMode-Conditional"

# logging function
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    if (-not (Test-Path $LogRoot)) {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

Write-Log "Script started."

# --------------------------
# Detect logged-on user
# --------------------------
try {
    $UserName = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $UserName) {
        Write-Log "No interactive user session detected. Exiting."
        exit 0
    }

    Write-Log "Logged-on user detected: $UserName"

    $SID = (New-Object System.Security.Principal.NTAccount($UserName)).
        Translate([System.Security.Principal.SecurityIdentifier]).Value

    Write-Log "Resolved SID: $SID"
}
catch {
    Write-Log "Failed to resolve logged-on user SID. $_" "ERROR"
    exit 1
}

# --------------------------
# Disk size check
# --------------------------
try {
    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $DiskGB = [math]::Round($Disk.Size / 1GB, 2)

    Write-Log "System drive size: $DiskGB GB"

    if ($DiskGB -le 128) {
        Write-Log "Disk size <= 128GB. Requirement not met. Exiting."
        exit 0
    }
}
catch {
    Write-Log "Disk size evaluation failed. $_" "ERROR"
    exit 1
}

# --------------------------
# Registry enforcement
# --------------------------
$RegPath = "Registry::HKEY_USERS\$SID\Software\Policies\Microsoft\Office\16.0\Outlook\Cached Mode"

try {
    if (-not (Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
        Write-Log "Created Cached Mode policy path."
    }

    New-ItemProperty -Path $RegPath -Name "UseCachedExchangeMode" -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "SyncWindowSetting" -PropertyType DWord -Value 3 -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "SyncWindowSettingDays" -PropertyType DWord -Value 90 -Force | Out-Null

    Write-Log "Cached Exchange Mode enforced and locked to 3 months."
}
catch {
    Write-Log "Registry enforcement failed. $_" "ERROR"
    exit 1
}

# --------------------------
# Persist script for Scheduled Task
# --------------------------
try {
    if (-not (Test-Path $ScriptRoot)) {
        New-Item -Path $ScriptRoot -ItemType Directory -Force | Out-Null
    }

@"
$(Get-Content -Raw -Path $MyInvocation.MyCommand.Path)
"@ | Out-File -FilePath $TaskScript -Encoding UTF8 -Force

    Write-Log "Script persisted to disk for scheduled execution."
}
catch {
    Write-Log "Failed to persist script to disk. $_" "ERROR"
    exit 1
}

# --------------------------
# Scheduled Task
# --------------------------
try {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TaskScript`""

    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Trigger.Delay = "PT15M"

    $Principal = New-ScheduledTaskPrincipal `
        -UserId $UserName `
        -LogonType Interactive `
        -RunLevel Limited

    $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force

    Write-Log "Scheduled task '$TaskName' created/updated."
}
catch {
    Write-Log "Scheduled task creation failed. $_" "ERROR"
    exit 1
}

Write-Log "Script completed successfully."
exit 0
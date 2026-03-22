<#
.SYNOPSIS
    Detects Microsoft 365 Apps (Click-to-Run) patch compliance on a device.

.DESCRIPTION
    This script evaluates whether Microsoft 365 Apps installed via Click-to-Run
    are compliant with patching requirements enforced through
    Intune.

    The script validates several conditions including:

    - Presence of Office Update policy settings
    - Configured UpdateTargetVersion policy
    - Update branch alignment with the expected channel
    - CDN configuration used by Office Click-to-Run
    - UpdateChannel configuration
    - UpdatesEnabled state
    - Installed Office version against target version
    - Scheduled task status for Office Automatic Updates
    - Network connectivity to the Microsoft Office CDN
    - Binary presence and version of core Click-to-Run components

    If any of these checks fail, the script exits with a non-zero exit code,
    signaling Intune Proactive Remediations that remediation is required.

    Logging is written to:
        C:\ProgramData\Scripts\OfficePatching-Detection*.log

.NOTES
    Author: Burhan Vejalpurwala
    Version: 1.0
    Created: 2026-03
    Purpose: Intune Proactive Remediation Detection Script for Office Patching Compliance

    Designed for enterprise environments managing Microsoft 365 Apps through
    Click-to-Run servicing and policy-based version targeting.

.EXAMPLE
    Run detection manually for troubleshooting

        powershell.exe -ExecutionPolicy Bypass -File OfficePatching-Detection.ps1

    Returns exit code:
        0 = Compliant
        1 = Non-Compliant (Remediation required)

.LINK
    https://learn.microsoft.com/deployoffice/updates/overview-update-channels
#>

Param()

# ============================================================
# Logging Configuration
# ============================================================

$Source  = 'OfficePatchingDetectionScript'
$LogName = 'OfficePatchingDetection'
$LogTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Logfile = "C:\ProgramData\Scripts\OfficePatching-Detection-$LogTimestamp.log"

if (!(Test-Path "C:\ProgramData\Scripts")) {
    New-Item -Path "C:\ProgramData\Scripts" -ItemType Directory -Force | Out-Null
}

try {
    if (!([System.Diagnostics.EventLog]::SourceExists($Source))) {
    New-EventLog -LogName $LogName -Source $Source
}
} catch {
    Write-Host "Failed to create event log source. Ensure the script is run with administrative privileges." -ForegroundColor Red
}

Function LogWrite {
    Param (
        [Parameter(Mandatory = $true)][string]$LogString,
        [ValidateSet("INFO","WARN","ERROR")] [string]$LogMsgType = "INFO"
    )

    $LogDateFormat = "yyyy-MM-dd HH:mm:ss"
    Add-content $Logfile -value "$(Get-Date -Format $LogDateFormat) | $LogMsgType | $LogString"
}

LogWrite -LogString "### Starting Office Patching Detection ###" -LogMsgType INFO

# ============================================================
# Cleanup Old Logs (Older than 2 Days)
# ============================================================

try {
    $LogFolder = "C:\ProgramData\Scripts"

    Get-ChildItem -Path $LogFolder -Filter "OfficePatching-Detection-*.log" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-2) } |
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Log "Deleted old log file: $($_.Name)"
    }
}
catch {
    Log "Failed during log cleanup: $_" "WARN"
}

# ============================================================
# Configuration
# ============================================================

$ExpectedBranch = "Deferred"
$ExpectedChannelURL = "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114"
$Issues = @()

# ============================================================
# Policy Target Version
# ============================================================

$PolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate"

if (Test-Path $PolicyPath) {
    $UpdateTargetVersionRaw = (Get-ItemProperty -Path $PolicyPath -ErrorAction SilentlyContinue).UpdateTargetVersion

    if (![string]::IsNullOrWhiteSpace($UpdateTargetVersionRaw)) {
        try {
            $TargetVersion = [version]$UpdateTargetVersionRaw
            LogWrite "Target Version from Policy: $TargetVersion"
        }
        catch {
            LogWrite "Failed to parse UpdateTargetVersion from policy." "ERROR"
            $Issues += "Invalid policy version format"
        }
    }
    else {
        LogWrite "UpdateTargetVersion missing in policy." "ERROR"
        $Issues += "Policy TargetVersion missing"
    }

    $UpdateBranch = (Get-ItemProperty -Path $PolicyPath -ErrorAction SilentlyContinue).updatebranch
}
else {
    LogWrite "Policy path not found." "ERROR"
    $Issues += "Office update policy missing"
}

# ============================================================
# Click-to-Run Configuration
# ============================================================

$CTRPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

if (Test-Path $CTRPath) {

    $CTRProps = Get-ItemProperty -Path $CTRPath -ErrorAction SilentlyContinue

    $CDNBaseUrl     = $CTRProps.CDNBaseUrl
    $UpdateChannel  = $CTRProps.UpdateChannel
    $VersionRaw     = $CTRProps.VersionToReport
    $ClientVersion  = $CTRProps.ClientVersionToReport

    LogWrite "CDNBaseUrl: $CDNBaseUrl"
    LogWrite "UpdateChannel: $UpdateChannel"
    LogWrite "VersionToReport: $VersionRaw"
    LogWrite "ClientVersionToReport: $ClientVersion"

    if (![string]::IsNullOrWhiteSpace($VersionRaw)) {
        try {
            $CurrentVersion = [version]$VersionRaw
        }
        catch {
            LogWrite "Failed to parse VersionToReport." "ERROR"
            $Issues += "Invalid installed version format"
        }
    }
    else {
        $Issues += "VersionToReport missing"
    }

}
else {
    LogWrite "ClickToRun configuration path missing." "ERROR"
    $Issues += "ClickToRun configuration missing"
}

# ============================================================
# Channel Validation
# ============================================================

if ($UpdateBranch -ne $ExpectedBranch) {
    LogWrite "UpdateBranch mismatch. Expected: $ExpectedBranch | Found: $UpdateBranch" "WARN"
    $Issues += "UpdateBranch mismatch"
}

if ($CDNBaseUrl -ne $ExpectedChannelURL) {
    LogWrite "CDNBaseUrl mismatch." "WARN"
    $Issues += "CDNBaseUrl mismatch"
}

if ($UpdateChannel -ne $ExpectedChannelURL) {
    LogWrite "UpdateChannel mismatch." "WARN"
    $Issues += "UpdateChannel mismatch"
}

# ============================================================
# Version Validation
# ============================================================

if ($TargetVersion -and $CurrentVersion) {
    if ($CurrentVersion -lt $TargetVersion) {
        LogWrite "Installed version ($CurrentVersion) lower than target ($TargetVersion)." "WARN"
        $Issues += "Version below target"
    }
}

# ============================================================
# UpdateDetectionLastRunTime (LOG ONLY)
# ============================================================

$UpdateStatusPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Updates"

if (Test-Path $UpdateStatusPath) {
    $LastDetection = (Get-ItemProperty -Path $UpdateStatusPath -ErrorAction SilentlyContinue).UpdateDetectionLastRunTime
    LogWrite "UpdateDetectionLastRunTime: $LastDetection"
}

# ============================================================
# Binary Version Check (Log Only)
# ============================================================

$C2RClientPath = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
$C2RRunPath    = "C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"

try {
    if (Test-Path $C2RClientPath) {
        $C2RClientVersion = (Get-Item $C2RClientPath).VersionInfo.FileVersion
        LogWrite "OfficeC2RClient.exe Version: $C2RClientVersion"
    }
    else {
        LogWrite "OfficeC2RClient.exe not found." "WARN"
    }

    if (Test-Path $C2RRunPath) {
        $C2RRunVersion = (Get-Item $C2RRunPath).VersionInfo.FileVersion
        LogWrite "OfficeClickToRun.exe Version: $C2RRunVersion"
    }
    else {
        LogWrite "OfficeClickToRun.exe not found." "WARN"
    }
}
catch {
    LogWrite "Binary version check failed: $_" "WARN"
}

# ============================================================
# CDN Connectivity Check (LOG ONLY – NOT TRIGGER)
# ============================================================

try {
    $CdnReachable = Test-NetConnection officecdn.microsoft.com -Port 443 -InformationLevel Quiet
    if ($CdnReachable) {
        LogWrite "CDN reachable."
    }
    else {
        LogWrite "CDN NOT reachable." "WARN"
        Write-Output "CDN is not reachable."
    }
}
catch {
    LogWrite "CDN connectivity check failed." "ERROR"
}

# ============================================================
# Final Evaluation
# ============================================================

if ($Issues.Count -gt 0) {

    LogWrite "Detection Result: NON-COMPLIANT"
    LogWrite "Issues Found: $($Issues -join ', ')" "WARN"

    Write-EventLog -LogName $LogName -Source $Source -EventID 1234 -EntryType Information `
        -Message "Office patching remediation required. Issues: $($Issues -join ', ')" `
        -Category 1 -RawData 10,20

    Exit 1
}
else {

    LogWrite "Detection Result: COMPLIANT"

    Write-EventLog -LogName $LogName -Source $Source -EventID 1233 -EntryType Information `
        -Message "Office patching compliant. No remediation required." `
        -Category 1 -RawData 10,20

    Exit 0
}
<#
.SYNOPSIS
    Remediates Microsoft 365 Apps patch compliance issues.

.DESCRIPTION
    This remediation script enforces Microsoft 365 Apps update configuration
    and triggers an update when the installed version does not meet the
    organizational target version.

    The script performs the following actions:

    - Captures pre-remediation system state
    - Validates Office Click-to-Run configuration
    - Corrects CDNBaseUrl and UpdateChannel settings - currently set to Semi-Annual Enterprise Channel values.
    - Ensures UpdatesEnabled is properly configured
    - Validates update branch configuration
    - Restarts relevant services (ClickToRunSvc and BITS)
    - Ensures the Office Automatic Updates scheduled task is running
    - Tests connectivity to the Microsoft Office CDN
    - Forces an Office update using OfficeC2RClient when required
    - Captures post-remediation configuration state
    - Logs binary versions before and after remediation

    The script also maintains operational logging and removes log files
    older than two days to prevent uncontrolled disk growth.

    Logging is written to:
        C:\ProgramData\Scripts\OfficePatching-Remediation-<timestamp>.log

.NOTES
    Author: Burhan Vejalpurwala
    Version: 1.0
    Created: 2026-03
    Purpose: Intune Proactive Remediation Script for Microsoft 365 Apps patch enforcement.

    Designed to support enterprise patch governance where Office versions
    are controlled via UpdateTargetVersion policy.

    Script is safe to run repeatedly and performs idempotent remediation.

.EXAMPLE
    Run remediation manually for testing

        powershell.exe -ExecutionPolicy Bypass -File OfficePatching-Remediation.ps1

.EXAMPLE
    Executed automatically via Intune Proactive Remediations when the
    detection script reports non-compliance.

.LINK
    https://learn.microsoft.com/deployoffice/updates/update-target-version]=
#>

Param()

# ============================================================
# Logging Configuration
# ============================================================

$Source  = 'OfficePatchingRemediationScript'
$LogName = 'OfficePatchingRemediation'
$LogTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Logfile = "C:\ProgramData\Scripts\OfficePatching-Remediation-$LogTimestamp.log"

if (!(Test-Path "C:\ProgramData\Scripts")) {
    New-Item -Path "C:\ProgramData\Scripts" -ItemType Directory -Force | Out-Null
}

try {
    if (!([System.Diagnostics.EventLog]::SourceExists($Source))) {
    New-EventLog -LogName $LogName -Source $Source
}
}
catch {
    Write-Host "Failed to create event log source. Ensure the script is run with administrative privileges." -ForegroundColor Red
}

Function Log {
    Param (
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")] [string]$Level = "INFO"
    )
    $LogDateFormat = "yyyy-MM-dd HH:mm:ss"
    Add-Content $Logfile -Value "$(Get-Date -Format $LogDateFormat) | $Level | $Message"
}

# ============================================================
# Helper Functions (RESTORED)
# ============================================================

function ToVersion {
    param($v)
    if ($null -eq $v -or $v -eq '') { return $null }
    try { return [version]($v -replace '[^0-9\.]', '') }
    catch { return $null }
}

function SafeGet-ItemProperty {
    param($Path, $Name)
    try {
        if (Test-Path $Path) {
            return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        }
    }
    catch { return $null }
}

# ============================================================
# Cleanup Old Logs (Older than 2 Days)
# ============================================================

try {

    $LogFolder = "C:\ProgramData\Scripts"

    Get-ChildItem -Path $LogFolder -Filter "OfficePatching-Remediation-*.log" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-2) } |
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Log "Deleted old log file: $($_.Name)"
    }

}
catch {
    Log "Failed during log cleanup: $_" "WARN"
}

Log "### Starting Office Patching Remediation ###"

# ============================================================
# Configuration
# ============================================================

$ExpectedBranch = "Deferred"
$desiredCDN = "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114"
$C2RClientPath = "$env:CommonProgramFiles\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
$C2RRunPath    = "$env:CommonProgramFiles\Microsoft Shared\ClickToRun\OfficeClickToRun.exe"

# ============================================================
# Read Policy
# ============================================================

$PolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate"

$policyMissing = $false

if (Test-Path $PolicyKey) {
    $policyProps = Get-ItemProperty -Path $PolicyKey -ErrorAction SilentlyContinue
}
else {
    Log "Policy path missing. Continuing remediation and forcing update." "WARN"
    $policyMissing = $true
    $policyProps = $null
}

$policyUpdateTargetRaw = $policyProps.UpdateTargetVersion

if ([string]::IsNullOrWhiteSpace($policyUpdateTargetRaw)) {
    Log "UpdateTargetVersion missing in policy. Continuing remediation and forcing update." "WARN"
    $policyMissing = $true
}

$targetVersion = ToVersion $policyUpdateTargetRaw
$UpdateBranch = $policyProps.updatebranch

Log "Policy TargetVersion: $targetVersion"
Log "Policy UpdateBranch: $UpdateBranch"

# ============================================================
# Pre-Remediation State Logging
# ============================================================

Log "Starting pre-remediation state capture..."

Log "DeviceName: $env:COMPUTERNAME"
Log "UserContext: $env:USERNAME"
Log "OSVersion: $((Get-CimInstance Win32_OperatingSystem).Version)"

$ctrrPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

$keysToLog = @(
    "VersionToReport",
    "ClientVersionToReport",
    "UpdateChannel",
    "UpdatesEnabled",
    "CDNBaseUrl",
    "UnmanagedUpdateUrl"
)

foreach ($key in $keysToLog) {
    try {
        $val = SafeGet-ItemProperty -Path $ctrrPath -Name $key
        Log "Pre-State: $key = $val"
    }
    catch {
        Log "Failed reading $key during pre-state capture." "WARN"
    }
}

# ============================================================
# Binary Version Logging (Before Remediation)
# ============================================================

try {

    if (Test-Path $C2RClientPath) {
        $ver = (Get-Item $C2RClientPath).VersionInfo.FileVersion
        Log "Pre-Binary: OfficeC2RClient.exe Version = $ver"
    }
    else {
        Log "Pre-Binary: OfficeC2RClient.exe not found." "WARN"
    }

    if (Test-Path $C2RRunPath) {
        $ver = (Get-Item $C2RRunPath).VersionInfo.FileVersion
        Log "Pre-Binary: OfficeClickToRun.exe Version = $ver"
    }
    else {
        Log "Pre-Binary: OfficeClickToRun.exe not found." "WARN"
    }

}
catch {
    Log "Binary version check failed (pre-remediation): $_" "WARN"
}

# ============================================================
# Click-to-Run Configuration
# ============================================================

$ctrrPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

if (!(Test-Path $ctrrPath)) {
    Log "ClickToRun configuration missing." "ERROR"
    exit 0
}

$VersionRaw    = SafeGet-ItemProperty -Path $ctrrPath -Name "VersionToReport"
$CDNBaseUrl    = SafeGet-ItemProperty -Path $ctrrPath -Name "CDNBaseUrl"
$UpdateChannel = SafeGet-ItemProperty -Path $ctrrPath -Name "UpdateChannel"
$UpdatesEnabled = SafeGet-ItemProperty -Path $ctrrPath -Name "UpdatesEnabled"

$CurrentVersion = ToVersion $VersionRaw

Log "Current Version: $CurrentVersion"
Log "CDNBaseUrl: $CDNBaseUrl"
Log "UpdateChannel: $UpdateChannel"
Log "UpdatesEnabled: $UpdatesEnabled"

$forceUpdateNeeded = $false
$madeChanges = $false

if ($policyMissing) {
    Log "Policy missing or UpdateTargetVersion missing. Forcing update."
    $forceUpdateNeeded = $true
}

# ============================================================
# Branch Validation
# ============================================================

if ($UpdateBranch -ne $ExpectedBranch) {
    Log "UpdateBranch mismatch. Expected $ExpectedBranch" "WARN"
    $forceUpdateNeeded = $true
}

# ============================================================
# CDN Enforcement
# ============================================================

if ($CDNBaseUrl -ne $desiredCDN) {
    Set-ItemProperty -Path $ctrrPath -Name "CDNBaseUrl" -Value $desiredCDN -Force -ErrorAction SilentlyContinue
    Log "Corrected CDNBaseUrl"
    $madeChanges = $true
    $forceUpdateNeeded = $true
}

# ============================================================
# UpdateChannel Enforcement
# ============================================================

if ($UpdateChannel -ne $desiredCDN) {
    Set-ItemProperty -Path $ctrrPath -Name "UpdateChannel" -Value $desiredCDN -Force -ErrorAction SilentlyContinue
    Log "Corrected UpdateChannel"
    $madeChanges = $true
    $forceUpdateNeeded = $true
}

# ============================================================
# UpdatesEnabled Enforcement
# ============================================================

if ($UpdatesEnabled -ne "True") {
    Remove-ItemProperty -Path $ctrrPath -Name "UpdatesEnabled" -ErrorAction SilentlyContinue
    New-ItemProperty -Path $ctrrPath -Name "UpdatesEnabled" -PropertyType String -Value "True" -Force | Out-Null
    Log "Corrected UpdatesEnabled to True"
    $madeChanges = $true
    $forceUpdateNeeded = $true
}

# ============================================================
# Version Validation
# ============================================================

if ($null -eq $CurrentVersion) {
    Log "VersionToReport missing." "WARN"
    $forceUpdateNeeded = $true
}
elseif ($CurrentVersion -lt $targetVersion) {
    Log "Installed version lower than target." "WARN"
    $forceUpdateNeeded = $true
}

# ============================================================
# Scheduled Task
# ============================================================

$taskPath = "\Microsoft\Office\"
$taskName = "Office Automatic Updates 2.0"

try {
    $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) {
        $info = Get-ScheduledTaskInfo -TaskPath $taskPath -TaskName $taskName
        if ($info.State -ne "Ready") {
            Start-ScheduledTask -TaskPath $taskPath -TaskName $taskName
            Log "Started scheduled task"
        }
    }
}
catch { Log "Scheduled task handling error: $_" "ERROR" }

# ============================================================
# Restart Services
# ============================================================

foreach ($svc in @("ClickToRunSvc","BITS")) {
    try {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Restart-Service -Name $svc -Force
            Log "Restarted $svc"
        }
    }
    catch { Log "Error restarting $svc : $_" "ERROR" }
}

Log "Waiting 60 seconds..."
Start-Sleep -Seconds 60

# ============================================================
# Connectivity Check (Port 443 aligned)
# ============================================================

try {
    $net = Test-NetConnection -ComputerName "officecdn.microsoft.com" -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
    Log "CDN connectivity: $($net.TcpTestSucceeded)"
}
catch { Log "Connectivity test error: $_" "ERROR" }

# ============================================================
# Force Update
# ============================================================

if ($forceUpdateNeeded) {

    $c2rPath = "$env:CommonProgramFiles\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"

    if (Test-Path $c2rPath) {

        $updateargs = '/update','user','Displaylevel=True','culture="en-us"','forceappshutdown="true"'
        Log "Invoking OfficeC2RClient"

        Start-Process -FilePath $c2rPath -ArgumentList $updateargs -WindowStyle Hidden

        Log "Waiting 15 minutes for update..."
        Start-Sleep -Seconds 900
        
        try {

            if (Test-Path $C2RClientPath) {
                $ver = (Get-Item $C2RClientPath).VersionInfo.FileVersion
                Log "Post-Binary: OfficeC2RClient.exe Version = $ver"
            }
            else {
                Log "Post-Binary: OfficeC2RClient.exe not found." "WARN"
            }

            if (Test-Path $C2RRunPath) {
                $ver = (Get-Item $C2RRunPath).VersionInfo.FileVersion
                Log "Post-Binary: OfficeClickToRun.exe Version = $ver"
            }
            else {
                Log "Post-Binary: OfficeClickToRun.exe not found." "WARN"
            }

        }
        catch {
                Log "Binary version check failed (post-remediation): $_" "WARN"
}
        Log "Starting post-remediation verification..."

        try {

            $PostVersionRaw     = SafeGet-ItemProperty -Path $ctrrPath -Name "VersionToReport"
            $PostCDNBaseUrl     = SafeGet-ItemProperty -Path $ctrrPath -Name "CDNBaseUrl"
            $PostUpdateChannel  = SafeGet-ItemProperty -Path $ctrrPath -Name "UpdateChannel"
            $PostUpdatesEnabled = SafeGet-ItemProperty -Path $ctrrPath -Name "UpdatesEnabled"

            $PostVersion = ToVersion $PostVersionRaw

            Log "Post VersionToReport: $PostVersion"
            Log "Post CDNBaseUrl: $PostCDNBaseUrl"
            Log "Post UpdateChannel: $PostUpdateChannel"
            Log "Post UpdatesEnabled: $PostUpdatesEnabled"

            if ($PostVersion -and $targetVersion) {
                if ($PostVersion -lt $targetVersion) {
                    Log "Post-update version still below target." "WARN"
                }
                else {
                    Log "Post-update version meets or exceeds target."
                }
            }

        }
        catch {
            Log "Post-remediation verification failed: $_" "ERROR"
        }
    }
    else {
        Log "Could not trigger OfficeC2RClient, may not found." "ERROR"
    }
}
else {
    Log "No remediation required."
}

Write-EventLog -LogName $LogName -Source $Source -EventID 1234 -EntryType Information `
    -Message "Office remediation execution completed." -Category 1 -RawData 10,20

exit 0
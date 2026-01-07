<#
.SYNOPSIS
    Detection script to verify Outlook SHA256 registry settings.
.DESCRIPTION
    This script checks if the Outlook registry settings for SHA256 hashing are correctly configured.

    It verifies the following registry keys under the current user's context:
    - UseAlternateDefaultHashAlg (DWORD) = 1
    - DefaultHashOID (String) = "2.16.840.1.101
.NOTES
    It logs detection results to a hidden log file in ProgramData.
    Log file path: %ProgramData%\RegistryScript\registry_detect.log
    Log file name: registry_detect.log
.VERSION
    1.0
.AUTHOR
    Burhan Vejalpurwala
.FUNCTIONALITY
    Intune Detection Script
    Chaanges to SHA256 for Outlook MIME settings and provides detection for the same.
#>

# Detection Script for Outlook SHA256 Registry Key
$logDir = "$env:ProgramData\RegistryScript"
$logFile = Join-Path $logDir "registry_detect.log"
if (!(Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        attrib +h $logDir
    } catch {}
}

# Delete log files older than 2 days
Get-ChildItem -Path $logDir -Filter *.log -File -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-2)
} | Remove-Item -Force -ErrorAction SilentlyContinue

#logging function
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        Add-Content -Path $logFile -Value "$timestamp - $message"
    } catch {
        # Ignore logging errors
    }
}

#MainBlock
try {
    $session = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $session) {
        Write-Log "ERROR: No user is currently logged in."
        exit 1
    }

    Write-Log "Detected logged-on user: $session"

    $SID = (New-Object System.Security.Principal.NTAccount($session)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    Write-Log "Resolved SID: $SID"

    $regBasePath = "Registry::HKEY_USERS\$SID\Software\Policies\Microsoft\office\16.0\outlook\security"
    if (-not (Test-Path $regBasePath)) {
        Write-Log "Detection: Registry path does not exist."
        exit 1
    }

    $algVal = Get-ItemProperty -Path $regBasePath -Name "UseAlternateDefaultHashAlg" -ErrorAction SilentlyContinue
    $oidVal = Get-ItemProperty -Path $regBasePath -Name "DefaultHashOID" -ErrorAction SilentlyContinue

    if ($algVal.UseAlternateDefaultHashAlg -eq 1 -and $oidVal.DefaultHashOID -eq "2.16.840.1.101.3.4.2.1") {
        Write-Log "Detection: Registry values are correct."
        exit 0
    } else {
        Write-Log "Detection: Registry values are missing or incorrect."
        exit 1
    }
} catch {
    Write-Log "ERROR: $_"
    exit 1
}
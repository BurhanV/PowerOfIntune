<#
.SYNOPSIS
    Remediation script to set Outlook SHA256 registry keys for the logged-in user.
.DESCRIPTION
    This script sets the Outlook registry settings for SHA256 hashing under the current user's context.

    It configures the following registry keys:
    - UseAlternateDefaultHashAlg (DWORD) = 1
    - DefaultHashOID (String) = "2.16.840.1.101
.NOTES
    It logs remediation results to a hidden log file in ProgramData.
    Log file path: %ProgramData%\RegistryScript\registry_patch.log
    Log file name: registry_patch.log
.VERSION
    1.0
.AUTHOR
    Burhan Vejalpurwala
.FUNCTIONALITY
    Intune Remediation Script
    Changes to SHA256 for Outlook MIME settings and provides remediation for the same.
#>

# Remediation Script for Outlook SHA256 Registry Key
$logDir = "$env:ProgramData\RegistryScript"
$logFile = Join-Path $logDir "registry_patch.log"
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

#Main Script Logic
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
        New-Item -Path $regBasePath -Force | Out-Null
        Write-Log "Created registry path: $regBasePath"
    } else {
        Write-Log "Registry path already exists: $regBasePath"
    }

    # Set keys (Always remediate)
    New-ItemProperty -Path $regBasePath -Name "UseAlternateDefaultHashAlg" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $regBasePath -Name "DefaultHashOID" -Value "2.16.840.1.101.3.4.2.1" -PropertyType String -Force | Out-Null

    Write-Log "Remediation: Registry values set successfully."
    exit 0

} catch {
    Write-Log "ERROR: $_"
    exit 1
}
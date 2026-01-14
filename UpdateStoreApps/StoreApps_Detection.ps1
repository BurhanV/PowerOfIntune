<#
.SYNOPSIS
    Detection script for Intune Store Apps update compliance.
.DESCRIPTION
    This script checks if specific Microsoft Store codec apps are at or above baseline versions.
    If any codec is below the baseline version, the script exits with code 1 to trigger remediation.
.NOTES
    File StoreApps_Detection.ps1
    2024-06-10
    Version 1.0 
.Author
    Burhan Vejalpurwala
#>

$LogRoot = "C:\Users\Public\Documents\IntuneStoreCodecLogs" # Log directory
$LogFile = Join-Path $LogRoot "StoreApps_Detection.log" # Detection log file
$LogRetentionDays = 2 # Retain logs for 2 days

# Baseline versions for each codec package
$BaselineVersions = @{
    "Microsoft.RawImageExtension"     = [version]"2.3.0.0"
    "Microsoft.AV1VideoExtension"     = [version]"1.1.61781.0"
    "Microsoft.MPEG2VideoExtension"  = [version]"1.0.61931.0"
    "Microsoft.HEVCVideoExtension"   = [version]"2.0.61931.0"
    "Microsoft.VP9VideoExtensions"   = [version]"1.0.61931.0"
}

# Logging functions
function Initialize-Logging {
    if (!(Test-Path $LogRoot)) {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }

    Get-ChildItem -Path $LogRoot -Filter "StoreApps*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-Log {
    param ([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $Message" | Out-File -Append -Encoding utf8 -FilePath $LogFile
}

Initialize-Logging
Write-Log "Detection started"

# Check each codec package against baseline versions
foreach ($pkg in $BaselineVersions.Keys) {
    $app = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue

    if ($null -eq $app) {
        Write-Log "$pkg not installed – skipping"
        continue
    }

    Write-Log "$pkg detected version $($app.Version)"

    if ([version]$app.Version -lt $BaselineVersions[$pkg]) {
        Write-Log "$pkg below baseline $($BaselineVersions[$pkg]) – remediation required"
        exit 1
    }
}

# All codecs meet baseline
Write-Log "All detected codecs meet baseline"
exit 0

<#
.SYNOPSIS
Intune Proactive Remediation - Detection Script for End-of-Life .NET Components

.DESCRIPTION
    This detection script identifies EOL versions of Microsoft .NET components installed on Windows Devices. The script checks the system registry for the following products:
    - Microsoft ASP.Net Core
    - Microsoft Windows Desktop Runtime
    - Microsoft .NET Runtime
    - Microsoft .NET Core Runtime
    
    If any installed version is found to be below the specified minimum allowed version (8.0.18), the script will exit with a non-zero code, indicating that remediation is required.
    
.NOTES
No folder or registry deletion is performed in this detection script. It solely identifies non-compliant .NET versions.

.VERSION
    1.0
.AUTHOR
    Burhan Vejalpurwala
#>

# ================================
# Detection Script
# ================================

$MinimumAllowedVersion = [version]"8.0.18" # Define the minimum allowed .NET version

# Define target .NET products to check
$TargetProducts = @(
    "Microsoft ASP.NET Core",
    "Microsoft .NET Runtime",
    "Microsoft .NET Core Runtime",
    "Microsoft Windows Desktop Runtime"
)

# Define registry paths to check for installed applications
$UninstallRegistryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Setup logging
$LogFolder = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogFolder "Detect_DotNet_EoL.log"

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# Clean up old logs (older than 2 days)
Get-ChildItem -Path $LogFolder -Filter "*DotNet_EoL*.log" -File -ErrorAction SilentlyContinue |
Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-2)
} |
Remove-Item -Force -ErrorAction SilentlyContinue

# Log function
function Write-Log {
    param([string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] $Message" |
    Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Start detection
Write-Log "Detection started. Minimum allowed version: $MinimumAllowedVersion"

$Detected = @()

# Check each registry path for installed .NET products
foreach ($path in $UninstallRegistryPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {

        foreach ($product in $TargetProducts) {

            if ($_.DisplayName -like "$product*") {

                if ($_.DisplayName -match '(\d+\.\d+\.\d+)') {
                    $installedVersion = [version]$Matches[1]

                    if ($installedVersion -lt $MinimumAllowedVersion) {
                        Write-Log "Detected non-compliant: $($_.DisplayName) (Version $installedVersion)"
                        $Detected += $_
                    }
                }
            }
        }
    }
}

# Final evaluation
if ($Detected.Count -gt 0) {
    Write-Log "Non-compliant .NET components detected. Remediation required."
    exit 1
}
else {
    Write-Log "No non-compliant .NET components found. Device compliant."
    exit 0
}
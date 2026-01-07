<#
.SYNOPSIS
Intune Proactive Remediation - Removal of End-of-Life .NET Components

.DESCRIPTION
    This remediation script silently uninstalls specific EOL versions of Microsoft .NET components installed on Windows Devices. 
    The script checks the system registry for the following products:
    - Microsoft ASP.Net Core
    - Microsoft Windows Desktop Runtime
    - Microsoft .NET Runtime
    - Microsoft .NET Core Runtime

    Scripts relies exclusively on the registered uninstallString values from the Windows registry to ensure supported and vendor-defined removal behavior.

.NOTES
No folder or registry deletion is performed in this remediation script. It solely uninstalls non-compliant .NET versions.

.VERSION
    1.0

.AUTHOR
    Burhan Vejalpurwala
#>

# ================================
# Remediation Script
# ================================

$MinimumAllowedVersion = [version]"8.0.18" # Define the minimum allowed .NET version

# Define target .NET products to check
$TargetProducts = @(
    "Microsoft ASP.NET Core",
    "Microsoft .NET Runtime",
    "Microsoft .NET Core Runtime"
    "Microsoft Windows Desktop Runtime"
)

# Define registry paths to check for installed applications
$UninstallRegistryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Setup logging
$LogFolder = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogFolder "Remediate_DotNet_EoL.log"

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

# Start remediation
Write-Log "Remediation started. Minimum allowed version: $MinimumAllowedVersion"

$ToRemove = @()

# Check each registry path for installed .NET products
foreach ($path in $UninstallRegistryPaths) {
    Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {

        foreach ($product in $TargetProducts) {

            if ($_.DisplayName -like "$product*") {

                if ($_.DisplayName -match '(\d+\.\d+\.\d+)') {
                    $installedVersion = [version]$Matches[1]

                    if ($installedVersion -lt $MinimumAllowedVersion) {
                        $ToRemove += $_
                    }
                }
            }
        }
    }
}

# Final evaluation
if ($ToRemove.Count -eq 0) {
    Write-Log "No remediation required. Exiting."
    exit 0
}

# Proceed with uninstallation
foreach ($app in $ToRemove) {

    Write-Log "Uninstalling $($app.DisplayName)"

    $uninstallCmd = $app.UninstallString
    if (-not $uninstallCmd) {
        Write-Log "UninstallString missing. Skipping."
        continue
    }

    if ($uninstallCmd -match "msiexec") {
        $uninstallCmd += " /quiet /norestart" # MSI uninstallation flags
    }
    else {
        $uninstallCmd += " /quiet /norestart /silent" # Common flags for EXE uninstallers
    }
    
    Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c $uninstallCmd" `
        -WindowStyle Hidden `
        -Wait

    Write-Log "Uninstall completed for $($app.DisplayName)"
}

Write-Log "Remediation completed successfully."
exit 0
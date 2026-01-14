<#
.SYNOPSIS
    Remediation script for Intune Store Apps update compliance.
.DESCRIPTION
    This script attempts to remediate Microsoft Store codec apps that are below baseline versions
    by re-registering the Microsoft Store and triggering an update scan.
.NOTES
    File StoreApps_Remediation.ps1
    2024-06-10
    Version 1.0
.AUTHOR
    Burhan Vejalpurwala
#>

$LogRoot = "C:\Users\Public\Documents\IntuneStoreCodecLogs"
$LogFile = Join-Path $LogRoot "StoreApps_Remediation.log"
$LogRetentionDays = 2
$WaitSeconds = 120

$CodecPackages = @(
    "Microsoft.RawImageExtension",
    "Microsoft.AV1VideoExtension",
    "Microsoft.MPEG2VideoExtension",
    "Microsoft.HEVCVideoExtension",
    "Microsoft.VP9VideoExtensions"
)

function Initialize-Logging {
    if (!(Test-Path $LogRoot)) {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }

    Get-ChildItem -Path $LogRoot -Filter "StoreApps*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Logging function
function Write-Log {
    param ([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts | $Message" | Out-File -Append -Encoding utf8 -FilePath $LogFile
}

Initialize-Logging
Write-Log "Remediation started"

# Pre-update versions
Write-Log "Pre-update codec versions:"
foreach ($pkg in $CodecPackages) {
    $app = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue
    if ($app) {
        Write-Log "$pkg | $($app.Version)"
    } else {
        Write-Log "$pkg | NotInstalled"
    }
}

# Re-register Microsoft Store (repair only)
Write-Log "Re-registering Microsoft Store"
Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue |
    ForEach-Object {
        Add-AppxPackage -DisableDevelopmentMode `
                        -Register "$($_.InstallLocation)\AppXManifest.xml" `
                        -ErrorAction SilentlyContinue
    }

# Trigger Store update scan
try {
    $wmi = Get-WmiObject -Namespace "root\cimv2\mdm\dmmap" `
                        -Class "MDM_EnterpriseModernAppManagement_AppManagement01" `
                        -ErrorAction Stop

    $result = $wmi.UpdateScanMethod()
    Write-Log "UpdateScanMethod invoked. ReturnValue=$($result.ReturnValue)"
}
catch {
    Write-Log "Failed to invoke Store update scan: $_"
    exit 1
}

# Wait for async updates
Write-Log "Waiting $WaitSeconds seconds for Store updates"
Start-Sleep -Seconds $WaitSeconds

# Post-update versions
Write-Log "Post-update codec versions:"
foreach ($pkg in $CodecPackages) {
    $app = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue
    if ($app) {
        Write-Log "$pkg | $($app.Version)"
    } else {
        Write-Log "$pkg | NotInstalled"
    }
}

Write-Log "Remediation completed"
exit 0
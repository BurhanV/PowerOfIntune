<#
.SYNOPSIS
    Scans the C: drive for low storage conditions and identifies large files and folders.
.DESCRIPTION
    This script performs a full disk scan on the C: drive when free space is below a critical threshold.
    It logs the top 20 largest files and top 20 largest folders, excluding specified system directories.
.NOTES
    File StorageDetection.ps1
    2024-06-10
    Version 1.0
.AUTHOR
    Burhan Vejalpurwala
#>

# ==========================================================
# FULL DISK DISCOVERY WITH LOGGING
# ==========================================================

$ErrorActionPreference = "SilentlyContinue"

# -----------------------------
# CONFIGURATION
# -----------------------------

$TargetDrive = "C:\"

# Excluded root paths (edit if needed)
$ExcludedPaths = @(
    "C:\Windows"   # Remove if Windows folder must be scanned
)

# Scan trigger threshold
$CriticalFreeSpaceGB = 10 # GB

# Log path
$LogRoot = "C:\Users\Public"
$LogFolder = Join-Path $LogRoot "DiskScanLogs"

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DeviceName = $env:COMPUTERNAME
$LogFile = Join-Path $LogFolder "DiskScan_$DeviceName`_$Timestamp.log"

function Write-Log {
    param ([string]$Message)
    $Message | Tee-Object -FilePath $LogFile -Append
}

# -----------------------------
# DISK SUMMARY
# -----------------------------

$Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$FreeSpaceGB  = [math]::Round($Disk.FreeSpace / 1GB, 2)
$TotalSpaceGB = [math]::Round($Disk.Size / 1GB, 2)

Write-Log "================ DISK SUMMARY ================"
Write-Log "Device Name           : $DeviceName"
Write-Log "Total Disk Size (GB)  : $TotalSpaceGB"
Write-Log "Free Disk Space (GB)  : $FreeSpaceGB"
Write-Log "Scan Threshold (GB)   : $CriticalFreeSpaceGB"
Write-Log "=============================================="

if ($FreeSpaceGB -gt $CriticalFreeSpaceGB) {
    Write-Log "Free space above threshold. Full scan skipped."
    exit 0
}

Write-Log "CRITICAL DISK SPACE DETECTED. STARTING FULL SCAN."
Write-Log "Excluded Paths:"
$ExcludedPaths | ForEach-Object { Write-Log " - $_" }
Write-Log "----------------------------------------------"

# -----------------------------
# FILE ENUMERATION
# -----------------------------

Write-Log "Enumerating all files (hidden + system)..."

$AllFiles = Get-ChildItem -Path $TargetDrive -Recurse -File -Force |
Where-Object {
    foreach ($Exclude in $ExcludedPaths) {
        if ($_.FullName -like "$Exclude*") {
            return $false
        }
    }
    return $true
}

# -----------------------------
# TOP 20 LARGEST FILES
# -----------------------------

Write-Log "TOP 20 LARGEST FILES (GB):"

$AllFiles |
Sort-Object Length -Descending |
Select-Object -First 20 |
ForEach-Object {
    $SizeGB = [math]::Round($_.Length / 1GB, 2)
    Write-Log "$($_.FullName) | $SizeGB GB"
}

Write-Log "----------------------------------------------"

# -----------------------------
# FOLDER SIZE CALCULATION
# -----------------------------

Write-Log "Calculating folder sizes..."

$FolderSizes = $AllFiles |
Group-Object { Split-Path $_.FullName -Parent } |
ForEach-Object {
    [PSCustomObject]@{
        FolderPath = $_.Name
        SizeGB     = [math]::Round((
                        $_.Group | Measure-Object Length -Sum
                     ).Sum / 1GB, 2)
    }
}

# -----------------------------
# TOP 20 FOLDERS
# -----------------------------

Write-Log "TOP 20 FOLDERS BY SIZE (GB):"

$FolderSizes |
Sort-Object SizeGB -Descending |
Select-Object -First 20 |
ForEach-Object {
    Write-Log "$($_.FolderPath) | $($_.SizeGB) GB"
}

Write-Log "=============================================="
Write-Log "Disk scan completed successfully."
exit 0
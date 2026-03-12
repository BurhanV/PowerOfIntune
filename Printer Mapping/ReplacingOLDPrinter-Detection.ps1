# ============================
# Detection Script  || PrinterMapping 
# ============================

<#
.SYNOPSIS
    Detection script for verifying printer mappings on a device. It checks for the presence of old (decommissioned) printers and the absence of new printers.

.DESCRIPTION
    This script checks if any old (decommissioned) printers are still present on the device,
    and whether all new printers are mapped. If any old printers are found OR any new printers
    are missing, the script exits with code 1 to trigger remediation.
    It is intended to be used in an automated environment where detection and remediation are handled together, such as Intune.

.NOTES
    Author: Burhan Vejalpurwala
    Created On: 12/03/2026
    Last Modified: 12/03/2026
    Version: 1.0
    Script ID: PrinterMapping_Detection

.VersionHistory
    Version: 1.0
        Script creates logs and maps the printers to the device. It checks for the presence of old printers and the absence of new printers, logging the results and exiting with code 1 if remediation is needed.
#>

$ErrorActionPreference = 'Continue'

$OldPrinters = @(
    "\\OldPrintServer\PrinterName_1",
    "\\OldPrintServer\PrinterName_2"
)

$NewPrinters = @(
    "\\NewPrintServer\PrinterName_A",
    "\\NewPrintServer\PrinterName_B",
    "\\NewPrintServer\PrinterName_C"
)

# --- Logging Setup ---
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogDir = Join-Path $env:TEMP "PrinterLogs"

if (-not (Test-Path $LogDir)) {
    try {
        $null = New-Item -Path $LogDir -ItemType Directory -Force
    } catch {
        Write-Output "Failed to create log directory: $($_.Exception.Message)"
    }
}

# Delete log files older than 2 days
Get-ChildItem -Path $LogDir -Filter "PrinterDetection*.log" -File -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-2)
} | Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path $LogDir "PrinterDetection_$Timestamp.log"

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$level] - $msg"
    try { $line | Out-File -FilePath $LogFile -Append -Encoding UTF8 -Force } catch {}
}

Write-Log "Starting Detection Script..."

# Check Print Spooler status
try {
    $spooler = Get-Service -Name "Spooler" -ErrorAction Stop
    Write-Log "Spooler status: $($spooler.Status)"
} catch {
    Write-Log "Could not query Spooler service: $($_.Exception.Message)" "WARN"
}

# Enumerate all printers
$allPrinters = @()
try {
    $allPrinters = Get-Printer
} catch {
    Write-Log "Failed to enumerate printers: $($_.Exception.Message)" "ERROR"
}

$remediationNeeded = $false

# --- Check for OLD printers (any found = remediation needed) ---
Write-Log "--- Checking for OLD (decommissioned) printers ---"
foreach ($printer in $OldPrinters) {
    $found = $allPrinters | Where-Object { $_.Name -eq $printer -or $_.ShareName -eq $printer }
    if ($found) {
        Write-Log "OLD printer still present: $printer" "WARN"
        $remediationNeeded = $true
    } else {
        Write-Log "OLD printer not found (good): $printer"
    }
}

# --- Check for NEW printers (any missing = remediation needed) ---
Write-Log "--- Checking for NEW printers ---"
foreach ($printer in $NewPrinters) {
    $found = $allPrinters | Where-Object { $_.Name -eq $printer -or $_.ShareName -eq $printer }
    if ($found) {
        Write-Log "NEW printer present (good): $printer"
    } else {
        Write-Log "NEW printer missing: $printer" "WARN"
        $remediationNeeded = $true
    }
}

# --- Final Result ---
if (-not $remediationNeeded) {
    Write-Log "All old printers removed and all new printers are present. No remediation needed."
    exit 0
} else {
    Write-Log "Remediation needed: old printers still present and/or new printers are missing."
    exit 1
}
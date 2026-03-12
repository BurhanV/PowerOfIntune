# ============================
# Remediation Script  || PrinterMapping 
# ============================

<#
.SYNOPSIS
    Remediation script to remove old decommissioned printers and map new network printers.

.DESCRIPTION
    This script ensures the Print Spooler service is running, removes all old (decommissioned)
    printers, and maps all required new printers with retry logic. It is triggered by the
    detection script when old printers are found or new printers are missing.
    It is intended to be used in an automated environment where detection and remediation are handled together, such as Intune.

.NOTES
    Author: Burhan Vejalpurwala
    Created On: 12/03/2026
    Last Modified: 12/03/2026
    Version: 1.0
    Script ID:

.VersionHistory
    Version: 1.0
        Script creates logs and maps the printers while removing the old printers. 
        It includes retry logic for mapping printers and logs detailed information about any failures.
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
Get-ChildItem -Path $LogDir -Filter "PrinterRemediation*.log" -File -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-2)
} | Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path $LogDir "PrinterRemediation_$Timestamp.log"

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$level] - $msg"
    try { $line | Out-File -FilePath $LogFile -Append -Encoding UTF8 -Force } catch {}
}

Write-Log "Starting Remediation Script..."

# PrintService Event Log Helper
function Log-PrintServiceEvents {
    try {
        $events = Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Admin' -MaxEvents 10 |
            Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-10) }
        foreach ($event in $events) {
            Write-Log "PrintService Event [$($event.TimeCreated)]: $($event.Message)" "WARN"
        }
    } catch {
        Write-Log "Failed to query PrintService event log: $($_.Exception.Message)" "WARN"
    }
}

# --- Step 1: Check and start Print Spooler ---
try {
    $spooler = Get-Service -Name "Spooler" -ErrorAction Stop
    Write-Log "Spooler status: $($spooler.Status)"

    if ($spooler.Status -ne 'Running') {
        Write-Log "Print Spooler is not running. Attempting to start the service..." "WARN"
        try {
            Start-Service -Name "Spooler" -ErrorAction Stop
            Write-Log "Print Spooler service started successfully."
        } catch {
            Write-Log "Failed to start Print Spooler service: $($_.Exception.Message)" "ERROR"
        }
    }
} catch {
    Write-Log "Could not query Spooler service: $($_.Exception.Message)" "WARN"
    try {
        Write-Log "Attempting to start Print Spooler service..." "WARN"
        Start-Service -Name "Spooler" -ErrorAction Stop
        Write-Log "Print Spooler service started successfully."
    } catch {
        Write-Log "Failed to start Print Spooler service: $($_.Exception.Message)" "ERROR"
    }
}

# --- Step 2: Enumerate current printers ---
$allPrinters = @()
try {
    $allPrinters = Get-Printer
    Write-Log "Enumerated $($allPrinters.Count) printer(s) on this device."
} catch {
    Write-Log "Failed to enumerate printers: $($_.Exception.Message)" "ERROR"
}

# --- Step 3: Remove OLD printers ---
Write-Log "--- Removing OLD (decommissioned) printers ---"
foreach ($printer in $OldPrinters) {
    $found = $allPrinters | Where-Object { $_.Name -eq $printer -or $_.ShareName -eq $printer }
    if ($found) {
        Write-Log "Removing old printer: $printer"
        try {
            Remove-Printer -Name $printer -ErrorAction Stop
            Write-Log "Successfully removed: $printer"
        } catch {
            Write-Log "Failed to remove $printer : $($_.Exception.Message)" "ERROR"
            if ($_.Exception.InnerException) {
                Write-Log "InnerException: $($_.Exception.InnerException.Message)" "ERROR"
            }
        }
    } else {
        Write-Log "Old printer not present on device, skipping: $printer"
    }
}

# --- Step 4: Map NEW printers with retry logic ---
function Install-PrinterWithRetry {
    param (
        [string]$PrinterPath,
        [int]$Retries = 3,
        [int]$DelaySeconds = 15
    )
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Write-Log "Attempt $i : Installing $PrinterPath"
            Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop
            Start-Sleep -Seconds 20
            $installed = Get-Printer | Where-Object { $_.Name -eq $PrinterPath -or $_.ShareName -eq $PrinterPath }
            if ($installed) {
                Write-Log "$PrinterPath successfully installed."
                return $true
            }
        } catch {
            Write-Log "$PrinterPath install failed on attempt $i : $($_.Exception.Message)" "WARN"
            if ($_.Exception.InnerException) {
                Write-Log "InnerException: $($_.Exception.InnerException.Message)" "WARN"
            }
            if ($_.ErrorRecord) {
                Write-Log "ErrorRecord: $($_.ErrorRecord | Out-String)" "WARN"
            }
            Write-Log "Full Exception: $($_.Exception | Format-List * | Out-String)" "WARN"
            Log-PrintServiceEvents
        }
        if ($i -lt $Retries) {
            Write-Log "Retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    Write-Log "$PrinterPath failed to install after $Retries attempts." "ERROR"
    return $false
}

Write-Log "--- Mapping NEW printers ---"
$successCount = 0
foreach ($printer in $NewPrinters) {
    # Skip if already installed (safe re-run behaviour)
    $alreadyMapped = Get-Printer | Where-Object { $_.Name -eq $printer -or $_.ShareName -eq $printer }
    if ($alreadyMapped) {
        Write-Log "$printer is already mapped. Skipping."
        $successCount++
        continue
    }
    $result = Install-PrinterWithRetry -PrinterPath $printer
    if ($result) { $successCount++ }
}

# --- Final Result ---
if ($successCount -eq $NewPrinters.Count) {
    Write-Log "All new printers successfully mapped."
    exit 0
} else {
    Write-Log "Remediation completed with errors. Mapped $successCount of $($NewPrinters.Count) new printers." "ERROR"
    exit 1
}
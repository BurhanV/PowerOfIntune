<#
.SYNOPSIS
    Remediation script to install specified network printers with retry logic and detailed logging.
.DESCRIPTION
    This script attempts to install a list of specified network printers.
    It includes retry logic, detailed error logging, and checks the Print Spooler
    service status before attempting installations.
.AUTHOR
    Burhan Vejalpurwala
.VERSION
    1.0.0
.NOTES
    Ensure to customize the $PrintersToMap array with the actual printer names.
#>

#Requires -Version 5.1 || higher
#Requires -Modules PrintManagement

# --- Configuration ---
$ErrorActionPreference = 'Continue'
$PrintersToMap = @(
    "\\print_servername\printername_1",
    "\\print_servername\printername_2"
)

# --- Logging Setup ---
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogDir = Join-Path $env:LOCALAPPDATA "Microsoft\PrinterLogs" # Log directory
if (-not (Test-Path $LogDir)) {
    try {
        $null = New-Item -Path $LogDir -ItemType Directory -Force
        (Get-Item $LogDir).Attributes = 'Hidden' # Hide the log directory from casual view
    } catch {}
}

# Delete log files older than 2 days | This is done to prevent unwanted disk space utilization
Get-ChildItem -Path $LogDir -Filter *.log -File -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-2)
} | Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path $LogDir "Remediation_$Timestamp.log" # Log file name
function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$level] - $msg"
    try { $line | Out-File -FilePath $LogFile -Append -Encoding UTF8 -Force } catch {}
}

Write-Log "Starting Remediation Script..."

# PrintService Event Log Helper
function PrintServiceEvents {
    try {
        $events = Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Admin' -MaxEvents 10 |
            Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-10) }
        foreach ($foundevent in $events) {
            Write-Log "PrintService Event [$($foundevent.TimeCreated)]: $($foundevent.Message)" "WARN"
        }
    } catch {
        Write-Log "Failed to query PrintService event log: $($_.Exception.Message)" "WARN"
    }
}

# Check Print Spooler status
try {
    $spooler = Get-Service -Name "Spooler" -ErrorAction Stop
    Write-Log "Spooler status: $($spooler.Status)"
    if ($spooler.Status -ne 'Running') {
        Write-Log "Print Spooler is not running. Printer installation may fail." "WARN"
        # Continue script execution
    }
} catch {
    Write-Log "Could not query Spooler service: $($_.Exception.Message)" "WARN"
    # Continue script execution
}

# Function to install printer with retry and detailed error logging
function Install-PrinterWithRetry {
    param (
        [string]$PrinterPath,
        [int]$Retries = 3,
        [int]$DelaySeconds = 15
    )
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Write-Log "Attempt $i : Installing $PrinterPath"
            try { Remove-Printer -Name $PrinterPath -ErrorAction SilentlyContinue } catch {}
            Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop
            Start-Sleep -Seconds 5
            $installed = Get-Printer | Where-Object { $_.Name -eq $PrinterPath -or $_.ShareName -eq $PrinterPath }
            # Also check for user-mapped printers in the registry
            if ($null -eq $installed) {
                $connKeys = Get-ChildItem "HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PrinterPorts" -ErrorAction SilentlyContinue
                if ($connKeys) {
                    foreach ($key in $connKeys) {
                        if ($key.PSChildName -replace '^,,','\\' -replace ',','\' -eq $PrinterPath) {
                            $installed = $true
                            break
                        }
                    }
                }
            }
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
            # Log recent PrintService event log entries for troubleshooting
            PrintServiceEvents
        }
        if ($i -lt $Retries) {
            Write-Log "Retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    Write-Log "$PrinterPath failed to install after $Retries attempts." "ERROR"
    return $false
}

# Install each printer with retry logic
$successCount = 0
foreach ($printer in $PrintersToMap) {
    $result = Install-PrinterWithRetry -PrinterPath $printer
    if ($result) { $successCount++ }
}

# --- Final Result ---
if ($successCount -eq $PrintersToMap.Count) {
    Write-Log "All printers successfully installed."
    exit 0
} else {
    Write-Log "Remediation completed with errors. Installed $successCount of $($PrintersToMap.Count) printers." "ERROR"
    exit 1
}
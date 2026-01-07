<#
.SYNOPSIS
    Detection script to verify if required printers are installed.
.DESCRIPTION
    This script checks for the presence of specific printers on the system.
    It logs the results and exits with code 0 if all printers are found, or
    exit code 1 if any are missing. Makes it Intune compatible.
.AUTHOR
    Burhan Vejalpurwala
.VERSION
    1.0.0
.NOTES
    Ensure to customize the $PrintersExpected array with the actual printer names.
#>

#Requires -Version 5.1 || higher
#Requires -Modules PrintManagement

# --- Configuration ---
$ErrorActionPreference = 'Continue' # Continue on errors
$PrintersExpected = @(
    "\\print_servername\printername_1",
    "\\print_servername\printername_2"
)

# --- Logging ---
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogDir = Join-Path $env:LOCALAPPDATA "Microsoft\PrinterLogs" # Log directory | Can be customized
if (-not (Test-Path $LogDir)) {
    try {
        $null = New-Item -Path $LogDir -ItemType Directory -Force
        (Get-Item $LogDir).Attributes = 'Hidden' # Hide the log directory from casual view
    } catch {}
}

# Clean up old logs (older than 2 days)
Get-ChildItem -Path $LogDir -Filter *.log -File -ErrorAction SilentlyContinue | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-2)
} | Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path $LogDir "Detection_$Timestamp.log" # Log file name

# --- Functions ---
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

# Check each printer
$allPresent = $true
try {
    $allPrinters = Get-Printer
} catch {
    Write-Log "Failed to enumerate printers: $($_.Exception.Message)" "ERROR"
    $allPresent = $false
    $allPrinters = @()
}

# Iterate through expected printers and check if they are installed
foreach ($printer in $PrintersExpected) {
    $found = $false
    if ($allPrinters) {
        $found = $allPrinters | Where-Object { $_.Name -eq $printer -or $_.ShareName -eq $printer }
    }
    # If not found in native printer list, check registry for user context mapping
    if (-not $found) {
        $connKeys = Get-ChildItem "HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PrinterPorts" -ErrorAction SilentlyContinue
        if ($connKeys) {
            foreach ($key in $connKeys) {
                if ($key.PSChildName -replace '^,,','\\' -replace ',','\' -eq $printer) {
                    $found = $true
                    break
                }
            }
        }
    #If - similarly can also check this registry path "HKCU:\Printers\Connections"
    }

    if ($found) {
        Write-Log "Installed: $printer"
    } else {
        Write-Log "Missing: $printer" "ERROR"
        $allPresent = $false
    }
}
# --- Final Result ---
if ($allPresent) {
    Write-Log "All required printers are installed."
    exit 0 #no remediation needed
} else {
    Write-Log "One or more printers are missing. Remediation needed."
    exit 1 #remediation needed
}
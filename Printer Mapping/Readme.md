# Printer Mapping Scripts for Intune
## Overview
This directory contains PowerShell scripts for automated printer deployment and management via Microsoft Intune. The solution includes detection and remediation scripts that work together to ensure required network printers are installed on target devices.

---

## Files

### `PrinterMapping_Detection.ps1`
Detects whether required printers are installed on the system.

**Features:**
- Checks for printer presence via `Get-Printer` cmdlet
- Falls back to registry checks for user-context mappings
- Validates Print Spooler service status
- Returns exit code 0 if all printers found, 1 if any are missing

### `PrinterMapping_Remediation.ps1`
Installs missing printers with retry logic and comprehensive error handling.

**Features:**
- Automatic retry mechanism (default: 3 attempts, 15-second intervals)
- Print Spooler service validation
- Detailed logging with cleanup (removes logs older than 2 days)
- Handles both system and user-context printer mappings
- Queries PrintService event log for troubleshooting

---

### `ReplacingOLDPrinter-Detection.ps1`
Detects whether old (decommissioned) printers are still present on the device and whether new printers are mapped.

**Features:**
- Checks for presence of old printers via `Get-Printer` cmdlet
- Checks for presence of new printers via `Get-Printer` cmdlet
- Validates Print Spooler service status
- Returns exit code 1 if any old printers are found OR if any new printers are missing
- Returns exit code 0 only when all old printers are removed AND all new printers are present

### `ReplacingOLDPrinter-Remediation.ps1`
Removes decommissioned printers and maps new network printers with retry logic and comprehensive error handling.

**Features:**
- Ensures Print Spooler service is running before proceeding (starts it if stopped)
- Removes all old (decommissioned) printers found on the device
- Maps all required new printers with automatic retry mechanism (default: 3 attempts, 15-second intervals)
- Skips new printers already mapped (safe to re-run)
- Detailed logging with cleanup (removes logs older than 2 days)
- Queries PrintService event log for troubleshooting

---

## Configuration

### `PrinterMapping_Detection.ps1` / `PrinterMapping_Remediation.ps1`
Edit the printer array in both scripts:
```powershell
$PrintersExpected = @(
    "\\print_servername\printername_1",
    "\\print_servername\printername_2"
)
```

### `ReplacingOLDPrinter-Detection.ps1` / `ReplacingOLDPrinter-Remediation.ps1`
Edit both arrays in both scripts:
```powershell
$OldPrinters = @(
    "\\OldPrintServer\PrinterName_1",
    "\\OldPrintServer\PrinterName_2"
)

$NewPrinters = @(
    "\\NewPrintServer\PrinterName_A",
    "\\NewPrintServer\PrinterName_B",
    "\\NewPrintServer\PrinterName_C"
)
```

> **Note:** Ensure `$OldPrinters` and `$NewPrinters` arrays are kept identical across the detection and remediation scripts.

---

## Logging
### `PrinterMapping_Detection.ps1` / `PrinterMapping_Remediation.ps1`
Logs are stored in: `%LOCALAPPDATA%\Microsoft\PrinterLogs\`
- Detection logs: `Detection_yyyyMMdd_HHmmss.log`
- Remediation logs: `Remediation_yyyyMMdd_HHmmss.log`

### `ReplacingOLDPrinter-Detection.ps1` / `ReplacingOLDPrinter-Remediation.ps1`
Logs are stored in: `%TEMP%\PrinterLogs\`
- Detection logs: `PrinterDetection_yyyyMMdd_HHmmss.log`
- Remediation logs: `PrinterRemediation_yyyyMMdd_HHmmss.log`

---

## Intune Deployment
1. **Detection Script:** Assign as detection rule
2. **Remediation Script:** Assign as remediation rule
3. Set remediation schedule as needed
4. Scripts are deployed and executed in **user context**

---

## Requirements
- PowerShell 5.1 or higher
- PrintManagement module
- Network printer server accessibility

---

**Author:** Burhan Vejalpurwala  
**Version:** 2.0
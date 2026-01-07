
# Printer Mapping Scripts for Intune

## Overview

This directory contains PowerShell scripts for automated printer deployment and management via Microsoft Intune. The solution includes detection and remediation scripts that work together to ensure required network printers are installed on target devices.

## Files

### `PrinterMapping_Detection.ps1`
Detects whether required printers are installed on the system.

**Features:**
- Checks for printer presence via `Get-Printer` cmdlet
- Falls back to registry checks for user-context mappings
- Validates Print Spooler service status
- Returns exit code 0 if all printers found, 1 if missing

### `PrinterMapping_Remediation.ps1`
Installs missing printers with retry logic and comprehensive error handling.

**Features:**
- Automatic retry mechanism (default: 3 attempts, 15-second intervals)
- Print Spooler service validation
- Detailed logging with cleanup (removes logs older than 2 days)
- Handles both system and user-context printer mappings
- Queries PrintService event log for troubleshooting

## Configuration

Edit the printer arrays in both scripts:

```powershell
$PrintersToMap = @(
    "\\print_servername\printername_1",
    "\\print_servername\printername_2"
)
```

## Logging

Logs are stored in: `%LOCALAPPDATA%\Microsoft\PrinterLogs\`

- Detection logs: `Detection_yyyyMMdd_HHmmss.log`
- Remediation logs: `Remediation_yyyyMMdd_HHmmss.log`

## Intune Deployment

1. **Detection Script:** Assign as detection rule
2. **Remediation Script:** Assign as remediation rule
3. Set remediation schedule as needed

## Requirements

- PowerShell 5.1 or higher
- PrintManagement module
- Network printer server accessibility

---

**Author:** Burhan Vejalpurwala  
**Version:** 1.0.0

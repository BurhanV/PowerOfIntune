
# Outlook S/MIME SHA256 Configuration

## Overview
This repository contains Intune detection and remediation scripts for configuring Outlook S/MIME to use SHA256 hashing algorithm.

## Prerequisites

### System Requirements
- Windows 10 or later
- Microsoft Outlook 2016 or later (Office 16.0+)
- PowerShell 3.0 or higher
- Administrator privileges to modify registry settings | Only need this if you are testing or modifying it manually. #caveat1
- Devices should be managed via Intune or workload shifted to Intune

### Permissions Required
- Local Administrator access on the device #caveat1
- Read/Write access to `HKEY_USERS` registry hive #caveat1
- Access to `%ProgramData%\RegistryScript\` directory for logging
- Should be Intune Admin or relevant RBACs required to import scripts.

### Dependencies
- No external PowerShell modules required
- Scripts run in system context via Intune Proactive Remediation

## Files

### Detection_OutlookS:MIME.ps1
Verification script that checks if Outlook registry settings for SHA256 hashing are correctly configured.

**Checks:**
- `UseAlternateDefaultHashAlg` (DWORD) = 1
- `DefaultHashOID` (String) = "2.16.840.1.101.3.4.2.1"

**Registry Path:** `HKEY_USERS\<SID>\Software\Policies\Microsoft\office\16.0\outlook\security`

**Logging:** Logs to `%ProgramData%\RegistryScript\registry_detect.log`

### Remediation_OutlookS:MIME.ps1
Configuration script that sets Outlook registry settings for SHA256 hashing under the current user's context.

**Applies:**
- `UseAlternateDefaultHashAlg` = 1
- `DefaultHashOID` = "2.16.840.1.101.3.4.2.1"

**Logging:** Logs to `%ProgramData%\RegistryScript\registry_patch.log`

## Usage

Deploy both scripts as an Intune Proactive Remediation:
1. Use Detection script to identify non-compliant devices
2. Use Remediation script to apply configuration

### Deployment via Intune Proactive Remediation

1. **Sign in to Intune Admin Center**
   - Navigate to `Devices` > `Scripts & Remediations`

2. **Create a New Remediation**
   - Under `Remediations` Click `Create`
   - Provide a descriptive name (e.g., "Outlook S/MIME SHA256 Configuration")

3. **Upload Detection Script**
   - Import `Detection_OutlookS:MIME.ps1`

4. **Upload Remediation Script**
   - Import `Remediation_OutlookS:MIME.ps1`
   - Set `Run this script using the logged-in credentials` to **No**
   - Set `Run script in 64-bit PowerShell` based on your environment - ideally **Yes**

5. **Configure Run Schedule**
   - Set frequency (recommended: Daily)
   - Filters (if applicable)

6. **Assign to Groups**
   - Assign to Azure AD groups containing devices requiring S/MIME SHA256 configuration
   - Review and create the remediation

### Manual Execution (Testing)

To test the scripts manually before deployment:

```powershell
# Run detection script
.\Detection_OutlookS:MIME.ps1

# Run remediation script (if needed)
.\Remediation_OutlookS:MIME.ps1
```

### Monitoring & Troubleshooting

**View Log Files:**
- Detection logs: `%ProgramData%\RegistryScript\registry_detect.log`
- Remediation logs: `%ProgramData%\RegistryScript\registry_patch.log`

**Check Script Status in Intune:**
1. Navigate to `Devices` > `All Devices` > Select device
2. Go to `Proactive remediations`
3. Review the status and details of the remediation


## What This Configuration Does

SHA256 is a more secure hashing algorithm compared to older alternatives. This configuration:
- Ensures Outlook uses SHA256 for S/MIME signature operations
- Enhances security for email signature verification
- Maintains compliance with security standards requiring stronger cryptographic algorithms

## Author
Burhan Vejalpurwala

## Version
1.0

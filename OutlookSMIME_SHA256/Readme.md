
# Outlook S/MIME SHA256 Configuration

## Overview
This repository contains Intune detection and remediation scripts for configuring Outlook S/MIME to use SHA256 hashing algorithm.

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

## Author
Burhan Vejalpurwala

## Version
1.0


# .NET End-of-Life Component Removal

Intune Proactive Remediation scripts for detecting and removing end-of-life .NET components from Windows devices.

## Overview

This solution provides automated detection and remediation of outdated .NET installations that fall below the minimum supported version (8.0.18). The scripts leverage Intune's Proactive Remediation feature to maintain .NET compliance across your device fleet.

## Scripts

### Detection Script (`DotNetRemoval_Detection.ps1`)

**Purpose:** Identifies non-compliant .NET installations without making changes.

**Behavior:**
- Scans `HKLM` registry for installed .NET products
- Compares installed versions against minimum allowed version (8.0.18)
- Logs findings to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Detect_DotNet_EoL.log`
- Exits with code `1` if non-compliant versions found, `0` if compliant

**Monitored Products:**
- Microsoft ASP.NET Core
- Microsoft .NET Runtime
- Microsoft .NET Core Runtime
- Microsoft Windows Desktop Runtime

### Remediation Script (`DotNetRemoval_Remediation.ps1`)

**Purpose:** Silently uninstalls non-compliant .NET versions using vendor-supplied uninstall strings.

**Behavior:**
- Executes only if detection script returns exit code `1`
- Invokes native MSI/EXE uninstallers with `/quiet /norestart` flags
- Logs all uninstall operations
- Exits with code `0` upon completion

## Requirements

- Windows 10/11
- PowerShell 5.0+
- Administrator privileges
- Intune enrollment with Proactive Remediation capability

## Configuration

### Minimum Version Threshold

Edit the `$MinimumAllowedVersion` variable in both scripts:

```powershell
$MinimumAllowedVersion = [version]"8.0.18"
```

## Logging

Logs are written to: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`

**Files:**
- `Detect_DotNet_EoL.log` — Detection results
- `Remediate_DotNet_EoL.log` — Remediation operations

Logs older than 2 days are automatically purged.

## Deployment

1. Create new Proactive Remediation in Intune
2. Assign detection script
3. Assign remediation script
4. Configure assignment and schedule

## Notes

- No registry keys are deleted; only vendor uninstallers are invoked
- May require system restart for some .NET components (post-remediation)
- Test in pilot group before fleet-wide deployment

## Author

Burhan Vejalpurwala

---

**Version:** 1.0

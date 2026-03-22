# Microsoft 365 Office Patching - Intune Proactive Remediation

## Overview

This solution provides automated detection and remediation for Microsoft 365 Apps (Click-to-Run) patch compliance through Intune's Proactive Remediation feature. It ensures devices maintain the organizational target version and are properly configured for automatic updates.

The two-script approach follows Intune's proactive remediation pattern:
- **Detection Script**: Identifies non-compliant devices
- **Remediation Script**: Automatically fixes compliance issues

---

## Script Descriptions

### OfficePatching_Detection.ps1

**Purpose**: Evaluates whether Microsoft 365 Apps meet organizational patching requirements.

**Exit Codes**:
- `0` = Compliant (no remediation needed)
- `1` = Non-Compliant (remediation required)

**Compliance Checks**:
- Office Update policy settings presence
- UpdateTargetVersion policy configuration
- Update branch alignment with expected channel
- CDN configuration for Click-to-Run
- UpdateChannel configuration
- UpdatesEnabled state
- Installed Office version vs. target version
- Scheduled task status for Office Automatic Updates
- Network connectivity to Microsoft Office CDN
- Binary presence and versions of core Click-to-Run components

**Logging**: `C:\ProgramData\Scripts\OfficePatching-Detection-<timestamp>.log`

---

### OfficePatching_Remediation.ps1

**Purpose**: Enforces Microsoft 365 Apps update configuration and triggers updates when necessary.

**Remediation Actions**:
- Captures pre-remediation system state
- Validates Office Click-to-Run configuration
- Corrects CDNBaseUrl and UpdateChannel settings (set to Semi-Annual Enterprise Channel)
- Ensures UpdatesEnabled is properly configured
- Validates update branch configuration
- Restarts relevant services (ClickToRunSvc and BITS)
- Ensures Office Automatic Updates scheduled task is running
- Tests connectivity to Microsoft Office CDN
- Forces an Office update using OfficeC2RClient when required
- Captures post-remediation configuration state
- Logs binary versions before and after remediation

**Logging**: `C:\ProgramData\Scripts\OfficePatching-Remediation-<timestamp>.log`

**Note**: This script is idempotent and safe to run repeatedly.

---

## Deployment Instructions

### Prerequisites

- Intune Tenant access with rights to create Proactive Remediations
- Devices must have Microsoft 365 Apps (Click-to-Run) installed
- PowerShell 5.0 or higher
- Script runs in system context, as registry changes require admin rights.

### Deployment Steps

#### 1. Deploy Detection and Remediation Scripts

1. In [Intune admin center](https://aka.ms/intuneportal), navigate to:
   - **Devices** > **Scripts and remediations** > **Proactive remediations**

2. Click **Create**

3. Configure the following:
   - **Name**: `Microsoft 365 Patching - Detection`
   - **Description**: Detects Microsoft 365 Apps patch compliance
   - **Publisher**: Your organization
   - **Script category**: `Microsoft Office Updates`

4. Under **Settings**:
   - **Run this script using the logged-in credentials**: `No`
   - **Enforce script signature check**: `No` (unless you sign the script)
   - **Run script in 64-bit PowerShell Host**: `Yes`

5. In **Detection script**, copy and paste the full content of `OfficePatching_Detection.ps1`

5. In **Remediation script**, Copy and paste the full content of `OfficePatching_Remediation.ps1`

6. Click **Next** and verify your device assignments (Mostly targeted at device level).

7. Click **Save**

---

## Monitoring and Troubleshooting

### View Remediation Status in Intune

1. **Devices** > **Scripts and remediations** > **Proactive remediations**
2. Select **Microsoft 365 Patching - Detection**
3. View the **Overview** tab for device compliance status
4. Click individual devices for detailed execution logs

### Check Logs on Device

Logs are stored locally on device:
- Detection Log: `C:\ProgramData\Scripts\OfficePatching-Detection-<timestamp>.log`
- Remediation Log: `C:\ProgramData\Scripts\OfficePatching-Remediation-<timestamp>.log`

**Access logs via PowerShell**:
```powershell
# View most recent detection log
Get-ChildItem -Path "C:\ProgramData\Scripts" -Filter "OfficePatching-Detection-*.log" -ErrorAction SilentlyContinue | 
Sort-Object CreationTime -Descending | 
Select-Object -First 1 | 
Get-Content

# View most recent remediation log
Get-ChildItem -Path "C:\ProgramData\Scripts" -Filter "OfficePatching-Remediation-*.log" -ErrorAction SilentlyContinue | 
Sort-Object CreationTime -Descending | 
Select-Object -First 1 | 
Get-Content
```

## Configuration Notes

### Update Channel Configuration

The remediation script is configured to enforce the **Semi-Annual Enterprise Channel**. To modify this:

1. Edit `OfficePatching_Remediation.ps1`
2. Locate the CDNBaseUrl and UpdateChannel settings
3. Modify the channel values according to your organization's policy

**Available Channels**:
- Semi-Annual Enterprise Channel (SEMB)
- Current Channel (CMR)
- Monthly Enterprise Channel (MEAC)

### Log Retention

Both scripts automatically clean up log files older than **2 days** to prevent disk space issues.

To adjust retention period, modify the cleanup logic in both scripts.

---

## Manual Testing

### Test Detection Script

```powershell
# Run detection script manually
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\path\to\OfficePatching_Detection.ps1"

# Check exit code
$LASTEXITCODE
```

### Test Remediation Script

```powershell
# Run remediation script manually
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\path\to\OfficePatching_Remediation.ps1"
```

---

## Technical Details

### Event Logging

Both scripts create Windows Event Log entries for auditing:
- Detection Script Source: `OfficePatchingDetectionScript`
- Remediation Script Source: `OfficePatchingRemediationScript`
- Log Name: `OfficePatchingDetection` and `OfficePatchingRemediation`

### Services and Tasks

Scripts interact with the following:
- **Service**: `ClickToRunSvc` (Office Click-to-Run Service)
- **Service**: `BITS` (Background Intelligent Transfer Service)
- **Scheduled Task**: Office Automatic Updates task
- **Binary**: `OfficeC2RClient.exe` (Click-to-Run Client)

### API References

- [Microsoft 365 Apps Update Channels Overview](https://learn.microsoft.com/deployoffice/updates/overview-update-channels)
- [Update Target Version for Microsoft 365 Apps](https://learn.microsoft.com/deployoffice/updates/update-target-version)

---

## Author & Version

- **Author**: Burhan Vejalpurwala
- **Version**: 1.0
- **Created**: March 2026
- **Purpose**: Intune Proactive Remediation for Microsoft 365 Apps Patch Compliance

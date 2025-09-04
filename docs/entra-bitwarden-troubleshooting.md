# Microsoft Entra ID and Bitwarden SSO Troubleshooting Guide

## Problem Description

Issues connecting Bitwarden Enterprise with Microsoft Entra ID for SSO using dan@allgrid.com.

## Account Verification Results

**Account Found:**

- Display Name: Dan Solberg
- UserPrincipalName: dan@allgrid.com
- Object ID: c8e41818-f402-4096-a5a0-66f8d0bc4520
- Assigned Licenses:
    - POWER_BI_STANDARD
    - Microsoft_Entra_Suite
    - FLOW_FREE
    - SPB (Microsoft 365 Business Premium)
    - Microsoft_365_Copilot
    - POWERAPPS_DEV

**Note:** No duplicate/ghost accounts detected for dan@allgrid.com.

## Application Registration Results

**Enterprise Application Found:**

- Display Name: Bitwarden SSO
- App ID: ab79eb4f-82da-436b-a8bb-6b193f3e800d
- Object ID: e4bcc967-f8f9-4d81-9067-2b03fd159c7d

**App Registration Found:**

- Display Name: Bitwarden SSO
- App ID: ab79eb4f-82da-436b-a8bb-6b193f3e800d
- Object ID: 53d8b496-fbd1-43d2-a435-889625a00b8b
- Redirect URIs:
    - http://localhost:3000
    - http://localhost:8080
    - http://localhost:50627
    - https://bitwarden.com
    - bitwarden://sso-callback
    - https://vault.bitwarden.com
    - https://vault.bitwarden.com/#/sso

## Verification Steps

### Microsoft Entra ID (Azure AD)

1. Log into [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to "Users" section
3. Search for "dan@allgrid.com"
4. Check if multiple accounts exist for this email
5. Verify correct Business Premium license is assigned
6. Check for any conflicting directory objects

### Check Application Registration

1. In Microsoft Entra admin center, go to "App registrations"
2. Look for any Bitwarden-related applications
3. Verify the correct redirect URIs and permissions

### Bitwarden Configuration

1. Log into Bitwarden admin portal
2. Navigate to "Settings" > "Single Sign-On"
3. Verify SAML configuration:
    - Correct Entity ID
    - Correct SSO URL
    - Proper certificate
    - Verify dan@allgrid.com is set as expected identifier

## Potential Issues

1. **Enterprise Application Configuration:** The Bitwarden enterprise application may not be properly configured in
   Entra ID
2. **Permission Issues:** The user account may not have the necessary permissions assigned
3. **Certificate Problems:** SSL certificate might be invalid or expired
4. **Claims Configuration:** Incorrect claim mappings in the SAML configuration

## Resolution Actions

### Automatic Resolution Script

An improved PowerShell script has been created to address the synchronization issues between dan@allgrid.com in MS Entra
and Bitwarden Enterprise:

- Script location: `C:\Users\DanSolberg\RiderProjects\Mistral app\Scripts\fix-bitwarden-sso-integration.ps1`
- The script will:
    1. Verify user account existence in MS Entra
    2. Manage Bitwarden application registration
    3. Ensure service principal is properly created
    4. Configure SAML settings
    5. Assign the user to the application and download the SAML certificate

**Key Improvements:**

- More robust error handling with strict error action preference
- Automatic SAML certificate download when possible
- Proper sequence with delays to ensure resources are fully provisioned
- Complete configuration output saved to a file for easy Bitwarden setup

### Running the Script

**Option 1: Run using CMD file (Recommended)**

```
1. Navigate to C:\Users\DanSolberg\RiderProjects\Mistral app\Scripts
2. Double-click run-without-bom.cmd
3. Allow the UAC prompt to run with admin privileges
```

**Option 2: Run in PowerShell directly**

```powershell
# Open PowerShell as Administrator first, then:
cd "C:\Users\DanSolberg\RiderProjects\Mistral app\Scripts"
.\fix-bitwarden-sso-integration.ps1
```

**Note:** The script has been optimized for simplicity and reliability.

### Analyzing Integration Logs

The script creates detailed logs in the `Scripts\logs` directory that can help diagnose any issues:

**Using the Log Analysis Script:**

```powershell
# Analyze the latest log file
.\Scripts\analyze-bitwarden-logs.ps1

# Or specify a particular log file
.\Scripts\analyze-bitwarden-logs.ps1 -LogFilePath "C:\logs\bitwarden-sso-fix-log-20250812-021035.txt"
```

**Common Error Patterns:**

1. **Connection Issues:** Error messages about connecting to Microsoft Graph suggest permission problems or network
   issues
2. **SAML Configuration Errors:** Problems with the SAML configuration often indicate incorrect URLs or certificate
   issues
3. **User Assignment Failures:** These may indicate permission problems with the user account

**External Log Analysis:**
If your log file is in a different location (e.g., `C:\logs\bitwarden-sso-fix-log-20250812-021035.txt`), you can copy it
to the script's logs directory for analysis:

```powershell
# Copy external log to script's logs directory
Copy-Item "C:\logs\bitwarden-sso-fix-log-20250812-021035.txt" -Destination "C:\Users\DanSolberg\RiderProjects\Mistral app\Scripts\logs\"
```

### Manual Resolution Options

1. **Fix Existing Enterprise Application**
    1. In Microsoft Entra admin center, go to "Enterprise applications"
    2. Search for and open "Bitwarden SSO" (Object ID: e4bcc967-f8f9-4d81-9067-2b03fd159c7d)
    3. Check "Users and groups" to ensure dan@allgrid.com is assigned to the application
    4. Review "Single sign-on" settings and verify SAML configuration:
        - Identifier (Entity ID) should match Bitwarden's expected value
        - Reply URL (Assertion Consumer Service URL) should be correct
        - Check that claim mappings are properly configured

2. **Update Bitwarden Configuration**
    1. Log into Bitwarden admin portal
    2. Navigate to "Settings" > "Single Sign-On"
    3. Verify or update configuration with correct values from Microsoft Entra:
        - SP Entity ID: ab79eb4f-82da-436b-a8bb-6b193f3e800d
        - Assertion Consumer Service (ACS) URL: should be one of the redirect URIs
        - SAML metadata URL: copy from Entra SAML configuration
        - X509 certificate: download from Entra and upload to Bitwarden

3. **Recreate Bitwarden SSO configuration**
    1. Remove existing Bitwarden Enterprise app integration in Microsoft Entra
    2. Create new app registration
       following [Bitwarden SSO with Azure documentation](https://bitwarden.com/help/configure-sso-azure/)
    3. Ensure Business Premium license is properly assigned
    4. Configure new integration in Bitwarden Enterprise portal

4. **Contact support**
   If issues persist:
    1. Microsoft Support: https://support.microsoft.com
    2. Bitwarden Support: https://bitwarden.com/contact/

## Tracking Log

| Date       | Action Taken                              | Result                                                                       |
|------------|-------------------------------------------|------------------------------------------------------------------------------|
| 2025-08-11 | Ran account verification script           | Found single account with Business Premium license                           |
| 2025-08-11 | Checked for application registrations     | Found existing Bitwarden SSO application and registration                    |
| 2025-08-11 | Created comprehensive fix script          | `fix-bitwarden-sso-integration.ps1` to forcefully resolve integration issues |
| 2025-08-11 | Updated script with improved stability    | Added error handling and created batch launcher for elevated execution       |
| 2025-08-11 | Fixed batch file encoding issues          | Created new CMD file without BOM character encoding                          |
| 2025-08-11 | Streamlined script                        | Simplified the script to be more concise and reliable                        |
| 2025-08-12 | Enhanced script with certificate download | Added SAML certificate download capability and stricter error handling       |
| 2025-08-13 | Fixed script parsing errors               | Created simplified version that avoids PowerShell parameter parsing issues   |
| 2025-08-13 | Added log analysis capability             | Created script to analyze integration logs for troubleshooting               |

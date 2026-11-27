param (
    [string]$UserName = "Kasutaja"
)

$ErrorActionPreference = "Stop"

$WinLogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$AdminGroupSID = "S-1-5-32-544"
$LogFile = "C:\ProgramData\LocalAccSetup\FirstBoot.log"

Start-Transcript -Path $LogFile -Append
$Success = $false

try {
    Write-Host "Cleaning up the scheduled task..."
    Unregister-ScheduledTask -TaskName "Configure-FirstBoot" -Confirm:$false

    Write-Host "Verifying user '$UserName' before proceeding..."
    $UserObj = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    $IsAdmin = Get-LocalGroupMember -SID $AdminGroupSID -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$UserName$" }

    if (-not ($UserObj -and $UserObj.Enabled -and $IsAdmin)) {
        throw "Safety check failed: User '$UserName' does not exist, disabled, or not in Administrators. Aborting to prevent lockout."
    }

    Write-Host "Configuring Auto-Logon..."
    Set-ItemProperty -Path $WinLogonPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $WinLogonPath -Name "DefaultUserName" -Value $UserName
    Set-ItemProperty -Path $WinLogonPath -Name "DefaultPassword" -Value ""
    Set-ItemProperty -Path $WinLogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME

    Write-Host "Disabling built-in Administrator (SID ending in -500)..."
    Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' } | Disable-LocalUser

    $Success = $true
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    Stop-Transcript
}

if ($Success) {
    Write-Host "Setup complete. Rebooting into $UserName ..."
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "Setup failed. Task removed. Manual intervention required. No reboot will occur. See log file at $LogFile" -ForegroundColor Red
}
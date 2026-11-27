#Requires -RunAsAdministrator

param (
    [string]$UserName = "Kasutaja",
    [string]$UserDescription = "Kohalik Kasutaja"
)

$ErrorActionPreference = "Stop"

if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $UserName -NoPassword -FullName $UserName -Description $UserDescription
    Set-LocalUser -Name $UserName -PasswordNeverExpires $true
    net user $UserName /logonpasswordchg:no | Out-Null
    # The net user command is an external program so without explicit error handling it would fail silently.
    if ($LASTEXITCODE -ne 0) { throw "'net user' command failed with exit code $LASTEXITCODE" }
}

$AdminGroupSID = "S-1-5-32-544" # This is always the SID for Administrators, but the group display name depends on display language.
if (-not (Get-LocalGroupMember -SID $AdminGroupSID | Where-Object { $_.Name -match "\\$UserName$" })) {
    Add-LocalGroupMember -SID $AdminGroupSID -Member $UserName
}

$DestinationDir = "C:\ProgramData\LocalAccSetup"
if (-not (Test-Path $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
}

$SourceScriptB = Join-Path -Path $PSScriptRoot "Configure-FirstBoot.ps1"
$DestinationScriptB = Join-Path -Path $DestinationDir "Configure-FirstBoot.ps1"
# ErrorAction Stop makes sure task scheduler doesn't schedule a task if the script is misplaced or missing or otherwise problematic
Copy-Item -Path $SourceScriptB -Destination $DestinationScriptB -Force -ErrorAction Stop

# $Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -UserName "{1}"' -f $DestinationScriptB, $UserName
# $Action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $Arguments
# TEMPORARY DEBUG: cmd wrapper captures PowerShell's own output/errors from the task launch. delete next 4 lines and uncomment two above to revert
$PSExe   = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$OutFile = Join-Path -Path $DestinationDir "out.txt"
$Arguments = '/c {0} -NoProfile -ExecutionPolicy Bypass -File "{1}" -UserName "{2}" > "{3}" 2>&1' -f $PSExe, $DestinationScriptB, $UserName, $OutFile
$Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $Arguments

$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "Configure-FirstBoot" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force
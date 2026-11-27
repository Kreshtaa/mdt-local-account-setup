#Requires -RunAsAdministrator

param (
    [string]$UserName = "Kasutaja",
    [string]$UserDescription = "Kohalik Kasutaja"
)

if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $UserName -NoPassword -PasswordNeverExpires -FullName $UserName -Description $UserDescription
    net user $UserName /logonpasswordchg:no | Out-Null
}

$AdminGroupSID = "S-1-5-32-544" # See on alati Administrators grupi SID, aga selle nimi oleneb keelest.
if (-not (Get-LocalGroupMember -SID $AdminGroupSID | Where-Object { $_.Name -match "\\$UserName$" })) {
    Add-LocalGroupMember -SID $AdminGroupSID -Member $UserName
}

$DestinationDir = "C:\ProgramData\LocalAccSetup"
if (-not (Test-Path $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
}

$SourceScriptB = Join-Path -Path $PSScriptRoot "Configure-FirstBoot.ps1"
$DestinationScriptB = Join-Path -Path $DestinationDir "Configure-FirstBoot.ps1"
# ErrorAction Stop tagab, et task scheduler ei registreeriks taski mitteeksisteeriva scripti korral.
Copy-Item -Path $SourceScriptB -Destination $DestinationScriptB -Force -ErrorAction Stop

$Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -UserName "{1}"' -f $DestinationScriptB, $UserName
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Arguments
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "Configure-FirstBoot" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force
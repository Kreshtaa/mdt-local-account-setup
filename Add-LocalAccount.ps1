param (
    [string]$UserName = "Kasutaja",
    [string]$UserDescription = "Kohalik Kasutaja"
)

if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $UserName -NoPassword -FullName $UserName -Description $UserDescription
}

$AdminGroupSID = "S-1-5-32-544" # See on alati Administrators grupi SID, aga selle nimi oleneb keelest.
if (-not (Get-LocalGroupMember -SID $AdminGroupSID | Where-Object { $_.Name -match "\\$UserName$" })) {
    Add-LocalGroupMember -SID $AdminGroupSID -Member $UserName
}
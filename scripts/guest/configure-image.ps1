# Image settings for a cloud instance. Equivalent of the [custom] options
# and enable_* flags of config/*.ini (windows-openstack-imaging-tools).
# Inputs (environment): OIC_TIME_ZONE, OIC_NTP_SERVERS.
$ErrorActionPreference = 'Stop'

# Time: UTC by default, NTP peers (DHCP supplied servers win at boot when
# Cloudbase-Init ntp_use_dhcp_config finds some).
$tz = if ($env:OIC_TIME_ZONE) { $env:OIC_TIME_ZONE } else { 'UTC' }
tzutil.exe /s "$tz"
if ($env:OIC_NTP_SERVERS) {
    $peers = ($env:OIC_NTP_SERVERS -split '\s+' | Where-Object { $_ } | ForEach-Object { "$_,0x9" }) -join ' '
    w32tm.exe /config /manualpeerlist:"$peers" /syncfromflags:manual /update | Out-Null
}
Set-Service -Name W32Time -StartupType Automatic

# Ping (enable_ping_requests).
New-NetFirewallRule -Name 'OIC-ICMPv4-Echo' -DisplayName 'Allow ICMPv4 echo request' `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any | Out-Null
New-NetFirewallRule -Name 'OIC-ICMPv6-Echo' -DisplayName 'Allow ICMPv6 echo request' `
    -Direction Inbound -Protocol ICMPv6 -IcmpType 128 -Action Allow -Profile Any | Out-Null

# IPv6 with EUI-64 interface ids and no temporary addresses
# (enable_ipv6_eui64): Neutron SLAAC and DHCPv6 expect the MAC derived
# address, see https://github.com/cloudbase/windows-openstack-imaging-tools/issues/192
Set-NetIPv6Protocol -RandomizeIdentifiers Disabled -UseTemporaryAddresses Disabled

# Never sleep, no hibernation file (enable_active_mode).
powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
powercfg.exe -change -monitor-timeout-ac 0
powercfg.exe -change -standby-timeout-ac 0
powercfg.exe -hibernate off

# Remote Desktop with Network Level Authentication (also set in the answer
# file; repeated here so the result does not depend on the ISO build).
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'

# Shutdown from the hypervisor (ACPI) must work without a logged on user.
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ShutdownWithoutLogon -Value 1

# Do not open Server Manager at every logon.
Get-ScheduledTask -TaskName 'ServerManager' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null

Write-Host 'Image settings applied'

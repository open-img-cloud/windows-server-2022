# Runs at the first logon of the BUILD VM (FirstLogonCommands of
# packer/autounattend.xml.pkrtpl). Opens an HTTP WinRM listener with Basic
# authentication so that Packer can connect over the QEMU user network.
# cleanup.ps1 schedules the removal of these settings: they never reach a
# deployed instance.
$ErrorActionPreference = 'Stop'
Start-Transcript -Path "$env:SystemRoot\Temp\oic-enable-winrm.log" -Append

# WinRM refuses to start its firewall exception on a Public network.
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

winrm quickconfig -quiet -force
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'

New-NetFirewallRule -Name 'OIC-Packer-WinRM-HTTP' -DisplayName 'Packer build WinRM (HTTP)' `
    -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any | Out-Null

Set-Service -Name WinRM -StartupType Automatic
Restart-Service -Name WinRM
Stop-Transcript

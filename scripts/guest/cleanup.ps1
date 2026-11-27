# Last provisioning step before sysprep (Packer shutdown_command).
$ErrorActionPreference = 'Stop'

# Forget any Cloudbase-Init run on the build VM.
Stop-Service -Name cloudbase-init -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SOFTWARE\Cloudbase Solutions\Cloudbase-Init\*' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:ProgramFiles\Cloudbase Solutions\Cloudbase-Init\log\*" -Force -ErrorAction SilentlyContinue

# Undo the build only WinRM settings (enable-winrm.ps1) on the first boot of
# each instance: SetupComplete.cmd runs once, as SYSTEM, at the end of
# Windows Setup after sysprep. Cloudbase-Init then creates its own HTTPS
# listener (ConfigWinRMListenerPlugin).
$setupScripts = "$env:SystemRoot\Setup\Scripts"
New-Item -ItemType Directory -Path $setupScripts -Force | Out-Null
$lines = @(
    '@echo off',
    'netsh advfirewall firewall delete rule name="Packer build WinRM (HTTP)"',
    'call winrm set winrm/config/service @{AllowUnencrypted="false"}',
    'call winrm set winrm/config/service/auth @{Basic="false"}',
    'call winrm delete winrm/config/Listener?Address=*+Transport=HTTP'
)
Add-Content -Path (Join-Path $setupScripts 'SetupComplete.cmd') -Value $lines -Encoding ASCII

# Component store cleanup (clean_updates_online): smaller image, updates can
# no longer be uninstalled.
& dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet
if ($LASTEXITCODE -ne 0) { Write-Warning "DISM component cleanup exited with $LASTEXITCODE" }

# Temporary files, event logs, installers.
Remove-Item -Path "$env:SystemRoot\Temp\*.msi" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 -and $_.IsEnabled } |
    ForEach-Object { try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch { } }

# Release free blocks: the disk is attached with discard=unmap, so TRIM turns
# into holes in the qcow2 (zero_unused_volume_sectors).
Optimize-Volume -DriveLetter C -ReTrim -Verbose

Write-Host 'Cleanup done, sysprep runs next'

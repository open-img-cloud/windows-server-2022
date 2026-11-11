# Installs Cloudbase-Init and the configuration of this repository:
#   config/cloud/cloudbase-init.conf          normal stage (service)
#   config/cloud/cloudbase-init-unattend.conf sysprep specialize stage
#   unattended/Unattend.xml                   sysprep answer file
# Inputs (environment): OIC_CLOUDBASE_INIT_MSI_URL, OIC_CLOUDBASE_INIT_MSI_SHA256.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cd = Get-PSDrive -PSProvider FileSystem |
    Where-Object { Test-Path (Join-Path $_.Root 'cloud\cloudbase-init.conf') } |
    Select-Object -First 1
if (-not $cd) { throw 'cloud\cloudbase-init.conf not found on any drive (OIC_SETUP CD missing?)' }
$root = $cd.Root

$url = if ($env:OIC_CLOUDBASE_INIT_MSI_URL) { $env:OIC_CLOUDBASE_INIT_MSI_URL } else { 'https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi' }
$msi = "$env:SystemRoot\Temp\CloudbaseInitSetup.msi"
Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

if ($env:OIC_CLOUDBASE_INIT_MSI_SHA256) {
    $hash = (Get-FileHash -Path $msi -Algorithm SHA256).Hash
    if ($hash -ne $env:OIC_CLOUDBASE_INIT_MSI_SHA256.ToUpper()) {
        throw "Cloudbase-Init MSI checksum mismatch: got $hash"
    }
}

$log = "$env:SystemRoot\Temp\cloudbase-init-msi.log"
$p = Start-Process -FilePath msiexec.exe -Wait -PassThru -ArgumentList @(
    '/i', "`"$msi`"", '/qn', '/l*v', "`"$log`"", 'LOGGINGSERIALPORTNAME=COM1')
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    throw "Cloudbase-Init MSI failed with exit code $($p.ExitCode), see $log"
}

$conf = "$env:ProgramFiles\Cloudbase Solutions\Cloudbase-Init\conf"
Copy-Item -Path (Join-Path $root 'cloud\cloudbase-init.conf') -Destination $conf -Force
Copy-Item -Path (Join-Path $root 'cloud\cloudbase-init-unattend.conf') -Destination $conf -Force
Copy-Item -Path (Join-Path $root 'unattended\Unattend.xml') -Destination (Join-Path $conf 'Unattend.xml') -Force
# Files copied from a CD keep the read-only attribute.
Get-ChildItem -Path $conf | ForEach-Object { $_.IsReadOnly = $false }

# The service must not run on the build VM (no metadata here); it starts on
# the first boot of each instance.
Stop-Service -Name cloudbase-init -ErrorAction SilentlyContinue
Set-Service -Name cloudbase-init -StartupType Automatic
Write-Host 'Cloudbase-Init installed and configured'

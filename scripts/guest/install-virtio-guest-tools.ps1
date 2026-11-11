# Installs every VirtIO driver (storage, network, balloon, serial, rng,
# input, pvpanic, fw_cfg) and the QEMU guest agent from
# virtio-win-guest-tools.exe, copied to the OIC_SETUP CD by
# scripts/fetch-virtio.sh.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$cd = Get-PSDrive -PSProvider FileSystem |
    Where-Object { Test-Path (Join-Path $_.Root 'virtio-win-guest-tools.exe') } |
    Select-Object -First 1
if (-not $cd) { throw 'virtio-win-guest-tools.exe not found on any drive (OIC_SETUP CD missing?)' }
$root = $cd.Root
Write-Host "VirtIO media found on $root"

# Trust the Red Hat driver publisher first, otherwise the silent install
# stops on a "Would you like to install this device software?" prompt.
$catalogs = Get-ChildItem -Path $root -Recurse -Filter '*.cat' -ErrorAction SilentlyContinue
foreach ($cat in $catalogs) {
    $cert = (Get-AuthenticodeSignature -FilePath $cat.FullName).SignerCertificate
    if ($cert) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
        $store.Open('ReadWrite')
        $store.Add($cert)
        $store.Close()
    }
}

$installer = Join-Path $root 'virtio-win-guest-tools.exe'
$log = "$env:SystemRoot\Temp\virtio-win-guest-tools.log"
$p = Start-Process -FilePath $installer -ArgumentList '/install', '/quiet', '/norestart', '/log', $log -Wait -PassThru
# 3010: success, reboot required (Packer reboots right after this script).
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    throw "virtio-win-guest-tools.exe failed with exit code $($p.ExitCode), see $log"
}

$ga = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
if (-not $ga) { throw 'QEMU guest agent service (QEMU-GA) not installed' }
Set-Service -Name 'QEMU-GA' -StartupType Automatic
Write-Host 'VirtIO drivers and QEMU guest agent installed'

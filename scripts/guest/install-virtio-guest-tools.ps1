# Installs the VirtIO drivers (storage, balloon, serial, rng, input,
# pvpanic, fw_cfg; network comes from Windows Setup) and the QEMU guest agent from the virtio-win
# MSI packages, copied to the OIC_SETUP CD by scripts/fetch-virtio.sh.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$cd = Get-PSDrive -PSProvider FileSystem |
    Where-Object { Test-Path (Join-Path $_.Root 'qemu-ga-x86_64.msi') } |
    Select-Object -First 1
if (-not $cd) { throw 'qemu-ga-x86_64.msi not found on any drive (OIC_SETUP CD missing?)' }
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

# msiexec, waited for with WaitForExit and a time limit: Start-Process -Wait
# also waits for every process the installer leaves behind, and a stuck
# install must fail the build instead of hanging it.
# NetKVM is left out of the driver package: Windows Setup already installed
# it from the same virtio-win media (DriverPaths in autounattend.xml), and
# reinstalling it resets the network card that carries the WinRM session,
# which leaves Packer waiting forever.
$extra = @{
    'virtio-win-gt-x64.msi' = @('ADDLOCAL=ALL', 'REMOVE=FE_network_driver')
    'qemu-ga-x86_64.msi'    = @()
}
foreach ($msi in 'virtio-win-gt-x64.msi', 'qemu-ga-x86_64.msi') {
    $log = Join-Path "$env:SystemRoot\Temp" "$msi.log"
    Write-Host "Installing $msi"
    $p = Start-Process -FilePath msiexec.exe -PassThru -ArgumentList (@(
        '/i', "`"$(Join-Path $root $msi)`"", '/qn', '/norestart', '/l*v', "`"$log`"") + $extra[$msi])
    # Reading Handle now keeps ExitCode available after WaitForExit.
    $null = $p.Handle
    if (-not $p.WaitForExit(15 * 60 * 1000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        throw "$msi still running after 15 minutes, see $log"
    }
    # 3010: success, reboot required (Packer reboots right after this script).
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "$msi failed with exit code $($p.ExitCode), see $log"
    }
    Write-Host "$msi installed (exit code $($p.ExitCode))"
}

$ga = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
if (-not $ga) { throw 'QEMU guest agent service (QEMU-GA) not installed' }
Set-Service -Name 'QEMU-GA' -StartupType Automatic
Write-Host 'VirtIO drivers and QEMU guest agent installed'

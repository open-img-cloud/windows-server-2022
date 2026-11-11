# Windows Server cloud images: build your own

[![Lint](https://github.com/open-img-cloud/windows-server-2022/actions/workflows/lint.yml/badge.svg)](https://github.com/open-img-cloud/windows-server-2022/actions/workflows/lint.yml)
[![GPL-2.0 License](https://img.shields.io/github/license/open-img-cloud/windows-server-2022.svg)](LICENSE)

**openimages.cloud does not publish Windows images.** Microsoft's
evaluation license lets you install and test the software, not
redistribute it, and the same holds for licensed media. This repository
is a kit instead: the tooling to build a Windows Server cloud image for
**OpenStack** or **Proxmox VE** from **your own ISO** (evaluation or
licensed), on a Linux host with KVM.

What you get, per build: one compressed, sysprepped `qcow2` with

- Windows Server 2022 or 2025, Standard or Datacenter (Desktop Experience
  or Core);
- BIOS (i440fx) or UEFI (q35 + OVMF) boot;
- VirtIO drivers (storage virtio-blk and virtio-scsi, network, balloon,
  serial, RNG, ...) and the QEMU guest agent;
- [Cloudbase-Init][cbi] (the Windows cloud-init): hostname, password,
  SSH keys, network configuration, volume extension, user data, from
  the OpenStack config drive or metadata service, or from a Proxmox
  cloud-init drive;
- Windows Update applied (optional), RDP with NLA, ping allowed, IPv6
  with EUI-64 addresses, UTC.

| | Linux host (recommended) | Windows host (alternative) |
|---|---|---|
| Tooling | [Packer][packer] + [QEMU plugin][packer-qemu] on KVM | [cloudbase/windows-openstack-imaging-tools][wit] on Hyper-V |
| Entry point | `scripts/build.sh` | `scripts/build-all-editions.ps1` |
| Configuration | `packer/*.pkr.hcl` | `config/*.ini` |
| Shared | `config/cloud/*.conf` (Cloudbase-Init) | `config/cloud/*.conf` (Cloudbase-Init) |

OpenStack and Proxmox operators run Linux and KVM already, so the Linux
path is the documented and tested one. The Windows host path is kept
for teams that already use the Cloudbase tools.

## Contents

1. [Licensing and activation](#licensing-and-activation)
2. [Prerequisites (Linux)](#prerequisites-linux)
3. [Get a Windows Server ISO](#get-a-windows-server-iso)
4. [Build](#build)
5. [What the build does](#what-the-build-does)
6. [VirtIO drivers](#virtio-drivers)
7. [Cloudbase-Init configuration](#cloudbase-init-configuration)
8. [Upload to OpenStack Glance](#upload-to-openstack-glance)
9. [Import into Proxmox VE](#import-into-proxmox-ve)
10. [First boot](#first-boot)
11. [Alternative: Windows host](#alternative-windows-host)
12. [Repository layout](#repository-layout)
13. [Validation and CI](#validation-and-ci)
14. [Troubleshooting](#troubleshooting)
15. [Sources](#sources)

## Licensing and activation

Read this before you build: licensing is the operator's job, the kit
does not change it.

- **Evaluation media** (Microsoft Evaluation Center) run for **180
  days** and must be activated over the Internet within the first 10
  days ([Evaluation Center][eval-2025]). Evaluation software is licensed
  for testing; its terms do not grant a right to redistribute it
  ([Microsoft license terms][ms-useterms]). Do not publish images built
  from it.
- **Converting** an evaluation install to retail needs a valid key:
  `DISM /online /Set-Edition:ServerStandard /ProductKey:<key> /AcceptEula`
  ([Microsoft Learn][ms-convert]).
- **Licensed media** (Volume Licensing, Microsoft 365 admin center,
  CSP, ...) need a product key during Setup: pass `--product-key`. For
  KMS activation use the public KMS client key (GVLK) of the edition
  ([KMS client keys][ms-gvlk]) and point the instances to your KMS host
  (`activate_windows=true` and `kms_host=` in
  `config/cloud/cloudbase-init.conf`, or Group Policy, or `slmgr /skms`).
- **Running Windows on a cloud** requires per-host or per-core licensing
  of the hypervisors (Datacenter for unlimited VMs, or SPLA for service
  providers). Check with your Microsoft licensing partner.
- The build runs `sysprep /generalize`, so each instance gets a new SID
  and a fresh activation state.

## Prerequisites (Linux)

- x86_64 host with KVM (`/dev/kvm` writable by your user), 4 vCPUs and
  8 GiB RAM free for the build VM, about 60 GiB free disk;
- Internet access from the build VM (Windows Update, Cloudbase-Init
  MSI) and from the host (Packer plugins, virtio-win ISO);
- [Packer][packer] 1.10 or later (tested with 1.16.2), QEMU, `qemu-img`,
  `xorriso`, OVMF for UEFI builds, `curl`.

Debian / Ubuntu:

```sh
sudo apt install qemu-system-x86 qemu-utils ovmf xorriso curl
# Packer: https://developer.hashicorp.com/packer/install
```

Fedora / RHEL / Rocky / Alma:

```sh
sudo dnf install qemu-kvm qemu-img edk2-ovmf xorriso curl
# Packer: https://developer.hashicorp.com/packer/install
# RHEL and derivatives ship QEMU as /usr/libexec/qemu-kvm: build.sh uses it
# when qemu-system-x86_64 is absent.
```

Add your user to the `kvm` group if needed (`sudo usermod -aG kvm $USER`,
then log in again).

## Get a Windows Server ISO

Pick one:

- **Evaluation** (free, registration required, 180 days):
  - Windows Server 2022: <https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022>
  - Windows Server 2025: <https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025>
- **Licensed**: the ISO from your Volume Licensing / Microsoft 365 admin
  center / Visual Studio subscription.

Check the images inside the ISO (the build selects them by index):

```sh
# wimtools package (wimlib)
7z x -so your.iso sources/install.wim > /tmp/install.wim   # or mount the ISO
wiminfo /tmp/install.wim
```

The 2022 and 2025 ISOs (evaluation and licensed) use this layout, which
`--edition` relies on:

| Index | Edition | `--edition` |
|---|---|---|
| 1 | Standard (Server Core) | `standard-core` |
| 2 | Standard (Desktop Experience) | `standard` |
| 3 | Datacenter (Server Core) | `datacenter-core` |
| 4 | Datacenter (Desktop Experience) | `datacenter` |

If yours differs, pass `-- -var image_index=<n>`.

## Build

```sh
git clone https://github.com/open-img-cloud/windows-server-2022.git
cd windows-server-2022

# Windows Server 2022 Standard, BIOS, evaluation ISO
scripts/build.sh --iso ~/iso/SERVER_EVAL_x64FRE_en-us.iso

# Windows Server 2022 Datacenter, UEFI
scripts/build.sh --iso ~/iso/ws2022.iso --edition datacenter --firmware uefi

# Windows Server 2025 Standard, UEFI, licensed media with a KMS client key
scripts/build.sh --iso ~/iso/ws2025.iso --version 2025 --firmware uefi \
  --product-key XXXXX-XXXXX-XXXXX-XXXXX-XXXXX

# Faster test build without Windows Update, with the VM console visible
scripts/build.sh --iso ~/iso/ws2022.iso --no-updates --headless false
```

`scripts/build.sh` checks the host, downloads and extracts the VirtIO
drivers (`scripts/fetch-virtio.sh`), generates a random build-only
Administrator password, then runs `packer init`, `packer validate` and
`packer build` in `packer/`. Anything after `--` goes to `packer build`
(for example `-- -var disk_size=60G -var iso_checksum=sha256:<hex>`).
All variables are documented in `packer/variables.pkr.hcl`.

Duration: 20 to 40 minutes without updates, 1 to 3 hours with them.

Result:

```
output/windows-server-2022-standard-bios/
  windows-server-2022-standard-bios.qcow2         compressed, sparse
  windows-server-2022-standard-bios.qcow2.sha256
```

Packer can also be called directly:

```sh
scripts/fetch-virtio.sh 2022
cd packer && packer init .
PKR_VAR_build_password='S0me-Strong-Pass!' packer build \
  -var iso_path=$HOME/iso/ws2022.iso -var edition=datacenter -var firmware=uefi .
```

## What the build does

1. Packer starts a QEMU/KVM VM with the ISO on an IDE CD-ROM and a
   second CD (`OIC_SETUP`) holding `autounattend.xml`, the VirtIO
   storage and network drivers, `scripts/guest/`, `config/cloud/` and
   `unattended/`.
2. Windows Setup reads `autounattend.xml` (rendered from
   `packer/autounattend.xml.pkrtpl`): language, VirtIO drivers in
   WinPE, disk layout (BIOS: one NTFS partition; UEFI: EFI + MSR +
   Windows; no recovery partition after C:, so it can be extended),
   edition by index, optional product key, RDP enabled, build password,
   one autologon that opens WinRM (`scripts/guest/enable-winrm.ps1`).
3. Over WinRM, Packer runs:
   - `install-virtio-guest-tools.ps1`: all VirtIO drivers and the QEMU
     guest agent, then a reboot;
   - Windows Update (`rgl/windows-update` plugin), unless `--no-updates`;
   - `configure-image.ps1`: time zone and NTP, ping, IPv6 EUI-64, power
     plan, RDP with NLA, shutdown without logon;
   - `install-cloudbase-init.ps1`: Cloudbase-Init MSI (stable channel)
     and this repository's configuration;
   - `cleanup.ps1`: component store cleanup, logs, TRIM, and a
     `SetupComplete.cmd` that removes the build-only WinRM HTTP listener
     on each instance's first boot.
4. `sysprep /generalize /oobe /shutdown` with `unattended/Unattend.xml`.
5. Packer converts the disk to a compressed qcow2 (`disk_compression`)
   and writes its SHA256.

The two Windows answer files are distinct:

| File | Used by | When |
|---|---|---|
| `packer/autounattend.xml.pkrtpl` | Windows Setup | Installation on the build VM |
| `unattended/Unattend.xml` | Sysprep | First boot of every instance |

## VirtIO drivers

The drivers come from the Fedora virtio-win project
([virtio-win-pkg-scripts][virtio]); `scripts/fetch-virtio.sh` downloads
the **stable** ISO (0.1.302 in November 2026) to `build/cache/`, then
extracts:

- `viostor` (virtio-blk), `vioscsi` (virtio-scsi) and `NetKVM`
  (virtio-net) for the target release (`2k22` or `2k25` folder), loaded
  by Windows Setup;
- `virtio-win-guest-tools.exe`, which installs every driver (balloon,
  serial, RNG, input, pvpanic, fw_cfg, ...) and the QEMU guest agent.

Options: `VIRTIO_CHANNEL=latest` for the newest (pre-release quality)
build, or `VIRTIO_ISO=/usr/share/virtio-win/virtio-win.iso` to use the
ISO of your distribution's `virtio-win` package. Both disk drivers are
installed, so the image boots with `hw_disk_bus=virtio` or `scsi`.

## Cloudbase-Init configuration

Cloudbase-Init runs twice ([docs][cbi-docs]):

| Stage | File | When | Plugins |
|---|---|---|---|
| Sysprep | `config/cloud/cloudbase-init-unattend.conf` | specialize pass, before the first logon, started by `unattended/Unattend.xml` | MTU, hostname |
| Normal | `config/cloud/cloudbase-init.conf` | Windows service, every boot | upstream default list (below) |

Main settings and why:

| Setting | Value | Reason |
|---|---|---|
| `username` / `groups` | `Administrator` / `Administrators` | The built-in account receives the password and keys |
| `inject_user_password` | `true` | Use the password from metadata (Nova `admin_pass`, Proxmox `cipassword`); otherwise a random one is generated and, on OpenStack, posted encrypted with the key pair |
| `first_logon_behaviour` | `no` | No forced password change at first logon |
| `metadata_services` | ConfigDrive, then HttpService (OpenStack), then EC2 | Config drive first needs no network, and it is the only source on Proxmox (`configdrive2`); metadata API as fallback |
| `config_drive_cdrom/raw_hhd/vfat` | `true` | Find the config drive whatever its form |
| `mtu_use_dhcp_config`, `ntp_use_dhcp_config` | `true` | Honor Neutron DHCP options |
| `logging_serial_port_settings` | `COM1,115200,N,8` | Logs in the console log (`openstack console log show`) |
| `check_latest_version` | `false` | No call home |
| `allow_reboot` | `true` normal, `false` sysprep | Hostname changes may need a reboot after Setup |

Normal stage plugins: MTU, NTP client, hostname, create user, network
configuration (static IPs from `network_data.json` or Proxmox
`ipconfig0`), Windows licensing (only acts if `activate_windows=true`),
SSH public keys, volume extension, user data, password, WinRM HTTPS
listener and certificate authentication, local scripts.

Change these files and rebuild to adapt (for example to rename the
account, enable KMS activation, or drop the WinRM plugins).

## Upload to OpenStack Glance

Properties ([Glance useful image properties][glance-props]):

| Property | Value | Effect |
|---|---|---|
| `os_type` | `windows` | Nova enables Hyper-V enlightenments, RTC in local time, Windows specific defaults |
| `os_distro` | `windows` | Libosinfo / scheduler hints |
| `os_version` | `2022` or `2025` | Informative |
| `hw_qemu_guest_agent` | `yes` | Adds the guest agent channel (quiesced snapshots, `virsh domifaddr`) |
| `hw_disk_bus` | `virtio` (or `scsi` with `hw_scsi_model=virtio-scsi`) | Paravirtual disk; both drivers are in the image |
| `hw_vif_model` | `virtio` | Paravirtual NIC |
| `hw_firmware_type` | `uefi` (UEFI builds only) | Boot with OVMF |
| `hw_machine_type` | `q35` (UEFI builds only) | Machine type used for the build; required for Secure Boot |
| `hw_pointer_model` | `usbtablet` | Usable mouse in the VNC/SPICE console |
| `min_disk` / `min_ram` | `40` / `2048` | Size of the build disk; Windows needs 2 GiB RAM |

BIOS image:

```sh
openstack image create "Windows Server 2022 Standard" \
  --disk-format qcow2 --container-format bare \
  --file output/windows-server-2022-standard-bios/windows-server-2022-standard-bios.qcow2 \
  --min-disk 40 --min-ram 2048 \
  --property os_type=windows --property os_distro=windows --property os_version=2022 \
  --property hw_qemu_guest_agent=yes --property hw_disk_bus=virtio \
  --property hw_vif_model=virtio --property hw_pointer_model=usbtablet \
  --private
```

UEFI image: same command plus

```sh
  --property hw_firmware_type=uefi --property hw_machine_type=q35
```

Keep images private or shared with your own projects only (see
[Licensing](#licensing-and-activation)). If your Glance backend is Ceph
RBD, convert to raw first (`qemu-img convert -O raw`) to get
copy-on-write clones.

## Import into Proxmox VE

Proxmox passes Windows cloud-init data in the `configdrive2` format,
which Cloudbase-Init reads with its ConfigDrive service
([Proxmox cloud-init support][pve-ci]). Proxmox `ostype` `win11` covers
Windows Server 2022 and 2025. `import-from` needs Proxmox VE 7.2 or
later.

```sh
VMID=9000
IMG=/var/lib/vz/import/windows-server-2022-standard-bios.qcow2
STORAGE=local-lvm

qm create $VMID --name ws2022-std-template --ostype win11 \
  --cores 2 --memory 4096 --cpu host --agent enabled=1 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single
qm set $VMID --scsi0 $STORAGE:0,import-from=$IMG,discard=on,iothread=1
qm set $VMID --ide2 $STORAGE:cloudinit --citype configdrive2
qm set $VMID --boot order=scsi0
qm template $VMID
```

UEFI image: add before `qm template`

```sh
qm set $VMID --machine q35 --bios ovmf \
  --efidisk0 $STORAGE:1,efitype=4m,pre-enrolled-keys=0
```

Deploy:

```sh
qm clone 9000 123 --name win01 --full
qm set 123 --ipconfig0 ip=dhcp --cipassword 'S0me-Strong-Pass!' --sshkeys ~/.ssh/id_ed25519.pub
qm resize 123 scsi0 +40G          # Cloudbase-Init extends C: at boot
qm start 123
```

Set `ostype` to a Windows type before `--cipassword`, otherwise Proxmox
stores the password hashed and Windows cannot use it. The first logon
may fail until the reboot that follows the hostname change.

## First boot

- OpenStack: boot with a key pair (RSA for password retrieval), then
  `nova get-password <server> ~/.ssh/id_rsa` returns the Administrator
  password generated by Cloudbase-Init. Open RDP (TCP 3389) in a
  security group. Progress is visible with
  `openstack console log show <server>`.
- User data: a script starting with `#ps1_sysnative` (PowerShell) or
  `rem cmd` runs at first boot; `#cloud-config` is partially supported
  ([user data formats][cbi-userdata]).
- Evaluation builds: check the remaining evaluation period with
  `slmgr /dlv`.

## Alternative: Windows host

`scripts/build-all-editions.ps1` drives
[windows-openstack-imaging-tools][wit] with the four `config/*.ini`
files (Standard and Datacenter, BIOS and UEFI, Windows Server 2022,
Desktop Experience). It needs Windows with Hyper-V, an external virtual
switch named `external`, the Windows ADK Deployment Tools, the mounted
Windows ISO and the virtio-win ISO:

```powershell
git clone --recurse-submodules https://github.com/cloudbase/windows-openstack-imaging-tools C:\src\wit
Mount-DiskImage C:\iso\ws2022.iso      # say it becomes E:
.\scripts\build-all-editions.ps1 -ImagingToolsPath C:\src\wit `
    -WimFilePath E:\sources\install.wim -VirtioIsoPath C:\iso\virtio-win.iso `
    -OutputPath C:\oic\output -Filter 'standard-*.ini'
```

The script writes a copy of each ini with absolute paths, then calls
`New-WindowsOnlineImage`. It uses this repository's Cloudbase-Init
configuration; the sysprep answer file is the one shipped with the
Cloudbase-Init MSI, identical to `unattended/Unattend.xml` except for
`ProtectYourPC`. Check `image_name` with `Get-WimFileImagesInfo` from
the tools before building (names differ between media). This path is
not exercised by CI.

## Repository layout

```
packer/
  windows.pkr.hcl            source (QEMU/KVM) and build steps
  variables.pkr.hcl          all inputs, documented
  autounattend.xml.pkrtpl    Windows Setup answer file (template)
scripts/
  build.sh                   Linux entry point
  fetch-virtio.sh            VirtIO drivers for 2022 (2k22) or 2025 (2k25)
  build-all-editions.ps1     Windows host entry point (imaging tools)
  guest/*.ps1                run inside the build VM
config/
  cloud/cloudbase-init.conf          Cloudbase-Init, normal stage
  cloud/cloudbase-init-unattend.conf Cloudbase-Init, sysprep stage
  {standard,datacenter}-{bios,uefi}.ini  imaging tools configuration
unattended/Unattend.xml      sysprep answer file
.github/workflows/lint.yml   static checks
```

## Validation and CI

`.github/workflows/lint.yml` runs on every pull request, without
secrets and without any Windows media: `packer fmt -check`,
`packer validate` for 2022/2025 x BIOS/UEFI, rendering of
`autounattend.xml` (with and without product key) checked by `xmllint`,
`xmllint` on `unattended/`, INI syntax, `bash -n` and `shellcheck`,
PowerShell parsing of every `.ps1`, and a check that no em dash slipped
in.

A real build needs a Windows ISO and about an hour of KVM time: it is
not run in CI. Please report your results (version, edition, firmware,
OpenStack or Proxmox version) in an issue.

## Troubleshooting

- **Packer waits for WinRM forever**: run with `--headless false` (or
  connect a VNC client to the port Packer prints) and look at the
  screen. A setup prompt usually means a wrong image index, a missing
  product key on licensed media, or no VirtIO driver for the disk
  (check `build/virtio-<version>/`). Logs of the first logon script are
  in `C:\Windows\Temp\oic-enable-winrm.log`.
- **UEFI build stuck at "Press any key"**: increase `boot_wait` or
  repeat the `boot_command` keys in `packer/windows.pkr.hcl`.
- **Instance boots, no password / hostname**: read the console log;
  Cloudbase-Init logs are in
  `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\`.
- **BSOD INACCESSIBLE_BOOT_DEVICE**: the disk bus does not match a
  driver (use `virtio` or `scsi` + `virtio-scsi`, not `ide`/`sata` with
  a qcow2 built for VirtIO), see the [imaging tools FAQ][wit].

## Sources

Checked in November 2026.

- Microsoft Evaluation Center, Windows Server 2022 and 2025 (180 days,
  online activation within 10 days): [2022][eval-2022], [2025][eval-2025]
- Microsoft license terms: [microsoft.com/useterms][ms-useterms]
- Convert evaluation to retail: [Microsoft Learn][ms-convert]
- KMS client activation keys (GVLK): [Microsoft Learn][ms-gvlk]
- Unattend reference: [Microsoft Learn][ms-unattend]
- Packer 1.16.2: [developer.hashicorp.com/packer][packer]; QEMU plugin
  1.1.8: [docs][packer-qemu]; windows-update plugin 0.18.5:
  [rgl/packer-plugin-windows-update][rgl]
- virtio-win stable 0.1.302: [virtio-win-pkg-scripts][virtio]
- Cloudbase-Init 1.1.8 (stable MSI): [cloudbase.it][cbi],
  [documentation][cbi-docs], [Unattend.xml of the installer][cbi-unattend]
- windows-openstack-imaging-tools: [GitHub][wit]
- Glance image properties: [docs.openstack.org][glance-props]
- Proxmox VE cloud-init and Windows: [pve.proxmox.com][pve-ci]

## License

GPL-2.0, see [LICENSE](LICENSE). The license covers this tooling only:
Windows, the VirtIO drivers and Cloudbase-Init keep their own licenses.

[cbi]: https://cloudbase.it/cloudbase-init/
[cbi-docs]: https://cloudbase-init.readthedocs.io/en/latest/
[cbi-userdata]: https://cloudbase-init.readthedocs.io/en/latest/userdata.html
[cbi-unattend]: https://github.com/cloudbase/cloudbase-init-installer/blob/master/CloudbaseInitSetup/Unattend.xml
[wit]: https://github.com/cloudbase/windows-openstack-imaging-tools
[packer]: https://developer.hashicorp.com/packer
[packer-qemu]: https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu
[rgl]: https://github.com/rgl/packer-plugin-windows-update
[virtio]: https://github.com/virtio-win/virtio-win-pkg-scripts
[glance-props]: https://docs.openstack.org/glance/latest/admin/useful-image-properties.html
[pve-ci]: https://pve.proxmox.com/wiki/Cloud-Init_Support
[eval-2022]: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
[eval-2025]: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
[ms-useterms]: https://www.microsoft.com/en-us/useterms
[ms-convert]: https://learn.microsoft.com/windows-server/get-started/upgrade-conversion-options
[ms-gvlk]: https://learn.microsoft.com/windows-server/get-started/kms-client-activation-keys
[ms-unattend]: https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/

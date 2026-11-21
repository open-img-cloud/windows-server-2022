<p align="center">
  <a href="https://openimages.cloud">
    <img src="https://openimages.cloud/img/og.png" alt="openimages.cloud: signed, boot-tested cloud images for OpenStack and Proxmox" width="720">
  </a>
</p>

<h1 align="center">windows-server-2022</h1>

<p align="center">
  <a href="LICENSE"><img alt="License GPL-2.0" src="https://img.shields.io/badge/license-GPL--2.0-555"></a>
  <img alt="Status: work in progress" src="https://img.shields.io/badge/status-work%20in%20progress-orange">
</p>

<p align="center">
  <a href="https://openimages.cloud"><b>Website</b></a> ·
  <a href="https://openimages.cloud/images/">Catalog</a> ·
  <a href="https://github.com/open-img-cloud/docs">Documentation</a> ·
  <a href="https://github.com/open-img-cloud/windows-server-2022/issues">Report an issue</a>
</p>

> [!WARNING]
> **Work in progress: no published image.** Windows Server is not part of the
> [openimages.cloud catalog](https://openimages.cloud/images/): nothing is signed, boot-tested
> or published from this repository. A kit to build your own image from your own ISO is
> proposed in [pull request #1](https://github.com/open-img-cloud/windows-server-2022/pull/1).

This repository holds build inputs for a Windows Server 2022 cloud image (qcow2, KVM) for
OpenStack and Proxmox VE, prepared with Cloudbase-Init:

- [`config/`](config): build settings per edition and firmware (Standard and Datacenter, BIOS
  and UEFI) and the Cloudbase-Init configuration in [`config/cloud/`](config/cloud);
- [`scripts/build-all-editions.ps1`](scripts/build-all-editions.ps1): runs an external
  `WindowsImageGenerator.ps1` (not included here) once per configuration file;
- [`unattended/`](unattended): Windows answer file.

## License

The build tooling in this repository is under [GPL-2.0](LICENSE). Windows Server is licensed by
Microsoft; no Windows image or license is distributed here. Windows is a trademark of the
Microsoft group of companies; this project is not affiliated with Microsoft.

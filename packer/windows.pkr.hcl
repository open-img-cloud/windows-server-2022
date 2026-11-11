# Windows Server cloud image for OpenStack and Proxmox, built on Linux with
# QEMU/KVM from an ISO supplied by the operator.
#
# Flow: Windows Setup (autounattend.xml.pkrtpl, VirtIO drivers loaded in
# WinPE) -> WinRM -> VirtIO guest tools + QEMU guest agent -> Windows Update
# (optional) -> image settings -> Cloudbase-Init -> cleanup -> sysprep
# /generalize /oobe /shutdown -> compressed qcow2.
#
# Entry point: scripts/build.sh (it prepares the drivers and the variables).

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.8"
    }
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = ">= 0.18.5"
    }
  }
}

locals {
  uefi = var.firmware == "uefi"

  # install.wim layout of the Windows Server 2022 and 2025 ISOs
  # (evaluation and licensed media alike).
  edition_index = {
    "standard-core"   = 1
    "standard"        = 2
    "datacenter-core" = 3
    "datacenter"      = 4
  }
  image_index = var.image_index > 0 ? var.image_index : local.edition_index[var.edition]

  vm_name    = "windows-server-${var.windows_version}-${var.edition}-${var.firmware}"
  virtio_dir = var.virtio_dir != "" ? var.virtio_dir : "${path.root}/../build/virtio-${var.windows_version}"
  output_dir = var.output_dir != "" ? var.output_dir : "${path.root}/../output"

  # The password lands in an XML file: escape the XML special characters.
  xml_password    = replace(replace(replace(var.build_password, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
  xml_product_key = replace(replace(replace(var.product_key, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

  autounattend = templatefile("${path.root}/autounattend.xml.pkrtpl", {
    uefi           = local.uefi
    image_index    = local.image_index
    product_key    = local.xml_product_key
    admin_password = local.xml_password
    ui_language    = var.ui_language
    time_zone      = var.time_zone
  })

  cloudbase_init_conf = "C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\conf"
}

source "qemu" "windows" {
  vm_name          = "${local.vm_name}.qcow2"
  output_directory = "${local.output_dir}/${local.vm_name}"

  iso_url      = var.iso_path
  iso_checksum = var.iso_checksum

  qemu_binary = var.qemu_binary
  accelerator = "kvm"
  cpu_model   = "host"
  cpus        = var.cpus
  memory      = var.memory
  headless    = var.headless

  # BIOS: i440fx, the Nova and Proxmox default. UEFI: q35 + OVMF without
  # Secure Boot (set efi_firmware_code to a .secboot/.ms file to change that).
  machine_type      = local.uefi ? "q35" : "pc"
  efi_boot          = local.uefi
  efi_firmware_code = local.uefi ? var.ovmf_code : null
  efi_firmware_vars = local.uefi ? var.ovmf_vars : null
  efi_drop_efivars  = true

  disk_size          = var.disk_size
  disk_interface     = var.disk_interface
  format             = "qcow2"
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  disk_compression   = true
  net_device         = "virtio-net"

  # Windows Setup has no VirtIO CD-ROM driver: keep the ISO on IDE/AHCI.
  cdrom_interface = "ide"

  # Second CD: answer file, VirtIO drivers for WinPE, guest scripts and
  # Cloudbase-Init configuration. Needs xorriso (or mkisofs) on the host.
  cd_label = "OIC_SETUP"
  cd_files = [
    "${local.virtio_dir}/*",
    "${path.root}/../scripts/guest",
    "${path.root}/../config/cloud",
    "${path.root}/../unattended",
  ]
  cd_content = {
    "autounattend.xml" = local.autounattend
  }

  # UEFI Windows media ask to "Press any key to boot from CD or DVD".
  boot_wait    = local.uefi ? "2s" : "5s"
  boot_command = local.uefi ? ["<spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar>"] : []

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.build_password
  winrm_timeout  = "2h"
  winrm_use_ssl  = false

  # Last step: generalize. The VM powers itself off when sysprep is done.
  shutdown_command = "C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe /shutdown /quiet \"/unattend:${local.cloudbase_init_conf}\\Unattend.xml\""
  shutdown_timeout = "1h"
}

build {
  name    = "windows-server"
  sources = ["source.qemu.windows"]

  # VirtIO drivers (all of them) and the QEMU guest agent.
  provisioner "powershell" {
    script = "${path.root}/../scripts/guest/install-virtio-guest-tools.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # Packer has no conditional provisioners: when install_updates is false the
  # filter excludes every update, so the step only runs a search.
  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
    filters = var.install_updates ? [
      "exclude:$_.Title -like '*Preview*'",
      "include:$true",
    ] : ["exclude:$true"]
    update_limit = 25
  }

  provisioner "powershell" {
    environment_vars = [
      "OIC_TIME_ZONE=${var.time_zone}",
      "OIC_NTP_SERVERS=${var.ntp_servers}",
    ]
    script = "${path.root}/../scripts/guest/configure-image.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "OIC_CLOUDBASE_INIT_MSI_URL=${var.cloudbase_init_msi_url}",
      "OIC_CLOUDBASE_INIT_MSI_SHA256=${var.cloudbase_init_msi_sha256}",
    ]
    script = "${path.root}/../scripts/guest/install-cloudbase-init.ps1"
  }

  provisioner "powershell" {
    script = "${path.root}/../scripts/guest/cleanup.ps1"
  }

  post-processor "checksum" {
    checksum_types = ["sha256"]
    output         = "${local.output_dir}/${local.vm_name}/${local.vm_name}.qcow2.{{.ChecksumType}}"
  }
}

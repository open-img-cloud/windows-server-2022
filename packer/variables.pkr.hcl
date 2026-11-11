# Inputs of the Windows Server build. scripts/build.sh sets most of them;
# they can also be passed with -var or a .pkrvars.hcl file.

variable "windows_version" {
  type        = string
  default     = "2022"
  description = "Windows Server release: 2022 or 2025."
  validation {
    condition     = contains(["2022", "2025"], var.windows_version)
    error_message = "The windows_version must be 2022 or 2025."
  }
}

variable "edition" {
  type        = string
  default     = "standard"
  description = "Edition to install: standard, datacenter (Desktop Experience), standard-core or datacenter-core."
  validation {
    condition     = contains(["standard", "datacenter", "standard-core", "datacenter-core"], var.edition)
    error_message = "The edition must be standard, datacenter, standard-core or datacenter-core."
  }
}

variable "image_index" {
  type        = number
  default     = 0
  description = "Index of the image inside sources/install.wim. 0 derives it from edition (1 standard-core, 2 standard, 3 datacenter-core, 4 datacenter, the layout of the 2022 and 2025 ISOs). Check yours with: wiminfo sources/install.wim."
}

variable "firmware" {
  type        = string
  default     = "bios"
  description = "Firmware of the build VM and of the target instances: bios or uefi."
  validation {
    condition     = contains(["bios", "uefi"], var.firmware)
    error_message = "The firmware must be bios or uefi."
  }
}

variable "iso_path" {
  type        = string
  description = "Path or URL of YOUR Windows Server ISO (evaluation or licensed). Never redistributed by this project."
}

variable "iso_checksum" {
  type        = string
  default     = "none"
  description = "Checksum of the ISO, for example sha256:<hex>. none skips the check."
}

variable "product_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Product key typed in Windows Setup. Leave empty for evaluation media; use your key or the public KMS client key (GVLK) for volume license media."
}

variable "virtio_dir" {
  type        = string
  default     = ""
  description = "Directory prepared by scripts/fetch-virtio.sh (viostor, vioscsi and NetKVM drivers plus virtio-win-guest-tools.exe). Empty means build/virtio-<windows_version> in the repository."
}

variable "build_password" {
  type        = string
  sensitive   = true
  description = "Administrator password used during the build only (WinRM). scripts/build.sh generates a random one. Cloudbase-Init replaces it at first boot."
}

variable "ui_language" {
  type        = string
  default     = "en-US"
  description = "Setup and system language. Must match a language present on the ISO."
}

variable "time_zone" {
  type        = string
  default     = "UTC"
  description = "Windows time zone id (tzutil /l)."
}

variable "ntp_servers" {
  type        = string
  default     = "time.windows.com"
  description = "Space separated NTP servers. DHCP provided servers still win when Cloudbase-Init finds some (ntp_use_dhcp_config)."
}

variable "install_updates" {
  type        = bool
  default     = true
  description = "Install Windows Updates during the build (needs Internet access from the build VM, adds 30 to 120 minutes)."
}

variable "cloudbase_init_msi_url" {
  type        = string
  default     = "https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi"
  description = "Cloudbase-Init installer. The Stable URL redirects to the current stable release (1.1.8 in November 2026)."
}

variable "cloudbase_init_msi_sha256" {
  type        = string
  default     = ""
  description = "Optional SHA256 of the Cloudbase-Init MSI. Empty skips the check."
}

variable "disk_size" {
  type        = string
  default     = "40G"
  description = "Virtual disk size. The image is sparse and compressed; Cloudbase-Init extends C: to the flavor or volume size."
}

variable "disk_interface" {
  type        = string
  default     = "virtio"
  description = "Disk bus of the build VM: virtio (virtio-blk) or virtio-scsi. Both drivers are installed, so the image boots on either."
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type        = number
  default     = 8192
  description = "RAM of the build VM, in MiB."
}

variable "headless" {
  type        = bool
  default     = true
  description = "Set to false to see the VM console (or connect a VNC client to the port Packer prints)."
}

variable "qemu_binary" {
  type        = string
  default     = "qemu-system-x86_64"
  description = "QEMU binary. RHEL and derivatives ship /usr/libexec/qemu-kvm; scripts/build.sh detects it."
}

variable "ovmf_code" {
  type        = string
  default     = "/usr/share/OVMF/OVMF_CODE_4M.fd"
  description = "OVMF firmware code, UEFI builds only. Fedora/RHEL: /usr/share/edk2/ovmf/OVMF_CODE.fd. scripts/build.sh detects it."
}

variable "ovmf_vars" {
  type        = string
  default     = "/usr/share/OVMF/OVMF_VARS_4M.fd"
  description = "OVMF variables template matching ovmf_code, UEFI builds only."
}

variable "output_dir" {
  type        = string
  default     = ""
  description = "Parent directory of the build output. Empty means output/ in the repository."
}

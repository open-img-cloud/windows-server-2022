#!/usr/bin/env bash
# Builds a Windows Server cloud image (qcow2) for OpenStack or Proxmox from
# YOUR Windows Server ISO, on Linux with QEMU/KVM and Packer.
#
# Usage:
#   scripts/build.sh --iso PATH [--version 2022|2025] [--edition EDITION]
#                    [--firmware bios|uefi] [--product-key KEY]
#                    [--no-updates] [--headless false] [-- extra packer args]
#
#   EDITION: standard (default), datacenter, standard-core, datacenter-core
#
# Output: output/windows-server-<version>-<edition>-<firmware>/*.qcow2
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

iso="" version="2022" edition="standard" firmware="bios" product_key=""
updates="true" headless="true"
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --iso) iso="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --edition) edition="$2"; shift 2 ;;
    --firmware) firmware="$2"; shift 2 ;;
    --product-key) product_key="$2"; shift 2 ;;
    --no-updates) updates="false"; shift ;;
    --headless) headless="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$iso" ] || { echo "--iso is required" >&2; usage >&2; exit 2; }
[ -f "$iso" ] || { echo "ISO not found: $iso" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Host requirements.
qemu_binary="$(command -v qemu-system-x86_64 || true)"
if [ -z "$qemu_binary" ] && [ -x /usr/libexec/qemu-kvm ]; then
  qemu_binary=/usr/libexec/qemu-kvm
fi
missing=()
[ -n "$qemu_binary" ] || missing+=(qemu-system-x86_64)
for bin in packer qemu-img xorriso curl; do
  command -v "$bin" >/dev/null || missing+=("$bin")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "missing tools: ${missing[*]} (see README, Prerequisites)" >&2
  exit 1
fi
[ -w /dev/kvm ] || { echo "/dev/kvm is not writable: enable KVM and add your user to the kvm group" >&2; exit 1; }

ovmf_args=()
if [ "$firmware" = "uefi" ]; then
  code="" vars=""
  for pair in \
    "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd" \
    "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd" \
    "/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd" \
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd" \
    "/usr/share/qemu/ovmf-x86_64-code.bin:/usr/share/qemu/ovmf-x86_64-vars.bin"; do
    if [ -f "${pair%%:*}" ] && [ -f "${pair##*:}" ]; then
      code="${pair%%:*}" vars="${pair##*:}"
      break
    fi
  done
  [ -n "$code" ] || { echo "OVMF firmware not found (package ovmf or edk2-ovmf)" >&2; exit 1; }
  ovmf_args=(-var "ovmf_code=$code" -var "ovmf_vars=$vars")
fi

# VirtIO drivers for this Windows release.
if [ ! -f "$repo_root/build/virtio-$version/virtio-win-guest-tools.exe" ]; then
  "$repo_root/scripts/fetch-virtio.sh" "$version"
fi

# Build only Administrator password: random, never stored in the repository.
# It is replaced at first boot by Cloudbase-Init (SetUserPasswordPlugin).
if [ -z "${PKR_VAR_build_password:-}" ]; then
  PKR_VAR_build_password="Oic-$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)-9a"
  export PKR_VAR_build_password
fi
if [ -n "$product_key" ]; then
  export PKR_VAR_product_key="$product_key"
fi

cd "$repo_root/packer"
packer init .
packer validate \
  -var "iso_path=$iso" -var "windows_version=$version" -var "edition=$edition" \
  -var "firmware=$firmware" "${ovmf_args[@]}" .
PACKER_LOG="${PACKER_LOG:-0}" packer build \
  -var "iso_path=$iso" \
  -var "windows_version=$version" \
  -var "edition=$edition" \
  -var "firmware=$firmware" \
  -var "install_updates=$updates" \
  -var "headless=$headless" \
  -var "qemu_binary=$qemu_binary" \
  "${ovmf_args[@]}" "${extra[@]}" .

out="$repo_root/output/windows-server-$version-$edition-$firmware"
echo
echo "Image ready: $out/windows-server-$version-$edition-$firmware.qcow2"
echo "Next: README.md, sections 'Upload to OpenStack Glance' and 'Import into Proxmox VE'."

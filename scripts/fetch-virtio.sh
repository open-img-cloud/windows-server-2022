#!/usr/bin/env bash
# Prepares the VirtIO drivers for one Windows Server release:
#   build/virtio-<version>/{viostor,vioscsi,NetKVM}/  drivers loaded by Windows Setup
#   build/virtio-<version>/virtio-win-guest-tools.exe all drivers + QEMU guest agent
#
# Usage: scripts/fetch-virtio.sh <2022|2025>
# Environment:
#   VIRTIO_ISO      use this local virtio-win ISO instead of downloading one
#                   (for example /usr/share/virtio-win/virtio-win.iso from the
#                   virtio-win package)
#   VIRTIO_CHANNEL  stable (default) or latest
# Source: https://github.com/virtio-win/virtio-win-pkg-scripts
set -euo pipefail

version="${1:-2022}"
case "$version" in
  2022) osdir=2k22 ;;
  2025) osdir=2k25 ;;
  *) echo "usage: $0 <2022|2025>" >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/build"
dest="$build_dir/virtio-$version"
channel="${VIRTIO_CHANNEL:-stable}"
case "$channel" in
  stable|latest) ;;
  *) echo "VIRTIO_CHANNEL must be stable or latest" >&2; exit 2 ;;
esac

command -v xorriso >/dev/null || { echo "xorriso is required (package xorriso)" >&2; exit 1; }

iso="${VIRTIO_ISO:-}"
if [ -z "$iso" ]; then
  iso="$build_dir/cache/virtio-win-$channel.iso"
  url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/$channel-virtio/virtio-win.iso"
  mkdir -p "$build_dir/cache"
  if [ ! -s "$iso" ]; then
    echo "Downloading $url"
    curl -fL --retry 3 -o "$iso.part" "$url"
    mv "$iso.part" "$iso"
  fi
fi
[ -s "$iso" ] || { echo "virtio-win ISO not found: $iso" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest"
for drv in viostor vioscsi NetKVM; do
  xorriso -osirrox on -indev "$iso" -extract "/$drv/$osdir/amd64" "$dest/$drv" >/dev/null 2>&1 \
    || true
  if ! ls "$dest/$drv"/*.inf >/dev/null 2>&1; then
    echo "driver $drv/$osdir/amd64 missing from $iso (too old for Windows Server $version?)" >&2
    exit 1
  fi
done
xorriso -osirrox on -indev "$iso" -extract /virtio-win-guest-tools.exe "$dest/virtio-win-guest-tools.exe" >/dev/null 2>&1 || true
[ -s "$dest/virtio-win-guest-tools.exe" ] || { echo "virtio-win-guest-tools.exe missing from $iso" >&2; exit 1; }

# Files extracted from an ISO are read-only; Packer copies the tree into a
# new CD image and must be able to write inside the copied directories.
chmod -R u+w "$dest"

volid="$(xorriso -indev "$iso" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -n1)"
echo "VirtIO drivers for Windows Server $version ready in $dest (${volid:-unknown virtio-win version})"

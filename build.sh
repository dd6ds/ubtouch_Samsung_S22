#!/bin/bash
# Ubuntu Touch 24.04 (Halium 16) for Galaxy S22 (r0s) and S22 Ultra (b0s), Exynos only.
#
#   ./build.sh <r0s|b0s|all> [stage...]
#
# stages (default: kernel images rootfs pack):
#   kernel  - LineageOS s5e9925 kernel + Halium config, modules, dtbs      (~1-2 h, 25 GB)
#   images  - boot.img, vendor_boot.img, dtbo.img (needs templates/<dev>, see README)
#   rootfs  - ubuntu.img (UT 24.04-2.x rootfs + Halium 16 GSI + device layer)
#   pack    - flash kit dir + SHA256SUMS in work/out/<dev>/
#
# Example: ./build.sh r0s kernel        # once
#          scripts/pull-templates.sh r0s # phone in LineageOS recovery
#          ./build.sh r0s images rootfs pack
set -euo pipefail
cd "$(dirname "$0")"
source scripts/lib.sh

target="${1:-}"; shift || true
[ -n "$target" ] || { sed -n '2,15p' "$0"; exit 1; }
stages=("$@"); [ ${#stages[@]} -gt 0 ] || stages=(kernel images rootfs pack)
devices=("$target"); [ "$target" = all ] && devices=(r0s b0s)

pack() {
	load_device "$1"
	msg "[$1] Flash kit"
	for f in boot.img vendor_boot.img dtbo.img ubuntu.img; do [ -f "$OUT/$f" ] || die "$OUT/$f missing"; done
	cp "$KIT/flash.sh" "$OUT/flash.sh"
	cp "$KIT/deviceinfo/$1.conf" "$OUT/deviceinfo.conf"
	(cd "$OUT" && sha256sum boot.img vendor_boot.img dtbo.img vbmeta-disabled.img ubuntu.img > SHA256SUMS)
	{ echo "device:  $1 ($deviceinfo_name)"; echo "kernel:  $(cat "$OUT/KERNELRELEASE")";
	  echo "source:  $deviceinfo_kernel_source_branch @ $(git -C "$KSRC" rev-parse --short HEAD 2>/dev/null || echo ?)";
	  echo "halium:  $deviceinfo_halium_version"; echo "channel: $deviceinfo_ubuntu_touch_channel";
	  echo "built:   $(date -u +%Y-%m-%dT%H:%MZ)"; } > "$OUT/build-info.txt"
	cat "$OUT/build-info.txt"
	info "flash with: cd work/out/$1 && ./flash.sh"
}

for d in "${devices[@]}"; do
	for s in "${stages[@]}"; do
		case "$s" in
			kernel) scripts/build-kernel.sh "$d" ;;
			images) scripts/make-boot-images.sh "$d" ;;
			rootfs) scripts/make-rootfs.sh "$d" ;;
			pack)   pack "$d" ;;
			*) die "unknown stage '$s'" ;;
		esac
	done
done

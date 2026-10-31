#!/bin/bash
# Install Ubuntu Touch on a Galaxy S22 (r0s) / S22 Ultra (b0s) from LineageOS recovery.
# Run from the flash-kit folder (work/out/<dev>/) with the phone in LineageOS recovery
# and "Advanced -> Enable ADB" on. No Odin/fastboot needed: Samsung has no fastboot,
# so everything is written with dd over adb (recovery runs as root).
#
#   ./flash.sh                full install: backup, format /data, ubuntu.img, boot images
#   ./flash.sh --boot-only    only boot + vendor_boot + dtbo (kernel iteration, keeps /data)
#   ./flash.sh --rootfs-only  only re-format /data and copy ubuntu.img
#   ./flash.sh --vbmeta       also write vbmeta-disabled.img (stock firmware without LineageOS)
#   ./flash.sh --restore DIR  write back boot/vendor_boot/dtbo from a backup folder
#
# WARNING: a full install wipes everything on the phone's internal storage.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./deviceinfo.conf
DEV="$deviceinfo_codename"
MODE=full; VBMETA=0; RESTORE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--boot-only) MODE=boot ;;
		--rootfs-only) MODE=rootfs ;;
		--vbmeta) VBMETA=1 ;;
		--restore) MODE=restore; RESTORE="${2:?backup dir}"; shift ;;
		*) echo "unknown option $1"; exit 1 ;;
	esac
	shift
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
sh_()  { adb shell "$@" | tr -d '\r'; }
psize() { sh_ blockdev --getsize64 "/dev/block/by-name/$1"; }

write_part() { # write_part PARTITION IMAGE
	local p="$1" img="$2" isz psz
	isz=$(stat -c %s "$img"); psz=$(psize "$p")
	[ -n "$psz" ] || die "partition $p not found"
	[ "$isz" -le "$psz" ] || die "$img ($isz) larger than $p ($psz)"
	adb push "$img" "/tmp/$p.img"
	sh_ "dd if=/tmp/$p.img of=/dev/block/by-name/$p bs=4194304 conv=fsync 2>&1 | tail -1; rm /tmp/$p.img"
	echo "    $p <- $img"
}

command -v adb >/dev/null || die "install adb (android-tools) first"
[ "$MODE" = restore ] || sha256sum -c SHA256SUMS --quiet || die "checksum mismatch"

step "Waiting for $deviceinfo_name in LineageOS recovery (adb)"
adb wait-for-recovery
model="$(sh_ getprop ro.product.device)"; bl="$(sh_ getprop ro.boot.bootloader)"
[ "$model" = "$DEV" ] || die "phone reports '$model', this kit is for '$DEV' ($deviceinfo_models)"
echo "    device $model, bootloader ${bl:-?}"
[ "$(sh_ id -u)" = 0 ] || die "recovery adb shell is not root"

if [ "$MODE" = restore ]; then
	step "Restoring from $RESTORE"
	for p in boot vendor_boot dtbo; do [ -f "$RESTORE/$p.img" ] && write_part "$p" "$RESTORE/$p.img"; done
	adb reboot recovery; exit 0
fi

step "Backing up current boot, vendor_boot, dtbo"
BK="backup-$DEV-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
for p in boot vendor_boot dtbo; do
	adb exec-out "dd if=/dev/block/by-name/$p bs=4194304 2>/dev/null" > "$BK/$p.img"
	[ "$(stat -c %s "$BK/$p.img")" = "$(psize $p)" ] || die "backup of $p incomplete"
done
echo "    saved in $BK/ (restore: ./flash.sh --restore $BK)"

if [ "$MODE" = full ] || [ "$MODE" = rootfs ]; then
	step "Formatting /data as ext4 (removes Android encryption and all user data)"
	echo "    5 seconds to abort with Ctrl+C ..."; sleep 5
	sh_ 'umount /data 2>/dev/null; umount /sdcard 2>/dev/null; true'
	sh_ 'mke2fs -F -t ext4 -L userdata /dev/block/by-name/userdata >/dev/null 2>&1 && echo "    ok"' | grep -q ok \
		|| die "mke2fs failed (is this LineageOS recovery?)"
	sh_ 'mount -t ext4 /dev/block/by-name/userdata /data && df -h /data | tail -1'
	step "Copying ubuntu.img to /data ($(du -h ubuntu.img | cut -f1), a few minutes)"
	adb push ubuntu.img /data/ubuntu.img
	sh_ 'sync; umount /data'
fi

if [ "$MODE" = full ] || [ "$MODE" = boot ]; then
	step "Writing boot images"
	write_part dtbo dtbo.img
	write_part vendor_boot vendor_boot.img
	write_part boot boot.img
	[ "$VBMETA" = 1 ] && write_part vbmeta vbmeta-disabled.img
fi

step "Rebooting into Ubuntu Touch"
echo "    First boot can take several minutes (resize + first setup)."
echo "    Back to recovery: hold Power + Vol Up while plugged into USB."
adb reboot

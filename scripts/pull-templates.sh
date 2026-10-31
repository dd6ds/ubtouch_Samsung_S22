#!/bin/bash
# Collect the phone's own boot images as templates + backup, and the firmware that
# first-stage drivers need (GPU, touchscreen, ...) from its vendor_boot ramdisk.
#
#   scripts/pull-templates.sh r0s|b0s                 # phone in LineageOS recovery (adb)
#   scripts/pull-templates.sh r0s|b0s --from-ap AP_S901BXX....tar.md5   # offline, stock firmware
#
# Result: templates/<dev>/{boot,vendor_boot,dtbo,recovery,vbmeta}.img   (backup!)
#         templates/<dev>/header.env + bootconfig.txt                   (boot header values)
#         templates/<dev>/vendor-ramdisk-firmware/{lib,vendor}/firmware (packed into our vendor_boot)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_device "${1:-}"
need python3 lz4 cpio
setup_tools
AP=""; [ "${2:-}" = "--from-ap" ] && AP="$(realpath "${3:?path to AP_*.tar.md5}")"
mkdir -p "$TEMPLATE_DIR"
cd "$TEMPLATE_DIR"

if [ -n "$AP" ]; then
	msg "[$DEVICE] Extracting images from $(basename "$AP")"
	for p in boot vendor_boot dtbo recovery vbmeta; do
		tar -xf "$AP" "$p.img.lz4" 2>/dev/null && lz4 -q -d -f "$p.img.lz4" "$p.img" && rm -f "$p.img.lz4" \
			&& info "$p.img" || warn "$p.img.lz4 not in AP tar"
	done
else
	need adb
	msg "[$DEVICE] Waiting for the phone in recovery (adb)"
	adb wait-for-recovery
	model="$(adb shell getprop ro.product.device | tr -d '\r')"
	[ "$model" = "$DEVICE" ] || die "phone reports '$model', expected '$DEVICE'"
	adb shell getprop > device-props.txt
	for p in boot vendor_boot dtbo recovery vbmeta; do
		sz="$(adb shell blockdev --getsize64 /dev/block/by-name/$p | tr -d '\r')"
		adb exec-out "dd if=/dev/block/by-name/$p bs=4194304 2>/dev/null" > "$p.img"
		[ "$(stat -c %s "$p.img")" = "$sz" ] || die "$p.img: short read"
		info "$p.img  $((sz / 1048576)) MiB"
	done
fi

msg "[$DEVICE] Boot header values"
python3 "$KIT/scripts/tmpl.py" "$TOOLS/mkbootimg/unpack_bootimg.py" boot.img vendor_boot.img .

msg "[$DEVICE] First-stage firmware from vendor_boot ramdisk"
U="$(mktemp -d)"; trap 'rm -rf "$U"' EXIT
python3 "$TOOLS/mkbootimg/unpack_bootimg.py" --boot_img vendor_boot.img --out "$U" >/dev/null
rm -rf vendor-ramdisk-firmware; mkdir -p vendor-ramdisk-firmware
for frag in "$U"/vendor_ramdisk*; do
	[ -f "$frag" ] || continue
	case "$(head -c4 "$frag" | od -An -tx1 | tr -d ' ')" in
		1f8b*) dec=(gzip -dc) ;;
		*) dec=(lz4 -dc) ;;
	esac
	(cd vendor-ramdisk-firmware && "${dec[@]}" < "$frag" | cpio -idm --quiet 'lib/firmware/*' 'vendor/firmware/*' 2>/dev/null) || true
done
find vendor-ramdisk-firmware -type f | sed 's|^vendor-ramdisk-firmware/|    |'
[ -n "$(find vendor-ramdisk-firmware -type f)" ] || warn "no firmware found in vendor_boot (GPU will likely fail at first stage)"
msg "[$DEVICE] Templates saved in templates/$DEVICE - keep these images as your backup"

#!/bin/bash
# Build ubuntu.img for one device: UT 24.04 rootfs + Halium 16 GSI + our device layer.
#   scripts/make-rootfs.sh r0s|b0s
# Same assembly as the vayu kit (build-2404.sh), no sudo needed (fakeroot + mkfs.ext4 -d).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_device "${1:-}"
need curl python3 fakeroot mkfs.ext4 xz tar
umask 022

[ -f "$KOUT/KERNELRELEASE" ] || die "kernel not built yet: run scripts/build-kernel.sh $DEVICE"
KREL="$(cat "$KOUT/KERNELRELEASE")"
CH="$deviceinfo_ubuntu_touch_channel"
REF="${UT_REF_DEVICE:-surya}"   # any android9plus device in the channel; only its rootfs is used

msg "[$DEVICE] Ubuntu Touch rootfs ($CH)"
ROOTFS_PATH="$(curl -fsSL "$SI_BASE/$CH/$REF/index.json" | python3 -c "
import json,sys; d=json.load(sys.stdin); f=[i for i in d['images'] if i['type']=='full'][-1]
print([x['path'] for x in f['files'] if '/rootfs-' in x['path']][0])")"
ROOTFS="$DL/$(basename "$ROOTFS_PATH")"
fetch "$SI_BASE$ROOTFS_PATH" "$ROOTFS"

msg "[$DEVICE] Halium $deviceinfo_halium_version GSI (UBports CI)"
HAL="$DL/halium-$deviceinfo_halium_version-arm64.tar.xz"
fetch "$UBPORTS_CI/job/halium-$deviceinfo_halium_version.0/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz" "$HAL"

msg "[$DEVICE] Device layer"
D="$WORK/tmp/$DEVICE-device"; rm -rf "$D"; mkdir -p "$D/system/usr/lib/modules" "$D/system/etc/modules-load.d" \
	"$D/system/etc/deviceinfo/devices" "$D/system/etc/modprobe.d" "$D/system/etc/system-image/config.d"
cp -a "$KSTAGE/lib/modules/$KREL" "$D/system/usr/lib/modules/"
# modules that Android/LineageOS would load from /vendor_dlkm (stock copies don't match our kernel)
printf '# Galaxy %s: modules normally loaded from /vendor_dlkm\n' "$DEVICE" > "$D/system/etc/modules-load.d/s22-vendor-dlkm.conf"
for m in $deviceinfo_late_modules; do echo "$m" >> "$D/system/etc/modules-load.d/s22-vendor-dlkm.conf"; done
cat > "$D/system/etc/deviceinfo/devices/$DEVICE.yaml" <<EOF
$DEVICE:
  Name: $DEVICE
  PrettyName: $deviceinfo_name
  DeviceType: phone
  GridUnit: $deviceinfo_gridunit
  PrimaryOrientation: Portrait
EOF
if [ "$DEVICE" = b0s ]; then
	# Broadcom dhd reads firmware/nvram by path (Kconfig default /etc/wifi/...);
	# on Android the Wi-Fi HAL redirects it, on Ubuntu Touch we do it here.
	mkdir -p "$D/system/etc/wifi"
	for f in bcmdhd_sta.bin bcmdhd_clm.blob bcmdhd_mfg.bin; do ln -sf "/vendor/firmware/$f" "$D/system/etc/wifi/$f"; done
	ln -sf /vendor/etc/wifi/nvram_net.txt "$D/system/etc/wifi/nvram_net.txt"
	echo "options dhd firmware_path=/vendor/firmware/bcmdhd_sta.bin clm_path=/vendor/firmware/bcmdhd_clm.blob" \
		> "$D/system/etc/modprobe.d/bcmdhd.conf"
fi
# system-image channel info (OTA updates from UBports will not exist for this port)
printf "[service]\nbase: system-image.ubports.com\nhttp_port: 80\nhttps_port: 443\nchannel: %s\ndevice: %s\n" "$CH" "$DEVICE" \
	> "$D/system/etc/system-image/channel.ini"
ln -s ../client.ini "$D/system/etc/system-image/config.d/00_default.ini"
ln -s ../channel.ini "$D/system/etc/system-image/config.d/01_channel.ini"
[ -d "$KIT/overlay/common/system" ] && cp -a "$KIT/overlay/common/system/." "$D/system/"
[ -d "$KIT/overlay/$DEVICE/system" ] && cp -a "$KIT/overlay/$DEVICE/system/." "$D/system/"
chmod 0755 "$D/system"
DEVTAR="$WORK/tmp/device_$DEVICE.tar.xz"
tar -cJf "$DEVTAR" -C "$D" --owner=root --group=root system
rm -rf "$D"

msg "[$DEVICE] Assemble ubuntu.img"
STAGE="$WORK/tmp/$DEVICE-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
export STAGE OUT LIST="$ROOTFS $HAL $DEVTAR"
fakeroot -- bash -ec '
umask 022
cd "$STAGE"
first=1
for f in $LIST; do
	echo "    extract $(basename $f)"
	if [ $first = 1 ]; then
		xzcat "$f" | tar --numeric-owner -xf -; first=0
	else
		xzcat "$f" | tar --numeric-owner --no-overwrite-dir --keep-directory-symlink -xf -
		xzcat "$f" | tar -tf - | grep "^system/." | sed "s|/$||" | while read p; do
			[ -L "$p" ] || [ -k "$p" ] || chmod go-w "$p" 2>/dev/null || true
		done
	fi
done
chmod 0755 system
if [ -e system/var/lib/lxc/android/system.img ]; then
	mv system/var/lib/lxc/android/system.img system/var/lib/lxc/android/android-rootfs.img
fi
[ -e system/var/lib/lxc/android/android-rootfs.img ] || { echo "Halium GSI image missing in rootfs"; exit 1; }
SZ=$(du -sm system | cut -f1); SZ=$((SZ + 1024))
echo "    rootfs ${SZ} MiB"
rm -f "$OUT/ubuntu.img"
truncate -s ${SZ}M "$OUT/ubuntu.img"
mkfs.ext4 -F -q -L ubuntu -d system "$OUT/ubuntu.img"
'
rm -rf "$STAGE"
ls -lh "$OUT/ubuntu.img"
msg "[$DEVICE] ubuntu.img done"

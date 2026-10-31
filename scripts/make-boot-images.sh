#!/bin/bash
# Pack boot.img, vendor_boot.img and dtbo.img for one device from the kernel build.
#   scripts/make-boot-images.sh r0s|b0s
#  boot.img        : our kernel + Halium "dynparts" initramfs (GKI-capable), lz4
#  vendor_boot.img : first-stage modules (modules/<dev>.load + deps) + dtb + cmdline/bootconfig
#  dtbo.img        : board-revision overlays from dts/<dev>.cfg
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_device "${1:-}"
need python3 lz4 cpio gzip curl
setup_tools

[ -f "$KOUT/KERNELRELEASE" ] || die "kernel not built yet: run scripts/build-kernel.sh $DEVICE"
KREL="$(cat "$KOUT/KERNELRELEASE")"
MODDIR="$KSTAGE/lib/modules/$KREL"
FLAT="$KOUT/dtbs-flat"
T="$WORK/tmp/$DEVICE"; rm -rf "$T"; mkdir -p "$T"

# ---------------------------------------------------------------- boot ramdisk
msg "[$DEVICE] Halium initramfs"
fetch "$HALIUM_RAMDISK_URL" "$DL/initrd.img-touch-arm64"
gzip -dc "$DL/initrd.img-touch-arm64" > "$T/halium-ramdisk.cpio"
lz4 -q -l -12 -f "$T/halium-ramdisk.cpio" "$T/halium-ramdisk.lz4"

# -------------------------------------------------------------- vendor ramdisk
msg "[$DEVICE] Vendor ramdisk modules ($deviceinfo_vendor_ramdisk_modules)"
VR="$T/vendor-ramdisk"; mkdir -p "$VR/lib/modules"
# resolve every listed module + its dependencies (modules.dep paths are relative to $MODDIR)
python3 - "$MODDIR" "$KIT/$deviceinfo_vendor_ramdisk_modules" "$VR/lib/modules" <<'EOF'
import os, shutil, sys
moddir, loadfile, dst = sys.argv[1:4]
dep = {}
for line in open(os.path.join(moddir, "modules.dep")):
    k, _, v = line.rstrip("\n").partition(":")
    dep[k] = v.split()
byname = {os.path.basename(k): k for k in dep}
want = [l.strip() for l in open(loadfile) if l.strip() and not l.startswith("#")]
missing, copy, order = [], [], []
def add(rel):
    if rel in copy: return
    for d in dep.get(rel, []): add(d)
    copy.append(rel)
for m in want:
    if m not in byname: missing.append(m); continue
    add(byname[m]); order.append(m)
for rel in copy:
    shutil.copy2(os.path.join(moddir, rel), dst)
with open(os.path.join(dst, "modules.dep"), "w") as f:      # flat GKI-style paths
    for rel in copy:
        f.write("/lib/modules/%s:%s\n" % (os.path.basename(rel),
                "".join(" /lib/modules/" + os.path.basename(d) for d in dep[rel])))
with open(os.path.join(dst, "modules.load"), "w") as f:
    f.write("\n".join(order) + "\n")
for extra in ("modules.alias", "modules.softdep"):
    p = os.path.join(moddir, extra)
    if os.path.exists(p): shutil.copy2(p, dst)
print(f"    {len(order)} listed, {len(copy)} copied incl. deps")
if missing:
    print(f"    WARN: {len(missing)} listed modules not built: {' '.join(missing[:12])}{' ...' if len(missing) > 12 else ''}")
EOF
if [ -d "$TEMPLATE_DIR/vendor-ramdisk-firmware" ]; then
	cp -a "$TEMPLATE_DIR/vendor-ramdisk-firmware/." "$VR/"
	info "first-stage firmware: $(find "$TEMPLATE_DIR/vendor-ramdisk-firmware" -type f | wc -l) files from templates/$DEVICE"
else
	warn "templates/$DEVICE/vendor-ramdisk-firmware missing: no GPU (sgpu) / touch firmware in vendor_boot."
	warn "Run scripts/pull-templates.sh $DEVICE first (README step 3), or expect a black screen."
	[ "${ALLOW_NO_FIRMWARE:-0}" = 1 ] || die "set ALLOW_NO_FIRMWARE=1 to build anyway (CI test builds)"
fi
(cd "$VR" && find . | cpio -o -H newc --quiet) | lz4 -q -l -12 > "$T/vendor-ramdisk.lz4"
info "vendor ramdisk $(du -h "$T/vendor-ramdisk.lz4" | cut -f1)"

# --------------------------------------------------------------- dtb / dtbo
msg "[$DEVICE] dtb.img + dtbo.img"
$MKDTBOIMG cfg_create "$T/dtb.img"  "$KIT/$deviceinfo_dtb_cfg"  -d "$FLAT"
$MKDTBOIMG cfg_create "$OUT/dtbo.img" "$KIT/$deviceinfo_dtbo_cfg" -d "$FLAT"
avb_footer "$OUT/dtbo.img" "$deviceinfo_dtbo_partition_size" dtbo

# ------------------------------------------------------- cmdline / bootconfig
VCMD="$(echo "${template_vendor_cmdline:-} $deviceinfo_kernel_cmdline_extra" | xargs)"
BC="$T/bootconfig.txt"
if [ -n "${template_bootconfig_file:-}" ] && [ -f "$template_bootconfig_file" ]; then
	grep -v '^androidboot.selinux' "$template_bootconfig_file" > "$BC" || true
else
	echo "buildtime_bootconfig=enable" > "$BC"
fi
for kv in $deviceinfo_bootconfig_extra; do echo "$kv" >> "$BC"; done
info "vendor cmdline: $VCMD"
info "bootconfig: $(tr '\n' ' ' < "$BC")"

# ----------------------------------------------------------------- images
msg "[$DEVICE] boot.img"
$MKBOOTIMG --header_version 4 \
	--kernel "$KOUT/arch/arm64/boot/Image" --ramdisk "$T/halium-ramdisk.lz4" \
	--cmdline "${template_boot_cmdline:-}" \
	--os_version "$deviceinfo_bootimg_os_version" --os_patch_level "$deviceinfo_bootimg_os_patch_level" \
	-o "$OUT/boot.img"
avb_footer "$OUT/boot.img" "$deviceinfo_bootimg_partition_size" boot

msg "[$DEVICE] vendor_boot.img"
$MKBOOTIMG --header_version 4 --vendor_boot "$OUT/vendor_boot.img" \
	--pagesize "$deviceinfo_bootimg_pagesize" --base "$deviceinfo_bootimg_base" \
	--kernel_offset "$deviceinfo_bootimg_kernel_offset" --ramdisk_offset "$deviceinfo_bootimg_ramdisk_offset" \
	--tags_offset "$deviceinfo_bootimg_tags_offset" --dtb_offset "$deviceinfo_bootimg_dtb_offset" \
	--dtb "$T/dtb.img" --vendor_cmdline "$VCMD" --vendor_bootconfig "$BC" \
	--ramdisk_type platform --ramdisk_name '' --vendor_ramdisk_fragment "$T/vendor-ramdisk.lz4"
avb_footer "$OUT/vendor_boot.img" "$deviceinfo_vendor_boot_partition_size" vendor_boot

# A "disabled" vbmeta, only needed if the phone does NOT already run LineageOS
# (LineageOS ships vbmeta with --flags 3 already). See README, path B.
$AVBTOOL make_vbmeta_image --flags 3 --padding_size 4096 --output "$OUT/vbmeta-disabled.img"

echo "$KREL" > "$OUT/KERNELRELEASE"
ls -lh "$OUT"/*.img
msg "[$DEVICE] Boot images done"

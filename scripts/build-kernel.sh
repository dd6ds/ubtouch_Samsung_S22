#!/bin/bash
# Build the Halium-enabled s5e9925 kernel, modules and device trees for one device.
#   scripts/build-kernel.sh r0s|b0s
# Env:  JOBS=n            parallel jobs (default: nproc)
#       USE_SYSTEM_CLANG=1 use clang/lld/llvm-* from PATH instead of AOSP clang
#       CLANG_VERSION / CLANG_BRANCH  pick another AOSP clang (default r510928)
#       MENUCONFIG=1      open menuconfig after merging the config
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_device "${1:-}"
need git curl make python3 bc bison flex perl lz4 cpio

msg "[$DEVICE] Kernel source ($deviceinfo_kernel_source_branch)"
git_shallow "$deviceinfo_kernel_source" "$deviceinfo_kernel_source_branch" "$KSRC"
info "$(git -C "$KSRC" log -1 --format='%h %cd %s' --date=short)"
cp "$KIT/kernel/halium-samsung.config" "$KSRC/arch/arm64/configs/halium-samsung.config"

msg "[$DEVICE] Toolchain"
if [ "${USE_SYSTEM_CLANG:-0}" = 1 ]; then
	need clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-strip
	info "system $(clang --version | head -1)"
else
	CLANG_DIR="$SRC/clang-$CLANG_VERSION"
	if [ ! -x "$CLANG_DIR/bin/clang" ]; then
		# googlesource streams this ~2.5 GB archive and often cuts it off; verify before use
		ARCHIVE="$DL/clang-$CLANG_VERSION.tar.gz"
		if fetch "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/$CLANG_BRANCH/clang-$CLANG_VERSION.tar.gz" "$ARCHIVE" \
			&& gzip -t "$ARCHIVE" 2>/dev/null; then
			mkdir -p "$CLANG_DIR" && tar -xzf "$ARCHIVE" -C "$CLANG_DIR"
		else
			rm -f "$ARCHIVE" "$ARCHIVE.part"
			warn "AOSP clang $CLANG_VERSION download failed or truncated - falling back to system clang"
			USE_SYSTEM_CLANG=1
		fi
	fi
	if [ "${USE_SYSTEM_CLANG:-0}" = 1 ]; then
		need clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-strip
		info "system $(clang --version | head -1)"
	else
		export PATH="$CLANG_DIR/bin:$PATH"
		info "AOSP $(clang --version | head -1)"
	fi
fi

KMAKE=(make -C "$KSRC" O="$KOUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -j"${JOBS:-$(nproc)}")

msg "[$DEVICE] Config: $deviceinfo_kernel_defconfig"
# shellcheck disable=SC2086
"${KMAKE[@]}" $deviceinfo_kernel_defconfig
[ "${MENUCONFIG:-0}" = 1 ] && "${KMAKE[@]}" menuconfig
"$KIT/scripts/check-config.sh" "$KOUT/.config" "$KIT/kernel/halium-samsung.config"

msg "[$DEVICE] Compile Image, modules, dtbs (ThinLTO: this takes a while)"
"${KMAKE[@]}" Image modules dtbs

msg "[$DEVICE] Install modules"
rm -rf "$KSTAGE"; mkdir -p "$KSTAGE"
"${KMAKE[@]}" INSTALL_MOD_PATH="$KSTAGE" INSTALL_MOD_STRIP=1 modules_install
KREL="$(cat "$KOUT/include/config/kernel.release")"
rm -f "$KSTAGE/lib/modules/$KREL/build" "$KSTAGE/lib/modules/$KREL/source"
echo "$KREL" > "$KOUT/KERNELRELEASE"
info "kernel release $KREL, $(find "$KSTAGE" -name '*.ko' | wc -l) modules"

msg "[$DEVICE] Collect device trees"
FLAT="$KOUT/dtbs-flat"; rm -rf "$FLAT"; mkdir -p "$FLAT"
find "$KOUT/arch/arm64/boot/dts/exynos" "$KOUT/arch/arm64/boot/dts/samsung/$DEVICE" \
	\( -name '*.dtb' -o -name '*.dtbo' \) -exec cp {} "$FLAT/" \;
for cfg in "$deviceinfo_dtb_cfg" "$deviceinfo_dtbo_cfg"; do
	grep -E '^[^ #].*\.dtbo?$' "$KIT/$cfg" | while read -r f; do
		[ -f "$FLAT/$f" ] || die "$f listed in $cfg was not built"
	done
done
info "$(ls "$FLAT" | wc -l) dtb/dtbo files"
ls -lh "$KOUT/arch/arm64/boot/Image"
msg "[$DEVICE] Kernel done"

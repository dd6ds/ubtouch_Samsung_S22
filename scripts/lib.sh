# Shared helpers for the Galaxy S22 / S22 Ultra Ubuntu Touch kit.  Sourced, not run.
# shellcheck shell=bash

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$KIT/work}"
SRC="$WORK/src"          # kernel source + tool checkouts (shared by both devices)
DL="$WORK/dl"            # downloads (rootfs, Halium GSI, ramdisk, clang)
TOOLS="$WORK/tools"      # mkbootimg, avbtool, mkdtboimg

CLANG_VERSION="${CLANG_VERSION:-r510928}"            # AOSP main-kernel-build-2024
CLANG_BRANCH="${CLANG_BRANCH:-main-kernel-build-2024}"
HALIUM_RAMDISK_URL="${HALIUM_RAMDISK_URL:-https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64}"
SI_BASE="https://system-image.ubports.com"
UBPORTS_CI="https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64"

msg()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

need() {
	local missing=()
	for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
	[ ${#missing[@]} -eq 0 ] || die "missing tools: ${missing[*]} (see README: 'Build host packages' or use ./build-docker.sh)"
}

# load_device r0s|b0s -> sources deviceinfo/<dev>.conf and sets per-device paths
load_device() {
	DEVICE="$1"
	case "$DEVICE" in r0s|b0s) ;; *) die "unknown device '$DEVICE' (use r0s = S22, b0s = S22 Ultra)";; esac
	# shellcheck disable=SC1090
	source "$KIT/deviceinfo/$DEVICE.conf"
	OUT="$WORK/out/$DEVICE"              # final images
	KOUT="$WORK/kernel-obj/$DEVICE"      # kernel O= dir
	KSTAGE="$WORK/kernel-stage/$DEVICE"  # modules_install root
	TEMPLATE_DIR="$KIT/templates/$DEVICE"
	KSRC="$SRC/kernel"
	mkdir -p "$OUT" "$KOUT" "$KSTAGE" "$SRC" "$DL" "$TOOLS"
	# templates/<dev>/header.env (from pull-templates.sh) wins over deviceinfo defaults
	if [ -f "$TEMPLATE_DIR/header.env" ]; then
		# shellcheck disable=SC1091
		source "$TEMPLATE_DIR/header.env"
		info "using boot header values from templates/$DEVICE/header.env"
	fi
}

fetch() { # fetch URL DEST  (skips if DEST exists and is non-empty)
	[ -s "$2" ] && { info "have $(basename "$2")"; return 0; }
	info "download $(basename "$2")"
	curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"
}

git_shallow() { # git_shallow URL BRANCH DIR
	if [ -d "$3/.git" ]; then info "have $(basename "$3")"; return 0; fi
	git clone -q --depth 1 -b "$2" "$1" "$3"
}

setup_tools() {
	msg "Host tools (mkbootimg, avbtool, mkdtboimg)"
	git_shallow https://github.com/LineageOS/android_system_tools_mkbootimg lineage-23.0 "$TOOLS/mkbootimg"
	git_shallow https://github.com/LineageOS/android_external_avb lineage-23.2 "$TOOLS/avb"
	if [ ! -s "$TOOLS/mkdtboimg.py" ]; then
		# python3 version from AOSP libufdt (googlesource serves base64 with ?format=TEXT)
		curl -fsSL "https://android.googlesource.com/platform/system/libufdt/+/refs/heads/main/utils/src/mkdtboimg.py?format=TEXT" \
			| base64 -d > "$TOOLS/mkdtboimg.py"
	fi
	MKBOOTIMG="python3 $TOOLS/mkbootimg/mkbootimg.py"
	UNPACK_BOOTIMG="python3 $TOOLS/mkbootimg/unpack_bootimg.py"
	AVBTOOL="python3 $TOOLS/avb/avbtool.py"
	MKDTBOIMG="python3 $TOOLS/mkdtboimg.py"
}

avb_footer() { # avb_footer IMAGE PARTITION_SIZE NAME
	$AVBTOOL add_hash_footer --image "$1" --partition_size "$2" --partition_name "$3"
}

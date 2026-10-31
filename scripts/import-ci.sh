#!/bin/bash
# Unpack a GitHub Actions artifact (s22-ut-<dev>) into work/ so only the local
# "images" and "pack" stages remain.
#   scripts/import-ci.sh r0s ~/Downloads/s22-ut-r0s      (folder or .zip)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_device "${1:-}"
need zstd tar
SRCA="$(realpath "${2:?artifact folder or zip}")"
if [ -f "$SRCA" ] && [[ "$SRCA" == *.zip ]]; then
	need unzip
	X="$(mktemp -d)"; trap 'rm -rf "$X"' EXIT
	unzip -q "$SRCA" -d "$X"; SRCA="$X"
fi
cd "$SRCA"
sha256sum -c "SHA256SUMS-$DEVICE" --quiet || die "artifact checksum mismatch"
msg "[$DEVICE] kernel, modules, dtbs -> $WORK"
zstd -dc "kernel-$DEVICE.tar.zst" | tar -C "$WORK" -xf -
msg "[$DEVICE] ubuntu.img -> $OUT"
zstd -d -f -q "ubuntu-$DEVICE.img.zst" -o "$OUT/ubuntu.img"
info "kernel $(cat "$KOUT/KERNELRELEASE")"
info "next: scripts/pull-templates.sh $DEVICE  then  ./build.sh $DEVICE images pack"

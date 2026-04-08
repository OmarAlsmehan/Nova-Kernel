#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

print_header "GKI packaging"
DEST="$PACKAGE_BASE"
mkdir -p "$DEST"

: "${DTB_NAME:?DTB_NAME is required — check .github/config/nova-env.sh}"

KERNEL_IMAGE="$OUT_DIR/arch/arm64/boot/Image"
DTB="$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/$DTB_NAME"
BOOT_IMG="$TC_DIR/images/$DEVICE_IMAGE/boot.img"
DTBO_IMG="$OUT_DIR/arch/arm64/boot/dtbo.img"
VENDOR_BOOT_IMG="$TC_DIR/images/$DEVICE_IMAGE/vendor_boot.img"

[[ -f "$KERNEL_IMAGE" ]] || { echo "::error::Missing kernel Image"; exit 1; }
[[ -f "$DTB" ]] || { echo "::error::Missing DTB: $DTB"; exit 1; }
[[ -f "$BOOT_IMG" ]] || { echo "::error::Missing boot image: $BOOT_IMG"; exit 1; }
[[ -f "$DTBO_IMG" ]] || { echo "::error::Missing dtbo image: $DTBO_IMG"; exit 1; }
[[ -f "$VENDOR_BOOT_IMG" ]] || { echo "::error::Missing vendor_boot image: $VENDOR_BOOT_IMG"; exit 1; }

cp "$DTBO_IMG" "$DEST/dtbo.img"
bash "$(dirname "$0")/repack-boot.sh" "$DEST" "$BOOT_IMG" "$KERNEL_IMAGE"
bash "$(dirname "$0")/repack-vendor-boot.sh" "$DEST" "$VENDOR_BOOT_IMG" "$DTB"
bash "$(dirname "$0")/create-zip.sh"

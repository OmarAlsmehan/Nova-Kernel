#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

print_header "AnyKernel3 packaging"

AK3_DIR="$RUNNER_TEMP/${KERNEL_NAME:?KERNEL_NAME is required}-AnyKernel3"
rm -rf "$AK3_DIR"
git clone --depth=1 "${AK3_REPO:?AK3_REPO is required}" "$AK3_DIR"

: "${DTB_NAME:?DTB_NAME is required — check .github/config/nova-env.sh}"

cp "$OUT_DIR/arch/arm64/boot/Image" "$AK3_DIR/Image"
cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/$DTB_NAME" "$AK3_DIR/dtb"
cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$AK3_DIR/dtbo.img"

: "${ZIP_NAME:?ZIP_NAME must be set by main.sh before calling this script}"
ZIP_PATH="$PACKAGE_BASE/$ZIP_NAME"
(
    cd "$AK3_DIR"
    zip -r -9 "$ZIP_PATH" . -x '.git' -x '.git/*' -x '*/.git/*'
)

export ZIP_PATH ZIP_NAME
printf 'ZIP_PATH=%s\n' "$ZIP_PATH" >> "$GITHUB_ENV"
printf 'ZIP_NAME=%s\n' "$ZIP_NAME" >> "$GITHUB_ENV"
printf 'PACKAGE_MODE=AnyKernel3\n' >> "$GITHUB_ENV"

echo "✅ AnyKernel3 package created"

#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

resolve_build_type
resolve_package_paths
make_zip_name   # computed ONCE here; gki.sh/anykernel3.sh inherit it as a real
                # env var (child processes see a parent's exports) instead of
                # each calling date +%H%M independently and risking a mismatch

print_header "${KERNEL_NAME:-NovaKernel} — Pack Process"
print_kv "Device" "$DEVICE_IMAGE ($VARIANT)"
print_kv "Type" "$BUILD_TYPE"
print_kv "Package" "$ZIP_NAME"

shopt -s nullglob
MODULE_FILES=("$MODULES_DIR"/*.ko)
shopt -u nullglob
KO_COUNT="${#MODULE_FILES[@]}"

export KO_COUNT
printf 'KO_COUNT=%s\n' "$KO_COUNT" >> "$GITHUB_ENV"

if (( KO_COUNT > 0 )); then
    PACKAGE_MODE=GKI
    echo "📦 Detected $KO_COUNT kernel module(s) → GKI"
    printf 'PACKAGE_MODE=%s\n' "$PACKAGE_MODE" >> "$GITHUB_ENV"
    export PACKAGE_MODE
    bash "$SCRIPT_DIR/gki.sh"
else
    PACKAGE_MODE=AnyKernel3
    echo "📦 No kernel modules detected → AnyKernel3"
    printf 'PACKAGE_MODE=%s\n' "$PACKAGE_MODE" >> "$GITHUB_ENV"
    export PACKAGE_MODE
    bash "$SCRIPT_DIR/anykernel3.sh"
fi

# ZIP_NAME/ZIP_PATH were already computed once at the top of this script
# and inherited by the child packaging script — no need to recompute.
ZIP_PATH="$PACKAGE_BASE/$ZIP_NAME"
export ZIP_PATH ZIP_NAME

[[ -f "$ZIP_PATH" ]] || { echo "::error::Package was not created: $ZIP_PATH"; exit 1; }

SHA="$(sha256sum "$ZIP_PATH" | awk '{print $1}')"
SIZE="$(du -sh "$ZIP_PATH" | cut -f1)"
printf 'ZIP_PATH=%s\n' "$ZIP_PATH" >> "$GITHUB_ENV"
printf 'ZIP_NAME=%s\n' "$ZIP_NAME" >> "$GITHUB_ENV"
printf 'ZIP_SHA256=%s\n' "$SHA" >> "$GITHUB_ENV"
printf 'ZIP_SIZE=%s\n' "$SIZE" >> "$GITHUB_ENV"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Package ready"
echo "  Name   : $ZIP_NAME"
echo "  Mode   : ${PACKAGE_MODE:-unknown}"
echo "  Size   : $SIZE"
echo "  SHA256 : $SHA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

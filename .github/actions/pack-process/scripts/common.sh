#!/usr/bin/env bash
set -euo pipefail

print_header() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_kv() {
    printf '  %-12s %s\n' "$1:" "$2"
}

resolve_build_type() {
    if [[ "${KERNELSU_ENABLED:-false}" == "true" ]]; then
        BUILD_TYPE=KSU
    else
        BUILD_TYPE=GKI
    fi
    export BUILD_TYPE
}

resolve_package_paths() {
    : "${OUT_DIR:?OUT_DIR is required}"
    : "${VARIANT:?VARIANT is required}"
    : "${DEVICE_IMAGE:?DEVICE_IMAGE is required}"
    : "${TC_DIR:?TC_DIR is required}"

    PACKAGE_BASE="$TC_DIR/${KERNEL_NAME:?KERNEL_NAME is required}/$DEVICE_IMAGE/$BUILD_TYPE"
    MODULES_DIR="${MODULES_DIR:-$PACKAGE_BASE/modules}"
    export PACKAGE_BASE MODULES_DIR
    mkdir -p "$PACKAGE_BASE"
}

get_ksu_version() {
    local cmd="$OUT_DIR/drivers/kernelsu/.ksu.o.cmd"
    if [[ "$BUILD_TYPE" == "KSU" && -f "$cmd" ]]; then
        grep -oP -- '-DKSU_VERSION=\K[0-9]+' "$cmd" 2>/dev/null | sed 's/^/-/' | head -n1 || true
    fi
}

make_zip_name() {
    local ksu_ver
    ksu_ver="$(get_ksu_version)"
    ZIP_NAME="${KERNEL_NAME}_${OS}_$(date +%Y%m%d-%H%M)_${BUILD_TYPE}${ksu_ver}_${VARIANT}.zip"
    export ZIP_NAME
}

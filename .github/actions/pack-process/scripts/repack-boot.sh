#!/usr/bin/env bash
set -euo pipefail

DEST="$1"
IMAGE="$2"
KERNEL_IMAGE="$3"

cp "$IMAGE" "$DEST/boot.img"
avbtool erase_footer --image "$DEST/boot.img"

local_tmp="$DEST/.boot-tmp"
rm -rf "$local_tmp"
mkdir -p "$local_tmp"
(
    cd "$local_tmp"
    magiskboot unpack ../boot.img
    rm -f kernel
    cp "$KERNEL_IMAGE" kernel
    magiskboot repack ../boot.img boot.img
    mv -f boot.img ../boot.img
)
rm -rf "$local_tmp"

echo "✅ boot.img repacked"

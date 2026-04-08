#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

DEST="$1"
IMAGE="$2"
DTB="$3"

cp "$IMAGE" "$DEST/vendor_boot.img"
avbtool erase_footer --image "$DEST/vendor_boot.img"

TMP="$DEST/.vendor-boot-tmp"
rm -rf "$TMP"
mkdir -p "$TMP"
(
    cd "$TMP"
    # magiskboot returns 3 for a valid vendor_boot image.
    # Accept status 3 instead of letting set -e abort the packaging step.
    magiskboot unpack -h ../vendor_boot.img || {
        rc=$?
        if (( rc != 3 )); then
            echo "::error::Failed to unpack vendor_boot.img (magiskboot status: $rc)"
            exit "$rc"
        fi
        echo "ℹ️ vendor_boot image detected (magiskboot status 3)"
    }

    sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header

    rm -f dtb
    cp "$DTB" dtb

    magiskboot cpio ramdisk.cpio "extract first_stage_ramdisk/fstab.qcom fstab.qcom"
    awk 'BEGIN{OFS="\t"} /^(system|vendor|product|odm)[[:space:]]/&&!seen[$1]++ {rest=$4;for(i=5;i<=NF;i++)rest=rest"\t"$i;for(i=1;i<=3;i++)print $1,$2,(i==1?"erofs":i==2?"ext4":"f2fs"),rest;next}1' fstab.qcom > fstab.qcom.new

    declare -a CPIO_TODO=()
    CPIO_TODO+=("rm first_stage_ramdisk/fstab.qcom")
    CPIO_TODO+=("add 0644 first_stage_ramdisk/fstab.qcom fstab.qcom.new")
    CPIO_TODO+=("mkdir 0755 lib/firmware")

    case "$DEVICE_IMAGE" in
        A73)
            FWDIR="lib/firmware/tsp_synaptics"
            SRCDIR="$GITHUB_WORKSPACE/firmware/tsp_synaptics"
            CPIO_TODO+=("mkdir 0755 ${FWDIR}")
            for f in s3908_a73xq_boe.bin s3908_a73xq_csot.bin s3908_a73xq_sdc.bin s3908_a73xq_sdc_4th.bin; do
                [[ -f "$SRCDIR/$f" ]] || { echo "::error::Missing firmware: $SRCDIR/$f"; exit 1; }
                CPIO_TODO+=("add 0644 ${FWDIR}/${f} ${SRCDIR}/${f}")
            done
            ;;
        A52S)
            FWDIR="lib/firmware/tsp_stm"
            SRCDIR="$GITHUB_WORKSPACE/firmware/tsp_stm"
            CPIO_TODO+=("mkdir 0755 ${FWDIR}")
            [[ -f "$SRCDIR/fts5cu56a_a52sxq.bin" ]] || { echo "::error::Missing firmware: $SRCDIR/fts5cu56a_a52sxq.bin"; exit 1; }
            CPIO_TODO+=("add 0644 ${FWDIR}/fts5cu56a_a52sxq.bin ${SRCDIR}/fts5cu56a_a52sxq.bin")
            ;;
        M52)
            FWDIR="lib/firmware/abov"
            SRCDIR="$GITHUB_WORKSPACE/firmware/abov"
            CPIO_TODO+=("mkdir 0755 ${FWDIR}")
            for f in a96t356_m52xq.bin a96t356_m52xq_sub.bin; do
                [[ -f "$SRCDIR/$f" ]] || { echo "::error::Missing firmware: $SRCDIR/$f"; exit 1; }
                CPIO_TODO+=("add 0644 ${FWDIR}/${f} ${SRCDIR}/${f}")
            done

            FWDIR2="lib/firmware/tsp_synaptics"
            SRCDIR2="$GITHUB_WORKSPACE/firmware/tsp_synaptics"
            CPIO_TODO+=("mkdir 0755 ${FWDIR2}")
            for f in s3908_m52xq.bin s3908_m52xq_boe.bin s3908_m52xq_sdc.bin; do
                [[ -f "$SRCDIR2/$f" ]] || { echo "::error::Missing firmware: $SRCDIR2/$f"; exit 1; }
                CPIO_TODO+=("add 0644 ${FWDIR2}/${f} ${SRCDIR2}/${f}")
            done
            ;;
        *)
            echo "::error::Unsupported DEVICE_IMAGE: $DEVICE_IMAGE"
            exit 1
            ;;
    esac

    CPIO_TODO+=("rm -r lib/modules")
    CPIO_TODO+=("mkdir 0755 lib/modules")

    # Keep the complete module set exactly as staged by build-modules:
    # .ko files + modules.alias + modules.dep + modules.load + modules.softdep.
    shopt -s nullglob
    MODULE_FILES=("$MODULES_DIR"/*)
    shopt -u nullglob

    for module in "${MODULE_FILES[@]}"; do
        [[ -f "$module" ]] || continue
        CPIO_TODO+=("add 0644 lib/modules/$(basename "$module") $module")
    done

    magiskboot cpio ramdisk.cpio "${CPIO_TODO[@]}"
    magiskboot repack ../vendor_boot.img vendor_boot.img
    mv -f vendor_boot.img ../vendor_boot.img
)
rm -rf "$TMP"

echo "✅ vendor_boot.img repacked"

#!/bin/env bash

set -e
set -o pipefail

check_dependencies() {
    local missing=false

    for tool in git curl wget jq unzip tar lz4 awk sed sha1sum md5sum; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed."
            missing=true
        fi
    done

    if $missing; then
        echo "Exiting due to missing dependencies." >&2
        exit 1
    fi
}

check_dependencies

################################################ Vars
USR_NAME="$(whoami)" SRC_DIR="$(pwd)" OUT_DIR="$SRC_DIR/out" TC_DIR="$HOME/toolchains" JOBS=$(nproc)
export USR_NAME
export SRC_DIR
export OUT_DIR
export TC_DIR
export JOBS

################################################ Tools
CLANGVER="clang-r530567" CLANG_PREBUILT_BIN="$TC_DIR/$CLANGVER/bin/"
export CLANGVER
export CLANG_PREBUILT_BIN
export PATH="$TC_DIR:$CLANG_PREBUILT_BIN:$PATH"

################################################ Environment
fetch_tools() {
    if [[ ! -d "$CLANG_PREBUILT_BIN" ]]; then
        mkdir -p "$TC_DIR/$CLANGVER"
        AOSPTC_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/$CLANGVER.tar.gz"
        echo "  -> Downloading Clang toolchain ($CLANGVER)..."
        [ ! -f "$TC_DIR/$CLANGVER.tar.gz" ] && wget "$AOSPTC_URL" -P "$TC_DIR"
        tar xf "$TC_DIR/$CLANGVER.tar.gz" -C "$TC_DIR/$CLANGVER"
        rm "$TC_DIR/$CLANGVER.tar.gz"
    fi

    if [[ ! -f "$TC_DIR/magiskboot" ]]; then
        APK_URL="$(curl -s "https://api.github.com/repos/topjohnwu/Magisk/releases" | grep -oE 'https://[^\"]+\.apk' | grep 'Magisk[-.]v' | head -n 1)"
        echo "  -> Downloading Magisk..."
        [ ! -f "$TC_DIR/magisk.apk" ] && wget "$APK_URL" -P "$TC_DIR" -O "$TC_DIR/magisk.apk"
        unzip -p "$TC_DIR/magisk.apk" "lib/x86_64/libmagiskboot.so" > "$TC_DIR/magiskboot"
        chmod +x "$TC_DIR/magiskboot"
        mkdir -p "$TC_DIR/magisk"
        unzip -p "$TC_DIR/magisk.apk" "assets/stub.apk" > "$TC_DIR/magisk/stub.apk"
        unzip -p "$TC_DIR/magisk.apk" "lib/arm64-v8a/libinit-ld.so" > "$TC_DIR/magisk/init-ld"
        unzip -p "$TC_DIR/magisk.apk" "lib/arm64-v8a/libmagiskinit.so" > "$TC_DIR/magisk/magiskinit"
        unzip -p "$TC_DIR/magisk.apk" "lib/arm64-v8a/libmagisk.so" > "$TC_DIR/magisk/magisk"
    fi

    if [[ ! -f "$TC_DIR/avbtool" ]]; then
        AVBTOOL_URL="https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT"
        echo "  -> Downloading avbtool..."
        curl -s "$AVBTOOL_URL" | base64 --decode > "$TC_DIR/avbtool"
        chmod +x "$TC_DIR/avbtool"
    fi

    if [[ ! -d "$TC_DIR/images" ]]; then
        mkdir -p "$TC_DIR/images"
        declare -A d
        d["A73"]="ngdplnk/proprietary_vendor_samsung_a73xq"
        d["A52S"]="RisenID/proprietary_vendor_samsung_a52sxq"
        d["M52"]="ngdplnk/proprietary_vendor_samsung_m52xq"
        echo "  -> Downloading Stock Images..."
        for n in "${!d[@]}"; do
            mkdir -p "$TC_DIR/images/$n"
            wget -qO- "$(curl -s "https://api.github.com/repos/${d[$n]}/releases/latest" | \
                jq -r '.assets[] | select(.name | test(".*_kernel.tar$")) | .browser_download_url')" | \
                tar xf - -C "$TC_DIR/images/$n" && \
                lz4 -dm --rm "$TC_DIR/images/$n/"*
        done
    fi
}

build_kernel() {
    case "$1" in
    
    export VARIANT="a73xq"; export DEVICE="A73";;
    export ARCH=arm64
    export BRANCH="android11"
    export KMI_GENERATION=2
    export LLVM=1
    export DEPMOD=depmod
    export KCFLAGS="${KCFLAGS} -D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1
    export IN_KERNEL_MODULES=1
    export DO_NOT_STRIP_MODULES=1
    export DEFCONF="rio_defconfig"
    export FRAG="${VARIANT}.config"
    export ABI_DEFINITION=android/abi_gki_aarch64.xml
    export KMI_SYMBOL_LIST=android/abi_gki_aarch64
    export ADDITIONAL_KMI_SYMBOL_LISTS="
android/abi_gki_aarch64_cuttlefish
android/abi_gki_aarch64_db845c
android/abi_gki_aarch64_exynos
android/abi_gki_aarch64_exynosauto
android/abi_gki_aarch64_fcnt
android/abi_gki_aarch64_galaxy
android/abi_gki_aarch64_goldfish
android/abi_gki_aarch64_hikey960
android/abi_gki_aarch64_imx
android/abi_gki_aarch64_oneplus
android/abi_gki_aarch64_microsoft
android/abi_gki_aarch64_oplus
android/abi_gki_aarch64_qcom
android/abi_gki_aarch64_sony
android/abi_gki_aarch64_sonywalkman
android/abi_gki_aarch64_sunxi
android/abi_gki_aarch64_trimble
android/abi_gki_aarch64_unisoc
android/abi_gki_aarch64_vivo
android/abi_gki_aarch64_xiaomi
android/abi_gki_aarch64_zebra
"
    export TRIM_NONLISTED_KMI=0
    export KMI_SYMBOL_LIST_ADD_ONLY=1
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export KMI_ENFORCED=0
    echo "--------------------------------"
    echo "Target: $VARIANT (GKI Build)"
    echo "Toolchain: $(clang --version | head -n 1)"
    echo "--------------------------------"
    echo "--- Kernel Build Starting ---"
    START=$(date +%s)
    COMREV=$(git rev-parse --verify HEAD --short)
    export LOCALVERSION="-$BRANCH-$KMI_GENERATION-$COMREV-rio-$VARIANT"
    echo "Kernel Version: 5.4.x$LOCALVERSION"

    make -j$JOBS -C $SRC_DIR O=$OUT_DIR $DEFCONF $FRAG
    make -j$JOBS -C $SRC_DIR O=$OUT_DIR menuconfig
    make -j$JOBS -C $SRC_DIR O=$OUT_DIR

    echo "Kernel Build took: $(date -u -d @$(($(date +%s) - START)) +'%T')"
}

build_modules() {
    case "$1" in
        gki) export TYPE="GKI";;
        ksu) export TYPE="KSU";;
        *) echo "Unknown arg: $1"; exit 1;;
    esac
    echo "--- Module Build Starting ---"
    START=$(date +%s)
    make -j$JOBS -C $SRC_DIR O=$OUT_DIR INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

    mkdir -p "$TC_DIR/RIO/$DEVICE/$TYPE/modules"
    find "$OUT_DIR/modules" -name '*.ko' -exec cp '{}' "$TC_DIR/RIO/$DEVICE/$TYPE/modules" \;
    cp "$OUT_DIR/modules/lib/modules/$(cat "$OUT_DIR/include/config/kernel.release")/modules.alias" "$TC_DIR/RIO/$DEVICE/$TYPE/modules/modules.alias"
    cp "$OUT_DIR/modules/lib/modules/$(cat "$OUT_DIR/include/config/kernel.release")/modules.dep" "$TC_DIR/RIO/$DEVICE/$TYPE/modules/modules.dep"
    cp "$OUT_DIR/modules/lib/modules/$(cat "$OUT_DIR/include/config/kernel.release")/modules.softdep" "$TC_DIR/RIO/$DEVICE/$TYPE/modules/modules.softdep"
    cp "$OUT_DIR/modules/lib/modules/$(cat "$OUT_DIR/include/config/kernel.release")/modules.order" "$TC_DIR/RIO/$DEVICE/$TYPE/modules/modules.load"
    sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/lib\/modules\/\2/g' "$TC_DIR/RIO/$DEVICE/$TYPE/modules/modules.dep"
    sed -i 's/.*\///g' "$TC_DIR/RIO/$DEVICE/$TYPE/modules/modules.load"

    echo "Modules took: $(date -u -d @$(($(date +%s) - START)) +'%T')"
}

gen_artifact() {
    echo "--- Preparing Artifacts ---"
    mkdir -p "$TC_DIR/RIO/$DEVICE"\
        "$TC_DIR/RIO/$DEVICE/GKI/modules" \
        "$TC_DIR/RIO/$DEVICE/KSU/modules" \
        "$TC_DIR/RIO/$DEVICE/MAG" \
        "$TC_DIR/RIO/$DEVICE/ZIP/META-INF/com/google/android" \
        "$TC_DIR/RIO/$DEVICE/ZIP/images"
    cp "$OUT_DIR/arch/arm64/boot/Image" "$TC_DIR/RIO/$DEVICE/kernel"
    cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$TC_DIR/RIO/$DEVICE/GKI/dtbo.img"
    cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$TC_DIR/RIO/$DEVICE/dtb"

    touch "$TC_DIR/RIO/$DEVICE/ZIP/META-INF/com/google/android/updater-script" \
            "$TC_DIR/RIO/$DEVICE/ZIP/META-INF/com/google/android/update-binary"
    echo "# Dummy file; update-binary is a shell script." > "$TC_DIR/RIO/$DEVICE/ZIP/META-INF/com/google/android/updater-script"
    cat <<'EOF' > "$TC_DIR/RIO/$DEVICE/ZIP/META-INF/com/google/android/update-binary"
#!/sbin/sh
# Shell Script EDIFY Replacement: Recovery Flashable Zip
# osm0sis @ XDAdevelopers
# salvogiangri @ XDAdevelopers
# Frax3r @ XDAdevelopers
OUTFD=/proc/self/fd/$2;
ZIPFILE="$3";
TMPDIR="/cache/rio";
package_extract_dir() {
  local entry outfile;
  for entry in $(unzip -l "$ZIPFILE" 2>/dev/null | tail -n+4 | grep -v '/$' | grep -o " $1.*$" | cut -c2-); do
    outfile="$(echo "$entry" | sed "s|${1}|${2}|")";
    mkdir -p "$(dirname "$outfile")";
    unzip -o "$ZIPFILE" "$entry" -p > "$outfile";
  done;
}
ui_print() {
  while [ "$1" ]; do
    echo -e "ui_print $1
      ui_print" >> $OUTFD;
    shift;
  done;
}
write_raw_image() { dd if="$1" of="$2"; }
set_progress() { echo "set_progress $1" >> $OUTFD; }
ui_print " ";
ui_print "********************************************";
ui_print "          Generic Kernel Installer          ";
ui_print "                          by Frax3r         ";
ui_print "********************************************";
ui_print " ";
set_progress 0
if ! getprop ro.boot.bootloader | grep -qE "A736|A528|M526"; then
  ui_print "- Device is not supported, aborting...";
  exit 1;
fi
ui_print "- Extracting images";
mount -o rw,remount -t auto "/cache";
mkdir -p $TMPDIR;
package_extract_dir "images" "$TMPDIR/";
set_progress 20;
ui_print "- Flashing boot.img...";
write_raw_image "$TMPDIR/boot.img" "/dev/block/bootdevice/by-name/boot";
set_progress 40;
ui_print "- Flashing dtbo.img...";
write_raw_image "$TMPDIR/dtbo.img" "/dev/block/bootdevice/by-name/dtbo";
set_progress 60;
ui_print "- Flashing vendor_boot.img...";
write_raw_image "$TMPDIR/vendor_boot.img" "/dev/block/bootdevice/by-name/vendor_boot";
set_progress 80;
ui_print "- Cleaning up...";
rm -rf "$TMPDIR";
set_progress 100;
ui_print " ";
ui_print "********************************************";
ui_print " Flashing completed.                        ";
ui_print "     Make sure to check the UN1CA project.  ";
ui_print "********************************************";
ui_print " ";
EOF
}

gki_repack() {
    case "$1" in
        gki) export TYPE="GKI";;
        ksu) export TYPE="KSU";;
        *) echo "Unknown arg: $1"; exit 1;;
    esac
    echo "--- Generating GKI Images ---"
    mkdir -p "$TC_DIR/RIO/$DEVICE/$TYPE"
    cp "$TC_DIR/images/$DEVICE/boot.img" "$TC_DIR/RIO/$DEVICE/$TYPE/boot.img"
    avbtool erase_footer --image "$TC_DIR/RIO/$DEVICE/$TYPE/boot.img"
    ( mkdir -p "$TC_DIR/RIO/$DEVICE/$TYPE/tmp" && cd "$TC_DIR/RIO/$DEVICE/$TYPE/tmp"
        magiskboot unpack ../boot.img
        rm kernel && cp "$OUT_DIR/arch/arm64/boot/Image" kernel
        magiskboot repack ../boot.img boot.img
        rm ../boot.img && mv boot.img ../boot.img
        cd .. && rm -rf "$TC_DIR/RIO/$DEVICE/$TYPE/tmp"
    )

    cp "$TC_DIR/images/$DEVICE/vendor_boot.img" "$TC_DIR/RIO/$DEVICE/$TYPE/vendor_boot.img"
    avbtool erase_footer --image "$TC_DIR/RIO/$DEVICE/$TYPE/vendor_boot.img"
    ( mkdir -p "$TC_DIR/RIO/$DEVICE/$TYPE/tmp" && cd "$TC_DIR/RIO/$DEVICE/$TYPE/tmp"
        magiskboot unpack -h ../vendor_boot.img || true
        sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header
        [[ $DEBUG ]] && sed -i '2 s/$/ androidboot.selinux=permissive/' header
        rm dtb && cp "$TC_DIR/RIO/$DEVICE/dtb" dtb
        magiskboot cpio ramdisk.cpio "extract first_stage_ramdisk/fstab.qcom fstab.qcom"
        awk 'BEGIN{OFS="\t"} /^(system|vendor|product|odm)\s/&&!seen[$1]++{rest=$4;for(i=5;i<=NF;i++)rest=rest"\t"$i;for(i=1;i<=3;i++)print $1,$2,(i==1?"erofs":i==2?"ext4":"f2fs"),rest;next}1' fstab.qcom > fstab.qcom.new
        declare -a cpio_todo=()
        cpio_todo+=("rm first_stage_ramdisk/fstab.qcom")
        cpio_todo+=("add 0644 first_stage_ramdisk/fstab.qcom fstab.qcom.new")
        cpio_todo+=("mkdir 0755 lib/firmware")
        case "$DEVICE" in
            A73)
                local fwdir="lib/firmware/tsp_synaptics" srcdir="$SRC_DIR/firmware/tsp_synaptics"
                cpio_todo+=("mkdir 0755 ${fwdir}")
                for f in s3908_a73xq_boe.bin s3908_a73xq_csot.bin s3908_a73xq_sdc.bin s3908_a73xq_sdc_4th.bin; do
                    cpio_todo+=("add 0644 ${fwdir}/${f} ${srcdir}/${f}")
                done
                ;;
            A52S)
                local fwdir="lib/firmware/tsp_stm" srcdir="$SRC_DIR/firmware/tsp_stm"
                cpio_todo+=("mkdir 0755 ${fwdir}")
                cpio_todo+=("add 0644 ${fwdir}/fts5cu56a_a52sxq.bin ${srcdir}/fts5cu56a_a52sxq.bin")
                ;;
            M52)
                local fwdir="lib/firmware/abov" srcdir="$SRC_DIR/firmware/abov"
                cpio_todo+=("mkdir 0755 ${fwdir}")
                for f in a96t356_m52xq.bin a96t356_m52xq_sub.bin; do
                    cpio_todo+=("add 0644 ${fwdir}/${f} ${srcdir}/${f}")
                done

                local fwdir="lib/firmware/tsp_synaptics" srcdir="$SRC_DIR/firmware/tsp_synaptics"
                cpio_todo+=("mkdir 0755 ${fwdir}")
                for f in s3908_m52xq.bin s3908_m52xq_boe.bin s3908_m52xq_sdc.bin; do
                    cpio_todo+=("add 0644 ${fwdir}/${f} ${srcdir}/${f}")
                done
                ;;
        esac
        cpio_todo+=("rm -r lib/modules")
        cpio_todo+=("mkdir 0755 lib/modules")
        for f in "$TC_DIR/RIO/$DEVICE/$TYPE/modules/"*; do
            cpio_todo+=("add 0644 lib/modules/$(basename "$f") $f")
        done
        magiskboot cpio ramdisk.cpio "${cpio_todo[@]}"
        magiskboot repack ../vendor_boot.img vendor_boot.img
        rm ../vendor_boot.img && mv vendor_boot.img ../vendor_boot.img
        cd .. && rm -rf "$TC_DIR/RIO/$DEVICE/$TYPE/tmp"
    )
}

mag_repack() {
    echo "--- Generating Magisk Images ---"
    cp "$TC_DIR/RIO/$DEVICE/GKI/boot.img" "$TC_DIR/RIO/$DEVICE/MAG/boot.img"
    ( mkdir -p "$TC_DIR/RIO/$DEVICE/MAG/tmp" && cd "$TC_DIR/RIO/$DEVICE/MAG/tmp"
        export KEEPVERITY=true
        export KEEPFORCEENCRYPT=true
        export LEGACYSAR=false

        magiskboot unpack ../boot.img
        cp -af ramdisk.cpio ramdisk.cpio.orig
        magiskboot compress=xz "$TC_DIR/magisk/magisk" magisk.xz
        magiskboot compress=xz "$TC_DIR/magisk/stub.apk" stub.xz
        magiskboot compress=xz "$TC_DIR/magisk/init-ld" init-ld.xz
        cat <<EOF > config
KEEPVERITY=$KEEPVERITY
KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT
RECOVERYMODE=false
VENDORBOOT=false
PREINITDEVICE=cache
SHA1=$(sha1sum ../boot.img | awk '{ print $1 }')
EOF

        magiskboot cpio ramdisk.cpio \
            "add 0750 init $TC_DIR/magisk/magiskinit" \
            "mkdir 0750 overlay.d" \
            "mkdir 0750 overlay.d/sbin" \
            "add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
            "add 0644 overlay.d/sbin/stub.xz stub.xz" \
            "add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
            "patch" \
            "backup ramdisk.cpio.orig" \
            "mkdir 000 .backup" \
            "add 000 .backup/.magisk config"

        rm -f config ./*.xz ramdisk.cpio.orig
        magiskboot repack ../boot.img boot.img
        magiskboot cleanup
        rm ../boot.img && mv boot.img ../boot.img
        cd .. && rm -rf "$TC_DIR/RIO/$DEVICE/MAG/tmp"
    )
}

gen_pack() {
    echo "--- Generating Packages ---"
    ZIP_WORKDIR="$TC_DIR/RIO/$DEVICE/ZIP"
    ODIN_WORKDIR="$ZIP_WORKDIR/images"
    for f in "$TC_DIR/RIO/$DEVICE/GKI" "$TC_DIR/RIO/$DEVICE/MAG" "$TC_DIR/RIO/$DEVICE/KSU"; do
        TYPE=$(basename "$f")
        [[ -f "$f/boot.img" ]] && cp -a "$f/boot.img" "$ZIP_WORKDIR/images/"

        if [[ -f "$f/dtbo.img" ]]; then
            cp -a "$f/dtbo.img" "$ZIP_WORKDIR/images/"
        else
            cp -a "$TC_DIR/RIO/$DEVICE/GKI/dtbo.img" "$ZIP_WORKDIR/images/"
        fi

        if [[ -f "$f/vendor_boot.img" ]]; then
            cp -a "$f/vendor_boot.img" "$ZIP_WORKDIR/images/"
        else
            cp -a "$TC_DIR/RIO/$DEVICE/GKI/vendor_boot.img" "$ZIP_WORKDIR/images/"
        fi

        echo "--- Tarring $TYPE ---"
        ( cd "$ODIN_WORKDIR"
            filelist=()
            for img in boot.img dtbo.img vendor_boot.img; do
                lz4 -12 -B6 --content-size -q --rm -f "$img" "$img.lz4"
                filelist+=("$img.lz4")
            done

            filename="RIO_$(date +%Y%m%d)_${TYPE}_${VARIANT}"
            tar --format=gnu \
                --owner=dpi \
                --group=dpi \
                --mode=644 \
                --overwrite \
                -cf "$filename.tar" "${filelist[@]}"

            echo -n "$(md5sum "$filename.tar" | cut -d " " -f1)" >> "$filename.tar"
            echo "  $filename.tar" >> "$filename.tar"
            mv "$filename.tar" "$f/$filename.tar.md5"
            lz4 --rm -d -m -q -f ./*
        )

        echo "--- Zipping $TYPE ---"
        [[ "$TYPE" == "KSU" ]] && KSU_VERSION=$(grep -oP -- "-DKSU_VERSION=\K[0-9]+" "$OUT_DIR/drivers/kernelsu/.ksu.o.cmd" 2>/dev/null | sed 's/^/-/')
        ( cd "$ZIP_WORKDIR"
            zip -r -9 "RIO_$(date +%Y%m%d)_${TYPE}${KSU_VERSION}_${VARIANT}.zip" images META-INF
            mv "$ZIP_WORKDIR"/RIO_*.zip "$f/"
        )

        rm -rf $ODIN_WORKDIR/*
    done
    rm -rf "$ZIP_WORKDIR"
}

ENTRY() {
    if [[ "$1" == "clean" ]]; then
        echo "--- Cleaning ---"
        rm -rf "$OUT_DIR" "$TC_DIR/RIO"
        exit 0
    fi

    DEBUG=false

    VARIANT="${1:-}"
    [[ -z "$VARIANT" ]] && { echo "Usage: $0 <a73xq|a52sxq|m52xq> | clean"; exit 1; }
    [[ ! "$VARIANT" =~ ^(a73xq|a52sxq|m52xq)$ ]] && { echo "Invalid device: $VARIANT"; exit 1; }

    echo "=== Building for $VARIANT ==="
    fetch_tools
    echo "--- Building GKI ---"
    git switch qcom_rio
    build_kernel "$VARIANT"
    build_modules gki
    gen_artifact
    gki_repack gki
    echo "--- Building KSU ---"
    make -C "$SRC_DIR" O="$OUT_DIR" clean
    git switch qcom_rio_ksu
    rm -rf $SRC_DIR/KernelSU
    git clone https://github.com/tiann/KernelSU.git
    build_kernel "$VARIANT"
    build_modules ksu
    gki_repack ksu

    echo "--- Packaging ---"
    mag_repack
    gen_pack

    echo "=== Build complete for $VARIANT ==="
}
ENTRY "${1:-}"
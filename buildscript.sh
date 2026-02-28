#!/bin/env bash

set -e
set -o pipefail

# ════════════════════════════════════════════════════════════════
#  NovaKernel Build Script
#  Devices: A73 (a73xq) | A52S (a52sxq) | M52 (m52xq)
# ════════════════════════════════════════════════════════════════

# ── Colors & Styles ──────────────────────────────────────────────
BOLD="\e[1m";  RESET="\e[0m";  DIM="\e[2m"
CYAN="\e[1;36m";  GREEN="\e[1;32m";  YELLOW="\e[1;33m"
RED="\e[1;31m";   BLUE="\e[1;34m";   MAGENTA="\e[1;35m"

IN_GHA="${GITHUB_ACTIONS:-false}"

# ── Logging helpers ──────────────────────────────────────────────
log_group_start() {
    if [[ "$IN_GHA" == "true" ]]; then
        echo "::group::  🔹 $1"
    else
        echo -e "\n${CYAN}${BOLD}╔════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}║  $1${RESET}"
        echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${RESET}"
    fi
}
log_group_end() { [[ "$IN_GHA" == "true" ]] && echo "::endgroup::"; }
log_notice()    { [[ "$IN_GHA" == "true" ]] && echo "::notice::$1" || true; }
log_step()      { echo -e "${GREEN}${BOLD}  ➤  $1${RESET}"; }
log_info()      { echo -e "${DIM}       $1${RESET}"; }
log_warn()      { echo -e "${YELLOW}  ⚠   $1${RESET}"
                  [[ "$IN_GHA" == "true" ]] && echo "::warning::$1" || true; }
log_ok()        { echo -e "${GREEN}  ✔   $1${RESET}"; }
log_err()       { echo -e "${RED}${BOLD}  ✖   $1${RESET}" >&2
                  [[ "$IN_GHA" == "true" ]] && echo "::error::$1" || true; }
log_kv()        { printf "  ${DIM}%-14s${RESET} ${BOLD}%s${RESET}\n" "$1" "$2"; }
log_sep()       { echo -e "${DIM}  ────────────────────────────────────────${RESET}"; }
elapsed()       { date -u -d @$(( $(date +%s) - $1 )) +'%-Mm %-Ss'; }
ts()            { date '+%H:%M:%S'; }

# ── Dependency check ─────────────────────────────────────────────
check_dependencies() {
    log_group_start "Dependency Check"
    local missing=false
    for tool in git curl wget jq unzip tar lz4 awk sed sha1sum md5sum zip; do
        if command -v "$tool" &>/dev/null; then
            log_info "$(printf '%-14s' "$tool")✔  $(command -v "$tool")"
        else
            log_err "Missing tool: '$tool'"
            missing=true
        fi
    done
    $missing && { log_err "Install missing tools and retry."; exit 1; }
    log_ok "All dependencies satisfied"
    log_group_end
}

# ── Variables ────────────────────────────────────────────────────
init_vars() {
    USR_NAME="$(whoami)"
    SRC_DIR="$(pwd)"
    OUT_DIR="$SRC_DIR/out"
    TC_DIR="$HOME/toolchains"
    JOBS=$(nproc)
    CLANGVER="clang-r563880c"
    CLANG_PREBUILT_BIN="$TC_DIR/$CLANGVER/bin/"
    export USR_NAME SRC_DIR OUT_DIR TC_DIR JOBS CLANGVER CLANG_PREBUILT_BIN
    export PATH="$TC_DIR:$CLANG_PREBUILT_BIN:$PATH"
}

# ── Tool fetching ────────────────────────────────────────────────
fetch_tools() {
    log_group_start "Toolchain & Assets"
    mkdir -p "$TC_DIR"

    if [[ ! -d "$CLANG_PREBUILT_BIN" ]]; then
        log_step "Downloading Clang ($CLANGVER)..."
        mkdir -p "$TC_DIR/$CLANGVER"
        local url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/$CLANGVER.tar.gz"
        wget -q --show-progress "$url" -P "$TC_DIR"
        tar xf "$TC_DIR/$CLANGVER.tar.gz" -C "$TC_DIR/$CLANGVER"
        rm "$TC_DIR/$CLANGVER.tar.gz"
        log_ok "Clang ready"
    else
        log_ok "Clang — cached ✓"
    fi

    if [[ ! -f "$TC_DIR/magiskboot" ]]; then
        log_step "Fetching magiskboot..."
        local apk_url
        apk_url="$(curl -s ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
            "https://api.github.com/repos/topjohnwu/Magisk/releases" \
            | grep -oE 'https://[^"]+\.apk' | grep 'Magisk[-.]v' | head -n1)"
        wget -q --show-progress "$apk_url" -O "$TC_DIR/magisk.apk"
        unzip -p "$TC_DIR/magisk.apk" "lib/x86_64/libmagiskboot.so" > "$TC_DIR/magiskboot"
        chmod +x "$TC_DIR/magiskboot"
        log_ok "magiskboot ready"
    else
        log_ok "magiskboot — cached ✓"
    fi

    if [[ ! -f "$TC_DIR/avbtool" ]]; then
        log_step "Fetching avbtool..."
        curl -s "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" \
            | base64 --decode > "$TC_DIR/avbtool"
        chmod +x "$TC_DIR/avbtool"
        log_ok "avbtool ready"
    else
        log_ok "avbtool — cached ✓"
    fi

    if [[ ! -d "$TC_DIR/images" ]]; then
        log_step "Downloading stock kernel images..."
        mkdir -p "$TC_DIR/images"
        declare -A image_urls=(
            ["A73"]="https://github.com/nicodotgit/proprietary_vendor_samsung_a73xq/releases/download/A736BXXSAGZA1_ODM/A736BXXSAGZA1_kernel.tar"
            ["A52S"]="https://github.com/RisenID/proprietary_vendor_samsung_a52sxq/releases/download/A528BXXUAGXK8_BTU/A528BXXUAGXK8_kernel.tar"
            ["M52"]="https://github.com/nicodotgit/proprietary_vendor_samsung_m52xq/releases/download/M526BXXS7CYE1_CAU/M526BXXS7CYE1_kernel.tar"
        )
        for name in "${!image_urls[@]}"; do
            log_step "→ Downloading $name image..."
            mkdir -p "$TC_DIR/images/$name"
            wget -qO- "${image_urls[$name]}" | tar xf - -C "$TC_DIR/images/$name"
            lz4 -dm --rm "$TC_DIR/images/$name/"*
            log_ok "$name image ready"
        done
    else
        log_ok "Stock images — cached ✓"
    fi

    log_group_end
}

# ── Kernel compile ───────────────────────────────────────────────
build_kernel() {
    log_group_start "Kernel Compile  [$(ts)]"
    case "$1" in
        a73xq)  VARIANT="a73xq";  DEVICE="A73";;
        a52sxq) VARIANT="a52sxq"; DEVICE="A52S";;
        m52xq)  VARIANT="m52xq";  DEVICE="M52";;
        *) log_err "Unknown variant: $1"; exit 1;;
    esac
    export VARIANT DEVICE ARCH=arm64

    export BRANCH="android11" KMI_GENERATION=2 LLVM=1 DEPMOD=depmod
    export KCFLAGS="${KCFLAGS} -D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1 IN_KERNEL_MODULES=1 DO_NOT_STRIP_MODULES=1
    export DEFCONF="nova_defconfig" FRAG="${VARIANT}.config"
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
    export TRIM_NONLISTED_KMI=0 KMI_SYMBOL_LIST_ADD_ONLY=1
    export KMI_SYMBOL_LIST_STRICT_MODE=0 KMI_ENFORCED=0

    COMREV=$(git rev-parse --short HEAD)
    export LOCALVERSION="-NovaKernel-${BRANCH}-${KMI_GENERATION}-${COMREV}-${VARIANT}"

    log_sep
    log_kv "Device:"    "$DEVICE ($VARIANT)"
    log_kv "Type:"      "$BUILD_TYPE"
    log_kv "Version:"   "5.4.x$LOCALVERSION"
    log_kv "Toolchain:" "$(clang --version | head -n1)"
    log_kv "Jobs:"      "$JOBS"
    log_sep

    local T0=$(date +%s)

    log_step "make clean..."
    [[ -d "$OUT_DIR" ]] && make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" clean 2>&1 | sed 's/^/       /'

    log_step "make defconfig + fragment..."
    make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" "$DEFCONF" "$FRAG" 2>&1 | sed 's/^/       /'

    log_step "make kernel..."
    make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" 2>&1 | sed 's/^/       /'

    log_ok "Kernel compiled in $(elapsed $T0)"
    log_group_end
}

# ── Modules ──────────────────────────────────────────────────────
build_modules() {
    log_group_start "Modules  [$(ts)]"
    local T0=$(date +%s)

    make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" \
        INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install 2>&1 | sed 's/^/       /'

    local MODOUT="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE/modules"
    mkdir -p "$MODOUT"
    find "$OUT_DIR/modules" -name '*.ko' -exec cp '{}' "$MODOUT/" \;

    local KREL
    KREL=$(cat "$OUT_DIR/include/config/kernel.release")
    local MODLIB="$OUT_DIR/modules/lib/modules/$KREL"
    cp "$MODLIB/modules.alias"   "$MODOUT/"
    cp "$MODLIB/modules.dep"     "$MODOUT/"
    cp "$MODLIB/modules.softdep" "$MODOUT/"
    cp "$MODLIB/modules.order"   "$MODOUT/modules.load"

    sed -i 's|\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)|/lib/modules/\2|g' "$MODOUT/modules.dep"
    sed -i 's|.*\/||g' "$MODOUT/modules.load"

    local KO_COUNT
    KO_COUNT=$(find "$MODOUT" -name '*.ko' | wc -l)
    log_ok "Modules done — ${KO_COUNT} .ko files  ($(elapsed $T0))"
    log_group_end
}

# ── Artifact staging ─────────────────────────────────────────────
stage_artifacts() {
    log_group_start "Staging Artifacts"
    mkdir -p \
        "$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE/modules" \
        "$TC_DIR/NovaKernel/$DEVICE/ZIP/META-INF/com/google/android" \
        "$TC_DIR/NovaKernel/$DEVICE/ZIP/images"

    cp "$OUT_DIR/arch/arm64/boot/Image"                      "$TC_DIR/NovaKernel/$DEVICE/kernel"
    cp "$OUT_DIR/arch/arm64/boot/dtbo.img"                   "$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE/dtbo.img"
    cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$TC_DIR/NovaKernel/$DEVICE/dtb"
    log_ok "Copied → kernel, dtbo.img, dtb"

    echo "# Dummy file; update-binary is a shell script." \
        > "$TC_DIR/NovaKernel/$DEVICE/ZIP/META-INF/com/google/android/updater-script"

cat >"$TC_DIR/NovaKernel/$DEVICE/ZIP/META-INF/com/google/android/update-binary" <<'FLASH_EOF'
#!/sbin/sh

OUTFD=/proc/self/fd/$2
ZIPFILE="$3"
TMPDIR="/cache/nova"

package_extract_dir() {
    local entry outfile
    for entry in $(unzip -l "$ZIPFILE" 2>/dev/null | tail -n+4 | grep -v '/$' \
                   | grep -o " $1.*$" | cut -c2-); do
        outfile="$(echo "$entry" | sed "s|${1}|${2}|")"
        mkdir -p "$(dirname "$outfile")"
        unzip -o "$ZIPFILE" "$entry" -p > "$outfile"
    done
}

ui_print() {
    while [ "$1" ]; do
        echo "ui_print $1" >> "$OUTFD"
        echo "ui_print" >> "$OUTFD"
        shift
    done
}

ui_printfile() {
    unzip -p "$ZIPFILE" "$1" 2>/dev/null | while IFS= read -r line; do
        ui_print "$line"
    done
}

write_raw_image() {
    dd if="$1" of="$2"
}

set_progress() {
    echo "set_progress $1" >> "$OUTFD"
}

set_progress 0
ui_printfile "banner"
ui_print " "
ui_print " "

if ! getprop ro.boot.bootloader | grep -qE "A736|A528|M526"; then
    ui_print "✖ Unsupported device — aborting."
    exit 1
fi

mount -o rw,remount -t auto /cache
mkdir -p "$TMPDIR"

ui_print "→ Extracting images..."
package_extract_dir "images" "$TMPDIR/"
set_progress 0.2

ui_print "→ Flashing boot.img..."
write_raw_image "$TMPDIR/boot.img" "/dev/block/bootdevice/by-name/boot"
set_progress 0.4

ui_print "→ Flashing dtbo.img..."
write_raw_image "$TMPDIR/dtbo.img" "/dev/block/bootdevice/by-name/dtbo"
set_progress 0.6

ui_print "→ Flashing vendor_boot.img..."
write_raw_image "$TMPDIR/vendor_boot.img" "/dev/block/bootdevice/by-name/vendor_boot"
set_progress 0.8

rm -rf "$TMPDIR"
set_progress 1.0

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Done! NovaKernel installed successfully."
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
FLASH_EOF

    chmod +x "$TC_DIR/NovaKernel/$DEVICE/ZIP/META-INF/com/google/android/update-binary"
    log_ok "Flash script → update-binary"
    log_group_end
}

# ── GKI image repack ─────────────────────────────────────────────
gki_repack() {
    log_group_start "Image Repack  [$(ts)]"
    local T0=$(date +%s)
    local DEST="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    mkdir -p "$DEST"

    log_step "Repacking boot.img..."
    cp "$TC_DIR/images/$DEVICE/boot.img" "$DEST/boot.img"
    avbtool erase_footer --image "$DEST/boot.img"
    (
        mkdir -p "$DEST/tmp" && cd "$DEST/tmp"
        magiskboot unpack ../boot.img
        rm kernel && cp "$OUT_DIR/arch/arm64/boot/Image" kernel
        magiskboot repack ../boot.img boot.img
        rm ../boot.img && mv boot.img ../boot.img
        cd .. && rm -rf tmp
    )
    log_ok "boot.img repacked"

    log_step "Repacking vendor_boot.img..."
    cp "$TC_DIR/images/$DEVICE/vendor_boot.img" "$DEST/vendor_boot.img"
    avbtool erase_footer --image "$DEST/vendor_boot.img"
    (
        mkdir -p "$DEST/tmp" && cd "$DEST/tmp"
        magiskboot unpack -h ../vendor_boot.img || true
        sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header
        [[ "${DEBUG:-false}" == "true" ]] && \
            sed -i '2 s/$/ androidboot.selinux=permissive/' header
        rm dtb && cp "$TC_DIR/NovaKernel/$DEVICE/dtb" dtb
        magiskboot cpio ramdisk.cpio "extract first_stage_ramdisk/fstab.qcom fstab.qcom"
        awk 'BEGIN{OFS="\t"} /^(system|vendor|product|odm)\s/&&!seen[$1]++ \
            {rest=$4;for(i=5;i<=NF;i++)rest=rest"\t"$i; \
            for(i=1;i<=3;i++) print $1,$2,(i==1?"erofs":i==2?"ext4":"f2fs"),rest;next}1' \
            fstab.qcom > fstab.qcom.new

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
                done;;
            A52S)
                local fwdir="lib/firmware/tsp_stm" srcdir="$SRC_DIR/firmware/tsp_stm"
                cpio_todo+=("mkdir 0755 ${fwdir}")
                cpio_todo+=("add 0644 ${fwdir}/fts5cu56a_a52sxq.bin ${srcdir}/fts5cu56a_a52sxq.bin");;
            M52)
                local fwdir="lib/firmware/abov" srcdir="$SRC_DIR/firmware/abov"
                cpio_todo+=("mkdir 0755 ${fwdir}")
                for f in a96t356_m52xq.bin a96t356_m52xq_sub.bin; do
                    cpio_todo+=("add 0644 ${fwdir}/${f} ${srcdir}/${f}")
                done
                local fwdir2="lib/firmware/tsp_synaptics" srcdir2="$SRC_DIR/firmware/tsp_synaptics"
                cpio_todo+=("mkdir 0755 ${fwdir2}")
                for f in s3908_m52xq.bin s3908_m52xq_boe.bin s3908_m52xq_sdc.bin; do
                    cpio_todo+=("add 0644 ${fwdir2}/${f} ${srcdir2}/${f}")
                done;;
        esac

        cpio_todo+=("rm -r lib/modules")
        cpio_todo+=("mkdir 0755 lib/modules")
        for f in "$DEST/modules/"*; do
            cpio_todo+=("add 0644 lib/modules/$(basename "$f") $f")
        done

        magiskboot cpio ramdisk.cpio "${cpio_todo[@]}"
        magiskboot repack ../vendor_boot.img vendor_boot.img
        rm ../vendor_boot.img && mv vendor_boot.img ../vendor_boot.img
        cd .. && rm -rf tmp
    )
    log_ok "vendor_boot.img repacked"

    log_ok "All images repacked in $(elapsed $T0)"
    log_group_end
}

# ── Package as ZIP ───────────────────────────────────────────────
gen_zip() {
    log_group_start "Package  [$(ts)]"
    local T0=$(date +%s)
    local SRC="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    local ZIP_DIR="$TC_DIR/NovaKernel/$DEVICE/ZIP"
    local IMG_DIR="$ZIP_DIR/images"

    wget -q "https://raw.githubusercontent.com/OmarAlsmehan/AnyKernel3/refs/heads/master/banner" -O "$IMG_DIR/banner"
    mv -a "$IMG_DIR/banner"      "$ZIP_DIR/"
    cp -a "$SRC/boot.img"        "$IMG_DIR/"
    cp -a "$SRC/dtbo.img"        "$IMG_DIR/"
    cp -a "$SRC/vendor_boot.img" "$IMG_DIR/"

    local KSU_VER=""
    if [[ "$BUILD_TYPE" == "KSU" ]]; then
        KSU_VER=$(grep -oP -- "-DKSU_VERSION=\K[0-9]+" \
            "$OUT_DIR/drivers/kernelsu/.ksu.o.cmd" 2>/dev/null | sed 's/^/-/' || true)
    fi

    local ZIPNAME="NovaKernel_$(date +%Y%m%d)_${BUILD_TYPE}${KSU_VER}_${VARIANT}.zip"
    local ZIPOUT="$SRC/$ZIPNAME"

    log_step "Creating $ZIPNAME..."
    ( cd "$ZIP_DIR"; zip -r -9 "$ZIPOUT" images META-INF banner )
    rm -rf "$IMG_DIR"/* "$ZIP_DIR/META-INF" "$ZIP_DIR/banner"

    local SIZE SHA
    SIZE=$(du -sh "$ZIPOUT" | cut -f1)
    SHA=$(sha256sum "$ZIPOUT" | awk '{print $1}')

    log_sep
    log_kv "📦 Output:"  "$ZIPNAME"
    log_kv "📏 Size:"    "$SIZE"
    log_kv "🔑 SHA256:"  "${SHA:0:16}...${SHA: -8}"
    log_kv "⏱  Time:"   "$(elapsed $T0)"
    log_sep

    log_notice "ZIP ready → $ZIPNAME  ($SIZE)"
    log_group_end
}

# ── Interactive prompts ──────────────────────────────────────────
prompt_variant() {
    echo -e "${CYAN}${BOLD}"
    echo "  Select target device:"
    echo "  [1] Galaxy A73 5G  (a73xq)"
    echo "  [2] Galaxy A52s 5G (a52sxq)"
    echo "  [3] Galaxy M52 5G  (m52xq)"
    echo -e "${RESET}"
    read -rp "  → Choice [1-3]: " choice
    case "$choice" in
        1) VARIANT="a73xq";;
        2) VARIANT="a52sxq";;
        3) VARIANT="m52xq";;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_ksu() {
    echo -e "${CYAN}${BOLD}"
    echo "  Build with KernelSU support?"
    echo "  [1] No  — standard GKI kernel"
    echo "  [2] Yes — KernelSU kernel"
    echo -e "${RESET}"
    read -rp "  → Choice [1-2]: " choice
    case "$choice" in
        1) KERNELSU=false;;
        2) KERNELSU=true;;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

# ── Entry ────────────────────────────────────────────────────────
ENTRY() {
    if [[ "${1:-}" == "clean" ]]; then
        log_group_start "Clean"
        rm -rf "$OUT_DIR" "$TC_DIR/NovaKernel"
        log_ok "Cleaned out/ and NovaKernel artifacts"
        log_group_end
        exit 0
    fi

    local BUILD_START=$(date +%s)

    check_dependencies
    init_vars

    if [[ -n "${1:-}" ]]; then
        VARIANT="$1"
    elif [[ -n "${NK_VARIANT:-}" ]]; then
        VARIANT="$NK_VARIANT"
    else
        prompt_variant
    fi

    [[ ! "$VARIANT" =~ ^(a73xq|a52sxq|m52xq)$ ]] && {
        log_err "Invalid variant: $VARIANT  (valid: a73xq | a52sxq | m52xq)"
        exit 1
    }

    if [[ -n "${NK_KSU:-}" ]]; then
        KERNELSU="${NK_KSU}"
    else
        prompt_ksu
    fi

    if [[ "$KERNELSU" == "true" ]]; then
        BUILD_TYPE="KSU"
        KSU_SUFFIX="-ksu"
    else
        BUILD_TYPE="GKI"
        KSU_SUFFIX=""
    fi
    export BUILD_TYPE KSU_SUFFIX

    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}  ║       🚀  NovaKernel  Build Plan         ║${RESET}"
    echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Device:")  ${YELLOW}${BOLD}${VARIANT}${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Type:")    ${YELLOW}${BOLD}${BUILD_TYPE}${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Out:")     ${DIM}${OUT_DIR:-$(pwd)/out}${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Started:") ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
    echo ""

    fetch_tools

    log_group_start "Source Preparation"
    if [[ "$KERNELSU" == "true" ]]; then
        log_step "Setting up KernelSU-Next..."
        rm -rf KernelSU drivers/kernelsu
        curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
        rm -rf KernelSU
        local KSU_REPO="${NK_KSU_REPO:-https://github.com/OmarAlsmehan/KernelSU-Next.git}"
        git clone --depth=1 -b legacy "$KSU_REPO" KernelSU
        log_ok "KernelSU-Next (legacy) integrated"
    else
        log_info "KernelSU: disabled — standard GKI build"
    fi
    log_group_end

    build_kernel "$VARIANT"
    build_modules
    stage_artifacts
    gki_repack
    gen_zip

    local TOTAL
    TOTAL=$(elapsed $BUILD_START)

    echo ""
    echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}  ║     ✅  Build Completed Successfully     ║${RESET}"
    echo -e "${GREEN}${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Device:")    ${BOLD}${VARIANT}${RESET}"
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Type:")      ${BOLD}${BUILD_TYPE}${RESET}"
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Duration:")  ${BOLD}${TOTAL}${RESET}"
    echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
    echo -e "${DIM}    @fraxer / @utkustnr — respect the authors' time${RESET}"
    echo ""

    log_notice "✅ Build complete — $VARIANT [$BUILD_TYPE] in $TOTAL"
}

ENTRY "${1:-}"

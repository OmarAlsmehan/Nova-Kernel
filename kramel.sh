#!/usr/bin/bash
# Written by: cyberknight777
# YAKB v1.0
# Copyright (c) 2022-2023 Cyber Knight <cyberknight755@gmail.com>
#
#			GNU GENERAL PUBLIC LICENSE
#			 Version 3, 29 June 2007
#
# Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.

# Some Placeholders: [!] [*] [✓] [✗]

# Default defconfig to use for builds.
export CONFIG=nethunter_defconfig
export FRAG=a73xq.config

# Default directory where kernel is located in.
KDIR=$(pwd)
export KDIR

# Device name.
export DEVICE="Samsung A73 5G"

# Device codename.
export CODENAME="a73xq"

# Builder name.
export BUILDER="Robin"

# Kernel repository URL.
export REPO_URL="https://github.com/MrR0b0X/Nethunter_kernel_samsung_a73xq"

# Commit hash of HEAD.
COMMIT_HASH=$(git rev-parse --short HEAD)
export COMMIT_HASH

# Telegram Information. Set 1 to enable. | Set 0 to disable.
export TGI=1
export CHATID=6010949455

# Necessary variables to be exported.
export ci
export version

# Number of jobs to run.
PROCS=$(nproc --all)
export PROCS

# Flag: set to 1 if "mod" is passed as an argument.
BUILD_MODULES=0
for _a in "$@"; do [[ "$_a" == "mod" ]] && BUILD_MODULES=1; done
export BUILD_MODULES

# Compiler to use for builds.
export COMPILER=clang

# Requirements
if [ "${ci}" != 1 ]; then
    if ! hash dialog make curl wget unzip find 2>/dev/null; then
        echo -e "\n\e[1;31m[✗] Install dialog, make, curl, wget, unzip, and find! \e[0m"
        exit 1
    fi
fi

if [[ "${COMPILER}" = gcc ]]; then
    if [ ! -d "${KDIR}/gcc64" ]; then
        wget -O 64.tar.xz https://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/aarch64-linux-gnu/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu.tar.xz && tar -xf 64.tar.xz
        mv "${KDIR}"/gcc-linaro-4.9-2016.02-x86_64_aarch64-linux-gnu "${KDIR}"/gcc64 && rm -rf 64.tar.xz
    fi

    KBUILD_COMPILER_STRING=$("${KDIR}"/gcc64/bin/aarch64-linux-gnu-gcc --version | head -n 1)
    export KBUILD_COMPILER_STRING
    export PATH="${KDIR}"/gcc64/bin:/usr/bin/:${PATH}
    MAKE+=(
        ARCH=arm64
        O=out
        CROSS_COMPILE=aarch64-linux-gnu-
    )

elif [[ "${COMPILER}" = clang ]]; then
    if [ ! -d "${KDIR}/clang" ]; then
       mkdir clang;wget -O clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r563880c.tar.gz;tar -xf clang.tar.gz -C clang;rm -rf clang.tar.gz
    fi

    KBUILD_COMPILER_STRING=$("${KDIR}"/clang/bin/clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
    export KBUILD_COMPILER_STRING

    export CLANG_PREBUILT_BIN=$KDIR/clang/bin
    export PATH=$CLANG_PREBUILT_BIN/:/usr/bin/:${PATH}
    MAKE+=(
        ARCH=arm64
	    O=out
	    KMI_GENERATION=2
	    LLVM=1
	    DEPMOD=depmod
	    KCFLAGS="${KCFLAGS} -D__ANDROID_COMMON_KERNEL__"
	    STOP_SHIP_TRACEPRINTK=1
	    IN_KERNEL_MODULES=1
	    DO_NOT_STRIP_MODULES=1
	    ABI_DEFINITION=android/abi_gki_aarch64.xml
	    KMI_SYMBOL_LIST=android/abi_gki_aarch64
	    ADDITIONAL_KMI_SYMBOL_LISTS="
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
        TRIM_NONLISTED_KMI=0
        KMI_SYMBOL_LIST_ADD_ONLY=1
        KMI_SYMBOL_LIST_STRICT_MODE=0
        KMI_ENFORCED=0
    )
fi

if [ ! -d "${KDIR}/anykernel3/" ]; then
    git clone --depth=1 https://github.com/MrR0b0X/anykernel3 -b a73xq anykernel3
fi

if [ "${ci}" != 1 ]; then
    if [ -z "${kver}" ]; then
        echo -ne "\e[1mEnter kver: \e[0m"
        read -r kver
    else
        export KBUILD_BUILD_VERSION=${kver}
    fi

    if [ -z "${zipn}" ]; then
        echo -ne "\e[1mEnter zipname: \e[0m"
        read -r zipn
    fi

else
    export KBUILD_BUILD_VERSION=${kver}
    export KBUILD_BUILD_HOST="builder"
    export KBUILD_BUILD_USER="MrR0b0X"
    export VERSION=$version
    kver=$KBUILD_BUILD_VERSION
    zipn=Nethunter-a73q-${VERSION}
fi

# A function to exit on SIGINT.
exit_on_signal_SIGINT() {
    echo -e "\n\n\e[1;31m[✗] Received INTR call - Exiting...\e[0m"
    exit 0
}
trap exit_on_signal_SIGINT SIGINT

# A function to send message(s) via Telegram's BOT api.
tg() {
    curl -sX POST https://api.telegram.org/bot"${TOKEN}"/sendMessage \
        -d chat_id="${CHATID}" \
        -d parse_mode=Markdown \
        -d disable_web_page_preview=true \
        -d text="$1" &>/dev/null
}

# A function to send file(s) via Telegram's BOT api.
tgs() {
    MD5=$(md5sum "$1" | cut -d' ' -f1)
    curl -fsSL -X POST -F document=@"$1" https://api.telegram.org/bot"${TOKEN}"/sendDocument \
        -F "chat_id=${CHATID}" \
        -F "parse_mode=Markdown" \
        -F "caption=$2 | *MD5*: \`$MD5\`"
}

# A function to clean kernel source prior building.
clean() {
    echo -e "\n\e[1;93m[*] Cleaning source and out/ directory! \e[0m"
    make clean && make mrproper && rm -rf "${KDIR}"/out
    echo -e "\n\e[1;32m[✓] Source cleaned and out/ removed! \e[0m"
}

# A function to regenerate defconfig.
rgn() {
    echo -e "\n\e[1;93m[*] Regenerating defconfig! \e[0m"
    make "${MAKE[@]}" $CONFIG $FRAG
    cp -rf "${KDIR}"/out/.config "${KDIR}"/arch/arm64/configs/$CONFIG
    echo -e "\n\e[1;32m[✓] Defconfig regenerated! \e[0m"
}

# A function to open a menu based program to update current config.
mcfg() {
    rgn
    echo -e "\n\e[1;93m[*] Making Menuconfig! \e[0m"
    make "${MAKE[@]}" menuconfig
    cp -rf "${KDIR}"/out/.config "${KDIR}"/arch/arm64/configs/$CONFIG
    echo -e "\n\e[1;32m[✓] Saved Modifications! \e[0m"
}

# A function to build the kernel.
img() {
    if [[ "${TGI}" != "0" ]]; then
        tg "
*Build Number*: \`${kver}\`
*Builder*: \`${BUILDER}\`
*Core count*: \`$(nproc --all)\`
*Device*: \`${DEVICE} [${CODENAME}]\`
*Kernel Version*: \`$(make kernelversion 2>/dev/null)\`
*Date*: \`$(date)\`
*Zip Name*: \`${zipn}\`
*Compiler*: \`${KBUILD_COMPILER_STRING}\`
*Branch*: \`$(git rev-parse --abbrev-ref HEAD)\`
*Last Commit*: [${COMMIT_HASH}](${REPO_URL}/commit/${COMMIT_HASH})
"
    fi
    rgn
    echo -e "\n\e[1;93m[*] Building Kernel! \e[0m"
    BUILD_START=$(date +"%s")
    time make -j"$PROCS" "${MAKE[@]}" 2>&1 | tee log.txt
    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
    if [ -f "${KDIR}/out/arch/arm64/boot/Image" ]; then
        if [[ "${SILENT}" != "1" ]]; then
            tg "*Kernel Built after $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)*"
        fi
        echo -e "\n\e[1;32m[✓] Kernel built after $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)! \e[0m"
    else
        if [[ "${TGI}" != "0" ]]; then
            tgs "log.txt" "*Build failed*"
        fi
        echo -e "\n\e[1;31m[✗] Build Failed! \e[0m"
        exit 1
    fi
}

# A function to build DTBs.
dtb() {
    rgn
    echo -e "\n\e[1;93m[*] Building DTBS! \e[0m"
    time make -j"$PROCS" "${MAKE[@]}" dtbs dtbo.img
    echo -e "\n\e[1;32m[✓] Built DTBS! \e[0m"
}

# Internal helper: repack vendor_boot.img (with or without newly built modules).
# Called by mod() after building modules, or by mkzip() when mod was not requested.
_repack_vendor_boot() {
    # -----------------------------------------------------------------
    # 1. Ensure helper tools (magiskboot, avbtool) are present
    # -----------------------------------------------------------------
    TOOLSDIR="${KDIR}/toolz"
    mkdir -p "$TOOLSDIR"

    # magiskboot
    if [[ ! -f "$TOOLSDIR/magiskboot" ]]; then
        echo "  -> Downloading magiskboot from Magisk release..."
        APK_URL="$(curl -s "https://api.github.com/repos/topjohnwu/Magisk/releases" | grep -oE 'https://[^\"]+\.apk' | grep 'Magisk[-.]v' | head -n 1)"
        wget -O "$TOOLSDIR/magisk.apk" "$APK_URL"
        unzip -p "$TOOLSDIR/magisk.apk" "lib/x86_64/libmagiskboot.so" > "$TOOLSDIR/magiskboot"
        chmod +x "$TOOLSDIR/magiskboot"
        rm -f "$TOOLSDIR/magisk.apk"
    fi

    # avbtool
    if [[ ! -f "$TOOLSDIR/avbtool" ]]; then
        echo "  -> Downloading avbtool..."
        AVBTOOL_URL="https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT"
        curl -s "$AVBTOOL_URL" | base64 --decode > "$TOOLSDIR/avbtool"
        chmod +x "$TOOLSDIR/avbtool"
    fi

    export PATH="$TOOLSDIR:$PATH"

    # -----------------------------------------------------------------
    # 2. Obtain the stock vendor_boot.img for A73
    # -----------------------------------------------------------------
    VENDOR_ZIP_URL="https://github.com/nicodotgit/proprietary_vendor_samsung_a73xq/releases/download/A736BXXSAGZA1_OJM/A736BXXSAGZA1_kernel.tar"
    VENDOR_IMG_LZ4="vendor_boot.img.lz4"
    VENDOR_IMG="$TOOLSDIR/vendor_boot.img"
    if [[ ! -f "$VENDOR_IMG" ]]; then
        echo "  -> Downloading stock vendor_boot.img for A73..."
        wget -O "$TOOLSDIR/kernel.tar" "$VENDOR_ZIP_URL"
        tar xf "$TOOLSDIR/kernel.tar" -C "$TOOLSDIR" "$VENDOR_IMG_LZ4"
        # Decompress LZ4
        lz4 -d --rm "$TOOLSDIR/vendor_boot.img.lz4" "$VENDOR_IMG"
        rm -f "$TOOLSDIR/kernel.tar"
    fi

    # Working copy in out/
    VENDOR_BOOT_OUT="${KDIR}/out/arch/arm64/boot/vendor_boot.img"
    mkdir -p "$(dirname "$VENDOR_BOOT_OUT")"
    cp "$VENDOR_IMG" "$VENDOR_BOOT_OUT"

    # -----------------------------------------------------------------
    # 3. Erase footer, unpack, and modify vendor_boot
    # -----------------------------------------------------------------
    TEMP_DIR="${KDIR}/out/vendor_boot_repack"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    avbtool erase_footer --image "$VENDOR_BOOT_OUT"
    magiskboot unpack -h "$VENDOR_BOOT_OUT"  # preserve header

    # Adjust header (set slot suffix to 001)
    sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header
    [[ "$DEBUG" == "true" ]] && sed -i '2 s/$/ androidboot.selinux=permissive/' header

    # -----------------------------------------------------------------
    # 4. Replace DTB with the one we just built
    # ----------------------------------------------------------------- 
    DTB_SRC="${KDIR}/out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb"
    if [ -f "$DTB_SRC" ]; then
        rm dtb && cp "$DTB_SRC" dtb
    else
        echo -e "\e[1;33m[!] yupik.dtb not found, keeping original DTB\e[0m"
    fi

    # -----------------------------------------------------------------
    # 5. Extract and modify fstab.qcom
    # -----------------------------------------------------------------
    magiskboot cpio ramdisk.cpio "extract first_stage_ramdisk/fstab.qcom fstab.qcom"
    awk 'BEGIN{OFS="\t"} /^(system|vendor|product|odm)\s/&&!seen[$1]++ \
        {rest=$4;for(i=5;i<=NF;i++)rest=rest"\t"$i; \
        for(i=1;i<=3;i++) print $1,$2,(i==1?"erofs":i==2?"ext4":"f2fs"),rest;next}1' \
        fstab.qcom > fstab.qcom.new

    # -----------------------------------------------------------------
    # 6. Prepare cpio commands
    # -----------------------------------------------------------------
    declare -a cpio_cmds=()

    # Remove old fstab, add modified one
    cpio_cmds+=("rm first_stage_ramdisk/fstab.qcom")
    if [ -s fstab.qcom.new ]; then
        cpio_cmds+=("add 0644 first_stage_ramdisk/fstab.qcom fstab.qcom.new")
    fi

    # Add firmware (for A73)
    FW_SRC_DIR="${KDIR}/firmware/tsp_synaptics"
    if [ -d "$FW_SRC_DIR" ]; then
        cpio_cmds+=("mkdir 0755 lib/firmware")
        cpio_cmds+=("mkdir 0755 lib/firmware/tsp_synaptics")
        for f in s3908_a73xq_boe.bin s3908_a73xq_csot.bin s3908_a73xq_sdc.bin s3908_a73xq_sdc_4th.bin; do
            if [ -f "$FW_SRC_DIR/$f" ]; then
                cpio_cmds+=("add 0644 lib/firmware/tsp_synaptics/$f $FW_SRC_DIR/$f")
            fi
        done
    else
        echo -e "\e[1;33m[!] Firmware directory not found, skipping firmware\e[0m"
    fi

    # Remove old modules and add newly built ones (only if modules were built this run)
    cpio_cmds+=("rm -r lib/modules")
    cpio_cmds+=("mkdir 0755 lib/modules")

    if [[ "${BUILD_MODULES}" == "1" ]]; then
    # Get kernel release
    KERNEL_RELEASE=$(cat "${KDIR}/out/include/config/kernel.release" 2>/dev/null)
    if [ -n "$KERNEL_RELEASE" ]; then
        MODULE_DIR="${KDIR}/out/modules/lib/modules/$KERNEL_RELEASE"
        if [ -d "$MODULE_DIR" ]; then
            # Add all .ko files
            for ko in $(find "$MODULE_DIR" -name '*.ko' -type f); do
                cpio_cmds+=("add 0644 lib/modules/$(basename "$ko") $ko")
            done

            # Add module metadata files with transformations
            for f in modules.alias modules.softdep modules.dep modules.order; do
                if [ -f "$MODULE_DIR/$f" ]; then
                    case "$f" in
                        modules.order)
                            sed 's/.*\///g' "$MODULE_DIR/$f" > "$TEMP_DIR/modules.load"
                            cpio_cmds+=("add 0644 lib/modules/modules.load $TEMP_DIR/modules.load")
                            ;;
                        modules.dep)
                            cp "$MODULE_DIR/$f" "$TEMP_DIR/modules.dep"
                            sed -i 's|\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)|/lib/modules/\2|g' "$TEMP_DIR/modules.dep"
                            cpio_cmds+=("add 0644 lib/modules/modules.dep $TEMP_DIR/modules.dep")
                            ;;
                        *)
                            cpio_cmds+=("add 0644 lib/modules/$f $MODULE_DIR/$f")
                            ;;
                    esac
                fi
            done
        else
            echo -e "\e[1;33m[!] Module directory not found, skipping modules\e[0m"
        fi
    else
        echo -e "\e[1;33m[!] Kernel release not found, skipping modules\e[0m"
    fi
    else
        echo -e "\e[1;33m[!] Skipping module injection (build with 'mod' to include modules)\e[0m"
    fi

    # Apply all cpio modifications
    magiskboot cpio ramdisk.cpio "${cpio_cmds[@]}"

    # -----------------------------------------------------------------
    # 7. Repack vendor_boot.img
    # -----------------------------------------------------------------
    magiskboot repack "$VENDOR_BOOT_OUT" vendor_boot.img
    mv -f vendor_boot.img "$VENDOR_BOOT_OUT"
    cd "${KDIR}" || exit 1
    rm -rf "$TEMP_DIR"

    echo -e "\n\e[1;32m[✓] vendor_boot.img rebuilt with new modules & firmware\e[0m"
}

# Build modules and pack them into vendor_boot.img.
mod() {
    if [[ "${TGI}" != "0" ]]; then
        tg "*Building Modules*"
    fi
    rgn
    echo -e "\n\e[1;93m[*] Building Modules! \e[0m"
    mkdir -p "${KDIR}"/out/modules
    make "${MAKE[@]}" modules_prepare
    make -j"$PROCS" "${MAKE[@]}" modules INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="${KDIR}"/out/modules
    make "${MAKE[@]}" modules_install INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="${KDIR}"/out/modules
    _repack_vendor_boot
}

# A function to build an AnyKernel3 zip.
mkzip() {
    if [[ "${TGI}" != "0" ]]; then
        tg "*Building zip!*"
    fi
    echo -e "\n\e[1;93m[*] Building zip! \e[0m"
    # If modules were not built this run, still repack vendor_boot (DTB + fstab, no new .ko files).
    if [[ "${BUILD_MODULES}" != "1" ]]; then
        echo -e "\n\e[1;93m[*] Repacking vendor_boot without modules (pass 'mod' to include modules)! \e[0m"
        _repack_vendor_boot
    fi
    mv "${KDIR}"/out/arch/arm64/boot/Image "${KDIR}"/anykernel3
    mv "${KDIR}"/out/arch/arm64/boot/dtbo.img "${KDIR}"/anykernel3
    if [ -f "${KDIR}/out/arch/arm64/boot/vendor_boot.img" ]; then
        cp "${KDIR}/out/arch/arm64/boot/vendor_boot.img" "${KDIR}/anykernel3"
    fi
    cd "${KDIR}"/anykernel3 || exit 1
    zip -r9 "$zipn".zip . -x ".git*" -x "README.md" -x "LICENSE" -x "*.zip"
    echo -e "\n\e[1;32m[✓] Built zip! \e[0m"
    if [[ "${TGI}" != "0" ]]; then
        tgs "${zipn}.zip" "*#${kver} ${KBUILD_COMPILER_STRING}*"
    fi
}

# A function to build specific objects.
obj() {
    rgn
    echo -e "\n\e[1;93m[*] Building ${1}! \e[0m"
    time make -j"$PROCS" "${MAKE[@]}" "$1"
    echo -e "\n\e[1;32m[✓] Built ${1}! \e[0m"
}

# A function to uprev localversion in defconfig.
upr() {
    echo -e "\n\e[1;93m[*] Bumping localversion to -MrR0b0X-${1}! \e[0m"
    "${KDIR}"/scripts/config --file "${KDIR}"/arch/arm64/configs/$CONFIG --set-str CONFIG_LOCALVERSION "-MrR0b0X-${1}"
    rgn
    if [ "${ci}" != 1 ]; then
        git add arch/arm64/configs/$CONFIG
        git commit -S -s -m "nethunter_defconfig: Bump to \`${1}\`"
    fi
    echo -e "\n\e[1;32m[✓] Bumped localversion to -MrR0b0X-${1}! \e[0m"
}

# A function to showcase the options provided for args-based usage.
helpmenu() {
    echo -e "\n\e[1m
usage: kver=<version number> zipn=<zip name> $0 <arg>
example: $0 --kver=69 --zipn=Kernel-Beta mcfg
example: $0 --kver=420 --zipn=Kernel-Beta mcfg img
example: $0 --kver=69420 --zipn=Kernel-Beta mcfg img mkzip
example: $0 --kver=1 --zipn=Kernel-Beta --obj=drivers/android/binder.o
example: $0 --kver=2 --zipn=Kernel-Beta --obj=kernel/sched/
example: $0 --kver=3 --zipn=Kernel-Beta--upr=r16
	 mcfg   Runs make menuconfig
	 img    Builds Kernel
	 dtb    Builds dtb(o).img
	 mod    Builds out-of-tree modules
	 mkzip  Builds anykernel3 zip
	 --obj  Builds specific driver/subsystem
	 rgn    Regenerates defconfig
	 --upr  Uprevs kernel version in defconfig
	 --kver kernel buildversion
	 --zipn zip name
\e[0m"
}

# A function to setup menu-based usage.
ndialog() {
    HEIGHT=16
    WIDTH=40
    CHOICE_HEIGHT=30
    BACKTITLE="Yet Another Kernel Builder"
    TITLE="YAKB v1.0"
    MENU="Choose one of the following options: "
    OPTIONS=(1 "Build kernel"
        2 "Build DTBs"
        3 "Build modules"
        4 "Open menuconfig"
        5 "Regenerate defconfig"
        6 "Uprev localversion"
        7 "Build AnyKernel3 zip"
        8 "Build a specific object"
        9 "Clean"
        10 "Exit"
    )
    CHOICE=$(dialog --clear \
        --backtitle "$BACKTITLE" \
        --title "$TITLE" \
        --menu "$MENU" \
        $HEIGHT $WIDTH $CHOICE_HEIGHT \
        "${OPTIONS[@]}" \`
        2>&1 >/dev/tty)
    clear
    case "$CHOICE" in
    1)
        clear
        img
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    2)
        clear
        dtb
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    3)
        clear
        mod
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    4)
        clear
        mcfg
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    5)
        clear
        rgn
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    6)
        dialog --inputbox --stdout "Enter version number: " 15 50 | tee .t
        ver=$(cat .t)
        clear
        upr "$ver"
        rm .t
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    7)
        mkzip
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    8)
        dialog --inputbox --stdout "Enter object path: " 15 50 | tee .f
        ob=$(cat .f)
        if [ -z "$ob" ]; then
            dialog --inputbox --stdout "Enter object path: " 15 50 | tee .f
        fi
        clear
        obj "$ob"
        rm .f
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    9)
        clear
        clean
        img
        echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
        read -r a1
        if [ "$a1" == "0" ]; then
            exit 0
        else
            clear
            ndialog
        fi
        ;;
    10)
        echo -e "\n\e[1m Exiting YAKB...\e[0m"
        sleep 3
        exit 0
        ;;
    esac
}

if [ "${ci}" == 1 ]; then
    upr "${version}"
fi

if [[ -z $* ]]; then
    ndialog
fi

for arg in "$@"; do
    case "${arg}" in
    "mcfg")
        mcfg
        ;;
    "img")
        img
        ;;
    "dtb")
        dtb
        ;;
    "mod")
        mod
        ;;
    "mkzip")
        mkzip
        ;;
    "--obj="*)
        object="${arg#*=}"
        if [[ -z "$object" ]]; then
            echo "Use --obj=filename.o"
            exit 1
        else
            obj "$object"
        fi
        ;;
    "rgn")
        rgn
        ;;
    "--upr="*)
        vers="${arg#*=}"
        if [[ -z "$vers" ]]; then
            echo "Use --upr=version"
            exit 1
        else
            upr "$vers"
        fi
        ;;
    "clean")
        clean
        ;;
    "help")
        helpmenu
        exit 1
        ;;
    *)
        helpmenu
        exit 1
        ;;
    esac
done

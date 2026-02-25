#!/bin/env bash
set -e
set -o pipefail

# --- 🎨 Palette ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
RED='\033[0;31m'
NC='\033[0m' 

# --- 🌐 Paths & Vars ---
SRC_DIR="$(pwd)"
OUT_DIR="$SRC_DIR/out"
TC_DIR="$HOME/toolchains"
AK3_DIR="$TC_DIR/AnyKernel3"
JOBS=$(nproc)

# Clang toolchain
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r563880c.tar.gz"
export PATH="$TC_DIR/clang-r563880c/bin:$PATH"

# AnyKernel3 - Use your custom one or fallback
AK3_CUSTOM_DIR="$SRC_DIR/AnyKernel3-Custom"  # Put your custom AnyKernel3 here
AK3_REPO="https://github.com/omarsmehan1/AnyKernel3.git"  # Fallback

# --- ✨ Enhanced Banner ---
display_banner() {
    local device_full_name=""
    local build_type="${2:-KSU}"
    
    case "$1" in
        a73xq)  device_full_name="SAMSUNG GALAXY A73 5G";;
        a52sxq) device_full_name="SAMSUNG GALAXY A52s 5G";;
        m52xq)  device_full_name="SAMSUNG GALAXY M52 5G";;
        *) device_full_name="UNKNOWN DEVICE";;
    esac

    echo -e "${CYAN}============================================================${NC}"
    echo -e "${PURPLE}   _   _  _____     ___    _    ${NC}"
    echo -e "${PURPLE}  | \ | |/ _ \ \   / / \  | | __${NC}"
    echo -e "${PURPLE}  |  \| | | | \ \ / / _ \ | |/ /${NC}"
    echo -e "${PURPLE}  | |\  | |_| |\ V / ___ \|   < ${NC}"
    echo -e "${PURPLE}  |_| \_|\___/  \_/_/   \_\_|\_\\${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${WHITE}  🚀 NOVA KERNEL BUILD SYSTEM | VERSION 3.0${NC}"
    echo -e "${WHITE}  💎 ENHANCED WITH ADVANCED ANYKERNEL3${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${WHITE}  📱 DEVICE      :${NC} ${GREEN}$device_full_name${NC}"
    echo -e "${WHITE}  🆔 VARIANT     :${NC} ${YELLOW}$1${NC}"
    echo -e "${WHITE}  🔧 BUILD TYPE  :${NC} ${PURPLE}$build_type${NC}"
    echo -e "${WHITE}  📅 DATE        :${NC} ${CYAN}$(date "+%Y-%m-%d %H:%M:%S")${NC}"
    echo -e "${WHITE}  🛠️ COMPILER    :${NC} ${PURPLE}Clang r563880c${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# --- 📦 1. Install Dependencies ---
install_deps() {
    display_banner "${1:-unknown}" "SETUP"
    echo -e "${BLUE}===> Installing System Dependencies...${NC}"
    
    sudo apt update && sudo apt install -y \
        git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk \
        gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils \
        erofs-utils default-jdk git gnupg flex bison gperf build-essential zip \
        curl libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 \
        libgl1-mesa-dev make sudo bc grep tofrodos python3-markdown libxml2-utils \
        xsltproc python-is-python3 libtinfo6 repo cpio kmod openssl libelf-dev \
        pahole libssl-dev aria2 libarchive-tools zstd rsync --fix-missing
    
    # Install libtinfo5 for older toolchains
    if ! dpkg -l | grep -q libtinfo5; then
        wget -q http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
        sudo dpkg -i libtinfo5_6.3-2ubuntu0.1_amd64.deb
        rm -f libtinfo5_6.3-2ubuntu0.1_amd64.deb
    fi
    
    echo -e "${GREEN}✔ Dependencies installed successfully${NC}"
}

# --- 🛠️ 2. Fetch Tools ---
fetch_tools() {
    echo -e "${BLUE}===> Checking Toolchain...${NC}"
    
    # Download Clang
    if [[ ! -d "$TC_DIR/clang-r563880c/bin" ]]; then
        echo -e "${YELLOW}-> Toolchain not found, downloading from AOSP...${NC}"
        mkdir -p "$TC_DIR/clang-r563880c"
        
        if command -v aria2c &> /dev/null; then
            aria2c -x16 -s16 -k1M "$CLANG_URL" -d "$TC_DIR" -o "clang.tar.gz"
        else
            wget -q --show-progress "$CLANG_URL" -O "$TC_DIR/clang.tar.gz"
        fi
        
        echo -e "${BLUE}===> Extracting Clang...${NC}"
        tar -xf "$TC_DIR/clang.tar.gz" -C "$TC_DIR/clang-r563880c"
        rm -f "$TC_DIR/clang.tar.gz"
        echo -e "${GREEN}✔ Toolchain ready${NC}"
    else
        echo -e "${GREEN}✔ Toolchain already exists${NC}"
    fi
    
    # Setup AnyKernel3
    echo -e "${BLUE}===> Setting up AnyKernel3...${NC}"
    rm -rf "$AK3_DIR"
    
    # Check for custom AnyKernel3 first
    if [[ -d "$AK3_CUSTOM_DIR" ]]; then
        echo -e "${GREEN}-> Using custom AnyKernel3 from $AK3_CUSTOM_DIR${NC}"
        cp -r "$AK3_CUSTOM_DIR" "$AK3_DIR"
    else
        echo -e "${YELLOW}-> Cloning default AnyKernel3...${NC}"
        git clone --depth 1 "$AK3_REPO" "$AK3_DIR"
    fi
    
    # Download magiskboot if not present
    if [[ ! -f "$AK3_DIR/tools/magiskboot" ]]; then
        echo -e "${YELLOW}-> Downloading magiskboot...${NC}"
        mkdir -p "$AK3_DIR/tools"
        
        MAGISK_APK_URL=$(curl -s "https://api.github.com/repos/topjohnwu/Magisk/releases/latest" | \
            grep -oE 'https://[^"]+\.apk' | head -n1)
        
        if [[ -n "$MAGISK_APK_URL" ]]; then
            wget -q "$MAGISK_APK_URL" -O /tmp/magisk.apk
            unzip -p /tmp/magisk.apk lib/x86_64/libmagiskboot.so > "$AK3_DIR/tools/magiskboot"
            chmod +x "$AK3_DIR/tools/magiskboot"
            rm -f /tmp/magisk.apk
            echo -e "${GREEN}✔ magiskboot downloaded${NC}"
        else
            echo -e "${YELLOW}⚠ Could not download magiskboot - add manually${NC}"
        fi
    fi
    
    # Download ak3-core.sh if not present
    if [[ ! -f "$AK3_DIR/tools/ak3-core.sh" ]]; then
        echo -e "${YELLOW}-> Downloading ak3-core.sh...${NC}"
        wget -q "https://raw.githubusercontent.com/osm0sis/AnyKernel3/master/tools/ak3-core.sh" \
            -O "$AK3_DIR/tools/ak3-core.sh"
        echo -e "${GREEN}✔ ak3-core.sh downloaded${NC}"
    fi
    
    # Download avbtool (optional but recommended)
    if [[ ! -f "$AK3_DIR/tools/avbtool" ]]; then
        echo -e "${YELLOW}-> Downloading avbtool...${NC}"
        wget -q "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" -O - | \
            base64 -d > "$AK3_DIR/tools/avbtool"
        chmod +x "$AK3_DIR/tools/avbtool"
        echo -e "${GREEN}✔ avbtool downloaded${NC}"
    fi
    
    echo -e "${GREEN}✔ All tools ready${NC}"
}

# --- 🧬 3. Setup KernelSU ---
setup_ksu() {
    echo -e "${BLUE}===> Integrating KernelSU & SUSFS...${NC}"
    
    # Clean previous KernelSU
    rm -rf KernelSU drivers/kernelsu
    
    # Setup KernelSU using official script
    echo -e "${YELLOW}-> Running KernelSU setup script...${NC}"
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main
    
    # Use custom KernelSU if available
    if [[ "$USE_CUSTOM_KSU" == "true" ]]; then
        rm -rf KernelSU
        echo -e "${YELLOW}-> Cloning custom KernelSU-Next...${NC}"
        git clone https://github.com/omarsmehan1/KernelSU-Next.git KernelSU
        cd KernelSU
        git switch legacy 2>/dev/null || git checkout legacy
        cd ..
    fi
    
    # Set permissions
    chmod -R +x drivers/kernelsu KernelSU/ 2>/dev/null || true
    
    echo -e "${GREEN}✔ KernelSU integrated${NC}"
}

# --- 🏗️ 4. Build Kernel ---
build_kernel() {
    if [ -z "$1" ]; then 
        echo -e "${RED}Error: No variant specified${NC}"
        exit 1
    fi
    
    display_banner "$1" "KSU-BUILD"
    
    export VARIANT="$1"
    echo -e "${PURPLE}===> Building NovaKernel for $VARIANT...${NC}"
    
    # Architecture
    export ARCH=arm64
    
    # Common settings
    export BRANCH="android11"
    export KMI_GENERATION=2
    export LLVM=1
    export DEPMOD=depmod
    export KCFLAGS="${KCFLAGS} -D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1
    export IN_KERNEL_MODULES=1
    export DO_NOT_STRIP_MODULES=1
    
    # Defconfig
    export DEFCONF="nova_defconfig"
    export FRAG="${VARIANT}.config"
    
    # GKI + aarch64
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
    
    # Version string
    COMREV=$(git rev-parse --verify HEAD --short)
    export LOCALVERSION="-NovaKernel-KSU-$COMREV-$VARIANT"
    
    # Performance optimizations
    export KCFLAGS="${KCFLAGS} -O3 -march=armv8.4-a+dotprod -mcpu=cortex-a78"
    
    echo -e "${CYAN}-> Kernel Version: 5.4.x$LOCALVERSION${NC}"
    
    START=$(date +%s)
    
    # Create output directory
    mkdir -p "$OUT_DIR"
    
    # Build
    echo -e "${YELLOW}-> Generating defconfig...${NC}"
    make -j$JOBS O="$OUT_DIR" $DEFCONF $FRAG
    
    echo -e "${YELLOW}-> Compiling kernel...${NC}"
    make -j$JOBS O="$OUT_DIR"
    
    BUILD_TIME=$(($(date +%s) - START))
    echo -e "\n${GREEN}✔ Build completed successfully in $BUILD_TIME seconds${NC}"
}

# --- 📦 5. Build Modules ---
build_modules() {
    echo -e "${BLUE}===> Building kernel modules...${NC}"
    
    make -j$JOBS -C "$SRC_DIR" O="$OUT_DIR" \
        INSTALL_MOD_PATH=modules \
        INSTALL_MOD_STRIP=1 \
        modules_install
    
    # Prepare modules for AnyKernel3
    MODULE_DEST="$AK3_DIR/modules"
    rm -rf "$MODULE_DEST"
    mkdir -p "$MODULE_DEST"
    
    # Copy .ko files
    find "$OUT_DIR/modules" -name "*.ko" -exec cp {} "$MODULE_DEST/" \;
    
    # Get kernel release version
    KERNEL_RELEASE=$(cat "$OUT_DIR/include/config/kernel.release")
    MODULE_PATH="$OUT_DIR/modules/lib/modules/$KERNEL_RELEASE"
    
    # Copy module metadata
    for modfile in modules.alias modules.dep modules.softdep modules.order; do
        if [ -f "$MODULE_PATH/$modfile" ]; then
            if [ "$modfile" = "modules.order" ]; then
                cp "$MODULE_PATH/$modfile" "$MODULE_DEST/modules.load"
            else
                cp "$MODULE_PATH/$modfile" "$MODULE_DEST/"
            fi
        fi
    done
    
    # Fix paths in modules.dep
    if [ -f "$MODULE_DEST/modules.dep" ]; then
        sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/lib\/modules\/\2/g' "$MODULE_DEST/modules.dep"
    fi
    
    # Fix paths in modules.load
    if [ -f "$MODULE_DEST/modules.load" ]; then
        sed -i 's/.*\///g' "$MODULE_DEST/modules.load"
    fi
    
    MODULE_COUNT=$(ls -1 "$MODULE_DEST/"*.ko 2>/dev/null | wc -l)
    echo -e "${GREEN}✔ Built and packaged $MODULE_COUNT kernel modules${NC}"
}

# --- 🎁 6. Package AnyKernel3 ---
gen_anykernel() {
    if [ -z "$1" ]; then 
        echo -e "${RED}Error: No variant specified${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}===> Packaging AnyKernel3...${NC}"
    
    # Remove nested .git directories
    find "$SRC_DIR" -maxdepth 2 -name ".git" -not -path "$SRC_DIR/.git" -exec rm -rf {} + 2>/dev/null || true
    
    # Check if kernel Image exists
    if [ ! -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        echo -e "${RED}❌ Error: Kernel Image not found!${NC}"
        exit 1
    fi
    
    # Copy kernel files
    echo -e "${YELLOW}-> Copying kernel Image...${NC}"
    cp "$OUT_DIR/arch/arm64/boot/Image" "$AK3_DIR/"
    
    # Copy DTBO
    if [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]; then
        echo -e "${YELLOW}-> Copying dtbo.img...${NC}"
        cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$AK3_DIR/"
    fi
    
    # Copy DTB
    if [ -f "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" ]; then
        echo -e "${YELLOW}-> Copying yupik.dtb...${NC}"
        cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$AK3_DIR/dtb"
    fi
    
    # Copy firmware if exists
    if [ -d "$SRC_DIR/firmware" ]; then
        echo -e "${YELLOW}-> Copying firmware files...${NC}"
        mkdir -p "$AK3_DIR/firmware"
        cp -r "$SRC_DIR/firmware/"* "$AK3_DIR/firmware/" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✔ AnyKernel3 package ready at: $AK3_DIR${NC}"
    
    # Show package contents
    echo -e "\n${CYAN}Package contents:${NC}"
    ls -lh "$AK3_DIR"/{Image,dtb,dtbo.img,modules,firmware} 2>/dev/null || true
}

# --- 📦 7. Create Flashable ZIP ---
create_zip() {
    if [ -z "$1" ]; then 
        echo -e "${RED}Error: No variant specified${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}===> Creating flashable ZIP...${NC}"
    
    DATE=$(date +%Y%m%d)
    ZIP_NAME="NovaKernel-KSU-${DATE}-$1.zip"
    OUTPUT_ZIP="$TC_DIR/$ZIP_NAME"
    
    cd "$AK3_DIR"
    
    # Create ZIP with maximum compression
    zip -r9 "$OUTPUT_ZIP" * \
        -x "*.git*" "README.md" ".gitignore" "*.md" \
        > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        ZIP_SIZE=$(du -h "$OUTPUT_ZIP" | cut -f1)
        echo -e "${GREEN}✔ Flashable ZIP created: $ZIP_NAME ($ZIP_SIZE)${NC}"
        echo -e "${CYAN}Location: $OUTPUT_ZIP${NC}"
    else
        echo -e "${RED}❌ Failed to create ZIP${NC}"
        exit 1
    fi
    
    cd "$SRC_DIR"
}

# --- 🧹 8. Clean ---
clean_build() {
    echo -e "${BLUE}===> Cleaning build...${NC}"
    rm -rf "$OUT_DIR"
    echo -e "${GREEN}✔ Build directory cleaned${NC}"
}

clean_all() {
    echo -e "${BLUE}===> Cleaning everything...${NC}"
    rm -rf "$OUT_DIR" "$TC_DIR/RIO" "$AK3_DIR"
    echo -e "${GREEN}✔ All build artifacts cleaned${NC}"
}

# --- 🚀 Main Control Logic ---
show_usage() {
    echo -e "${CYAN}NovaKernel Build System v3.0${NC}"
    echo -e ""
    echo -e "${WHITE}Usage:${NC}"
    echo -e "  $0 ${GREEN}deps${NC} <device>              Install dependencies"
    echo -e "  $0 ${GREEN}tools${NC}                      Download toolchain & AnyKernel3"
    echo -e "  $0 ${GREEN}ksu${NC}                        Setup KernelSU"
    echo -e "  $0 ${GREEN}build${NC} <device>             Build kernel"
    echo -e "  $0 ${GREEN}modules${NC}                    Build kernel modules"
    echo -e "  $0 ${GREEN}pack${NC} <device>              Package AnyKernel3"
    echo -e "  $0 ${GREEN}zip${NC} <device>               Create flashable ZIP"
    echo -e "  $0 ${GREEN}all${NC} <device>               Do everything (tools→ksu→build→modules→pack→zip)"
    echo -e "  $0 ${GREEN}clean${NC}                      Clean build directory"
    echo -e "  $0 ${GREEN}cleanall${NC}                   Clean everything"
    echo -e ""
    echo -e "${WHITE}Devices:${NC} a73xq, a52sxq, m52xq"
    echo -e ""
    echo -e "${WHITE}Examples:${NC}"
    echo -e "  $0 all a73xq                  ${CYAN}# Full build for A73${NC}"
    echo -e "  $0 build a52sxq               ${CYAN}# Build only for A52s${NC}"
    echo -e ""
}

case "$1" in
    deps)
        install_deps "$2"
        ;;
    tools)
        fetch_tools
        ;;
    ksu)
        setup_ksu
        ;;
    build)
        build_kernel "$2"
        ;;
    modules)
        build_modules
        ;;
    pack)
        gen_anykernel "$2"
        ;;
    zip)
        create_zip "$2"
        ;;
    all)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Device not specified${NC}"
            show_usage
            exit 1
        fi
        display_banner "$2" "FULL-BUILD"
        fetch_tools
        setup_ksu
        build_kernel "$2"
        build_modules
        gen_anykernel "$2"
        create_zip "$2"
        echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  🎉 BUILD COMPLETED SUCCESSFULLY! 🎉  ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        ;;
    clean)
        clean_build
        ;;
    cleanall)
        clean_all
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

exit 0

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
NC='\033[0m' 

# --- 🌐 Paths & Vars ---
AK3_REPO="https://github.com/omarsmehan1/AnyKernel3.git"
SRC_DIR="$(pwd)"
OUT_DIR="$SRC_DIR/out"
TC_DIR="$HOME/toolchains"
JOBS=$(nproc)

# الرابط الذي أرسلته مع تعديل الفرع لضمان العمل
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r563880c.tar.gz"

export PATH="$TC_DIR/clang-r563880c/bin:$PATH"

# --- ✨ البانر المطور ---
display_target_banner() {
    local device_full_name=""
    case "$1" in
        a73xq)  device_full_name="SAMSUNG GALAXY A73 5G";;
        a52sxq) device_full_name="SAMSUNG GALAXY A52s 5G";;
        m52xq)  device_full_name="SAMSUNG GALAXY M52 5G";;
        *) device_full_name="UNKNOWN DEVICE";;
    esac

    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${PURPLE}   ____    _    _        _    __  ____   __"
    echo -e "  / ___|  / \  | |      / \   \ \/ /\ \ / /"
    echo -e " | |  _  / _ \ | |     / _ \   \  /  \ V / "
    echo -e " | |_| |/ ___ \| |___ / ___ \  /  \   | |  "
    echo -e "  \____/_/   \_\_____/_/   \_\/_/\_\  |_|  "
    echo -e "${NC}"
    echo -e "${CYAN}  🚀 NOVA KERNEL BUILD SYSTEM | VERSION 2.2${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${WHITE}  📱 DEVICE   :${NC} ${GREEN}$device_full_name${NC}"
    echo -e "${WHITE}  🆔 VARIANT  :${NC} ${YELLOW}$1${NC}"
    echo -e "${WHITE}  📅 DATE     :${NC} ${CYAN}$(date "+%Y-%m-%d %H:%M:%S")${NC}"
    echo -e "${WHITE}  🛠️ COMPILER :${NC} ${PURPLE}Clang r563880c${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
}

# --- 📦 1. تثبيت الاعتمادات ---
install_deps() {
    display_target_banner "$1"
    echo -e "${BLUE}===> Installing System Dependencies...${NC}"
    sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
            default-jdk git gnupg flex bison gperf build-essential zip curl libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
            python3 make sudo gcc g++ bc grep tofrodos python3-markdown libxml2-utils xsltproc zlib1g-dev python-is-python3 libc6-dev libtinfo6 \
            make repo cpio kmod openssl libelf-dev pahole libssl-dev aria2 libarchive-tools zstd rsync --fix-missing && wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb && sudo dpkg -i libtinfo5_6.3-2ubuntu0.1_amd64.deb
}

# --- 🛠️ 2. تحميل الأدوات ---
fetch_tools() {
    echo -e "${BLUE}===> Checking Toolchain...${NC}"
    if [[ ! -d "$TC_DIR/clang-r563880c/bin" ]]; then
        echo -e "${YELLOW}-> Toolchain not found, downloading from AOSP...${NC}"
        mkdir -p "$TC_DIR/clang-r563880c"
        # استخدام aria2 للتحميل السريع كما تفضل
        aria2c -x16 -s16 -k1M "$CLANG_URL" -d "$TC_DIR" -o "clang.tar.gz"
        
        echo -e "${BLUE}===> Extracting Clang...${NC}"
        tar -xf "$TC_DIR/clang.tar.gz" -C "$TC_DIR/clang-r563880c"
        rm "$TC_DIR/clang.tar.gz"
        echo -e "${GREEN}✔ Toolchain ready.${NC}"
    else
        echo -e "${GREEN}✔ Toolchain already exists.${NC}"
    fi

    echo -e "${YELLOW}-> Cloning AnyKernel3...${NC}"
    rm -rf "$TC_DIR/AnyKernel3"
    git clone --depth 1 "$AK3_REPO" "$TC_DIR/AnyKernel3"
}

# --- 🧬 3. إعداد KernelSU ---
setup_ksu() {
rm -rf KernelSU
rm -rf drivers/kernelsu
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
rm -rf KernelSU
git clone https://github.com/omarsmehan1/KernelSU-Next.git KernelSU
cd KernelSU
git switch legacy
cd ..
    echo -e "${BLUE}===> Integrating KernelSU & SUSFS...${NC}"
}

# --- 🏗️ 4. بناء النواة ---
build_kernel() {
    if [ -z "$1" ]; then echo "Error: No variant specified"; exit 1; fi
    display_target_banner "$1"
    
    export VARIANT="$1"
    echo -e "${PURPLE}===> Building for $VARIANT...${NC}"
    
    export ARCH=arm64

    # common
    export BRANCH="android11"
    export KMI_GENERATION=2
    export LLVM=1
    export DEPMOD=depmod
    export KCFLAGS="${KCFLAGS} -D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1
    export IN_KERNEL_MODULES=1
    export DO_NOT_STRIP_MODULES=1

    chmod +x drivers/kernelsu
    chmod +x KernelSU/
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
    
    # تحسين التسمية
    COMREV=$(git rev-parse --verify HEAD --short)
    export LOCALVERSION="-NovaKernel-$COMREV-$VARIANT"

    START=$(date +%s)
    
    # تنظيف مسبق للـ Out
    mkdir -p "$OUT_DIR"
    
    make -j$JOBS O="$OUT_DIR" $DEFCONF $FRAG
    make -j$JOBS O="$OUT_DIR"

    echo -e "\n${GREEN}✔ Build Successful in $(($(date +%s) - START)) seconds.${NC}"
}

# --- 🎁 5. التجميع النهائي ---
gen_anykernel() {
    echo -e "${BLUE}===> Packaging...${NC}"
    # حذف ملفات .git الفرعية لمنع تعارض الرفع
    find "$SRC_DIR" -maxdepth 2 -name ".git" -not -path "$SRC_DIR/.git" -exec rm -rf {} + || true

    AK3_DIR="$TC_DIR/RIO/work_ksu"
    rm -rf "$AK3_DIR" && mkdir -p "$AK3_DIR"
    
    cp -af "$TC_DIR/AnyKernel3/"* "$AK3_DIR/"
    
    if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        cp "$OUT_DIR/arch/arm64/boot/Image" "$AK3_DIR/"
        cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$AK3_DIR/"
        [ -f "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" ] && cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$AK3_DIR/dtb"
        echo -e "${GREEN}✔ AnyKernel3 folder is ready at $AK3_DIR${NC}"
    else
        echo -e "${YELLOW}❌ Error: Kernel Image not found!${NC}"
        exit 1
    fi
}

# --- 🚀 Main Control Logic ---
case "$1" in
    deps)  install_deps "$2" ;;
    tools) fetch_tools ;;
    ksu)   setup_ksu ;;
    build) build_kernel "$2" ;;
    pack)  gen_anykernel ;;
    *)     echo "Usage: $0 {deps|tools|ksu|build|pack}" ;;
esac

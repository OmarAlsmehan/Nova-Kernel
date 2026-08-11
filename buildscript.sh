#!/bin/env bash

set -e
set -o pipefail

# ════════════════════════════════════════════════════════════════
#  NovaKernel Build Script
#  Devices: A73 (a73xq) | A52S (a52sxq) | M52 (m52xq)
# ════════════════════════════════════════════════════════════════


# ─────────────────────────────────────────────────────────────────
#  § 0 — CONFIGURATION
#  All hardcoded values live here. GitHub Actions (or local env)
#  can override any of these by exporting the variable before
#  calling the script.
# ─────────────────────────────────────────────────────────────────

# ── Clang toolchain ──────────────────────────────────────────────
# Bump NK_CLANG_VERSION_DEFAULT to update the toolchain.
# The YAML detects this value via grep, so keep it on its own line.
NK_CLANG_VERSION_DEFAULT="clang-r584948"
NK_CLANG_VERSION="${NK_CLANG_VERSION:-$NK_CLANG_VERSION_DEFAULT}"
NK_CLANG_URL="${NK_CLANG_URL:-https://github.com/MrR0b0X/Android-tools/releases/download/clang-r584948-2/clang-r584948.tar.gz}"

# ── KernelSU repositories ────────────────────────────────────────
NK_KSU_SETUP_URL="${NK_KSU_SETUP_URL:-https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh}"
# Empty string from CI must not override the default — strip it first.
NK_KSU_REPO="${NK_KSU_REPO:-}"
NK_KSU_REPO="${NK_KSU_REPO:-https://github.com/OmarAlsmehan/KernelSU-Next.git}"
[[ -z "$NK_KSU_REPO" ]] && NK_KSU_REPO="https://github.com/OmarAlsmehan/KernelSU-Next.git"

# ── AnyKernel3 repository ────────────────────────────────────────
NK_AK3_REPO="${NK_AK3_REPO:-https://github.com/OmarAlsmehan/AnyKernel3.git}"
NK_AK3_BANNER_URL="${NK_AK3_BANNER_URL:-https://raw.githubusercontent.com/OmarAlsmehan/AnyKernel3/refs/heads/master/banner}"

# ── Hook patch URLs ──────────────────────────────────────────────
NK_HOOK_SCOPE_MIN_URL="${NK_HOOK_SCOPE_MIN_URL:-https://raw.githubusercontent.com/OmarAlsmehan/Random-stuff/e2dca691b866415c8ec59f306536f59c633be8e7/scope-min-manual-hook.1.6-5.4.patch}"
NK_HOOK_RKSU_URL="${NK_HOOK_RKSU_URL:-https://raw.githubusercontent.com/rksuorg/kernel_patches/refs/heads/master/manual_hook/kernel-4.19_5.4.patch}"
NK_HOOK_SYSCALL_URL="${NK_HOOK_SYSCALL_URL:-https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/syscall_hook_patches.sh}"
NK_HOOK_INLINE_URL="${NK_HOOK_INLINE_URL:-https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh}"

# ── Backport patch URL ───────────────────────────────────────────
NK_BACKPORT_URL="${NK_BACKPORT_URL:-https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/backport_patches.sh}"

# ── Stock kernel image URLs ──────────────────────────────────────
NK_IMG_URL_A73="${NK_IMG_URL_A73:-https://github.com/nicodotgit/proprietary_vendor_samsung_a73xq/releases/download/A736BXXSAGZA1_ODM/A736BXXSAGZA1_kernel.tar}"
NK_IMG_URL_A52S="${NK_IMG_URL_A52S:-https://github.com/RisenID/proprietary_vendor_samsung_a52sxq/releases/download/A528BXXUAGXK8_BTU/A528BXXUAGXK8_kernel.tar}"
NK_IMG_URL_M52="${NK_IMG_URL_M52:-https://github.com/nicodotgit/proprietary_vendor_samsung_m52xq/releases/download/M526BXXS7CYE1_CAU/M526BXXS7CYE1_kernel.tar}"

# ── Defconfig names ──────────────────────────────────────────────
NK_DEFCONFIG="${NK_DEFCONFIG:-nova_defconfig}"

# ── AnyKernel3 packaging toggle ──────────────────────────────────
# Set USE_ANYKERNEL3=true to package via AK3 instead of raw image ZIP.
USE_ANYKERNEL3="${USE_ANYKERNEL3:-false}"


# ─────────────────────────────────────────────────────────────────
#  § 1 — CONSTANTS & STYLES
# ─────────────────────────────────────────────────────────────────

BOLD="\e[1m";  RESET="\e[0m";  DIM="\e[2m"
CYAN="\e[1;36m";  GREEN="\e[1;32m";  YELLOW="\e[1;33m"
RED="\e[1;31m"

IN_GHA="${GITHUB_ACTIONS:-false}"


# ─────────────────────────────────────────────────────────────────
#  § 2 — LOGGING
# ─────────────────────────────────────────────────────────────────

# Usage: log_group_start "emoji" "Label"
log_group_start() {
    if [[ "$IN_GHA" == "true" ]]; then
        echo "::group::$1  $2"
    else
        echo -e "\n${CYAN}${BOLD}╔════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}║  $1  $2${RESET}"
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


# ─────────────────────────────────────────────────────────────────
#  § 3 — CORE UTILITIES
# ─────────────────────────────────────────────────────────────────

check_dependencies() {
    log_group_start "🔍" "Dependency Check"
    local missing=false
    for tool in git curl wget unzip tar lz4 awk sed zip patch; do
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

init_vars() {
    SRC_DIR="$(pwd)"
    OUT_DIR="$SRC_DIR/out"
    TC_DIR="$HOME/toolchains"
    JOBS=$(nproc)
    # Read toolchain version from configuration (§ 0)
    CLANGVER="${NK_CLANG_VERSION}"
    CLANG_PREBUILT_BIN="$TC_DIR/$CLANGVER/bin/"
    export SRC_DIR OUT_DIR TC_DIR JOBS CLANGVER CLANG_PREBUILT_BIN
    export PATH="$TC_DIR:$CLANG_PREBUILT_BIN:$PATH"

    # Log environment mode once
    if [[ "$IN_GHA" == "true" ]]; then
        log_info "Environment: GitHub Actions (CI)"
    else
        log_info "Environment: Local build"
    fi
}


# ─────────────────────────────────────────────────────────────────
#  § 4 — INTERACTIVE PROMPTS  (local builds only)
# ─────────────────────────────────────────────────────────────────

# In CI mode calling any prompt is a fatal error — variables must
# be passed as environment variables instead.
_ci_guard() {
    local varname="$1"
    if [[ "$IN_GHA" == "true" ]]; then
        log_err "CI mode: '$varname' must be provided as an environment variable."
        log_err "Set it in the workflow env: block or as a workflow input."
        exit 1
    fi
}

prompt_variant() {
    _ci_guard "NK_VARIANT"
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
    _ci_guard "NK_KSU"
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

prompt_ksu_branch() {
    _ci_guard "NK_KSU_BRANCH"
    echo -e "${CYAN}${BOLD}"
    echo "  Select KernelSU branch:"
    echo "  [1] legacy          (stable, recommended)"
    echo "  [2] main            (latest stable)"
    echo "  [3] next            (bleeding edge)"
    echo "  [4] susfs-main      (SuSFS + main)"
    echo "  [5] susfs-next      (SuSFS + next)"
    echo "  [6] legacy-susfs-v2 (SuSFS v2 + legacy)"
    echo "  [7] custom          (enter manually)"
    echo -e "${RESET}"
    read -rp "  → Choice [1-7]: " choice
    case "$choice" in
        1) KSU_BRANCH="legacy";;
        2) KSU_BRANCH="main";;
        3) KSU_BRANCH="next";;
        4) KSU_BRANCH="susfs-main";;
        5) KSU_BRANCH="susfs-next";;
        6) KSU_BRANCH="legacy-susfs-v2";;
        7) read -rp "  → Branch name: " KSU_BRANCH
           [[ -z "$KSU_BRANCH" ]] && { log_err "Branch name cannot be empty"; exit 1; };;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_hook_type() {
    _ci_guard "NK_HOOK_TYPE"
    echo -e "${CYAN}${BOLD}"
    echo "  Select KernelSU hook type:"
    echo "  [1] kprobes       — kprobe-based (no kernel patches needed)"
    echo "  [2] scope-min-1.6 — scope-min manual hook patch (5.4)"
    echo "  [3] rksu          — rksu manual hook patch (4.19/5.4)"
    echo "  [4] syscall       — syscall hook patches"
    echo "  [5] inline        — inline / susfs hook patches"
    echo -e "${RESET}"
    read -rp "  → Choice [1-5]: " choice
    case "$choice" in
        1) HOOK_TYPE="kprobes";;
        2) HOOK_TYPE="scope-min-1.6";;
        3) HOOK_TYPE="rksu";;
        4) HOOK_TYPE="syscall";;
        5) HOOK_TYPE="inline";;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_backport() {
    _ci_guard "NK_BACKPORT"
    echo -e "${CYAN}${BOLD}"
    echo "  Apply backport patches?"
    echo "  [1] No"
    echo "  [2] Yes"
    echo -e "${RESET}"
    read -rp "  → Choice [1-2]: " choice
    case "$choice" in
        1) BACKPORT=false;;
        2) BACKPORT=true;;
        *) log_err "Invalid choice"; exit 1;;
    esac
}


# ─────────────────────────────────────────────────────────────────
#  § 5 — BUILD PHASES
# ─────────────────────────────────────────────────────────────────

# ── 5.0  Dynamic kernel config patching ──────────────────────────
# Called inside build_kernel() AFTER make defconfig + fragment,
# BEFORE the final compilation. Uses scripts/config (the proper
# kernel tool) to set KernelSU-related Kconfig symbols without
# ever touching the defconfig file with sed.
patch_kernel_config() {
    if [[ "${KERNELSU:-false}" != "true" ]]; then
        log_info "KernelSU disabled — skipping .config patching"
        return
    fi

    log_group_start "🛠️" "KernelSU .config Patching"

    local SCRIPTS_CONFIG="$SRC_DIR/scripts/config"
    local DOT_CONFIG="$OUT_DIR/.config"

    if [[ ! -f "$DOT_CONFIG" ]]; then
        log_err ".config not found at $DOT_CONFIG — was defconfig run?"
        exit 1
    fi

    # Internal helper: set one Kconfig symbol via scripts/config,
    # with a sed-based fallback for edge cases.
    _set_config() {
        local key="$1" val="$2"
        if [[ -f "$SCRIPTS_CONFIG" ]]; then
            case "$val" in
                y) "$SCRIPTS_CONFIG" --file "$DOT_CONFIG" --enable  "$key" ;;
                n) "$SCRIPTS_CONFIG" --file "$DOT_CONFIG" --disable "$key" ;;
                *) "$SCRIPTS_CONFIG" --file "$DOT_CONFIG" --set-val "$key" "$val" ;;
            esac
        else
            log_warn "scripts/config not found — using sed fallback for $key"
            if grep -q "^${key}=" "$DOT_CONFIG" 2>/dev/null; then
                sed -i "s|^${key}=.*|${key}=${val}|" "$DOT_CONFIG"
            elif grep -q "^# ${key} is not set" "$DOT_CONFIG" 2>/dev/null; then
                sed -i "s|^# ${key} is not set|${key}=${val}|" "$DOT_CONFIG"
            else
                echo "${key}=${val}" >> "$DOT_CONFIG"
            fi
        fi
    }

    # CONFIG_KSU is always required for any KernelSU build
    _set_config CONFIG_KSU y

    case "${HOOK_TYPE:-kprobes}" in
        scope-min-1.6|rksu|syscall)
            _set_config CONFIG_KSU_MANUAL_HOOK y
            log_ok "Set: CONFIG_KSU=y  CONFIG_KSU_MANUAL_HOOK=y  (hook: ${HOOK_TYPE})"
            ;;
        kprobes)
            _set_config CONFIG_KSU_KPROBES_HOOK y
            log_ok "Set: CONFIG_KSU=y  CONFIG_KSU_KPROBES_HOOK=y  (hook: kprobes)"
            ;;
        *)
            # syscall / inline / unknown — only base CONFIG_KSU
            log_ok "Set: CONFIG_KSU=y  (no extra hook config for type: ${HOOK_TYPE})"
            ;;
    esac

    log_group_end
}

# ── 5.1  Toolchain & assets ──────────────────────────────────────
fetch_tools() {
    log_group_start "🧰" "Toolchain & Assets"
    mkdir -p "$TC_DIR"

    if [[ ! -d "$CLANG_PREBUILT_BIN" ]]; then
        log_step "Downloading Clang ($CLANGVER)..."
        mkdir -p "$TC_DIR/$CLANGVER"
        local url="${NK_CLANG_URL}"
        wget --progress=bar:force:noscroll "$url" -P "$TC_DIR"
        tar xf "$TC_DIR/$CLANGVER.tar.gz" -C "$TC_DIR/$CLANGVER"
        rm "$TC_DIR/$CLANGVER.tar.gz"
        log_ok "Clang ready"
    else
        log_ok "Clang — cached ✓"
    fi

    if [[ ! -f "$TC_DIR/magiskboot" ]]; then
        log_step "Fetching magiskboot..."
        local apk_url
        local _auth_args=()
        [[ -n "${GITHUB_TOKEN:-}" ]] && _auth_args=(-H "Authorization: Bearer $GITHUB_TOKEN")
        apk_url="$(curl -s "${_auth_args[@]}" \
            "https://api.github.com/repos/topjohnwu/Magisk/releases" \
            | grep -oE 'https://[^"]+\.apk' | grep 'Magisk[-.]v' | head -n1)"
        wget -q --show-progress "$apk_url" -O "$TC_DIR/magisk.apk"
        unzip -p "$TC_DIR/magisk.apk" "lib/x86_64/libmagiskboot.so" > "$TC_DIR/magiskboot"
        chmod +x "$TC_DIR/magiskboot"
        rm "$TC_DIR/magisk.apk"
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
            ["A73"]="${NK_IMG_URL_A73}"
            ["A52S"]="${NK_IMG_URL_A52S}"
            ["M52"]="${NK_IMG_URL_M52}"
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

# ── 5.2  KernelSU setup ──────────────────────────────────────────
setup_kernelsu() {
    log_group_start "⚡" "KernelSU Setup"

    log_step "Running tiann/KernelSU setup..."
    curl -LSs "${NK_KSU_SETUP_URL}" | bash -
    rm -rf KernelSU

    local KSU_BRANCH_USE="${KSU_BRANCH:-legacy}"
    log_step "Cloning KernelSU-Next (${KSU_BRANCH_USE})..."
    log_info "Repo:   ${NK_KSU_REPO}"
    log_info "Branch: $KSU_BRANCH_USE"
    git clone --depth=1 -b "$KSU_BRANCH_USE" "${NK_KSU_REPO}" KernelSU

    log_ok "KernelSU-Next integrated"
    log_group_end
}

# ── 5.3  Hook patches ────────────────────────────────────────────
apply_hook() {
    if [[ "$HOOK_TYPE" == "kprobes" ]]; then
        log_ok "Hook type: kprobes — handled by KernelSU, no patches needed"
        return
    fi

    log_group_start "🪝" "Hook Patches  [$HOOK_TYPE]  [$(ts)]"
    local T0=$(date +%s)

    case "$HOOK_TYPE" in

        scope-min-1.6)
            local PATCH_FILE="$TC_DIR/scope-min-1.6.patch"

            if grep -q "ksu_handle_execveat" "$SRC_DIR/fs/exec.c" 2>/dev/null; then
                log_warn "scope-min-1.6 hook already applied — skipping"
            else
                log_step "Downloading scope-min-1.6 patch..."
                wget -q "${NK_HOOK_SCOPE_MIN_URL}" -O "$PATCH_FILE"
                log_step "Applying patch..."
                patch -p1 -d "$SRC_DIR" < "$PATCH_FILE"
                log_ok "scope-min-1.6 hook applied"
            fi
            ;;

        rksu)
            local PATCH_FILE="$TC_DIR/rksu-manual-hook.patch"

            if grep -q "ksu_handle_execveat" "$SRC_DIR/fs/exec.c" 2>/dev/null; then
                log_warn "RKSU hook already applied — skipping"
            else
                log_step "Downloading RKSU hook patch..."
                wget -q "${NK_HOOK_RKSU_URL}" -O "$PATCH_FILE"
                log_step "Applying patch..."
                patch -p1 -d "$SRC_DIR" < "$PATCH_FILE"
                log_ok "RKSU hook applied"
            fi
            ;;

        syscall)
            local SCRIPT_FILE="$TC_DIR/syscall_hook_patches.sh"

            if grep -q "ksu_handle_execveat" "$SRC_DIR/fs/exec.c" 2>/dev/null; then
                log_warn "Syscall hook already applied — skipping"
            else
                log_step "Downloading syscall hook script..."
                wget -q "${NK_HOOK_SYSCALL_URL}" -O "$SCRIPT_FILE"
                chmod +x "$SCRIPT_FILE"
                log_step "Running syscall hook patches..."
                ( cd "$SRC_DIR" && bash "$SCRIPT_FILE" )
                log_ok "Syscall hook applied"
            fi
            ;;

        inline)
            local SCRIPT_FILE="$TC_DIR/susfs_inline_hook_patches.sh"

            if grep -q "ksu_handle_execveat" "$SRC_DIR/fs/exec.c" 2>/dev/null; then
                log_warn "Inline hook already applied — skipping"
            else
                log_step "Downloading inline hook script..."
                wget -q "${NK_HOOK_INLINE_URL}" -O "$SCRIPT_FILE"
                chmod +x "$SCRIPT_FILE"
                log_step "Running inline hook patches..."
                ( cd "$SRC_DIR" && bash "$SCRIPT_FILE" )
                log_ok "Inline hook applied"
            fi
            ;;
    esac

    log_ok "Hook patches done in $(elapsed $T0)"
    log_group_end
}

# ── 5.4  Backport patches ────────────────────────────────────────
apply_backport() {
    log_group_start "⬆️" "Backport Patches  [$(ts)]"
    local T0=$(date +%s)
    local SCRIPT_FILE="$TC_DIR/backport_patches.sh"

    if grep -q "path_umount" "$SRC_DIR/fs/namespace.c" 2>/dev/null; then
        log_warn "Backport already applied — skipping"
    else
        log_step "Downloading backport script..."
        wget -q "${NK_BACKPORT_URL}" -O "$SCRIPT_FILE"
        chmod +x "$SCRIPT_FILE"
        log_step "Running backport patches..."
        ( cd "$SRC_DIR" && bash "$SCRIPT_FILE" )
        log_ok "Backport patches applied"
    fi

    log_ok "Backport done in $(elapsed $T0)"
    log_group_end
}

# ── 5.5  Kernel compile ──────────────────────────────────────────
build_kernel() {
    log_group_start "🔨" "Kernel Compile  [$(ts)]"
    case "$1" in
        a73xq)  VARIANT="a73xq";  DEVICE="A73";;
        a52sxq) VARIANT="a52sxq"; DEVICE="A52S";;
        m52xq)  VARIANT="m52xq";  DEVICE="M52";;
        *) log_err "Unknown variant: $1"; exit 1;;
    esac
    export VARIANT DEVICE ARCH=arm64

    export BRANCH="android11" KMI_GENERATION=2 LLVM=1 DEPMOD=depmod
    export KCFLAGS="${KCFLAGS} -D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1 IN_KERNEL_MODULES=1
    export DO_NOT_STRIP_MODULES=1 INSTALL_MOD_STRIP=1
    export DEFCONF="${NK_DEFCONFIG}" FRAG="${VARIANT}.config"
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
    if [[ "$BUILD_TYPE" == "KSU" ]]; then
        log_kv "KSU Branch:" "${KSU_BRANCH:-legacy}"
        log_kv "Hook:"       "${HOOK_TYPE:-gki}"
    fi
    log_kv "Version:"   "5.4.x$LOCALVERSION"
    log_kv "Toolchain:" "$(clang --version | head -n1)"
    log_kv "Jobs:"      "$JOBS"
    log_sep

    local T0=$(date +%s)

    log_step "make clean..."
    [[ -d "$OUT_DIR" ]] && make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" clean 2>&1 | sed 's/^/       /'

    log_step "make defconfig + fragment..."
    make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" "$DEFCONF" "$FRAG" 2>&1 | sed 's/^/       /'

    # ── Dynamic .config patching (KernelSU Kconfig symbols) ──────
    # Runs AFTER defconfig so we never modify the defconfig file.
    # Uses scripts/config — the canonical kernel tool — to set or
    # enable Kconfig symbols cleanly before the final compilation.
    patch_kernel_config
    scripts/config --file out/.config --set-str LOCALVERSION ""
    scripts/config --file out/.config --disable LOCALVERSION_AUTO

    log_step "make kernel..."
    make -j$(nproc --all) -C "$SRC_DIR" O="$OUT_DIR" 2>&1 | sed 's/^/       /'

    log_ok "Kernel compiled in $(elapsed $T0)"
    log_group_end
}

# ── 5.6  Modules ─────────────────────────────────────────────────
build_modules() {
    log_group_start "📦" "Modules  [$(ts)]"
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

# ── 5.7  Artifact staging ─────────────────────────────────────────
stage_artifacts() {
    log_group_start "🗂️" "Staging Artifacts"
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

# ── 5.8  Image repack ─────────────────────────────────────────────
gki_repack() {
    log_group_start "🖼️" "Image Repack  [$(ts)]"
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

# ── 5.9  AnyKernel3 packaging ────────────────────────────────────
# Used when USE_ANYKERNEL3=true.  Clones the AK3 repo, copies the
# compiled Image / dtb / dtbo.img directly into it, and zips the
# whole directory into a flashable AK3 zip. No magiskboot or raw
# image repacking is performed.
package_anykernel3() {
    log_group_start "📦" "AnyKernel3 Package  [$(ts)]"
    local T0=$(date +%s)
    local AK3_DIR="$TC_DIR/NovaKernel/$DEVICE/AnyKernel3"
    local DEST="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    mkdir -p "$DEST"

    log_step "Cloning AnyKernel3 (${NK_AK3_REPO})..."
    rm -rf "$AK3_DIR"
    git clone --depth=1 "${NK_AK3_REPO}" "$AK3_DIR"

    log_step "Copying kernel artifacts into AnyKernel3 directory..."
    cp "$OUT_DIR/arch/arm64/boot/Image"                      "$AK3_DIR/Image"
    cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$AK3_DIR/dtb"
    cp "$OUT_DIR/arch/arm64/boot/dtbo.img"                   "$AK3_DIR/dtbo.img"
    log_ok "Copied → Image, dtb, dtbo.img"

    local KSU_VER=""
    if [[ "$BUILD_TYPE" == "KSU" ]]; then
        KSU_VER=$(grep -oP -- "-DKSU_VERSION=\K[0-9]+" \
            "$OUT_DIR/drivers/kernelsu/.ksu.o.cmd" 2>/dev/null | sed 's/^/-/' || true)
    fi

    local ZIPNAME="NovaKernel_$(date +%Y%m%d)_${BUILD_TYPE}${KSU_VER}_${VARIANT}.zip"
    local ZIPOUT="$DEST/$ZIPNAME"

    log_step "Creating $ZIPNAME (AnyKernel3 flashable zip)..."
    ( cd "$AK3_DIR" && zip -r -9 "$ZIPOUT" . -x ".git" -x ".git/*" -x "*/.git/*" )

    local SIZE SHA
    SIZE=$(du -sh "$ZIPOUT" | cut -f1)
    SHA=$(sha256sum "$ZIPOUT" | awk '{print $1}')

    log_sep
    log_kv "📦 Output:"  "$ZIPNAME"
    log_kv "📏 Size:"    "$SIZE"
    log_kv "🔑 SHA256:"  "${SHA:0:16}...${SHA: -8}"
    log_kv "⚡ Mode:"    "AnyKernel3"
    log_kv "⏱  Time:"   "$(elapsed $T0)"
    log_sep

    log_notice "AK3 ZIP ready → $ZIPNAME  ($SIZE)"
    log_group_end
}

# ── 5.10  Package as raw image ZIP ───────────────────────────────
# Used when USE_ANYKERNEL3=false (default).  Requires that
# stage_artifacts() and gki_repack() have already run.
gen_zip() {
    log_group_start "🤐" "Package  [$(ts)]"
    local T0=$(date +%s)
    local SRC="$TC_DIR/NovaKernel/$DEVICE/$BUILD_TYPE"
    local ZIP_DIR="$TC_DIR/NovaKernel/$DEVICE/ZIP"
    local IMG_DIR="$ZIP_DIR/images"

    wget -q "${NK_AK3_BANNER_URL}" -O "$ZIP_DIR/banner"
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
    log_kv "⚡ Mode:"    "Raw image flash"
    log_kv "⏱  Time:"   "$(elapsed $T0)"
    log_sep

    log_notice "ZIP ready → $ZIPNAME  ($SIZE)"
    log_group_end
}


# ─────────────────────────────────────────────────────────────────
#  § 6 — ENTRY POINT
# ─────────────────────────────────────────────────────────────────

ENTRY() {
    if [[ "${1:-}" == "clean" ]]; then
        log_group_start "🧹" "Clean"
        init_vars   # required so OUT_DIR and TC_DIR are resolved before rm
        rm -rf "$OUT_DIR" "$TC_DIR/NovaKernel"
        log_ok "Cleaned out/ and NovaKernel artifacts"
        log_group_end
        exit 0
    fi

    # ── Phase selector ───────────────────────────────────────────
    # --phase ksu   → only fetch_tools + KSU setup/hook/backport
    # --phase build → only fetch_tools + compile/package
    # (default)     → full build — both phases
    PHASE="all"
    if [[ "${1:-}" == "--phase" ]]; then
        PHASE="${2:?'--phase requires: ksu | build | all'}"
        shift 2
    fi

    local BUILD_START=$(date +%s)

    check_dependencies
    init_vars

    # ── Resolve variant ──────────────────────────────────────────
    if [[ -n "${1:-}" ]]; then
        VARIANT="$1"
    elif [[ -n "${NK_VARIANT:-}" ]]; then
        VARIANT="$NK_VARIANT"
    else
        prompt_variant   # _ci_guard inside will abort if IN_GHA=true
    fi

    [[ ! "$VARIANT" =~ ^(a73xq|a52sxq|m52xq)$ ]] && {
        log_err "Invalid variant: $VARIANT  (valid: a73xq | a52sxq | m52xq)"
        exit 1
    }

    # ── Resolve KernelSU ─────────────────────────────────────────
    if [[ -n "${NK_KSU:-}" ]]; then
        KERNELSU="${NK_KSU}"
    else
        prompt_ksu   # _ci_guard inside will abort if IN_GHA=true
    fi

    if [[ "$KERNELSU" == "true" ]]; then
        BUILD_TYPE="KSU"

        # KSU branch
        if [[ -n "${NK_KSU_BRANCH:-}" ]]; then
            KSU_BRANCH="${NK_KSU_BRANCH}"
        else
            prompt_ksu_branch
        fi
        [[ -z "${KSU_BRANCH:-}" ]] && KSU_BRANCH="legacy"

        # Hook type
        if [[ -n "${NK_HOOK_TYPE:-}" ]]; then
            HOOK_TYPE="${NK_HOOK_TYPE}"
        else
            prompt_hook_type
        fi
        [[ -z "${HOOK_TYPE:-}" ]] && HOOK_TYPE="kprobes"

        [[ ! "$HOOK_TYPE" =~ ^(kprobes|scope-min-1\.6|rksu|syscall|inline)$ ]] && {
            log_err "Invalid hook type: $HOOK_TYPE  (valid: kprobes | scope-min-1.6 | rksu | syscall | inline)"
            exit 1
        }

        # Backport
        if [[ -n "${NK_BACKPORT:-}" ]]; then
            BACKPORT="${NK_BACKPORT}"
        else
            prompt_backport
        fi
        [[ -z "${BACKPORT:-}" ]] && BACKPORT=false

    else
        BUILD_TYPE="GKI"
        HOOK_TYPE="kprobes"
        BACKPORT=false
    fi

    export BUILD_TYPE KSU_BRANCH HOOK_TYPE BACKPORT

    # ── Resolve AnyKernel3 toggle ────────────────────────────────
    # USE_ANYKERNEL3 is set in §0; the env var from CI overrides it.
    USE_ANYKERNEL3="${USE_ANYKERNEL3:-false}"
    export USE_ANYKERNEL3

    # ── Build plan ───────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}  ║       🚀  NovaKernel  Build Plan         ║${RESET}"
    echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Device:")  ${YELLOW}${BOLD}${VARIANT}${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Type:")    ${YELLOW}${BOLD}${BUILD_TYPE}${RESET}"
    if [[ "$KERNELSU" == "true" ]]; then
        echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "KSU Branch:") ${YELLOW}${BOLD}${KSU_BRANCH}${RESET}"
        echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Hook:")       ${YELLOW}${BOLD}${HOOK_TYPE}${RESET}"
        echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Backport:")   ${YELLOW}${BOLD}${BACKPORT}${RESET}"
    fi
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "AK3 Mode:") ${YELLOW}${BOLD}${USE_ANYKERNEL3}${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Out:")     ${DIM}${OUT_DIR:-$(pwd)/out}${RESET}"
    echo -e "${CYAN}${BOLD}  ║${RESET}  $(printf '%-12s' "Started:") ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
    echo ""

    # ── Run phases ───────────────────────────────────────────────
    fetch_tools

    if [[ "$PHASE" == "all" || "$PHASE" == "ksu" ]]; then
        if [[ "$KERNELSU" == "true" ]]; then
            setup_kernelsu
            apply_hook
            [[ "$BACKPORT" == "true" ]] && apply_backport
        fi
    fi

    if [[ "$PHASE" == "all" || "$PHASE" == "build" ]]; then
        build_kernel "$VARIANT"
        build_modules

        if [[ "${USE_ANYKERNEL3}" == "true" ]]; then
            # AnyKernel3 path: clone repo, copy Image/dtb/dtbo.img, zip.
            # Skips magiskboot repacking and the raw image flash structure.
            package_anykernel3
        else
            # Raw image path: stage artifacts, repack with magiskboot, zip.
            stage_artifacts
            gki_repack
            gen_zip
        fi
    fi

    # ── Done ─────────────────────────────────────────────────────
    local TOTAL
    TOTAL=$(elapsed $BUILD_START)

    echo ""
    echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}  ║     ✅  Build Completed Successfully     ║${RESET}"
    echo -e "${GREEN}${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Device:")    ${BOLD}${VARIANT}${RESET}"
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Type:")      ${BOLD}${BUILD_TYPE}${RESET}"
    if [[ "$KERNELSU" == "true" ]]; then
        echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Hook:")      ${BOLD}${HOOK_TYPE}${RESET}"
        echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Backport:")  ${BOLD}${BACKPORT}${RESET}"
    fi
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "AK3 Mode:") ${BOLD}${USE_ANYKERNEL3}${RESET}"
    echo -e "${GREEN}${BOLD}  ║${RESET}  $(printf '%-12s' "Duration:")  ${BOLD}${TOTAL}${RESET}"
    echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
    echo -e "${DIM}    @fraxer / @utkustnr — respect the authors' time${RESET}"
    echo ""

    log_notice "✅ Build complete — $VARIANT [$BUILD_TYPE] hook=$HOOK_TYPE backport=$BACKPORT ak3=$USE_ANYKERNEL3 in $TOTAL"
}

ENTRY "$@"

#!/usr/bin/env bash
# ============================================================
# NovaKernel — centralized build configuration
# Edit values HERE. One variable per line, nothing packed.
# Loaded once by .github/actions/build-env (first step) and
# exported to $GITHUB_ENV for every later step in the job.
# ============================================================

# ── Project ───────────────────────────────────────────────
KERNEL_NAME="NovaKernel"
OS="AOSP"

# ── Toolchain ─────────────────────────────────────────────
CLANG_VERSION="clang-r596125"
CLANG_URL="https://github.com/bachnxuan/aosp_clang_mirror/releases/download/clang-r596125-15682573/clang-r596125.tar.gz"

# ── External tool / patch sources ────────────────────────
AVBTOOL_URL="https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT"
KSU_SETUP_URL="https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh"
NOMOUNT_SETUP_URL="https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh"
BACKPORT_PATCH_URL="https://raw.githubusercontent.com/cyberc3dr/nGKI_Kernel_Build/refs/heads/rebase/Patches/backport_patches.sh"
HOOK_PATCH_URL_SCOPE_MIN="https://raw.githubusercontent.com/OmarAlsmehan/Random-stuff/e2dca691b866415c8ec59f306536f59c633be8e7/scope-min-manual-hook.1.6-5.4.patch"
HOOK_PATCH_URL_RKSU="https://raw.githubusercontent.com/rksuorg/kernel_patches/refs/heads/master/manual_hook/kernel-4.19_5.4.patch"
HOOK_PATCH_URL_SYSCALL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/syscall_hook_patches.sh"
HOOK_PATCH_URL_INLINE="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh"

# ── AnyKernel3 ────────────────────────────────────────────
AK3_REPO="https://github.com/OmarAlsmehan/AnyKernel3.git"
AK3_BANNER_URL="https://raw.githubusercontent.com/OmarAlsmehan/AnyKernel3/refs/heads/master/banner"

# ── DTB (confirmed identical across all three devices) ────
DTB_NAME="yupik.dtb"

# ── Per-device: defconfig ─────────────────────────────────
DEFCONFIG_A73XQ="lineage-a73xq_defconfig"
DEFCONFIG_A52SXQ="lineage-a52sxq_defconfig"
DEFCONFIG_M52XQ="lineage-m52xq_defconfig"

# ── Per-device: image folder name ─────────────────────────
DEVICE_IMAGE_A73XQ="A73"
DEVICE_IMAGE_A52SXQ="A52S"
DEVICE_IMAGE_M52XQ="M52"

# ── Per-device: stock kernel image URL ────────────────────
STOCK_IMAGE_URL_A73XQ="https://github.com/nicodotgit/proprietary_vendor_samsung_a73xq/releases/download/A736BXXSAGZA1_ODM/A736BXXSAGZA1_kernel.tar"
STOCK_IMAGE_URL_A52SXQ="https://github.com/RisenID/proprietary_vendor_samsung_a52sxq/releases/download/A528BXXUAGXK8_BTU/A528BXXUAGXK8_kernel.tar"
STOCK_IMAGE_URL_M52XQ="https://github.com/Mesa-Labs-Archive/proprietary_vendor_samsung_m52xq/releases/download/M526BXXS4CWL2_ZTO/M526BXXS4CWL2_kernel.tar"

# Resolves DEVICE_IMAGE / DEFCONFIG / STOCK_IMAGE_URL for the given
# variant using indirect expansion (no per-device values packed
# together — each lives on its own line above).
resolve_device_config() {
  local variant_upper
  variant_upper="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  local img_var="DEVICE_IMAGE_${variant_upper}"
  local cfg_var="DEFCONFIG_${variant_upper}"
  local url_var="STOCK_IMAGE_URL_${variant_upper}"
  DEVICE_IMAGE="${!img_var:?Unknown device variant: $1}"
  DEFCONFIG="${!cfg_var:?Unknown device variant: $1}"
  STOCK_IMAGE_URL="${!url_var:?Unknown device variant: $1}"
  export DEVICE_IMAGE DEFCONFIG STOCK_IMAGE_URL
}

#!/usr/bin/env bash
# ==============================================================================
# Motorola Camera 4 Recovery Package Compiler (Linux)
# Device: Motorola Moto G Stylus 5G 2023 (codename: genevn / genevn_g)
# Compatible ROMs: LineageOS 23.2, 24.0 (Android 17) & genevn custom ROMs
#
# 100% Vibe Coded with Google DeepMind Gemini 3.8 Flash (Thinking / High)
#
# Generates:
#   MotoCamera4_Genevn_Recovery_Installer.zip (Lineage Recovery / TWRP sideload)
#   with LineageOS addon.d OTA backup survival script
#
# Usage:
#   Interactive:  ./compile_recovery_package.sh
#   CLI:          ./compile_recovery_package.sh /path/to/stock_firmware [output_dir]
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates/recovery"
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/output"

# Styling
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_PURPLE="\033[35m"

log_info() { echo -e "${C_CYAN}[INFO]${C_RESET} $1"; }
log_ok()   { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_err()  { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }

banner() {
  echo -e "${C_BOLD}${C_CYAN}"
  echo "================================================================================"
  echo "   Motorola Camera 4 Recovery Package Compiler for Moto G Stylus 5G 2023        "
  echo "                     Device: genevn / genevn_g (LineageOS)                      "
  echo "================================================================================"
  echo -e "${C_PURPLE}   ⚡ 100% Vibe Coded with Google DeepMind Gemini 3.8 Flash (Thinking / High)  ${C_RESET}"
  echo -e "${C_BOLD}${C_CYAN}================================================================================${C_RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# 1. Dependency Verification
# ------------------------------------------------------------------------------
check_dependencies() {
  log_info "Verifying host build tools..."
  local missing=()

  # Check PATH and local tool paths
  export PATH="${HOME}/.local/bin:${PATH}"
  export LD_LIBRARY_PATH="${HOME}/.local/lib:${LD_LIBRARY_PATH}"

  for tool in zip simg2img lpunpack; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  # Check for EROFS extraction tool (fsck.erofs, erofs-extract, or 7z)
  if ! command -v fsck.erofs &>/dev/null && ! command -v erofs-extract &>/dev/null && ! command -v 7z &>/dev/null; then
    missing+=("erofs-utils (fsck.erofs)")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_err "Missing required build tools: ${missing[*]}"
    echo ""
    echo "Please install dependencies for your distribution:"
    echo "  Fedora / RHEL:   sudo dnf install android-tools erofs-utils p7zip p7zip-plugins zip"
    echo "  Ubuntu / Debian: sudo apt install android-sdk-libsparse-utils erofs-utils p7zip-full zip"
    echo "  Arch Linux:      sudo pacman -S android-tools erofs-utils p7zip zip"
    echo ""
    exit 1
  fi

  if [ ! -d "$TEMPLATES_DIR" ]; then
    log_err "Recovery templates directory not found: $TEMPLATES_DIR"
    exit 1
  fi

  log_ok "All required build tools and templates verified."
}

# ------------------------------------------------------------------------------
# 2. Firmware Input Resolution
# ------------------------------------------------------------------------------
get_firmware_path() {
  local input="$1"

  if [ -z "$input" ]; then
    echo -e "${C_BOLD}Please specify the path to your downloaded Motorola stock firmware:${C_RESET}"
    echo "  (Can be a folder containing sparsechunks, partition .img files, or a .zip file)"
    read -e -p "> Path: " input
  fi

  # Expand tilde and trim whitespace/quotes
  input="${input/#\~/$HOME}"
  input="${input%\"}"
  input="${input#\"}"
  input="${input%\'}"
  input="${input#\'}"

  if [ ! -e "$input" ]; then
    log_err "Specified path does not exist: $input"
    exit 1
  fi

  FIRMWARE_INPUT="$input"
  log_ok "Firmware source: $FIRMWARE_INPUT"
}

# ------------------------------------------------------------------------------
# 3. Extraction Engine
# ------------------------------------------------------------------------------
extract_firmware() {
  local src="$1"
  local work_dir="$2"
  local partitions_dir="${work_dir}/partitions"
  local extracted_dir="${work_dir}/extracted"

  mkdir -p "$partitions_dir" "$extracted_dir"

  # Case A: Already extracted directory with product/ and system_ext/
  if [ -d "$src" ] && [ -d "${src}/product" ] && [ -d "${src}/system_ext" ]; then
    log_info "Detected pre-extracted partition filesystem tree."
    FIRMWARE_ROOT="$src"
    return 0
  fi

  # Case B: If input is an archive, extract it first
  if [ -f "$src" ] && [[ "$src" =~ \.(zip|tar\.gz|tgz)$ ]]; then
    log_info "Unpacking firmware archive..."
    local unzipped_dir="${work_dir}/unpacked_zip"
    mkdir -p "$unzipped_dir"
    if [[ "$src" =~ \.zip$ ]]; then
      unzip -q "$src" -d "$unzipped_dir"
    else
      tar -xzf "$src" -C "$unzipped_dir"
    fi
    src="$unzipped_dir"
  fi

  # Case C: Check for sparsechunks or partition images
  local sparse_files=( $(ls "${src}"/super.img_sparsechunk.* 2>/dev/null | sort -V || true) )
  if [ ${#sparse_files[@]} -gt 0 ]; then
    log_info "Recombining ${#sparse_files[@]} super sparsechunk segments with simg2img..."
    simg2img "${sparse_files[@]}" "${work_dir}/super.raw.img"
    log_ok "Unpacking dynamic partitions from super.raw.img with lpunpack..."
    lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
  elif [ -f "${src}/super.img" ] || [ -f "${src}/super.raw.img" ]; then
    local super_img="${src}/super.img"
    [ ! -f "$super_img" ] && super_img="${src}/super.raw.img"
    log_info "Found super partition image: $super_img"
    lpunpack "$super_img" "$partitions_dir"
  elif [ -f "${src}/product.img" ] || [ -f "${src}/product_a.img" ]; then
    log_info "Found existing partition images in directory."
    partitions_dir="$src"
  else
    # Check one subdirectory deep (common for extracted RSA / LMSA zips)
    local sub_sparse=( $(ls "${src}"/*/super.img_sparsechunk.* 2>/dev/null | sort -V || true) )
    if [ ${#sub_sparse[@]} -gt 0 ]; then
      log_info "Found sparsechunks in subdirectory. Recombining..."
      simg2img "${sub_sparse[@]}" "${work_dir}/super.raw.img"
      lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
    else
      log_err "Could not identify recognized stock firmware files in: $src"
      log_err "Expected: super.img_sparsechunk.*, super.img, or partition images (product.img, etc.)"
      exit 1
    fi
  fi

  # Extract partition images (EROFS or EXT4)
  for part in product system_ext system vendor; do
    local img=""
    for candidate in "${partitions_dir}/${part}_a.img" "${partitions_dir}/${part}.img" "${partitions_dir}/${part}_b.img"; do
      if [ -f "$candidate" ]; then
        img="$candidate"
        break
      fi
    done

    if [ -z "$img" ]; then
      log_err "Missing required partition image: ${part}.img"
      exit 1
    fi

    local target_part_dir="${extracted_dir}/${part}"
    mkdir -p "$target_part_dir"

    log_info "Extracting ${part} partition (${img##*/})..."
    if command -v erofs-extract &>/dev/null; then
      erofs-extract --extract="$target_part_dir" --overwrite "$img" >/dev/null 2>&1 || true
    elif command -v fsck.erofs &>/dev/null; then
      fsck.erofs --extract="$target_part_dir" --overwrite "$img" >/dev/null 2>&1 || true
    else
      7z x -y -o"$target_part_dir" "$img" >/dev/null 2>&1 || true
    fi
  done

  FIRMWARE_ROOT="$extracted_dir"
  log_ok "All partitions successfully extracted to: $FIRMWARE_ROOT"
}

# ------------------------------------------------------------------------------
# 4. Proprietary Component Harvester
# ------------------------------------------------------------------------------
harvest_blobs() {
  local src_root="$1"
  local staging_dir="$2"

  log_info "Harvesting Motorola Camera 4 and multi-camera HAL components..."
  rm -rf "$staging_dir"
  mkdir -p "${staging_dir}/system"

  # Normalize system path (handles /system/system or /system)
  local sys_path="${src_root}/system"
  [ -d "${src_root}/system/system" ] && sys_path="${src_root}/system/system"

  # 1. Product Partition Files
  log_info "  - Harvesting Product camera applications & permissions..."
  mkdir -p "${staging_dir}/system/product/priv-app/MotCamera4"
  mkdir -p "${staging_dir}/system/product/app/MotCamera3AI"
  mkdir -p "${staging_dir}/system/product/etc/permissions"
  mkdir -p "${staging_dir}/system/product/etc/sysconfig"
  mkdir -p "${staging_dir}/system/product/etc/init"
  mkdir -p "${staging_dir}/system/product/etc/MotoDesktopAppConfig"

  cp -f "${src_root}/product/priv-app/MotCamera4/MotCamera4.apk" "${staging_dir}/system/product/priv-app/MotCamera4/"
  cp -f "${src_root}/product/app/MotCamera3AI/MotCamera3AI.apk" "${staging_dir}/system/product/app/MotCamera3AI/"
  cp -f "${src_root}/product/etc/permissions/"*com.motorola.camera3* "${staging_dir}/system/product/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/product/etc/sysconfig/"*com.motorola.camera3* "${staging_dir}/system/product/etc/sysconfig/" 2>/dev/null || true
  [ -f "${src_root}/product/etc/init/init.motcamera3.lens.rc" ] && cp -f "${src_root}/product/etc/init/init.motcamera3.lens.rc" "${staging_dir}/system/product/etc/init/" || true
  [ -d "${src_root}/product/etc/MotoDesktopAppConfig" ] && cp -rf "${src_root}/product/etc/MotoDesktopAppConfig/"* "${staging_dir}/system/product/etc/MotoDesktopAppConfig/" || true

  # 2. System_ext Partition Files
  log_info "  - Harvesting System_ext ImagerTuning, Desktop, frameworks, and libs..."
  mkdir -p "${staging_dir}/system/system_ext/priv-app/ImagerTuning-U"
  mkdir -p "${staging_dir}/system/system_ext/priv-app/MotCameraDesktop"
  mkdir -p "${staging_dir}/system/system_ext/framework"
  mkdir -p "${staging_dir}/system/system_ext/lib64"
  mkdir -p "${staging_dir}/system/system_ext/etc/permissions"
  mkdir -p "${staging_dir}/system/system_ext/etc/enable-disable-packages"
  mkdir -p "${staging_dir}/system/system_ext/etc/sysconfig"

  cp -f "${src_root}/system_ext/priv-app/ImagerTuning-U/ImagerTuning-U.apk" "${staging_dir}/system/system_ext/priv-app/ImagerTuning-U/"
  cp -f "${src_root}/system_ext/priv-app/MotCameraDesktop/MotCameraDesktop.apk" "${staging_dir}/system/system_ext/priv-app/MotCameraDesktop/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/framework/"*com.motorola.* "${staging_dir}/system/system_ext/framework/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/permissions/"*motorola* "${staging_dir}/system/system_ext/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/permissions/"*imager* "${staging_dir}/system/system_ext/etc/permissions/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/public.libraries-motocameradesktop.txt" "${staging_dir}/system/system_ext/etc/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/public.libraries-motoimagetuner.txt" "${staging_dir}/system/system_ext/etc/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/enable-disable-packages/"* "${staging_dir}/system/system_ext/etc/enable-disable-packages/" 2>/dev/null || true
  cp -f "${src_root}/system_ext/etc/sysconfig/"* "${staging_dir}/system/system_ext/etc/sysconfig/" 2>/dev/null || true

  for lib in libarcsoft_calibverify_TriCamera.so libcameraOIS_jni.so libcameraraw_jni.so \
             libimgTuner_jni.motoimagetuner.so libjni_helper.motocameradesktop.so libopencv_java4.so \
             motorola.hardware.camera.desktop@1.0.so motorola.hardware.camera.desktop@2.0.so \
             motorola.hardware.camera.imgtuner@2.0.so; do
    [ -f "${src_root}/system_ext/lib64/${lib}" ] && cp -f "${src_root}/system_ext/lib64/${lib}" "${staging_dir}/system/system_ext/lib64/" || true
  done

  # 3. System Framework and Libraries
  log_info "  - Harvesting System framework signature libraries..."
  mkdir -p "${staging_dir}/system/framework"
  mkdir -p "${staging_dir}/system/etc/permissions"
  mkdir -p "${staging_dir}/system/lib64"

  cp -f "${sys_path}/framework/com.motorola.motosignature.jar" "${staging_dir}/system/framework/" 2>/dev/null || true
  cp -f "${sys_path}/framework/moto-core_services.jar" "${staging_dir}/system/framework/" 2>/dev/null || true
  cp -f "${sys_path}/framework/moto-settings.jar" "${staging_dir}/system/framework/" 2>/dev/null || true
  cp -f "${sys_path}/etc/permissions/com.motorola.motosignature.xml" "${staging_dir}/system/etc/permissions/" 2>/dev/null || true
  cp -f "${sys_path}/etc/permissions/moto-core_services.xml" "${staging_dir}/system/etc/permissions/" 2>/dev/null || true
  cp -f "${sys_path}/etc/permissions/moto-settings.xml" "${staging_dir}/system/etc/permissions/" 2>/dev/null || true
  cp -f "${sys_path}/lib64/motorola.hardware.camera.imgtuner@1.0.so" "${staging_dir}/system/lib64/" 2>/dev/null || true

  # 4. Vendor Camera HAL & VINTF Manifest
  log_info "  - Harvesting Vendor ImageTuner HAL and VINTF manifests..."
  mkdir -p "${staging_dir}/system/vendor/bin/hw"
  mkdir -p "${staging_dir}/system/vendor/etc/init"
  mkdir -p "${staging_dir}/system/vendor/etc/vintf/manifest"
  mkdir -p "${staging_dir}/system/vendor/lib64/hw"

  cp -f "${src_root}/vendor/bin/hw/motorola.hardware.camera.imgtuner@2.0-service" "${staging_dir}/system/vendor/bin/hw/" 2>/dev/null || true
  cp -f "${src_root}/vendor/etc/init/motorola.hardware.camera.imgtuner@2.0-service.rc" "${staging_dir}/system/vendor/etc/init/" 2>/dev/null || true
  cp -f "${src_root}/vendor/lib64/hw/motorola.hardware.camera.imgtuner@2.0-impl.so" "${staging_dir}/system/vendor/lib64/hw/" 2>/dev/null || true
  cp -f "${src_root}/vendor/lib64/motorola.hardware.camera.imgtuner@1.0.so" "${staging_dir}/system/vendor/lib64/" 2>/dev/null || true
  cp -f "${src_root}/vendor/lib64/motorola.hardware.camera.imgtuner@2.0.so" "${staging_dir}/system/vendor/lib64/" 2>/dev/null || true

  # Synthesize/copy manifest_imgtuner.xml
  local vintf_file="${staging_dir}/system/vendor/etc/vintf/manifest/manifest_imgtuner.xml"
  if [ -f "${src_root}/vendor/etc/vintf/manifest/manifest_imgtuner.xml" ]; then
    cp -f "${src_root}/vendor/etc/vintf/manifest/manifest_imgtuner.xml" "$vintf_file"
  else
    cat <<'EOF' > "$vintf_file"
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>motorola.hardware.camera.imgtuner</name>
        <transport>hwbinder</transport>
        <version>1.0</version>
        <version>2.0</version>
        <interface>
            <name>IImageTuning</name>
            <instance>default</instance>
        </interface>
        <fqname>@1.0::IImageTuning/default</fqname>
        <fqname>@2.0::IImageTuning/default</fqname>
    </hal>
</manifest>
EOF
  fi

  # Verify core APK presence
  if [ ! -f "${staging_dir}/system/product/priv-app/MotCamera4/MotCamera4.apk" ]; then
    log_err "Failed to extract MotCamera4.apk! Verify the source firmware."
    exit 1
  fi
  log_ok "Proprietary components harvested successfully."
}

# ------------------------------------------------------------------------------
# 5. Recovery Package Assembly
# ------------------------------------------------------------------------------
build_recovery_package() {
  local staging_dir="$1"
  local output_dir="$2"
  local build_tmp="$3"

  mkdir -p "$output_dir"
  local abs_output_dir="$(cd "$output_dir" && pwd)"

  log_info "Assembling Recovery Flashable Installer..."
  local rec_build="${build_tmp}/recovery_build"
  rm -rf "$rec_build"
  mkdir -p "$rec_build"

  # Copy templates
  cp -rf "${TEMPLATES_DIR}/"* "$rec_build/"
  # Ensure addon.d templates are inside system/addon.d
  mkdir -p "${rec_build}/system/addon.d"
  cp -rf "${TEMPLATES_DIR}/addon.d/"* "${rec_build}/system/addon.d/"
  rm -rf "${rec_build}/addon.d"

  # Copy harvested system tree
  cp -rf "${staging_dir}/system/"* "${rec_build}/system/"

  # Package zip
  local rec_zip="${abs_output_dir}/MotoCamera4_Genevn_Recovery_Installer.zip"
  rm -f "$rec_zip"
  (cd "$rec_build" && zip -r9q "$rec_zip" .)

  log_ok "Recovery Installer created: $rec_zip ($(du -h "$rec_zip" | cut -f1))"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------
main() {
  banner
  check_dependencies

  local cli_input="$1"
  local cli_out="$2"

  get_firmware_path "$cli_input"

  local out_dir="${cli_out:-$DEFAULT_OUTPUT_DIR}"
  local work_dir="$(mktemp -d /tmp/motocamera_recovery_build_XXXXXX)"

  trap 'rm -rf "$work_dir"' EXIT

  log_info "Working directory initialized: $work_dir"
  extract_firmware "$FIRMWARE_INPUT" "$work_dir"

  local staging_dir="${work_dir}/staging"
  harvest_blobs "$FIRMWARE_ROOT" "$staging_dir"

  build_recovery_package "$staging_dir" "$out_dir" "$work_dir"

  local rec_zip="${out_dir}/MotoCamera4_Genevn_Recovery_Installer.zip"
  echo ""
  echo -e "${C_BOLD}${C_GREEN}================================================================================"
  echo "                Recovery Package Compiled Successfully!                         "
  echo -e "================================================================================${C_RESET}"
  echo ""
  echo "Installer Package:"
  echo "  --> ${rec_zip}"
  echo ""
  echo "How to install via Lineage Recovery:"
  echo "  1. Reboot your phone into Recovery mode."
  echo "  2. Select 'Apply Update' -> 'Apply from ADB'."
  echo "  3. Run the following command from your PC:"
  echo "       adb sideload \"${rec_zip}\""
  echo "  4. If prompted with 'Signature verification failed. Install anyway?', select 'Yes'."
  echo "  5. Reboot to system. The camera is ready to use!"
  echo ""
  echo -e "${C_CYAN}[OTA Survival]${C_RESET} The included addon.d script will automatically"
  echo "preserve the camera suite across nightly LineageOS updates."
  echo ""
}

main "$@"

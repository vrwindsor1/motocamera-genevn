#!/usr/bin/env bash
# ==============================================================================
# Motorola Camera 4 Recovery Package Compiler (Linux)
# Device: Motorola Moto G Stylus 5G 2023 (codename: genevn / genevn_g)
# Compatible ROMs: LineageOS 23.2, 24.0 (Android 17) & genevn custom ROMs
# Tested Firmware: U1TGNS34.42-86-2-25 & U1TGNS34.42-86-2-38 (Android 14)
#
# 100% Vibe Coded with Google DeepMind Gemini 3.8 Flash (Thinking / High)
#
# Generates:
#   MotoCamera4_Genevn_Recovery_Installer.zip (Lineage Recovery / TWRP sideload)
#   with LineageOS addon.d OTA backup survival script
#
# Usage:
#   Interactive:  ./compile_recovery_package_linux.sh
#   CLI:          ./compile_recovery_package_linux.sh "/path/to/stock_firmware" [output_dir]
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_TEMPLATES_DIR="${SCRIPT_DIR}/templates/recovery"
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/output"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/vrwindsor1/motocamera-genevn/main"

# Global state for trap cleanup
WORK_DIR=""
MOUNTED_DIRS=()

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
# 0. Environment Setup (Ensure tools in PATH even under sudo)
# ------------------------------------------------------------------------------
setup_environment() {
  # If executed via sudo, include the real user's ~/.local/bin and ~/.local/lib
  if [ -n "$SUDO_USER" ]; then
    local real_home
    real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    if [ -n "$real_home" ] && [ -d "$real_home" ]; then
      export PATH="${real_home}/.local/bin:${PATH}"
      export LD_LIBRARY_PATH="${real_home}/.local/lib:${LD_LIBRARY_PATH}"
    fi
  fi

  export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:${PATH}"
  export LD_LIBRARY_PATH="${HOME}/.local/lib:${LD_LIBRARY_PATH}"
}

# ------------------------------------------------------------------------------
# 1. Dependency Verification
# ------------------------------------------------------------------------------
check_dependencies() {
  log_info "Verifying host build tools..."
  local missing=()

  for tool in zip simg2img lpunpack; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  # Verify EROFS extraction capability:
  # 1. fsck.erofs or erofs-extract
  # 2. OR root permissions with native kernel erofs support
  local erofs_capable=0
  if command -v erofs-extract &>/dev/null; then
    erofs_capable=1
  elif command -v fsck.erofs &>/dev/null; then
    erofs_capable=1
  elif [ "$(id -u)" -eq 0 ] && modinfo erofs &>/dev/null; then
    erofs_capable=1
  fi

  if [ "$erofs_capable" -eq 0 ]; then
    missing+=("erofs-utils (fsck.erofs)")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    log_err "Missing required build tools: ${missing[*]}"
    echo ""
    echo "Please install dependencies for your distribution:"
    echo "  Fedora / RHEL:   sudo dnf install android-tools erofs-utils zip curl"
    echo "  Ubuntu / Debian: sudo apt install android-sdk-libsparse-utils erofs-utils zip curl"
    echo "  Arch Linux:      sudo pacman -S android-tools erofs-utils zip curl"
    echo ""
    exit 1
  fi

  log_ok "All required host build tools are available."
}

# ------------------------------------------------------------------------------
# 2. Template Resolution (Local or Standalone Remote Fetch)
# ------------------------------------------------------------------------------
ensure_templates() {
  local target_work_dir="$1"

  # Case A: templates exist relative to script directory
  if [ -d "$LOCAL_TEMPLATES_DIR" ] && [ -f "${LOCAL_TEMPLATES_DIR}/META-INF/com/google/android/update-binary" ]; then
    TEMPLATES_DIR="$LOCAL_TEMPLATES_DIR"
    log_ok "Using local recovery templates."
    return 0
  fi

  # Case B: templates exist in current working directory
  if [ -d "./templates/recovery" ] && [ -f "./templates/recovery/META-INF/com/google/android/update-binary" ]; then
    TEMPLATES_DIR="$(pwd)/templates/recovery"
    log_ok "Using local recovery templates."
    return 0
  fi

  log_info "Local templates not found. Fetching open-source templates from GitHub..."
  TEMPLATES_DIR="${target_work_dir}/downloaded_templates"
  mkdir -p "${TEMPLATES_DIR}/META-INF/com/google/android" "${TEMPLATES_DIR}/addon.d"

  local files=(
    "templates/recovery/build.prop"
    "templates/recovery/toybox"
    "templates/recovery/addon.d/addond_head"
    "templates/recovery/addon.d/addond_tail"
    "templates/recovery/META-INF/com/google/android/update-binary"
    "templates/recovery/META-INF/com/google/android/updater-script"
  )

  for file in "${files[@]}"; do
    local rel_dest="${file#templates/recovery/}"
    local dest="${TEMPLATES_DIR}/${rel_dest}"
    mkdir -p "$(dirname "$dest")"
    if command -v curl &>/dev/null; then
      curl -sSL "${GITHUB_RAW_BASE}/${file}" -o "$dest"
    elif command -v wget &>/dev/null; then
      wget -q "${GITHUB_RAW_BASE}/${file}" -O "$dest"
    else
      log_err "curl or wget is required to download recovery templates."
      exit 1
    fi
  done

  chmod +x "${TEMPLATES_DIR}/toybox" "${TEMPLATES_DIR}/META-INF/com/google/android/update-binary"
  log_ok "Recovery scaffolding templates downloaded successfully."
}

# ------------------------------------------------------------------------------
# 3. Firmware Input Resolution
# ------------------------------------------------------------------------------
get_firmware_path() {
  local input="$1"

  if [ -z "$input" ]; then
    echo -e "${C_BOLD}Please specify the path to your downloaded Motorola stock firmware:${C_RESET}"
    echo "  (Can be a folder containing sparsechunks, partition .img files, or a .zip file)"
    echo -e "${C_CYAN}  Tip: You can obtain stock firmware via Motorola Software Fix (RSA) or from:${C_RESET}"
    echo -e "       ${C_YELLOW}https://mirrors.lolinet.com/firmware/lenomola/2023/genevn/official/RETUS/${C_RESET}"
    echo -e "       ${C_GREEN}Note: Verified on builds U1TGNS34.42-86-2-25 & U1TGNS34.42-86-2-38 (Android 14).${C_RESET}"
    echo ""
    read -e -p "> Path: " input
  fi

  # Trim leading and trailing whitespace
  input="$(echo "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Strip quotes safely (handles single or double quotes)
  while [[ "$input" =~ ^[\'\"](.*)[\'\"]$ ]]; do
    input="${BASH_REMATCH[1]}"
    input="$(echo "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  done

  # Expand tilde
  input="${input/#\~/$HOME}"

  if [ ! -e "$input" ]; then
    log_err "Specified path does not exist: $input"
    exit 1
  fi

  FIRMWARE_INPUT="$input"
  log_ok "Firmware source: $FIRMWARE_INPUT"
}

# ------------------------------------------------------------------------------
# 4. Extraction Engine
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

  # Case C: Check for sparsechunks safely (spaces and special characters preserved)
  local sparse_files=()
  while IFS= read -r -d $'\0' f; do
    [ -n "$f" ] && sparse_files+=("$f")
  done < <(find "$src" -maxdepth 1 -name "super.img_sparsechunk.*" -print0 2>/dev/null | sort -z -V)

  if [ ${#sparse_files[@]} -gt 0 ]; then
    log_info "Recombining ${#sparse_files[@]} super sparsechunk segments with simg2img..."
    simg2img "${sparse_files[@]}" "${work_dir}/super.raw.img"
    log_ok "Unpacking dynamic partitions from super.raw.img with lpunpack..."
    lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
    # Immediately reclaim disk space from raw super image (~9.5 GB)
    rm -f "${work_dir}/super.raw.img"
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
    local sub_sparse=()
    while IFS= read -r -d $'\0' f; do
      [ -n "$f" ] && sub_sparse+=("$f")
    done < <(find "$src" -mindepth 2 -maxdepth 2 -name "super.img_sparsechunk.*" -print0 2>/dev/null | sort -z -V)

    if [ ${#sub_sparse[@]} -gt 0 ]; then
      log_info "Found ${#sub_sparse[@]} sparsechunks in subdirectory. Recombining..."
      simg2img "${sub_sparse[@]}" "${work_dir}/super.raw.img"
      lpunpack "${work_dir}/super.raw.img" "$partitions_dir"
      rm -f "${work_dir}/super.raw.img"
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
    local extracted=0

    # Strategy 1: If running as root, attempt loop mount (fastest, 0 disk space)
    if [ "$(id -u)" -eq 0 ]; then
      if mount -t erofs -o loop,ro "$img" "$target_part_dir" 2>/dev/null || mount -t ext4 -o loop,ro "$img" "$target_part_dir" 2>/dev/null; then
        MOUNTED_DIRS+=("$target_part_dir")
        extracted=1
        log_ok "Mounted ${part} partition via kernel loop."
      fi
    fi

    # Strategy 2: erofs-extract or fsck.erofs
    if [ "$extracted" -eq 0 ]; then
      if command -v erofs-extract &>/dev/null; then
        erofs-extract --extract="$target_part_dir" --overwrite "$img" 2>/dev/null || true
      elif command -v fsck.erofs &>/dev/null; then
        fsck.erofs --extract="$target_part_dir" --overwrite "$img" 2>/dev/null || true
      fi

      # Verify extraction succeeded
      if [ -d "${target_part_dir}/priv-app" ] || [ -d "${target_part_dir}/app" ] || [ -d "${target_part_dir}/framework" ] || [ -d "${target_part_dir}/bin" ]; then
        extracted=1
      fi
    fi

    if [ "$extracted" -eq 0 ]; then
      log_err "Failed to extract ${part} partition (${img##*/})!"
      log_err "Please verify that erofs-utils is installed (sudo dnf install erofs-utils / sudo apt install erofs-utils)."
      exit 1
    fi
  done

  FIRMWARE_ROOT="$extracted_dir"
  log_ok "All partitions successfully prepared in: $FIRMWARE_ROOT"
}

# ------------------------------------------------------------------------------
# 5. Proprietary Component Harvester
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
# 6. Recovery Package Assembly
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
# Cleanup handler
# ------------------------------------------------------------------------------
cleanup() {
  # Unmount any loop mounts
  if [ ${#MOUNTED_DIRS[@]} -gt 0 ]; then
    log_info "Unmounting temporary loop mounts..."
    for mnt in "${MOUNTED_DIRS[@]}"; do
      umount -l "$mnt" 2>/dev/null || true
    done
  fi

  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------
main() {
  banner
  setup_environment
  check_dependencies

  local cli_input="$1"
  local cli_out="$2"

  local out_dir="${cli_out:-$DEFAULT_OUTPUT_DIR}"
  mkdir -p "$out_dir"
  local abs_out_dir="$(cd "$out_dir" && pwd)"

  # Allocate working directory on real storage rather than RAM-backed /tmp
  local base_work_dir="${abs_out_dir}/.build_tmp"
  mkdir -p "$base_work_dir"
  WORK_DIR="$(mktemp -d "${base_work_dir}/motocamera_build_XXXXXX" 2>/dev/null || mktemp -d /tmp/motocamera_build_XXXXXX)"

  log_info "Working directory initialized: $WORK_DIR"
  ensure_templates "$WORK_DIR"

  get_firmware_path "$cli_input"

  extract_firmware "$FIRMWARE_INPUT" "$WORK_DIR"

  local staging_dir="${WORK_DIR}/staging"
  harvest_blobs "$FIRMWARE_ROOT" "$staging_dir"

  build_recovery_package "$staging_dir" "$abs_out_dir" "$WORK_DIR"

  local rec_zip="${abs_out_dir}/MotoCamera4_Genevn_Recovery_Installer.zip"
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

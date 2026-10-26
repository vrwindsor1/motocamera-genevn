# Motorola Camera 4 & Multi-Camera HAL Suite for Moto G Stylus 5G 2023 (`genevn`)
### Custom ROM Compatibility Package for LineageOS

---

## Overview

This suite restores the official Motorola Camera experience and unlocks full multi-camera hardware access on the **Moto G Stylus 5G 2023** (codename: `genevn`, Qualcomm Snapdragon 6 Gen 1 / SM6450) running **LineageOS 23.2 and 24.0**.

> [!TIP]
> **Install Anytime — No First-Boot Requirement**:  
> Unlike GApps (which must be installed before first boot to properly register privileged permissions), this package **can be installed at any time**. It works whether flashed alongside a fresh ROM install or applied to an already configured, running daily-driver setup.

> [!NOTE]
> **OTA Survival vs. Major Android Revision Sideloads**:
> * **Standard LineageOS OTA Updates**: Survives automatically via the included `/system/addon.d/30-motocamera.sh` backup script.
> * **Major Android Revision Sideloads**: Upgrading across major Android versions via full zip sideloading overwrites the system partitions without running `addon.d`. Simply re-flash the recovery installer package or re-run the live installer after the major OS upgrade.

Four installation methods are provided to fit any setup:
1. **Recovery Flashable Zip** (`output/MotoCamera4_Genevn_Recovery_Installer.zip`) — Flashed in Lineage Recovery / TWRP.
2. **Magisk / KernelSU Module** (`output/MotoCamera4_Genevn_Magisk_KernelSU_Module.zip`) — Systemless overlay module installable via the KernelSU Manager or Magisk.
3. **1-Click Live Installer** (`output/install_motocamera_live.sh`) — Installs directly via ADB root on a running device using native Android OverlayFS.
4. **Transplanted Partition Images** (`output/transplanted_images/`) — Pre-built `product.img`, `system_ext.img`, `system.img`, and `vendor.img` dynamic partitions.

---

## Hardware Camera Mapping on Genevn

Analyzed and verified directly from the stock ROM device configurations (`config_devices_genevn` and `app_feature_genevn`):
- **Camera ID 0 (`BACK_MAIN`)**: OmniVision OV50A 50MP sensor (`mot_ov50a`) with Quad-Bayer output (12.5MP binned / 50MP Ultra-Res).
- **Camera ID 1 (`FRONT_MAIN`)**: OmniVision OV16A1Q 16MP selfie sensor (`mot_ov16a1q`).
- **Camera ID 2 (`BACK_WIDE` / `BACK_MACRO`)**: Samsung S5K4H7 8MP Ultra-Wide & Autofocus Macro sensor (`mot_s5k4h7` / `mot_s5k4h7_macro`).
- **Logical Multi-Cam (`LOGICAL_DEPTH`)**: Dual-camera depth pipeline combining `BACK_MAIN` and `BACK_WIDE` for hardware bokeh / portrait mode (`mot_depth`).

---

## Included Components & Dependencies

### 1. Applications (`product/` & `system_ext/`)
- `MotCamera4.apk` (`com.motorola.camera3`): Official Motorola Camera app (v9.1.14.42) with ArcSoft post-processing, Meishe video effects, Morpho panorama, Super Night, Slow Motion, Document Scanner, and Pro controls.
- `MotCamera3AI.apk` (`com.motorola.camera3.content.ai`): AI scene detection, smart composition, and auto-smile capture models (`ModelContentProvider`).
- `ImagerTuning-U.apk` (`com.motorola.imagertuning_u`): Motorola tuning provider (`TuningContentProvider`) for real-time sensor tuning and image quality calibration.
- `MotCameraDesktop.apk` (`com.motorola.motcameradesktop`): Ready For desktop webcam mode and wireless webcam streaming.

### 2. Framework Jars & Shared Libraries (`system/framework` & `system_ext/framework`)
- `com.motorola.motosignature.jar`: Required framework library verified by `MotCamera4` (`<uses-library android:name="com.motorola.motosignature" android:required="true"/>`).
- `moto-core_services.jar`: Core Motorola framework helper services.
- `moto-settings.jar`: Motorola device settings bridge.
- `com.motorola.hardware.camera.desktop.jar`: Desktop camera HAL client interface.
- `com.motorola.libimgTuner.jar`: Client library for `motorola.hardware.camera.imgtuner`.
- `com.motorola.imager.u.jar`: Imager tuning library interface.

### 3. Native Libraries & HAL Service (`vendor/` & `system_ext/lib64/`)
- `motorola.hardware.camera.imgtuner@2.0-service`: The missing Motorola vendor camera daemon responsible for image tuning parameters.
- `motorola.hardware.camera.imgtuner@2.0-impl.so`, `@1.0.so`, `@2.0.so`: Vendor implementation libraries.
- `libopencv_java4.so`: OpenCV 4 native runtime required by `libcameraraw_jni.so` and `libcameraOIS_jni.so`.
- `libarcsoft_calibverify_TriCamera.so`: ArcSoft multi-camera calibration verification library.
- `libjni_helper.motocameradesktop.so`: Native JNI helper for Ready For desktop camera pipeline.
- `libimgTuner_jni.motoimagetuner.so`: JNI bridge for image tuning hardware binder.

### 4. Permissions & System Features
- `com.motorola.camera3.genevn.xml`: Declares system feature `com.motorola.camera3.genevn` for sensor topology resolution.
- `com.motorola.camera3.xml`: Declares system feature `com.motorola.camera3`.
- `com.motorola.camera3.content.ai.xml`: Feature flag for AI camera content.
- `com.motorola.camera3.lens.xml`: Feature flag `com.google.lens.feature.CAMERA_INTEGRATION`.
- `com.motorola.imager.access.u.xml`: Grants `camera` Linux GID to imager tuning services.
- `privapp-permissions-com.motorola.camera3.xml`: Grants privileged signature permissions.
- `public.libraries-motoimagetuner.txt` & `public.libraries-motocameradesktop.txt`: Public namespace access for app JNI libraries.

### 5. Multi-Camera Hardware Expose Properties
Configured automatically via `system.prop` (Module) or `init.motcamera_genevn.rc` (Recovery / Transplant):
```properties
persist.vendor.camera.physical.num=3
persist.vendor.camera.expose.aux=1
vendor.camera.aux.packagelist=org.codeaurora.snapcam,com.motorola.camera3,com.motorola.motocit,org.lineageos.aperture,net.sourceforge.opencamera,com.google.android.GoogleCamera
vendor.camera.aux.packagelist2=com.motorola.ccc,com.android.settings,com.motorola.handycam,com.motorola.motointelligence
vendor.camera.aux.logicalCamPackagelist=org.codeaurora.snapcam,com.motorola.camera3,org.lineageos.aperture
ro.camera.cfa.packagelist=com.motorola.coresettingsext,com.motorola.camera2,com.motorola.camera3,com.motorola.actions
camera.disable_zsl_mode=1
ro.camera.enableCamera1MaxZsl=1
persist.vendor.camera.privapp.list=org.codeaurora.snapcam,com.motorola.camera3
ro.product.motcameradesktop=1
ro.com.google.lens.oem_camera_package=com.motorola.camera3
```

---

## Installation Instructions

### Method 1: Recovery Flashable Zip (Recommended for Clean Installs)
1. Boot into **Lineage Recovery** (or TWRP).
2. Flash the LineageOS 24.0 ROM:
   ```bash
   adb sideload android/LineageOS_24.0_Android17/lineage-24.0-20261024-nightly-genevn-signed.zip
   ```
3. (Optional) Flash GApps:
   ```bash
   adb sideload android/LineageOS_24.0_Android17/MindTheGapps-17.0.0-arm64-20261022_132445.zip
   ```
4. Flash the **Moto Camera 4 Recovery Installer**:
   ```bash
   adb sideload output/MotoCamera4_Genevn_Recovery_Installer.zip
   ```
5. Reboot to system.
   > **Note on Updates**: The installer places a `30-motocamera.sh` script into `/system/addon.d/` so the camera suite automatically survives subsequent LineageOS OTA updates!

---

### Method 2: KernelSU / Magisk Module (Systemless)
If you are using the patched kernel boot image (`android/LineageOS_24.0_Android17/kernelsu_next_patched_boot.img`):
1. Flash the KernelSU patched boot image in bootloader:
   ```bash
   fastboot flash boot android/LineageOS_24.0_Android17/kernelsu_next_patched_boot.img
   ```
2. Boot into Android and open the **KernelSU** (or **Magisk**) app.
3. Go to **Modules** -> **Install from Storage**.
4. Select `MotoCamera4_Genevn_Magisk_KernelSU_Module.zip`.
5. Reboot when prompted.

---

### Method 3: Direct Fastboot Flash of Transplanted Partitions
1. Reboot into **fastbootd** mode:
   ```bash
   adb reboot fastboot
   ```
2. Flash the transplanted dynamic partitions:
   ```bash
   fastboot flash product output/transplanted_images/product.img
   fastboot flash system_ext output/transplanted_images/system_ext.img
   fastboot flash system output/transplanted_images/system.img
   fastboot flash vendor output/transplanted_images/vendor.img
   ```
3. Reboot into system:
   ```bash
   fastboot reboot
   ```

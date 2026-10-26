#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
STAGING_DIR="${ROOT_DIR}/build_module/staging"

echo "=================================================="
echo "  Moto Camera 4 Live Environment Installer        "
echo "  Moto G Stylus 5G 2023 (genevn) - LineageOS 24.0 "
echo "=================================================="

echo "[1/7] Checking ADB connection..."
adb wait-for-device
adb root
adb wait-for-device

echo "[2/7] Enabling writable OverlayFS on dynamic partitions..."
adb remount

echo "[3/7] Pushing camera suite, companion apps, framework, and HAL..."
adb push "${STAGING_DIR}/system/"* /system/
adb push "${STAGING_DIR}/product/"* /product/
adb push "${STAGING_DIR}/system_ext/"* /system_ext/
adb push "${STAGING_DIR}/vendor/"* /vendor/

echo "[4/7] Setting permissions and SELinux security contexts..."
adb shell "chmod -R 0755 /product/priv-app/MotCamera4 /product/app/MotCamera3AI /system_ext/priv-app/ImagerTuning-U /system_ext/priv-app/MotCameraDesktop"
adb shell "find /product/priv-app/MotCamera4 /product/app/MotCamera3AI /system_ext/priv-app/ImagerTuning-U /system_ext/priv-app/MotCameraDesktop -name '*.apk' -exec chmod 0644 {} \;"
adb shell "chmod 0644 /system/framework/com.motorola.* /system/framework/moto-* /system_ext/framework/com.motorola.*"
adb shell "chmod 0644 /system/etc/permissions/com.motorola.* /system/etc/permissions/moto-* /product/etc/permissions/*motorola* /system_ext/etc/permissions/*motorola*"
adb shell "chmod 0755 /vendor/bin/hw/motorola.hardware.camera.imgtuner@2.0-service"
adb shell "chmod 0644 /vendor/lib64/hw/motorola.hardware.camera.imgtuner@2.0-impl.so /vendor/lib64/motorola.hardware.camera.imgtuner*.so"
adb shell "chmod 0644 /vendor/etc/init/motorola.hardware.camera.imgtuner@2.0-service.rc /vendor/etc/vintf/manifest/manifest_imgtuner.xml"

# Precise SELinux labels
adb shell "chcon -R u:object_r:system_file:s0 /product/priv-app/MotCamera4 /product/app/MotCamera3AI /system_ext/priv-app/ImagerTuning-U /system_ext/priv-app/MotCameraDesktop /system/framework/com.motorola.* /system/framework/moto-* /system_ext/framework/com.motorola.* /system/etc/permissions/*moto* /product/etc/permissions/*moto* /system_ext/etc/permissions/*moto*"
adb shell "chcon u:object_r:system_lib_file:s0 /system/lib64/motorola.hardware.camera.imgtuner@1.0.so /system_ext/lib64/*.so"
adb shell "chcon u:object_r:vendor_configs_file:s0 /vendor/etc/vintf/manifest/manifest_imgtuner.xml /vendor/etc/init/motorola.hardware.camera.imgtuner@2.0-service.rc"
adb shell "chcon u:object_r:vendor_file:s0 /vendor/bin/hw/motorola.hardware.camera.imgtuner@2.0-service /vendor/lib64/hw/motorola.hardware.camera.imgtuner@2.0-impl.so /vendor/lib64/motorola.hardware.camera.imgtuner*.so"

echo "[5/7] Configuring auxiliary multi-camera properties..."
adb shell "setprop persist.vendor.camera.expose.aux 1"
adb shell "setprop persist.vendor.camera.physical.num 3"
adb shell "setprop persist.vendor.camera.privapp.list com.motorola.camera3"
adb shell "setprop vendor.camera.aux.packagelist com.motorola.camera3,com.motorola.imagertuning_u,com.motorola.motcameradesktop"

# Append to system_ext build.prop if missing
if ! adb shell grep -q "persist.vendor.camera.expose.aux" /system_ext/etc/build.prop 2>/dev/null; then
  adb shell "echo '# Moto Camera Properties' >> /system_ext/etc/build.prop"
  adb shell "echo 'persist.vendor.camera.expose.aux=1' >> /system_ext/etc/build.prop"
  adb shell "echo 'persist.vendor.camera.physical.num=3' >> /system_ext/etc/build.prop"
fi

echo "[6/7] Restarting Android framework to register shared libraries..."
adb shell stop
sleep 2
adb shell start
adb wait-for-device
while [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" != "1" ]; do sleep 2; done

echo "[7/7] Registering packages with PackageManager and granting permissions..."
adb shell pm install -r -d /product/priv-app/MotCamera4/MotCamera4.apk
adb shell pm install -r -d /product/app/MotCamera3AI/MotCamera3AI.apk
adb shell pm install -r -d /system_ext/priv-app/ImagerTuning-U/ImagerTuning-U.apk
adb shell pm install -r -d /system_ext/priv-app/MotCameraDesktop/MotCameraDesktop.apk

adb shell pm grant com.motorola.camera3 android.permission.CAMERA
adb shell pm grant com.motorola.camera3 android.permission.RECORD_AUDIO
adb shell pm grant com.motorola.camera3 android.permission.ACCESS_FINE_LOCATION
adb shell pm grant com.motorola.camera3 android.permission.ACCESS_COARSE_LOCATION
adb shell pm grant com.motorola.camera3 android.permission.READ_MEDIA_IMAGES
adb shell pm grant com.motorola.camera3 android.permission.READ_MEDIA_VIDEO
adb shell pm grant com.motorola.camera3 android.permission.POST_NOTIFICATIONS

echo "=================================================="
echo "  Installation Successful!                       "
echo "  All camera lenses and features are ready.      "
echo "=================================================="

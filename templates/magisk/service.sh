#!/system/bin/sh
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done

# Ensure permissions on imgtuner binary
chmod 0755 /vendor/bin/hw/motorola.hardware.camera.imgtuner@2.0-service 2>/dev/null

# If imgtuner service is not running via init, start it as daemon
if ! pgrep -f "motorola.hardware.camera.imgtuner" > /dev/null 2>&1; then
  /vendor/bin/hw/motorola.hardware.camera.imgtuner@2.0-service &
fi

ui_print "- Installing Motorola Camera 4 for Moto G Stylus 5G 2023 (genevn)"
ui_print "- Setting file permissions and contexts..."
set_perm_recursive "$MODPATH/system/framework" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/etc/permissions" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/product/priv-app" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/product/app" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/product/etc" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/system_ext/priv-app" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/system_ext/framework" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/system_ext/etc" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/system_ext/lib64" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/vendor/lib64" 0 2000 0755 0644
set_perm_recursive "$MODPATH/system/vendor/etc" 0 2000 0755 0644
set_perm "$MODPATH/system/vendor/bin/hw/motorola.hardware.camera.imgtuner@2.0-service" 0 2000 0755
ui_print "- Multi-camera AUX allowlists and sensor properties configured."
ui_print "- Motorola Camera 4 installation complete!"

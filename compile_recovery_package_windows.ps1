# ==============================================================================
# Motorola Camera 4 Recovery Package Compiler (Windows PowerShell)
# Device: Motorola Moto G Stylus 5G 2023 (codename: genevn / genevn_g)
# Compatible ROMs: LineageOS 23.2, 24.0 (Android 17) & genevn custom ROMs
# Tested Firmware: U1TGNS34.42-86-2-25 (Android 14)
#
# 100% Vibe Coded with Google DeepMind Gemini 3.8 Flash (Thinking / High)
#
# Generates:
#   MotoCamera4_Genevn_Recovery_Installer.zip (Lineage Recovery / TWRP sideload)
#   with LineageOS addon.d OTA backup survival script
#
# Usage:
#   Interactive:  .\compile_recovery_package_windows.ps1
#   CLI:          .\compile_recovery_package_windows.ps1 -FirmwarePath "C:\path\to\stock_firmware" [-OutputDir "C:\output"]
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$FirmwarePath,

    [Parameter(Position=1)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalTemplatesDir = Join-Path $ScriptDir "templates\recovery"
$GitHubRawBase = "https://raw.githubusercontent.com/vrwindsor1/motocamera-genevn/main"

if (-not $OutputDir) {
    $OutputDir = Join-Path $ScriptDir "output"
}

# --- Colorized Logging ---
function Write-Header {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   Motorola Camera 4 Recovery Package Compiler for Moto G Stylus 5G 2023        " -ForegroundColor Cyan
    Write-Host "                     Device: genevn / genevn_g (LineageOS)                      " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   ⚡ 100% Vibe Coded with Google DeepMind Gemini 3.8 Flash (Thinking / High)  " -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Log-Info([string]$msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Log-Ok([string]$msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Log-Warn([string]$msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Log-Err([string]$msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# Helper: Copy single file safely
function Copy-BlobFile([string]$Source, [string]$DestinationDir) {
    if (Test-Path $Source) {
        if (-not (Test-Path $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }
        Copy-Item -Path $Source -Destination $DestinationDir -Force
    }
}

# Helper: Copy files matching wildcard safely
function Copy-BlobPattern([string]$SourcePattern, [string]$DestinationDir) {
    $items = Get-ChildItem -Path $SourcePattern -ErrorAction SilentlyContinue
    if ($items) {
        if (-not (Test-Path $DestinationDir)) {
            New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        }
        foreach ($item in $items) {
            Copy-Item -Path $item.FullName -Destination $DestinationDir -Force
        }
    }
}

# Ensure open-source packaging templates are available
function Ensure-Templates([string]$WorkDir) {
    if ((Test-Path $LocalTemplatesDir) -and (Test-Path (Join-Path $LocalTemplatesDir "META-INF\com\google\android\update-binary"))) {
        Log-Ok "Using local recovery templates."
        return $LocalTemplatesDir
    }

    Log-Info "Local templates not found. Fetching open-source templates from GitHub..."
    $downloadDir = Join-Path $WorkDir "templates\recovery"
    New-Item -ItemType Directory -Path (Join-Path $downloadDir "META-INF\com\google\android") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $downloadDir "addon.d") -Force | Out-Null

    $files = @(
        "templates/recovery/build.prop",
        "templates/recovery/toybox",
        "templates/recovery/addon.d/addond_head",
        "templates/recovery/addon.d/addond_tail",
        "templates/recovery/META-INF/com/google/android/update-binary",
        "templates/recovery/META-INF/com/google/android/updater-script"
    )

    foreach ($file in $files) {
        $relDest = $file.Replace("templates/recovery/", "").Replace('/', '\')
        $destPath = Join-Path $downloadDir $relDest
        $parentDir = Split-Path -Parent $destPath
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        
        $url = "$GitHubRawBase/$file"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
        } catch {
            Log-Err "Failed to download required template file: $url"
            throw $_
        }
    }

    Log-Ok "Recovery scaffolding templates downloaded successfully."
    return $downloadDir
}

# --- Main Flow ---
Write-Header

# 1. Prompt for Firmware Directory if not supplied
if (-not $FirmwarePath) {
    Write-Host "Please specify the path to your Motorola stock firmware:" -ForegroundColor White
    Write-Host "  (Can be a pre-extracted directory or your Motorola RSA / Software Fix folder)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Tip: Stock firmware can be downloaded via Motorola Software Fix (RSA) or from:" -ForegroundColor Cyan
    Write-Host "     https://mirrors.lolinet.com/firmware/lenomola/2023/genevn/official/RETUS/" -ForegroundColor Yellow
    Write-Host "     Note: Verified and tested on build U1TGNS34.42-86-2-25 (Android 14)." -ForegroundColor Green
    Write-Host ""
    $FirmwarePath = Read-Host "> Path"
}

$FirmwarePath = $FirmwarePath.Trim().Trim('"').Trim("'")

if (-not (Test-Path $FirmwarePath)) {
    Log-Err "Specified path does not exist: $FirmwarePath"
    exit 1
}

$ResolvedFirmware = (Resolve-Path $FirmwarePath).Path
Log-Ok "Firmware source: $ResolvedFirmware"

# 2. Locate Partitions Root
$FirmwareRoot = $null
if ((Test-Path (Join-Path $ResolvedFirmware "product")) -and (Test-Path (Join-Path $ResolvedFirmware "system_ext"))) {
    $FirmwareRoot = $ResolvedFirmware
} else {
    # Check one subdirectory deep (e.g. extracted zip or RSA folder structure)
    $subDirs = Get-ChildItem -Path $ResolvedFirmware -Directory
    foreach ($sub in $subDirs) {
        if ((Test-Path (Join-Path $sub.FullName "product")) -and (Test-Path (Join-Path $sub.FullName "system_ext"))) {
            $FirmwareRoot = $sub.FullName
            break
        }
    }
}

if (-not $FirmwareRoot) {
    # Check if raw sparsechunks are present
    $sparseChunks = Get-ChildItem -Path $ResolvedFirmware -Filter "super.img_sparsechunk.*" -Recurse -ErrorAction SilentlyContinue
    if ($sparseChunks) {
        Log-Warn "Detected raw super.img_sparsechunks, but dynamic partition extraction is required."
        Write-Host ""
        Write-Host "On Windows, dynamic Android super partitions (sparsechunks) can be extracted via:" -ForegroundColor Yellow
        Write-Host "  1. Windows Subsystem for Linux (WSL):" -ForegroundColor White
        Write-Host "       wsl ./compile_recovery_package_linux.sh `"$ResolvedFirmware`"" -ForegroundColor Gray
        Write-Host "  2. 7-Zip (v23+ with EROFS plugin) or lpunpack/simg2img for Windows" -ForegroundColor White
        Write-Host ""
        Log-Err "Please point this script to the extracted directory containing 'product' and 'system_ext'."
        exit 1
    } else {
        Log-Err "Could not find 'product' and 'system_ext' directories in: $ResolvedFirmware"
        Log-Err "Please ensure the firmware partitions are extracted."
        exit 1
    }
}

Log-Ok "Partitions located at: $FirmwareRoot"

# 3. Create Temporary Staging Directory
$TempWorkDir = Join-Path $env:TEMP ("motocamera_build_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
$StagingDir = Join-Path $TempWorkDir "staging\system"
$RecBuildDir = Join-Path $TempWorkDir "recovery_build"

New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
New-Item -ItemType Directory -Path $RecBuildDir -Force | Out-Null

try {
    # Ensure templates
    $TemplatesDir = Ensure-Templates $TempWorkDir

    # Normalize system path (/system/system or /system)
    $sysPath = Join-Path $FirmwareRoot "system"
    if (Test-Path (Join-Path $FirmwareRoot "system\system")) {
        $sysPath = Join-Path $FirmwareRoot "system\system"
    }

    Log-Info "Harvesting Motorola Camera 4 and multi-camera HAL components..."

    # --- 1. Product Partition Files ---
    Log-Info "  - Harvesting Product camera applications & permissions..."
    Copy-BlobFile (Join-Path $FirmwareRoot "product\priv-app\MotCamera4\MotCamera4.apk") (Join-Path $StagingDir "product\priv-app\MotCamera4")
    Copy-BlobFile (Join-Path $FirmwareRoot "product\app\MotCamera3AI\MotCamera3AI.apk") (Join-Path $StagingDir "product\app\MotCamera3AI")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\permissions\*com.motorola.camera3*") (Join-Path $StagingDir "product\etc\permissions")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\sysconfig\*com.motorola.camera3*") (Join-Path $StagingDir "product\etc\sysconfig")
    Copy-BlobFile (Join-Path $FirmwareRoot "product\etc\init\init.motcamera3.lens.rc") (Join-Path $StagingDir "product\etc\init")
    Copy-BlobPattern (Join-Path $FirmwareRoot "product\etc\MotoDesktopAppConfig\*") (Join-Path $StagingDir "product\etc\MotoDesktopAppConfig")

    # --- 2. System_ext Partition Files ---
    Log-Info "  - Harvesting System_ext ImagerTuning, Desktop, frameworks, and libs..."
    Copy-BlobFile (Join-Path $FirmwareRoot "system_ext\priv-app\ImagerTuning-U\ImagerTuning-U.apk") (Join-Path $StagingDir "system_ext\priv-app\ImagerTuning-U")
    Copy-BlobFile (Join-Path $FirmwareRoot "system_ext\priv-app\MotCameraDesktop\MotCameraDesktop.apk") (Join-Path $StagingDir "system_ext\priv-app\MotCameraDesktop")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\framework\*com.motorola.*") (Join-Path $StagingDir "system_ext\framework")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\permissions\*motorola*") (Join-Path $StagingDir "system_ext\etc\permissions")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\permissions\*imager*") (Join-Path $StagingDir "system_ext\etc\permissions")
    Copy-BlobFile (Join-Path $FirmwareRoot "system_ext\etc\public.libraries-motocameradesktop.txt") (Join-Path $StagingDir "system_ext\etc")
    Copy-BlobFile (Join-Path $FirmwareRoot "system_ext\etc\public.libraries-motoimagetuner.txt") (Join-Path $StagingDir "system_ext\etc")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\enable-disable-packages\*") (Join-Path $StagingDir "system_ext\etc\enable-disable-packages")
    Copy-BlobPattern (Join-Path $FirmwareRoot "system_ext\etc\sysconfig\*") (Join-Path $StagingDir "system_ext\etc\sysconfig")

    $nativeLibs = @(
        "libarcsoft_calibverify_TriCamera.so", "libcameraOIS_jni.so", "libcameraraw_jni.so",
        "libimgTuner_jni.motoimagetuner.so", "libjni_helper.motocameradesktop.so", "libopencv_java4.so",
        "motorola.hardware.camera.desktop@1.0.so", "motorola.hardware.camera.desktop@2.0.so",
        "motorola.hardware.camera.imgtuner@2.0.so"
    )
    foreach ($lib in $nativeLibs) {
        Copy-BlobFile (Join-Path $FirmwareRoot "system_ext\lib64\$lib") (Join-Path $StagingDir "system_ext\lib64")
    }

    # --- 3. System Framework and Libraries ---
    Log-Info "  - Harvesting System framework signature libraries..."
    Copy-BlobFile (Join-Path $sysPath "framework\com.motorola.motosignature.jar") (Join-Path $StagingDir "system\framework")
    Copy-BlobFile (Join-Path $sysPath "framework\moto-core_services.jar") (Join-Path $StagingDir "system\framework")
    Copy-BlobFile (Join-Path $sysPath "framework\moto-settings.jar") (Join-Path $StagingDir "system\framework")
    Copy-BlobFile (Join-Path $sysPath "etc\permissions\com.motorola.motosignature.xml") (Join-Path $StagingDir "system\etc\permissions")
    Copy-BlobFile (Join-Path $sysPath "etc\permissions\moto-core_services.xml") (Join-Path $StagingDir "system\etc\permissions")
    Copy-BlobFile (Join-Path $sysPath "etc\permissions\moto-settings.xml") (Join-Path $StagingDir "system\etc\permissions")
    Copy-BlobFile (Join-Path $sysPath "lib64\motorola.hardware.camera.imgtuner@1.0.so") (Join-Path $StagingDir "system\lib64")

    # --- 4. Vendor Camera HAL & VINTF Manifest ---
    Log-Info "  - Harvesting Vendor ImageTuner HAL and VINTF manifests..."
    Copy-BlobFile (Join-Path $FirmwareRoot "vendor\bin\hw\motorola.hardware.camera.imgtuner@2.0-service") (Join-Path $StagingDir "system\vendor\bin\hw")
    Copy-BlobFile (Join-Path $FirmwareRoot "vendor\etc\init\motorola.hardware.camera.imgtuner@2.0-service.rc") (Join-Path $StagingDir "system\vendor\etc\init")
    Copy-BlobFile (Join-Path $FirmwareRoot "vendor\lib64\hw\motorola.hardware.camera.imgtuner@2.0-impl.so") (Join-Path $StagingDir "system\vendor\lib64\hw")
    Copy-BlobFile (Join-Path $FirmwareRoot "vendor\lib64\motorola.hardware.camera.imgtuner@1.0.so") (Join-Path $StagingDir "system\vendor\lib64")
    Copy-BlobFile (Join-Path $FirmwareRoot "vendor\lib64\motorola.hardware.camera.imgtuner@2.0.so") (Join-Path $StagingDir "system\vendor\lib64")

    $vintfDest = Join-Path $StagingDir "system\vendor\etc\vintf\manifest\manifest_imgtuner.xml"
    $vintfSrc = Join-Path $FirmwareRoot "vendor\etc\vintf\manifest\manifest_imgtuner.xml"
    if (Test-Path $vintfSrc) {
        Copy-BlobFile $vintfSrc (Split-Path -Parent $vintfDest)
    } else {
        $vintfParent = Split-Path -Parent $vintfDest
        if (-not (Test-Path $vintfParent)) { New-Item -ItemType Directory -Path $vintfParent -Force | Out-Null }
        $manifestXml = @"
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
"@
        Set-Content -Path $vintfDest -Value $manifestXml -Encoding ASCII
    }

    # Verify MotCamera4.apk was harvested
    $coreApk = Join-Path $StagingDir "product\priv-app\MotCamera4\MotCamera4.apk"
    if (-not (Test-Path $coreApk)) {
        Log-Err "Failed to harvest MotCamera4.apk! Please verify the source firmware root."
        exit 1
    }
    Log-Ok "Proprietary camera components harvested successfully."

    # --- 5. Assemble Recovery Package ---
    Log-Info "Assembling Recovery Flashable Installer..."

    # Copy templates to recovery build root
    Copy-Item -Path (Join-Path $TemplatesDir "*") -Destination $RecBuildDir -Recurse -Force

    # Ensure addon.d scripts are inside system\addon.d
    $recSystemAddond = Join-Path $RecBuildDir "system\addon.d"
    New-Item -ItemType Directory -Path $recSystemAddond -Force | Out-Null
    Copy-Item -Path (Join-Path $TemplatesDir "addon.d\*") -Destination $recSystemAddond -Force
    if (Test-Path (Join-Path $RecBuildDir "addon.d")) {
        Remove-Item -Path (Join-Path $RecBuildDir "addon.d") -Recurse -Force
    }

    # Copy staged system tree into recBuild\system
    Copy-Item -Path (Join-Path $StagingDir "*") -Destination (Join-Path $RecBuildDir "system") -Recurse -Force

    # Ensure output directory exists
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    $AbsOutputDir = (Resolve-Path $OutputDir).Path
    $ZipOutputPath = Join-Path $AbsOutputDir "MotoCamera4_Genevn_Recovery_Installer.zip"

    if (Test-Path $ZipOutputPath) {
        Remove-Item -Path $ZipOutputPath -Force
    }

    # Package into Zip with standard POSIX forward slashes and Unix permission bits
    Log-Info "Packaging zip archive: $ZipOutputPath ..."
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Unix permissions (high 16 bits of ExternalAttributes):
    # 0755 (-rwxr-xr-x) = 0x81ED0000 -> signed int32: -2115174400
    # 0644 (-rw-r--r--) = 0x81A40000 -> signed int32: -2119958528
    $posix755 = -2115174400
    $posix644 = -2119958528

    $zipStream = [System.IO.File]::Open($ZipOutputPath, [System.IO.FileMode]::Create)
    $zipArchive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

    try {
        $buildFiles = Get-ChildItem -Path $RecBuildDir -Recurse -File
        $baseLen = $RecBuildDir.TrimEnd('\').Length + 1

        foreach ($file in $buildFiles) {
            $relPath = $file.FullName.Substring($baseLen).Replace('\', '/')
            $entry = $zipArchive.CreateEntry($relPath, [System.IO.Compression.CompressionLevel]::Optimal)

            # Copy file content
            $fs = [System.IO.File]::OpenRead($file.FullName)
            $es = $entry.Open()
            $fs.CopyTo($es)
            $es.Dispose()
            $fs.Dispose()

            # Assign POSIX execute permissions where required
            if ($relPath -eq "META-INF/com/google/android/update-binary" -or `
                $relPath -eq "toybox" -or `
                $relPath -like "system/vendor/bin/hw/*") {
                $entry.ExternalAttributes = $posix755
            } else {
                $entry.ExternalAttributes = $posix644
            }
        }
    } finally {
        $zipArchive.Dispose()
        $zipStream.Dispose()
    }

    $zipSizeMb = [math]::Round((Get-Item $ZipOutputPath).Length / 1MB, 2)
    Log-Ok "Recovery Installer created: $ZipOutputPath ($zipSizeMb MB)"

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "                Recovery Package Compiled Successfully!                         " -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installer Package:" -ForegroundColor White
    Write-Host "  --> $ZipOutputPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "How to install via Lineage Recovery:" -ForegroundColor White
    Write-Host "  1. Reboot your phone into Recovery mode."
    Write-Host "  2. Select 'Apply Update' -> 'Apply from ADB'."
    Write-Host "  3. Run the following command from your PC terminal / Command Prompt:"
    Write-Host "       adb sideload `"$ZipOutputPath`"" -ForegroundColor Yellow
    Write-Host "  4. If prompted with 'Signature verification failed. Install anyway?', select 'Yes'."
    Write-Host "  5. Reboot to system. The camera is ready to use!"
    Write-Host ""
    Write-Host "[OTA Survival] The included addon.d script will automatically" -ForegroundColor Cyan
    Write-Host "preserve the camera suite across nightly LineageOS updates."
    Write-Host ""

} finally {
    if (Test-Path $TempWorkDir) {
        Remove-Item -Path $TempWorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

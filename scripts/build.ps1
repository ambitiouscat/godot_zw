<#
.SYNOPSIS
    GDAI Build System — Godot 4.7 OpenHarmony Compilation & Packaging Script

.DESCRIPTION
    Compiles libgodot.so for OpenHarmony (aarch64) using SCons and the DevEco Studio LLVM toolchain.
    Copies the built library to the template project and optionally triggers DevEco CLI to package HAP.

.PARAMETER Profile
    Build profile: release-debug (default), debug, release, test, clean

.PARAMETER Package
    If specified, calls devecocli to build and sign the HAP package after engine compilation.

.PARAMETER Install
    If specified, installs the generated HAP onto the connected HarmonyOS device.

.PARAMETER Jobs
    Number of parallel compilation jobs (default: CPU logical cores).

.PARAMETER SdkPath
    Custom path to OpenHarmony SDK (default: auto-detected).

.EXAMPLE
    .\scripts\build.ps1
    .\scripts\build.ps1 -Profile debug
    .\scripts\build.ps1 -Profile release-debug -Package
    .\scripts\build.ps1 -Profile release-debug -Package -Install
    .\scripts\build.ps1 -Profile clean
#>

[CmdletBinding()]
param (
    [ValidateSet("release-debug", "debug", "release", "test", "clean")]
    [string]$Profile = "release-debug",

    [switch]$Package,
    [switch]$Install,

    [int]$Jobs = [System.Environment]::ProcessorCount,
    [string]$SdkPath = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path "$ScriptDir\..").Path
Set-Location $ProjectRoot

# ============================================================
#  1. Clean Mode
# ============================================================
if ($Profile -eq "clean") {
    Write-Host "`n=========================================" -ForegroundColor Cyan
    Write-Host "  Cleaning Build Artifacts" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  Removing SCons cache and build outputs..."

    try { python -m SCons --clean platform=openharmony target=editor 2>$null } catch {}
    try { python -m SCons --clean platform=windows target=editor tests=yes 2>$null } catch {}

    $sconsign = "$ProjectRoot\.sconsign.dblite"
    if (Test-Path $sconsign) { Remove-Item -Force $sconsign }
    $binObj = "$ProjectRoot\bin\obj"
    if (Test-Path $binObj) { Remove-Item -Recurse -Force $binObj }

    Write-Host "`n  ✅ Clean complete.`n" -ForegroundColor Green
    exit 0
}

# ============================================================
#  2. Windows Desktop Test Mode
# ============================================================
if ($Profile -eq "test") {
    Write-Host "`n=========================================" -ForegroundColor Cyan
    Write-Host "  Windows Editor Build + Automated Tests" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan

    $sconsArgs = @(
        "platform=windows",
        "target=editor",
        "tests=yes",
        "accesskit=no",
        "d3d12=no",
        "angle=no",
        "-j$Jobs"
    )

    Write-Host "  scons $($sconsArgs -join ' ')`n"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    python -m SCons @sconsArgs
    $sw.Stop()

    $exe = Get-ChildItem "$ProjectRoot\bin\godot.windows.editor*.exe" | Select-Object -First 1
    if (-not $exe) {
        Write-Error "Could not find built .exe file in bin\"
        exit 1
    }

    Write-Host "`n  Built: $($exe.Name) ($([math]::Round($exe.Length / 1MB, 1)) MB)" -ForegroundColor Green
    Write-Host "  Build time: $($sw.Elapsed.TotalSeconds)s`n"

    Write-Host "[2/2] Running automated doctest suite..." -ForegroundColor Cyan
    & $exe.FullName --test
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n=========================================" -ForegroundColor Green
        Write-Host "  ✅ ALL TESTS PASSED" -ForegroundColor Green
        Write-Host "=========================================`n" -ForegroundColor Green
    } else {
        Write-Host "`n=========================================" -ForegroundColor Red
        Write-Host "  ❌ TESTS FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "=========================================`n" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    exit 0
}

# ============================================================
#  3. Locate HarmonyOS SDK
# ============================================================
if (-not $SdkPath) {
    $candidates = @(
        $env:OPENHARMONY_SDK_PATH,
        $env:OHOS_SDK_HOME,
        "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony",
        "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony",
        "$env:LOCALAPPDATA\Huawei\Sdk\default\openharmony"
    )

    foreach ($c in $candidates) {
        if ($c -and (Test-Path "$c\native")) {
            $SdkPath = (Resolve-Path $c).Path
            break
        }
    }
}

if (-not $SdkPath -or -not (Test-Path "$SdkPath\native")) {
    Write-Error "Cannot find OpenHarmony SDK. Please provide -SdkPath or set OPENHARMONY_SDK_PATH."
    exit 1
}

# Normalize path with forward slashes for SCons / Clang
$SdkPathNorm = $SdkPath -replace '\\', '/'
$env:OPENHARMONY_SDK_PATH = $SdkPathNorm

# Inject LLVM toolchain into PATH
$llvmBin = "$SdkPath\native\llvm\bin"
if (Test-Path $llvmBin) {
    $env:PATH = "$llvmBin;$env:PATH"
}

# ============================================================
#  4. SCons Profile Mapping
# ============================================================
$target = "editor"
$debugSymbols = "yes"
$optimize = "speed"
$devBuild = "no"

switch ($Profile) {
    "debug" {
        $target = "editor"
        $debugSymbols = "yes"
        $optimize = "none"
        $devBuild = "no"
    }
    "release-debug" {
        $target = "editor"
        $debugSymbols = "yes"
        $optimize = "speed"
        $devBuild = "no"
    }
    "release" {
        $target = "template_release"
        $debugSymbols = "no"
        $optimize = "speed"
        $devBuild = "no"
    }
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "  GDAI OpenHarmony Build Configuration" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Project:       godot_zw (GDAI-4.7)"
Write-Host "  Profile:       $Profile"
Write-Host "  Target:        $target"
Write-Host "  Debug symbols: $debugSymbols"
Write-Host "  Optimization:  $optimize"
Write-Host "  Parallel jobs: $Jobs"
Write-Host "  SDK:           $SdkPathNorm"
Write-Host "=========================================`n" -ForegroundColor Cyan

# ============================================================
#  5. Step 1: SCons Compilation
# ============================================================
$sconsArgs = @(
    "platform=openharmony",
    "target=$target",
    "debug_symbols=$debugSymbols",
    "optimize=$optimize",
    "dev_build=$devBuild",
    "vulkan=yes",
    "ohos_opengl3=yes",
    "-j$Jobs",
    "OPENHARMONY_SDK_PATH=$SdkPathNorm",
    "module_zip_enabled=yes"
)

Write-Host "[1/3] Compiling engine libgodot.so..." -ForegroundColor Cyan
Write-Host "  scons $($sconsArgs -join ' ')`n"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
python -m SCons @sconsArgs
$sw.Stop()

if ($LASTEXITCODE -ne 0) {
    Write-Error "SCons compilation failed with code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`n  Engine compilation finished in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s" -ForegroundColor Green

# Locate output .so
$soPatterns = @(
    "$ProjectRoot\bin\openharmony_editor_arm64-v8a.so",
    "$ProjectRoot\bin\openharmony_template_debug_arm64-v8a.so",
    "$ProjectRoot\bin\openharmony_release_arm64-v8a.so",
    "$ProjectRoot\bin\openharmony_template_release_arm64-v8a.so",
    "$ProjectRoot\bin\libgodot*.so"
)

$soFile = $null
foreach ($p in $soPatterns) {
    $found = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $soFile = $found
        break
    }
}

if (-not $soFile) {
    Write-Error "Could not find built .so file in bin\"
    exit 1
}

$soSizeMB = [math]::Round($soFile.Length / 1MB, 2)
Write-Host "  Output SO: $($soFile.Name) ($soSizeMB MB)" -ForegroundColor Green

# ============================================================
#  6. Step 2: Copy .so to Template
# ============================================================
Write-Host "`n[2/3] Copying libgodot.so to DevEco template..." -ForegroundColor Cyan
$templateLibs = "$ProjectRoot\platform\openharmony\template\entry\libs\arm64-v8a"
if (-not (Test-Path $templateLibs)) {
    New-Item -ItemType Directory -Force -Path $templateLibs | Out-Null
}

$destSo = "$templateLibs\libgodot.so"
Copy-Item -Force $soFile.FullName $destSo
Write-Host "  Copied → $destSo ($soSizeMB MB)" -ForegroundColor Green

# ============================================================
#  7. Step 3: Copy Bridge Headers
# ============================================================
Write-Host "`n[3/3] Synchronizing NAPI bridge headers to template..." -ForegroundColor Cyan
$templateInclude = "$ProjectRoot\platform\openharmony\template\entry\src\main\cpp\include"
if (-not (Test-Path $templateInclude)) {
    New-Item -ItemType Directory -Force -Path $templateInclude | Out-Null
}

Copy-Item -Force "$ProjectRoot\platform\openharmony\bridge_openharmony.h" "$templateInclude\napi_bridge.h"
Copy-Item -Force "$ProjectRoot\platform\openharmony\platform_config.h" "$templateInclude\platform_config.h"
Write-Host "  Bridge headers synchronized → $templateInclude\" -ForegroundColor Green

# ============================================================
#  8. Optional: Package HAP with DevEco CLI
# ============================================================
if ($Package -or $Install) {
    Write-Host "`n=========================================" -ForegroundColor Cyan
    Write-Host "  Packaging HAP with DevEco CLI" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan

    $templateDir = "$ProjectRoot\platform\openharmony\template"
    Push-Location $templateDir

    $buildMode = if ($Profile -eq "release") { "release" } else { "debug" }
    Write-Host "  Running: devecocli.cmd build --product default --build-mode $buildMode" -ForegroundColor Yellow

    try {
        & devecocli.cmd build --product default --build-mode $buildMode
        if ($LASTEXITCODE -ne 0) {
            Write-Error "devecocli build failed with code $LASTEXITCODE"
            exit $LASTEXITCODE
        }
        Write-Host "  ✅ HAP package built successfully!" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }

    # Find generated HAP
    $hapFiles = Get-ChildItem -Path "$templateDir\entry\build\default\outputs" -Recurse -Filter "*.hap" -ErrorAction SilentlyContinue
    if ($hapFiles) {
        foreach ($hap in $hapFiles) {
            Write-Host "  HAP: $($hap.FullName) ($([math]::Round($hap.Length / 1MB, 2)) MB)" -ForegroundColor Green
        }

        # Optional: Deploy to device
        if ($Install) {
            Write-Host "`n=========================================" -ForegroundColor Cyan
            Write-Host "  Installing HAP to Connected Device" -ForegroundColor Cyan
            Write-Host "=========================================" -ForegroundColor Cyan

            $targetHap = $hapFiles | Select-Object -First 1
            Write-Host "  Running: hdc install -r `"$($targetHap.FullName)`"" -ForegroundColor Yellow
            hdc install -r "$($targetHap.FullName)"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ Successfully installed to device!" -ForegroundColor Green
            } else {
                Write-Warning "hdc install returned code $LASTEXITCODE"
            }
        }
    }
}

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "  ✅ GDAI Build Completed Successfully!" -ForegroundColor Green
Write-Host "=========================================`n" -ForegroundColor Green

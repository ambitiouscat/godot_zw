@echo off
chcp 65001 >nul 2>&1
title Godot Engine 4.7.0 Build

set "GODOT_BIN=bin\godot.windows.editor.x86_64.mono.exe"
set "NUPKGS_DIR=bin\GodotSharp\Tools\nupkgs"

:menu
echo.
echo ============================================
echo    Godot Engine 4.7.0 Build (Windows)
echo ============================================
echo.
echo   Build mode comparison:
echo   +-----------------+----------+--------+---------+-----------------------------+
echo   ^| Mode            ^| Optimize ^| PDB    ^| Speed   ^| Debug capability            ^|
echo   +-----------------+----------+--------+---------+-----------------------------+
echo   ^| 1. Debug        ^| None     ^| Yes    ^| Slow    ^| Full: stack, vars, watches  ^|
echo   ^| 2. RelWithDeb   ^| Speed    ^| Yes    ^| Fast    ^| Stack + line numbers only   ^|
echo   ^| 3. Release      ^| Speed    ^| No     ^| Fast    ^| None                        ^|
echo   ^| 4. Template     ^| Speed    ^| No     ^| Fast    ^| Export template (no editor) ^|
echo   +-----------------+----------+--------+---------+-----------------------------+
echo.
echo   Tip: Use RelWithDebInfo for production debugging (crash dumps + WinDbg).
echo.
echo   1. Debug          (debug_symbols=true,  optimize=debug)
echo   2. RelWithDebInfo (debug_symbols=true,  optimize=speed)
echo   3. Release        (optimize=speed,      no symbols)
echo   4. Template Release (target=template_release, no editor)
echo   5. Full Debug      (engine + C# glue + assemblies)
echo   6. Full RelWithDeb (engine + C# glue + assemblies)
echo   7. Full Release    (engine + C# glue + assemblies)
echo   8. C# Glue Only   (regenerate C# bindings + assemblies)
echo   9. Install Deps    (accesskit, d3d12 SDK)
echo   10. Clean
echo   11. Exit
echo.
set /p choice=Please select [1-11]:

if "%choice%"=="1" goto debug
if "%choice%"=="2" goto relwithdebinfo
if "%choice%"=="3" goto release
if "%choice%"=="4" goto template
if "%choice%"=="5" goto full_debug
if "%choice%"=="6" goto full_relwithdeb
if "%choice%"=="7" goto full_release
if "%choice%"=="8" goto csharp_glue
if "%choice%"=="9" goto install_deps
if "%choice%"=="10" goto clean
if "%choice%"=="11" goto end
echo Invalid choice.
goto menu

:: ============================================
::  Engine only
:: ============================================

:debug
echo.
echo [DEBUG] Starting build...
echo.
scons p=windows target=editor debug_symbols=true optimize=debug module_mono_enabled=yes
echo.
echo [DEBUG] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:relwithdebinfo
echo.
echo [RELWITHDEBINFO] Starting build...
echo.
scons p=windows target=editor debug_symbols=true optimize=speed module_mono_enabled=yes
echo.
echo [RELWITHDEBINFO] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:release
echo.
echo [RELEASE] Starting build...
echo.
scons p=windows target=editor optimize=speed module_mono_enabled=yes
echo.
echo [RELEASE] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:: ============================================
::  Export template
:: ============================================

:template
echo.
echo [TEMPLATE_RELEASE] Starting build...
echo.
scons p=windows target=template_release optimize=speed
echo.
echo [TEMPLATE_RELEASE] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:: ============================================
::  Full build: engine + C#
:: ============================================

:full_debug
echo.
echo [FULL DEBUG] Step 1/4: Building engine...
echo.
scons p=windows target=editor debug_symbols=true optimize=debug module_mono_enabled=yes
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL DEBUG] Step 2/4: Generating C# glue...
echo.
if not exist "%GODOT_BIN%" (
    echo Error: %GODOT_BIN% not found!
    goto buildfail
)
"%GODOT_BIN%" --generate-mono-glue ./modules/mono/glue
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL DEBUG] Step 3/4: Building C# assemblies...
echo.
python ./modules/mono/build_scripts/build_assemblies.py --godot-output-dir ./bin --push-nupkgs-local ./bin/GodotSharp/Tools/nupkgs
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL DEBUG] Step 4/4: Registering NuGet source...
echo.
dotnet nuget add source "%CD%\%NUPKGS_DIR%" -n GodotLocal --configfile "%APPDATA%\NuGet\NuGet.Config" 2>nul || echo NuGet source may already exist, skipping.
echo.
echo [FULL DEBUG] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:full_relwithdeb
echo.
echo [FULL RELWITHDEB] Step 1/4: Building engine...
echo.
scons p=windows target=editor debug_symbols=true optimize=speed module_mono_enabled=yes
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELWITHDEB] Step 2/4: Generating C# glue...
echo.
if not exist "%GODOT_BIN%" (
    echo Error: %GODOT_BIN% not found!
    goto buildfail
)
"%GODOT_BIN%" --generate-mono-glue ./modules/mono/glue
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELWITHDEB] Step 3/4: Building C# assemblies...
echo.
python ./modules/mono/build_scripts/build_assemblies.py --godot-output-dir ./bin --push-nupkgs-local ./bin/GodotSharp/Tools/nupkgs
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELWITHDEB] Step 4/4: Registering NuGet source...
echo.
dotnet nuget add source "%CD%\%NUPKGS_DIR%" -n GodotLocal --configfile "%APPDATA%\NuGet\NuGet.Config" 2>nul || echo NuGet source may already exist, skipping.
echo.
echo [FULL RELWITHDEB] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:full_release
echo.
echo [FULL RELEASE] Step 1/4: Building engine...
echo.
scons p=windows target=editor optimize=speed module_mono_enabled=yes
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELEASE] Step 2/4: Generating C# glue...
echo.
if not exist "%GODOT_BIN%" (
    echo Error: %GODOT_BIN% not found!
    goto buildfail
)
"%GODOT_BIN%" --generate-mono-glue ./modules/mono/glue
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELEASE] Step 3/4: Building C# assemblies...
echo.
python ./modules/mono/build_scripts/build_assemblies.py --godot-output-dir ./bin --push-nupkgs-local ./bin/GodotSharp/Tools/nupkgs
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELEASE] Step 4/4: Registering NuGet source...
echo.
dotnet nuget add source "%CD%\%NUPKGS_DIR%" -n GodotLocal --configfile "%APPDATA%\NuGet\NuGet.Config" 2>nul || echo NuGet source may already exist, skipping.
echo.
echo [FULL RELEASE] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:csharp_glue
echo.
echo [C# GLUE] Launching update-csharp-api.bat ...
echo.
call update-csharp-api.bat
goto menu

:: ============================================
::  Install optional dependencies
:: ============================================

:install_deps
echo.
echo [INSTALL] Installing accesskit dependencies...
echo.
python misc\scripts\install_accesskit.py
if %ERRORLEVEL% neq 0 (
    echo accesskit install FAILED.
    pause
    goto menu
)
echo.
echo [INSTALL] Installing d3d12 SDK...
echo.
python misc\scripts\install_d3d12_sdk_windows.py
if %ERRORLEVEL% neq 0 (
    echo d3d12 SDK install FAILED.
    pause
    goto menu
)
echo.
echo [INSTALL] All dependencies installed.
echo.
pause
goto menu

:: ============================================
::  Clean
:: ============================================

:clean
echo.
echo [CLEAN] Removing build artifacts...
echo.
if exist ".scons_cache" (
    echo Removing .scons_cache ...
    rmdir /s /q ".scons_cache"
)
if exist "bin" (
    echo Removing bin/ ...
    rmdir /s /q "bin"
)
echo.
echo [CLEAN] Done.
pause
goto menu

:: ============================================
::  Error & Exit
:: ============================================

:buildfail
echo.
echo Build FAILED with exit code: %ERRORLEVEL%
pause
goto menu

:end

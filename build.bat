@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

title Godot Engine 4.7 Build

:: ============================================================================
:: Python 3.9+ Check (Godot 4.7 requires Python >= 3.9)
:: ============================================================================

set PYTHON_CMD=

:: Try py launcher first (Windows Python Launcher)
py -3.9 --version >nul 2>&1
if !errorlevel! equ 0 (
    set PYTHON_CMD=py -3.9
    goto python_found
)
py -3.10 --version >nul 2>&1
if !errorlevel! equ 0 (
    set PYTHON_CMD=py -3.10
    goto python_found
)
py -3.11 --version >nul 2>&1
if !errorlevel! equ 0 (
    set PYTHON_CMD=py -3.11
    goto python_found
)
py -3.12 --version >nul 2>&1
if !errorlevel! equ 0 (
    set PYTHON_CMD=py -3.12
    goto python_found
)
py -3.13 --version >nul 2>&1
if !errorlevel! equ 0 (
    set PYTHON_CMD=py -3.13
    goto python_found
)

:: Try python/python3 commands
python --version >nul 2>&1
if !errorlevel! equ 0 (
    for /f "tokens=2" %%v in ('python --version 2^>^&1') do (
        for /f "tokens=1,2 delims=." %%a in ("%%v") do (
            if %%a geq 3 if %%b geq 9 (
                set PYTHON_CMD=python
                goto python_found
            )
        )
    )
)

python3 --version >nul 2>&1
if !errorlevel! equ 0 (
    for /f "tokens=2" %%v in ('python3 --version 2^>^&1') do (
        for /f "tokens=1,2 delims=." %%a in ("%%v") do (
            if %%a geq 3 if %%b geq 9 (
                set PYTHON_CMD=python3
                goto python_found
            )
        )
    )
)

echo.
echo [ERROR] Python 3.9+ not found.
echo   Godot 4.7 requires Python >= 3.9
echo.
echo   Please install Python from:
echo     https://www.python.org/downloads/
echo.
echo   Or via package managers:
echo     winget install Python.Python.3.11
echo     choco install python3
echo     scoop install python
echo.
pause
exit /b 1

:python_found

:: ============================================================================
:: SCons Check
:: ============================================================================

%PYTHON_CMD% -m SCons --version >nul 2>&1
if !errorlevel! neq 0 (
    echo.
    echo [ERROR] SCons not found.
    echo   Install via: %PYTHON_CMD% -m pip install scons
    echo.
    pause
    exit /b 1
)

set SCONS_CMD=%PYTHON_CMD% -m SCons

:: ============================================================================
:: Environment Detection
:: ============================================================================

:: Detect architecture
set ARCH_TAG=x86_64
if "%PROCESSOR_ARCHITECTURE%"=="ARM64" set ARCH_TAG=arm64
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" set ARCH_TAG=x86_64

:: Detect CPU cores
if defined BUILD_JOBS (
    set JOBS=!BUILD_JOBS!
) else if defined NUMBER_OF_PROCESSORS (
    set JOBS=%NUMBER_OF_PROCESSORS%
) else (
    set JOBS=4
)

:: Build output binary path (used by full builds)
set "GODOT_BIN=bin\godot.windows.editor.%ARCH_TAG%.mono.exe"
set "NUPKGS_DIR=bin\GodotSharp\Tools\nupkgs"

:: ============================================================================
:: Dependency Check Function
:: ============================================================================

:check_deps
echo.
echo   [CHECK] Verifying build dependencies...
echo.

:: Check Python
%PYTHON_CMD% --version
if !errorlevel! equ 0 (
    echo   [OK] Python 3.9+ found
) else (
    echo   [ERROR] Python not found
    set DEPS_OK=0
)

:: Check SCons
%SCONS_CMD% --version >nul 2>&1
if !errorlevel! equ 0 (
    for /f "tokens=1-3" %%a in ('%SCONS_CMD% --version 2^>^&1 ^| findstr /i "SCons"') do echo   [OK] SCons %%c
) else (
    echo   [ERROR] SCons not found
    set DEPS_OK=0
)

:: Check Visual Studio (cl.exe)
where cl.exe >nul 2>&1
if !errorlevel! equ 0 (
    echo   [OK] Visual Studio compiler ^(cl.exe^) found
) else (
    echo   [WARN] cl.exe not in PATH
    echo          Run from "x64 Native Tools Command Prompt for VS 2022"
    echo          Or use Visual Studio Developer Command Prompt
    set DEPS_OK=0
)

echo.
if defined DEPS_OK (
    if "!DEPS_OK!"=="0" (
        echo   [ERROR] Some dependencies are missing
        echo.
        echo   Install missing dependencies:
        echo     Python 3.9+:  https://www.python.org/downloads/
        echo     SCons:        %PYTHON_CMD% -m pip install scons
        echo     Visual Studio: https://visualstudio.microsoft.com/downloads/
        echo.
    ) else (
        echo   [OK] All dependencies OK
    )
) else (
    echo   [OK] All dependencies OK
)
echo.
pause
goto menu

:: ============================================================================
:: Main Menu
:: ============================================================================

:menu
echo.
echo ============================================
echo    Godot Engine 4.7 Build ^(Windows^)
echo ============================================
echo.
echo   Build mode comparison:
echo   +-----------------+----------+--------+---------+-----------------------------+
echo   ^| Mode            ^| Optimize ^| PDB    ^| Speed   ^| Debug capability            ^|
echo   +-----------------+----------+--------+---------+-----------------------------+
echo   ^| 1. Debug        ^| None     ^| Yes    ^| Slow    ^| Full: stack, vars, watches  ^|
echo   ^| 2. RelWithDeb   ^| Speed    ^| Yes    ^| Fast    ^| Stack + line numbers only   ^|
echo   ^| 3. Release      ^| Speed    ^| No     ^| Fast    ^| None                        ^|
echo   ^| 4. Template     ^| Speed    ^| No     ^| Fast    ^| Export template ^(no editor^) ^|
echo   +-----------------+----------+--------+---------+-----------------------------+
echo.
echo   Tip: Use RelWithDebInfo for production debugging ^(crash dumps + WinDbg^).
echo.
echo   Environment:
echo   ├─ Platform:    windows
echo   ├─ Arch:        %ARCH_TAG%
echo   ├─ CPU Cores:   %JOBS%
echo   ├─ Python:      %PYTHON_CMD%
echo   └─ SCons:       %SCONS_CMD%
echo.
echo   1. Debug          ^(debug_symbols=true,  optimize=debug^)
echo   2. RelWithDebInfo ^(debug_symbols=true,  optimize=speed^)
echo   3. Release        ^(optimize=speed,      no symbols^)
echo   4. Template Release ^(target=template_release, no editor^)
echo   5. Full Debug      ^(engine + C# glue + assemblies^)
echo   6. Full RelWithDeb ^(engine + C# glue + assemblies^)
echo   7. Full Release    ^(engine + C# glue + assemblies^)
echo   8. C# Glue Only   ^(regenerate C# bindings + assemblies^)
echo   9. Check Dependencies
echo   10. Install Deps  ^(accesskit, d3d12 SDK^)
echo   11. Clean
echo   12. Exit
echo.
set /p choice=Please select [1-12]:

if "%choice%"=="1" goto debug
if "%choice%"=="2" goto relwithdebinfo
if "%choice%"=="3" goto release
if "%choice%"=="4" goto template
if "%choice%"=="5" goto full_debug
if "%choice%"=="6" goto full_relwithdeb
if "%choice%"=="7" goto full_release
if "%choice%"=="8" goto csharp_glue
if "%choice%"=="9" goto check_deps
if "%choice%"=="10" goto install_deps
if "%choice%"=="11" goto clean
if "%choice%"=="12" goto end
echo Invalid choice.
goto menu

:: ============================================
::  Engine only
:: ============================================

:debug
echo.
echo [DEBUG] Starting build... ^(%ARCH_TAG%, -j%JOBS%^)
echo.
%SCONS_CMD% p=windows target=editor debug_symbols=true optimize=debug module_mono_enabled=yes -j%JOBS%
echo.
echo [DEBUG] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:relwithdebinfo
echo.
echo [RELWITHDEBINFO] Starting build... ^(%ARCH_TAG%, -j%JOBS%^)
echo.
%SCONS_CMD% p=windows target=editor debug_symbols=true optimize=speed module_mono_enabled=yes -j%JOBS%
echo.
echo [RELWITHDEBINFO] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:release
echo.
echo [RELEASE] Starting build... ^(%ARCH_TAG%, -j%JOBS%^)
echo.
%SCONS_CMD% p=windows target=editor optimize=speed module_mono_enabled=yes -j%JOBS%
echo.
echo [RELEASE] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:: ============================================
::  Export template
:: ============================================

:template
echo.
echo [TEMPLATE_RELEASE] Starting build... ^(%ARCH_TAG%, -j%JOBS%^)
echo.
%SCONS_CMD% p=windows target=template_release optimize=speed -j%JOBS%
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
%SCONS_CMD% p=windows target=editor debug_symbols=true optimize=debug module_mono_enabled=yes -j%JOBS%
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
%PYTHON_CMD% ./modules/mono/build_scripts/build_assemblies.py --godot-output-dir ./bin --push-nupkgs-local ./bin/GodotSharp/Tools/nupkgs
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
%SCONS_CMD% p=windows target=editor debug_symbols=true optimize=speed module_mono_enabled=yes -j%JOBS%
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
%PYTHON_CMD% ./modules/mono/build_scripts/build_assemblies.py --godot-output-dir ./bin --push-nupkgs-local ./bin/GodotSharp/Tools/nupkgs
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
%SCONS_CMD% p=windows target=editor optimize=speed module_mono_enabled=yes -j%JOBS%
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
%PYTHON_CMD% ./modules/mono/build_scripts/build_assemblies.py --godot-output-dir ./bin --push-nupkgs-local ./bin/GodotSharp/Tools/nupkgs
if %ERRORLEVEL% neq 0 goto buildfail
echo.
echo [FULL RELEASE] Step 4/4: Registering NuGet source...
echo.
dotnet nuget add source "%CD%\%NUPKGS_DIR%" -n GodotLocal --configfile "%APPDATA%\NuGet\NuGet.Config" 2>nul || echo NuGet source may already exist, skipping.
echo.
echo [FULL RELEASE] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:: ============================================
::  C# glue only (regenerate bindings + assemblies)
:: ============================================

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
%PYTHON_CMD% misc\scripts\install_accesskit.py
if %ERRORLEVEL% neq 0 (
    echo accesskit install FAILED.
    pause
    goto menu
)
echo.
echo [INSTALL] Installing d3d12 SDK...
echo.
%PYTHON_CMD% misc\scripts\install_d3d12_sdk_windows.py
if %ERRORLEVEL% neq 0 (
    echo d3d12 SDK install FAILED.
    pause
    goto menu
)
echo.
echo [INSTALL] All dependencies installed.
echo   Now you can remove 'accesskit=no d3d12=no' from build options to enable them.
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
endlocal

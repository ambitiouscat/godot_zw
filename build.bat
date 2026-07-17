@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

title Godot Engine 4.7.0 Build

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
echo    Godot Engine 4.7.0 Build ^(Windows^)
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
echo   5. C# Glue Only   ^(regenerate C# bindings + assemblies^)
echo   6. Check Dependencies
echo   7. Exit
echo.
set /p choice=Please select [1-7]:

if "%choice%"=="1" goto debug
if "%choice%"=="2" goto relwithdebinfo
if "%choice%"=="3" goto release
if "%choice%"=="4" goto template
if "%choice%"=="5" goto csharp_glue
if "%choice%"=="6" goto check_deps
if "%choice%"=="7" goto end
echo Invalid choice.
goto menu

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

:template
echo.
echo [TEMPLATE_RELEASE] Starting build... ^(%ARCH_TAG%, -j%JOBS%^)
echo.
%SCONS_CMD% p=windows target=template_release optimize=speed -j%JOBS%
echo.
echo [TEMPLATE_RELEASE] Build finished with exit code: %ERRORLEVEL%
pause
goto menu

:csharp_glue
echo.
echo [C# GLUE] Launching update-csharp-api.bat ...
echo.
call update-csharp-api.bat
goto menu

:end
endlocal

@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

title Godot Engine - Update C# API

echo ============================================
echo   Godot Engine - Update C# API
echo   (Glue generation + Assembly build)
echo ============================================
echo.

:: ============================================================================
:: Python 3.9+ Check
:: ============================================================================

set PYTHON_CMD=

py -3.9 --version >nul 2>&1
if !errorlevel! equ 0 ( set PYTHON_CMD=py -3.9 & goto py_found )
py -3.10 --version >nul 2>&1
if !errorlevel! equ 0 ( set PYTHON_CMD=py -3.10 & goto py_found )
py -3.11 --version >nul 2>&1
if !errorlevel! equ 0 ( set PYTHON_CMD=py -3.11 & goto py_found )
py -3.12 --version >nul 2>&1
if !errorlevel! equ 0 ( set PYTHON_CMD=py -3.12 & goto py_found )
py -3.13 --version >nul 2>&1
if !errorlevel! equ 0 ( set PYTHON_CMD=py -3.13 & goto py_found )

python --version >nul 2>&1
if !errorlevel! equ 0 (
    for /f "tokens=2" %%v in ('python --version 2^>^&1') do (
        for /f "tokens=1,2 delims=." %%a in ("%%v") do (
            if %%a geq 3 if %%b geq 9 ( set PYTHON_CMD=python & goto py_found )
        )
    )
)

echo [ERROR] Python 3.9+ is required. Please install it first.
echo   https://www.python.org/downloads/
pause
exit /b 1

:py_found

:: ============================================================================
:: .NET SDK Check
:: ============================================================================

where dotnet >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] dotnet CLI not found. Required for building C# assemblies.
    echo.
    echo   Install .NET SDK:
    echo     https://dotnet.microsoft.com/download
    echo   Or via:
    echo     winget install Microsoft.DotNet.SDK.8
    echo.
    pause
    exit /b 1
)

:: ============================================================================
:: Detect architecture
:: ============================================================================

set ARCH_TAG=x86_64
if "%PROCESSOR_ARCHITECTURE%"=="ARM64" set ARCH_TAG=arm64

echo   Platform:  windows
echo   Arch:      %ARCH_TAG%
echo   Python:    %PYTHON_CMD%
echo   dotnet:    !dotnet --version!
echo.

:: ============================================================================
:: Find Godot binary
:: ============================================================================

set GODOT_EXE=

:: Godot 4.x: mono is built into the editor binary (no .mono suffix)
if exist bin\godot.windows.editor.%ARCH_TAG%.exe (
    set GODOT_EXE=bin\godot.windows.editor.%ARCH_TAG%.exe
    goto found_exe
)
:: Fallback: check with .mono suffix (older builds)
if exist bin\godot.windows.editor.%ARCH_TAG%.mono.exe (
    set GODOT_EXE=bin\godot.windows.editor.%ARCH_TAG%.mono.exe
    goto found_exe
)
:: Generic fallback
if exist bin\godot.windows.exe (
    set GODOT_EXE=bin\godot.windows.exe
    goto found_exe
)

echo [ERROR] Cannot find godot editor binary in bin\
echo   Expected: bin\godot.windows.editor.%ARCH_TAG%.exe
echo         or: bin\godot.windows.editor.%ARCH_TAG%.mono.exe
echo.
echo   Please compile the editor first with module_mono_enabled=yes (use build.bat option 1-3).
pause
exit /b 1

:found_exe

echo   Found: %GODOT_EXE%
echo.

:: ============================================================================
:: Step 1: Generate Mono glue code
:: ============================================================================

echo ============================================
echo   [1/2] Generating Mono glue code...
echo ============================================
echo.
echo   Command: %GODOT_EXE% --headless --generate-mono-glue modules\mono\glue
echo.

%GODOT_EXE% --headless --generate-mono-glue modules\mono\glue
if !errorlevel! neq 0 (
    echo.
    echo [ERROR] Glue generation failed (exit code: !errorlevel!).
    echo   Check the error messages above and ensure the editor was built with module_mono_enabled=yes.
    pause
    exit /b 1
)

echo.
echo   ^> Glue generated successfully
echo.

:: ============================================================================
:: Step 2: Build C# assemblies
:: ============================================================================

echo ============================================
echo   [2/2] Building C# assemblies...
echo ============================================
echo.
echo   Command: %PYTHON_CMD% modules\mono\build_scripts\build_assemblies.py --godot-output-dir=.\bin
echo.

%PYTHON_CMD% modules\mono\build_scripts\build_assemblies.py --godot-output-dir=.\bin
if !errorlevel! neq 0 (
    echo.
    echo [ERROR] Assembly build failed (exit code: !errorlevel!).
    pause
    exit /b 1
)

echo.
echo ============================================
echo   ^> C# API update completed successfully!
echo ============================================
echo.
echo   Next step: run the editor to use C# projects:
echo     %GODOT_EXE%
echo.
pause
endlocal

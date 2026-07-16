@echo off
chcp 65001 >nul 2>&1
title Godot Engine - Update C# API

echo ============================================
echo   Godot Engine - Update C# API (Glue + Assemblies)
echo ============================================
echo.

:: Step 1: Generate mono glue
echo [1/2] Generating mono glue...

set GODOT_EXE=
if exist bin\godot.windows.editor.x86_64.mono.exe (
    set GODOT_EXE=bin\godot.windows.editor.x86_64.mono.exe
) else if exist bin\godot.windows.editor.x86_64.exe (
    set GODOT_EXE=bin\godot.windows.editor.x86_64.exe
) else if exist bin\godot.windows.exe (
    set GODOT_EXE=bin\godot.windows.exe
) else (
    echo [ERROR] No editor executable found in bin\
    echo Expected: bin\godot.windows.editor.x86_64.mono.exe
    echo       or: bin\godot.windows.editor.x86_64.exe
    echo Please build the editor first (use build.bat options 1-3).
    pause
    exit /b 1
)

echo   Using: %GODOT_EXE%
echo.
%GODOT_EXE% --headless --generate-mono-glue modules\mono\glue
if %ERRORLEVEL% neq 0 (
    echo.
    echo [WARN] Glue generation exited with code: %ERRORLEVEL%
    echo The red ERROR messages above are normal - ignore them.
    echo If other errors occurred, check your build.
    echo.
)

:: Step 2: Build C# assemblies
echo.
echo [2/2] Building C# assemblies...
echo   Command: python modules\mono\build_scripts\build_assemblies.py --godot-output-dir=.\bin
echo.
python modules\mono\build_scripts\build_assemblies.py --godot-output-dir=.\bin
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Assembly build failed with exit code: %ERRORLEVEL%
    goto done
)

echo.
echo ============================================
echo   C# API update completed successfully!
echo ============================================
:done
echo.
pause

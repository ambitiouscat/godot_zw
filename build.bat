@echo off
chcp 65001 >nul 2>&1
title Godot Engine 4.7.0 Build

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
echo   5. C# Glue Only   (regenerate C# bindings + assemblies)
echo   6. Exit
echo.
set /p choice=Please select [1-6]:

if "%choice%"=="1" goto debug
if "%choice%"=="2" goto relwithdebinfo
if "%choice%"=="3" goto release
if "%choice%"=="4" goto template
if "%choice%"=="5" goto csharp_glue
if "%choice%"=="6" goto end
echo Invalid choice.
goto menu

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

:template
echo.
echo [TEMPLATE_RELEASE] Starting build...
echo.
scons p=windows target=template_release optimize=speed
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

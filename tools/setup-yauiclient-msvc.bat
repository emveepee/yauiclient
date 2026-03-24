@echo off
setlocal EnableDelayedExpansion
:: ============================================================================
:: setup-yauiclient-msvc.bat
::
:: Sets up the yauiclient build environment for MSVC (Visual Studio).
::
:: What this script does:
::   1. Installs vcpkg dependencies (everything except libmpv)
::   2. Copies libmpv runtime DLLs from sdk\ into bin\Debug and bin\Release
::   3. Copies vcpkg runtime DLLs into bin\Debug and bin\Release
::
:: Prerequisites:
::   - Visual Studio 2022 with C++ workload installed
::   - vcpkg installed and VCPKG_ROOT environment variable set
::     (or pass it as: setup-yauiclient-msvc.bat C:\path\to\vcpkg)
::   - libmpv SDK tarball extracted to sdk\ in the repo root:
::       Download from https://github.com/emveepee/libmpv-mingw64-builder/wiki
::       Then extract: 7z x libmpv-sdk-vX.X.X-windows-x86_64.tar.gz -o sdk\
::   - libmpv runtime tarball also extracted to sdk\:
::       7z x libmpv-runtime-vX.X.X-windows-x86_64.tar.gz -o sdk\
::
:: Usage:
::   tools\setup-yauiclient-msvc.bat [vcpkg_root]
::
:: Example:
::   tools\setup-yauiclient-msvc.bat C:\tools\vcpkg
:: ============================================================================

:: ---------------------------------------------------------------------------
:: Locate repo root (parent of tools\)
:: ---------------------------------------------------------------------------
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set REPO_ROOT=%SCRIPT_DIR%\..
pushd "%REPO_ROOT%"
set REPO_ROOT=%CD%
popd

set SDK_DIR=%REPO_ROOT%\sdk

:: ---------------------------------------------------------------------------
:: Locate vcpkg
:: ---------------------------------------------------------------------------
if not "%~1"=="" set VCPKG_ROOT=%~1

if "%VCPKG_ROOT%"=="" (
    echo ERROR: VCPKG_ROOT is not set.
    echo   Set it as an environment variable or pass it as the first argument.
    echo   Example: tools\setup-yauiclient-msvc.bat C:\tools\vcpkg
    exit /b 1
)

if not exist "%VCPKG_ROOT%\vcpkg.exe" (
    echo ERROR: vcpkg.exe not found at %VCPKG_ROOT%\vcpkg.exe
    exit /b 1
)

set VCPKG=%VCPKG_ROOT%\vcpkg.exe

echo.
echo === yauiclient MSVC setup ===
echo VCPKG_ROOT : %VCPKG_ROOT%
echo Repo root  : %REPO_ROOT%
echo SDK dir    : %SDK_DIR%
echo.

:: ---------------------------------------------------------------------------
:: Validate SDK
:: ---------------------------------------------------------------------------
if not exist "%SDK_DIR%\include\mpv\client.h" (
    echo ERROR: libmpv SDK not found at %SDK_DIR%
    echo.
    echo   Download the SDK tarball from the wiki and extract it to sdk\:
    echo     https://github.com/emveepee/libmpv-mingw64-builder/wiki
    echo     7z x libmpv-sdk-vX.X.X-windows-x86_64.tar.gz -o sdk\
    exit /b 1
)

if not exist "%SDK_DIR%\lib\libmpv.lib" (
    echo ERROR: libmpv.lib not found in %SDK_DIR%\lib
    echo   Check that the correct Windows SDK tarball was extracted to sdk\
    exit /b 1
)

echo SDK validated: %SDK_DIR%

:: ---------------------------------------------------------------------------
:: [1/3] Install vcpkg dependencies (x64-windows)
:: ---------------------------------------------------------------------------
echo.
echo [1/3] Installing vcpkg dependencies for x64-windows...
echo       (this may take a while on first run)
echo.

%VCPKG% install ^
    cpr:x64-windows ^
    curl:x64-windows ^
    glew:x64-windows ^
    glfw3:x64-windows ^
    nlohmann-json:x64-windows ^
    fmt:x64-windows ^
    zlib:x64-windows

if errorlevel 1 (
    echo ERROR: vcpkg install failed.
    exit /b 1
)

%VCPKG% integrate install
if errorlevel 1 (
    echo WARNING: vcpkg integrate install failed - continuing anyway.
)
echo [1/3] vcpkg dependencies installed OK.

:: ---------------------------------------------------------------------------
:: [2/3] Copy libmpv runtime DLLs into bin\Debug and bin\Release
:: ---------------------------------------------------------------------------
echo.
echo [2/3] Copying libmpv runtime DLLs to bin\Debug and bin\Release...

if not exist "%REPO_ROOT%\bin\Debug"   mkdir "%REPO_ROOT%\bin\Debug"
if not exist "%REPO_ROOT%\bin\Release" mkdir "%REPO_ROOT%\bin\Release"

set COPIED=0
for %%f in ("%SDK_DIR%\*.dll") do (
    copy /Y "%%f" "%REPO_ROOT%\bin\Debug\"   >nul
    copy /Y "%%f" "%REPO_ROOT%\bin\Release\" >nul
    echo   + %%~nxf
    set /a COPIED+=1
)

if !COPIED!==0 (
    echo WARNING: No DLLs found in %SDK_DIR%
    echo   Check that the runtime tarball was also extracted to sdk\
)

:: ---------------------------------------------------------------------------
:: [3/3] Copy vcpkg runtime DLLs
:: ---------------------------------------------------------------------------
echo.
echo [3/3] Copying vcpkg runtime DLLs...

set VCPKG_BIN=%VCPKG_ROOT%\installed\x64-windows\bin
set VCPKG_DBG=%VCPKG_ROOT%\installed\x64-windows\debug\bin

if exist "%VCPKG_BIN%" (
    for %%p in (cpr libcurl glew32 glfw3 fmt zlib1) do (
        for %%f in ("%VCPKG_BIN%\%%p*.dll") do (
            if exist "%%f" (
                copy /Y "%%f" "%REPO_ROOT%\bin\Release\" >nul
                copy /Y "%%f" "%REPO_ROOT%\bin\Debug\"   >nul
                echo   + %%~nxf
            )
        )
    )
    if exist "%VCPKG_DBG%" (
        for %%p in (cprd libcurl-d glew32d fmtd zlibd) do (
            for %%f in ("%VCPKG_DBG%\%%p*.dll") do (
                if exist "%%f" (
                    copy /Y "%%f" "%REPO_ROOT%\bin\Debug\" >nul
                    echo   + %%~nxf  [debug]
                )
            )
        )
    )
) else (
    echo WARNING: vcpkg bin not found at %VCPKG_BIN%
)

:: ---------------------------------------------------------------------------
:: Done
:: ---------------------------------------------------------------------------
echo.
echo ============================================================
echo  Setup complete.
echo.
echo  sdk\include\mpv\      - libmpv headers
echo  sdk\lib\              - libmpv.lib + libmpv.def (MSVC)
echo  bin\Debug\            - all runtime DLLs
echo  bin\Release\          - all runtime DLLs
echo.
echo  To build:
echo    cmake -B build\windows ^
echo      -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake ^
echo      -DLIBMPV_SDK_DIR=%REPO_ROOT%\sdk
echo    cmake --build build\windows --config Release
echo ============================================================
echo.
endlocal
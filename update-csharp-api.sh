#!/bin/bash
# Godot Engine - Update C# API (Glue + Assemblies)
# Supports: Linux, macOS, Windows (x86_64, arm64)

set -e

# ============================================================================
# Python 3.9+ Check (same logic as build.sh)
# ============================================================================

find_python39() {
    for candidate in python3.13 python3.12 python3.11 python3.10 python3.9 python3; do
        if command -v "$candidate" &>/dev/null; then
            local major minor
            major=$("$candidate" -c 'import sys; print(sys.version_info.major)' 2>/dev/null) || continue
            minor=$("$candidate" -c 'import sys; print(sys.version_info.minor)' 2>/dev/null) || continue
            if [ "$major" -ge 3 ] && [ "$minor" -ge 9 ]; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

PYTHON_CMD="$(find_python39)" || PYTHON_CMD=""

if [ -z "$PYTHON_CMD" ]; then
    echo ""
    echo "[ERROR] Python 3.9+ is required. Please install it first."
    echo "  sudo apt-get install -y python3.9 python3.9-venv python3.9-distutils"
    exit 1
fi

# ============================================================================
# Pre-flight checks
# ============================================================================

echo "============================================"
echo "  Godot Engine - Update C# API"
echo "  (Glue generation + Assembly build)"
echo "============================================"
echo ""

# Detect platform
UNAME_S="$(uname -s)"
case "$UNAME_S" in
    Linux)   PLATFORM="linuxbsd" ;;
    Darwin)  PLATFORM="macos" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *)       echo "[ERROR] Unsupported platform: $UNAME_S"; exit 1 ;;
esac

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) ARCH_TAG="x86_64" ;;
    aarch64|arm64) ARCH_TAG="arm64" ;;
    *)             echo "[ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Check dotnet CLI
if ! command -v dotnet &>/dev/null; then
    echo "[ERROR] dotnet CLI not found. Required for building C# assemblies."
    echo ""
    echo "  Install .NET SDK:"
    echo "    https://dotnet.microsoft.com/download"
    echo "  Or via apt (Debian/Ubuntu/Kylin):"
    echo "    sudo apt-get install -y dotnet-sdk-8.0"
    echo ""
    exit 1
fi

DOTNET_VER="$(dotnet --version 2>/dev/null || echo 'unknown')"

echo "  Platform:  $PLATFORM"
echo "  Arch:      $ARCH_TAG"
echo "  Python:    $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"
echo "  dotnet:    $DOTNET_VER"
echo ""

# ============================================================================
# Find Godot binary
# ============================================================================

EXE=""
# Godot 4.x: mono is built into the editor binary (no .mono suffix)
if [ -f "bin/godot.${PLATFORM}.editor.${ARCH_TAG}" ]; then
    EXE="bin/godot.${PLATFORM}.editor.${ARCH_TAG}"
fi
# Fallback: check with .mono suffix (older builds)
if [ -z "$EXE" ] && [ -f "bin/godot.${PLATFORM}.editor.${ARCH_TAG}.mono" ]; then
    EXE="bin/godot.${PLATFORM}.editor.${ARCH_TAG}.mono"
fi

if [ -z "$EXE" ]; then
    echo "[ERROR] Cannot find godot editor binary in bin/"
    echo "  Expected: bin/godot.${PLATFORM}.editor.${ARCH_TAG}"
    echo "        or: bin/godot.${PLATFORM}.editor.${ARCH_TAG}.mono"
    echo ""
    echo "  Please compile the editor first with module_mono_enabled=yes (use build.sh option 1-3)."
    exit 1
fi

echo "  Found: $EXE"
echo ""
chmod +x "$EXE"

# ============================================================================
# Step 1: Generate Mono glue code
# ============================================================================

echo "============================================"
echo "  [1/2] Generating Mono glue code..."
echo "============================================"
echo ""
echo "  Command: $EXE --headless --generate-mono-glue modules/mono/glue"
echo ""

export LD_LIBRARY_PATH="$(pwd)/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$EXE" --headless --generate-mono-glue modules/mono/glue
GLUE_EXIT=$?

if [ $GLUE_EXIT -ne 0 ]; then
    echo ""
    echo "[ERROR] Glue generation failed (exit code: $GLUE_EXIT)."
    echo "  Check the error messages above and ensure the editor was built with module_mono_enabled=yes."
    exit 1
fi

echo ""
echo "  ✓ Glue generated successfully"
echo ""

# ============================================================================
# Step 2: Build C# assemblies
# ============================================================================

echo "============================================"
echo "  [2/2] Building C# assemblies..."
echo "============================================"
echo ""
echo "  Command: $PYTHON_CMD modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin"
echo ""

"$PYTHON_CMD" modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin
ASM_EXIT=$?

if [ $ASM_EXIT -ne 0 ]; then
    echo ""
    echo "[ERROR] Assembly build failed (exit code: $ASM_EXIT)."
    exit 1
fi

echo ""
echo "============================================"
echo "  ✓ C# API update completed successfully!"
echo "============================================"
echo ""
echo "  Next step: run the editor to use C# projects:"
echo "    ./bin/godot.${PLATFORM}.editor.${ARCH_TAG}"
echo ""

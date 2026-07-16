#!/bin/bash
# Godot Engine - Update C# API (Glue + Assemblies)

echo "============================================"
echo "  Godot Engine - Update C# API (Glue + Assemblies)"
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

echo "  Platform: $PLATFORM"
echo "  Arch:     $ARCH_TAG"
echo ""

# Step 1: Generate mono glue
echo "[1/2] Generating mono glue..."

EXE=""
# Try mono-suffixed binary first
if [ -f "bin/godot.${PLATFORM}.editor.${ARCH_TAG}.mono" ]; then
    EXE="bin/godot.${PLATFORM}.editor.${ARCH_TAG}.mono"
elif [ -f "bin/godot.${PLATFORM}.editor.${ARCH_TAG}" ]; then
    EXE="bin/godot.${PLATFORM}.editor.${ARCH_TAG}"
else
    echo "[ERROR] Cannot find godot binary for ${PLATFORM}/${ARCH_TAG} in bin/"
    echo "Expected: bin/godot.${PLATFORM}.editor.${ARCH_TAG}.mono"
    echo "      or: bin/godot.${PLATFORM}.editor.${ARCH_TAG}"
    echo "Please compile the editor first (use build.sh)."
    exit 1
fi

echo "  Found: $EXE"
echo ""
chmod +x "$EXE"
export LD_LIBRARY_PATH="$(pwd)/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$EXE" --headless --generate-mono-glue modules/mono/glue
result=$?
if [ $result -ne 0 ]; then
    echo ""
    echo "[WARN] Glue generation exited with code: $result"
    echo "The red ERROR messages above are normal - ignore them."
    echo "If other errors occurred, check your build."
    echo ""
fi

# Step 2: Build C# assemblies
echo ""
echo "[2/2] Building C# assemblies..."
echo "  Command: python3 modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin"
echo ""
python3 modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin
if [ $? -ne 0 ]; then
    echo ""
    echo "[ERROR] Assembly build failed."
    exit 1
fi

echo ""
echo "============================================"
echo "  C# API update completed successfully!"
echo "============================================"

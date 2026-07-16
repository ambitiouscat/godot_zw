#!/bin/bash
# Godot Engine Build (Linux/macOS)
# Supports: x86_64, arm64 (Kylin/飞腾/鲲鹏), rv64, ppc64, loongarch64

set -e

# ============================================================================
# Environment Detection
# ============================================================================

# Detect CPU architecture
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64)    ARCH_TAG="x86_64" ;;
    aarch64|arm64)    ARCH_TAG="arm64" ;;
    riscv64)          ARCH_TAG="rv64" ;;
    ppc64le|ppc64)    ARCH_TAG="ppc64" ;;
    loongarch64)      ARCH_TAG="loongarch64" ;;
    *)                echo "[WARN] Unrecognized arch: $HOST_ARCH, falling back to x86_64"; ARCH_TAG="x86_64" ;;
esac

# Detect CPU cores for parallel build
if command -v nproc &>/dev/null; then
    JOBS=$(nproc)
elif [ -f /proc/cpuinfo ]; then
    JOBS=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 4)
else
    JOBS=4
fi

# Detect OS distribution (for helpful dependency hints)
DISTRO="unknown"
if [ -f /etc/os-release ]; then
    DISTRO=$(. /etc/os-release && echo "${ID:-unknown}")
fi

# Detect platform for SCons
UNAME_S="$(uname -s)"
case "$UNAME_S" in
    Linux)   PLATFORM="linuxbsd" ;;
    Darwin)  PLATFORM="macos" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *)       PLATFORM="linuxbsd" ;;
esac

# Build arch flag (only pass if not auto-detected correctly)
ARCH_FLAG=""
if [ "$ARCH_TAG" != "x86_64" ]; then
    ARCH_FLAG="arch=$ARCH_TAG"
fi

# ============================================================================
# Dependency Check
# ============================================================================

check_deps() {
    local missing=()

    if ! command -v scons &>/dev/null; then
        missing+=("scons (pip3 install scons)")
    fi
    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    fi
    if ! command -v pkg-config &>/dev/null; then
        missing+=("pkg-config")
    fi
    if ! command -v gcc &>/dev/null && ! command -v g++ &>/dev/null && ! command -v clang++ &>/dev/null; then
        missing+=("gcc/g++ or clang++")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo "[ERROR] Missing build dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""

        # Distribution-specific install hints
        case "$DISTRO" in
            ubuntu|debian|kylin|neokylin|openkylin|uos|deepin)
                echo "Install command (Debian/Ubuntu/Kylin):"
                echo "  sudo apt-get install -y build-essential scons pkg-config python3 \\"
                echo "    libx11-dev libxcursor-dev libxinerama-dev libxext-dev libxrandr-dev \\"
                echo "    libxrender-dev libxi-dev libxkbcommon-dev libxkbcommon-x11-dev \\"
                echo "    libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev \\"
                echo "    libudev-dev libdbus-1-dev libwayland-dev libdecor-0-dev \\"
                echo "    libfontconfig-dev libspeechd-dev"
                ;;
            fedora|centos|rhel|rocky)
                echo "Install command (Fedora/RHEL):"
                echo "  sudo dnf install -y gcc-c++ scons pkgconf-pkg-config python3 \\"
                echo "    libX11-devel libXcursor-devel libXinerama-devel libXext-devel \\"
                echo "    libXrandr-devel libXi-devel libXrender-devel \\"
                echo "    mesa-libGL-devel mesa-libGLU-devel alsa-lib-devel pulseaudio-libs-devel \\"
                echo "    systemd-devel dbus-devel wayland-devel libxkbcommon-devel \\"
                echo "    fontconfig-devel"
                ;;
            arch|manjaro)
                echo "Install command (Arch):"
                echo "  sudo pacman -S gcc scons pkgconf python3 \\"
                echo "    libx11 libxcursor libxinerama libxext libxrandr libxi libxrender \\"
                echo "    mesa glu alsa-lib pulseaudio systemd wayland libxkbcommon fontconfig"
                ;;
            *)
                echo "Please install the missing dependencies using your system's package manager."
                ;;
        esac
        echo ""
        return 1
    fi
    return 0
}

# ============================================================================
# Print Environment Info
# ============================================================================

print_env() {
    echo ""
    echo "  Environment:"
    echo "  ├─ Platform:    $PLATFORM"
    echo "  ├─ Arch:        $ARCH_TAG ($HOST_ARCH)"
    echo "  ├─ Distro:      $DISTRO"
    echo "  ├─ CPU Cores:   $JOBS"
    if [ -n "$ARCH_FLAG" ]; then
        echo "  ├─ SCons Arch:  $ARCH_FLAG"
    fi
    if [ "$DISTRO" = "kylin" ] || [ "$DISTRO" = "neokylin" ] || [ "$DISTRO" = "openkylin" ]; then
        echo "  ├─ ★ Kylin OS detected — ARM64 native build"
    fi
    echo "  └─ SCons Jobs:  -j$JOBS"
    echo ""
}

# ============================================================================
# Interactive Build Menu
# ============================================================================

while true; do
    echo ""
    echo "============================================"
    echo "    Godot Engine 4.7.0 Build ($PLATFORM)"
    echo "============================================"
    echo ""
    echo "  Build mode comparison:"
    echo "  +-----------------+----------+---------+---------+-----------------------------+"
    echo "  | Mode            | Optimize | Symbols | Speed   | Debug capability            |"
    echo "  +-----------------+----------+---------+---------+-----------------------------+"
    echo "  | 1. Debug        | None     | Yes     | Slow    | Full: stack, vars, watches  |"
    echo "  | 2. RelWithDeb   | Speed    | Yes     | Fast    | Stack + line numbers only   |"
    echo "  | 3. Release      | Speed    | No      | Fast    | None                        |"
    echo "  | 4. Template     | Speed    | No      | Fast    | Export template (no editor) |"
    echo "  +-----------------+----------+---------+---------+-----------------------------+"
    echo ""
    echo "  Tip: Use RelWithDebInfo for production debugging (core files + GDB)."
    echo ""
    print_env
    echo "  1. Debug          (debug_symbols=true,  optimize=debug)"
    echo "  2. RelWithDebInfo (debug_symbols=true,  optimize=speed)"
    echo "  3. Release        (optimize=speed,      no symbols)"
    echo "  4. Template Release (target=template_release, no editor)"
    echo "  5. Check Dependencies"
    echo "  6. Exit"
    echo ""
    read -p "Please select [1-6]: " choice

    case "$choice" in
        1)
            echo ""
            echo "[DEBUG] Starting build... ($ARCH_TAG, -j$JOBS)"
            echo ""
            scons p=$PLATFORM target=editor debug_symbols=true optimize=debug module_mono_enabled=yes $ARCH_FLAG -j$JOBS
            echo ""
            echo "[DEBUG] Build finished with exit code: $?"
            ;;
        2)
            echo ""
            echo "[RELWITHDEBINFO] Starting build... ($ARCH_TAG, -j$JOBS)"
            echo ""
            scons p=$PLATFORM target=editor debug_symbols=true optimize=speed module_mono_enabled=yes $ARCH_FLAG -j$JOBS
            echo ""
            echo "[RELWITHDEBINFO] Build finished with exit code: $?"
            ;;
        3)
            echo ""
            echo "[RELEASE] Starting build... ($ARCH_TAG, -j$JOBS)"
            echo ""
            scons p=$PLATFORM target=editor optimize=speed module_mono_enabled=yes $ARCH_FLAG -j$JOBS
            echo ""
            echo "[RELEASE] Build finished with exit code: $?"
            ;;
        4)
            echo ""
            echo "[TEMPLATE_RELEASE] Starting build... ($ARCH_TAG, -j$JOBS)"
            echo ""
            scons p=$PLATFORM target=template_release optimize=speed $ARCH_FLAG -j$JOBS
            echo ""
            echo "[TEMPLATE_RELEASE] Build finished with exit code: $?"
            ;;
        5)
            echo ""
            echo "[CHECK] Verifying build dependencies..."
            if check_deps; then
                echo "[CHECK] All dependencies OK ✓"
            fi
            ;;
        6)
            echo "Bye."
            break
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
done

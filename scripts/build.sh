#!/bin/bash
# ============================================================
#  Build harmonyos-godot — Godot Engine for HarmonyOS
# ============================================================
#  This script compiles libgodot.so and copies it into the
#  HarmonyOS template project. Signing & HAP packaging are
#  handled by DevEco Studio IDE.
#
#  Usage:
#    ./scripts/build.sh              # interactive menu
#    ./scripts/build.sh [profile]    # skip menu, use named profile
#
#    Profiles: debug | release-debug | release | test
#    Modes:    gui (interactive menu)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- Auto-detect CPU cores ----
if [ "$(uname -s)" = "Linux" ]; then
    JOBS=$(nproc)
elif [ "$(uname -s)" = "Darwin" ]; then
    JOBS=$(sysctl -n hw.ncpu)
else
    JOBS=$(nproc 2>/dev/null || echo 8)
fi

# ============================================================
#  GUI — Interactive Build Menu
# ============================================================
show_gui_menu() {
    echo ""
    echo "========================================="
    echo "  GDAI Build System — Interactive Menu"
    echo "========================================="
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │  HarmonyOS (cross-compile → aarch64 .so)                       │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"
    echo "  │ [1] debug          编辑器 Debug 版本                            │"
    echo "  │     调试符号: 开启 | 优化: 无 | 目标: editor                    │"
    echo "  │     用途: 日常开发调试, crash 堆栈分析                          │"
    echo "  │                                                                 │"
    echo "  │ [2] release-debug  编辑器 Release-Debug 版本                    │"
    echo "  │     调试符号: 开启 | 优化: speed | 目标: editor                  │"
    echo "  │     用途: 性能测试, 保留调试信息                                 │"
    echo "  │                                                                 │"
    echo "  │ [3] release        模板 Release 版本                            │"
    echo "  │     调试符号: 无 | 优化: speed | 目标: template_release          │"
    echo "  │     用途: 导出模板, 正式发布                                     │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"
    echo "  │  Windows Desktop (本地测试)                                      │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"
    echo "  │ [4] test           Windows Editor + 自动化测试                   │"
    echo "  │     scons platform=windows target=editor tests=yes               │"
    echo "  │     编译后自动执行 --test 运行全部 C++ 单元测试                   │"
    echo "  │     用途: 本地验证 engine commands / bridge 逻辑                 │"
    echo "  │                                                                 │"
    echo "  │ [5] windows-editor Windows Editor (无测试)                       │"
    echo "  │     scons platform=windows target=editor                         │"
    echo "  │     用途: 编译桌面版 Godot 编辑器进行手动测试                     │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"
    echo "  │ [6] clean         清理编译产物                                    │"
    echo "  │     scons --clean + 删除 bin/obj/, 重置 SCons 缓存                │"
    echo "  │     用途: 编译失败后清理, 强制重新编译                             │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    read -r -p "  请选择 [1-8, 默认=2]: " CHOICE
    CHOICE="${CHOICE:-2}"

    case "$CHOICE" in
        1) echo ""; echo "  → 已选择: [1] OHOS debug — 编辑器 Debug 版本"; echo ""; do_ohos_build "debug" ;;
        2) echo ""; echo "  → 已选择: [2] OHOS release-debug — 编辑器 Release-Debug 版本"; echo ""; do_ohos_build "release-debug" ;;
        3) echo ""; echo "  → 已选择: [3] OHOS release — 模板 Release 版本"; echo ""; do_ohos_build "release" ;;
        4) echo ""; echo "  → 已选择: [4] Rust 交叉编译 (release)"; echo ""; do_rust_build "release" ;;
        5) echo ""; echo "  → 已选择: [5] Rust 交叉编译 (debug)"; echo ""; do_rust_build "debug" ;;
        6) echo ""; echo "  → 已选择: [6] Windows Editor + 自动化测试"; echo ""; do_test_build "yes" ;;
        7) echo ""; echo "  → 已选择: [7] Windows Editor (无测试)"; echo ""; do_test_build "no" ;;
        8) echo ""; echo "  → 已选择: [8] 清理编译产物"; echo ""; do_clean ;;
        q|Q) echo "  已取消"; exit 0 ;;
        *) echo "  无效选择, 使用默认 release-debug"; echo ""; do_ohos_build "release-debug" ;;
    esac
}

# ============================================================
#  Help — detailed descriptions
# ============================================================
show_help() {
    echo ""
    echo "GDAI Build System — 编译模式详解"
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────┐"
    echo "│ HarmonyOS 交叉编译 (→ aarch64 .so)                                │"
    echo "├──────────────────────────────────────────────────────────────────┤"
    echo "│ debug          编辑器 Debug, 调试符号全开, 无优化                  │"
    echo "│                 适用: 开发中需要 crash 堆栈、gdb/lldb 调试         │"
    echo "│                 .so 大小: ~1.2 GB (含完整 debug_info)              │"
    echo "│                                                                  │"
    echo "│ release-debug  编辑器 Release-Debug, 保留调试符号 + speed 优化     │"
    echo "│                 适用: 日常编译测试, 兼顾性能和调试                  │"
    echo "│                 .so 大小: ~500 MB                                  │"
    echo "│                                                                  │"
    echo "│ release        模板 Release, 无调试符号, speed 优化               │"
    echo "│                 适用: 导出模板打包, 上架前构建                     │"
    echo "│                 .so 大小: ~100 MB                                  │"
    echo "├──────────────────────────────────────────────────────────────────┤"
    echo "│ Rust FFI 交叉编译                                                 │"
    echo "├──────────────────────────────────────────────────────────────────┤"
    echo "│ rust-release   交叉编译 Rust → aarch64 libclaude_code_ffi.a       │"
    echo "│                 自动生成 .cargo/config.toml, 恢复原始配置          │"
    echo "│                 产物: template/entry/libs/arm64-v8a/               │"
    echo "│                       libclaude_code_ffi.a (~60 MB)                │"
    echo "│                                                                  │"
    echo "│ rust-debug     Rust debug 交叉编译 (同上 + debug 符号)            │"
    echo "├──────────────────────────────────────────────────────────────────┤"
    echo "│ Windows Desktop (本地 x86_64)                                     │"
    echo "├──────────────────────────────────────────────────────────────────┤"
    echo "│ test           Windows Editor + 自动化测试                        │"
    echo "│                 scons platform=windows target=editor tests=yes     │"
    echo "│                 编译后执行 --test 运行全部 C++ doctest 用例        │"
    echo "│                 产物: bin/godot.windows.editor.*.exe (~200 MB)     │"
    echo "│                 适用: 本地 CI, 代码变更后批量验证                  │"
    echo "│                                                                  │"
    echo "│ windows-editor Windows Editor (无测试)                            │"
    echo "│                 scons platform=windows target=editor               │"
    echo "│                 适用: 手动启动编辑器调试 UI/交互问题               │"
    echo "└──────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "使用示例:"
    echo "  ./scripts/build.sh              # 默认: OHOS release-debug"
    echo "  ./scripts/build.sh gui           # 进入交互菜单"
    echo "  ./scripts/build.sh test          # Windows Editor + 自动化测试"
    echo "  ./scripts/build.sh debug         # OHOS debug 编译"
    echo "  ./scripts/build.sh release       # OHOS release 编译"
    echo "  ./scripts/build.sh --help        # 显示此帮助"
    echo ""
}

# ============================================================
#  Windows Test Build
# ============================================================
do_test_build() {
    local WITH_TESTS="${1:-yes}"

    echo ""
    echo "========================================="
    echo "  Windows Editor Build"
    echo "========================================="
    echo "  Platform:     windows"
    echo "  Target:       editor"
    echo "  Tests:        ${WITH_TESTS}"
    echo "  Parallel:     ${JOBS} jobs"
    echo "========================================="
    echo ""

    cd "$PROJECT_ROOT"

    local SCONS_ARGS=(
        "platform=windows"
        "target=editor"
        "accesskit=no"
        "d3d12=no"
        "angle=no"
        "module_visual_shader_enabled=no"
        "-j${JOBS}"
    )

    if [ "$WITH_TESTS" = "yes" ]; then
        SCONS_ARGS+=("tests=yes")
    fi

    echo "[1/2] Building Godot Editor (Windows)..."
    echo "  scons ${SCONS_ARGS[*]}"
    echo ""

    local START_TIME=$(date +%s)
    python -m SCons "${SCONS_ARGS[@]}"
    local BUILD_TIME=$(($(date +%s) - START_TIME))
    echo ""
    echo "  Build finished in ${BUILD_TIME}s"

    # Find the built binary
    local EXE_FILE=""
    for pattern in \
        "$PROJECT_ROOT/bin/godot.windows.editor.dev.x86_64.exe" \
        "$PROJECT_ROOT/bin/godot.windows.editor.x86_64.exe" \
        "$PROJECT_ROOT/bin/godot.windows.editor.dev.x86_64.console.exe" \
        "$PROJECT_ROOT/bin/godot.windows.editor.x86_64.console.exe" \
        "$PROJECT_ROOT/bin/godot.windows.editor.*.exe"; do
        for f in $pattern; do
            if [ -f "$f" ]; then
                EXE_FILE="$f"
                break 2
            fi
        done
    done

    if [ -z "$EXE_FILE" ]; then
        echo "ERROR: Could not find built .exe file. Searching bin/..."
        ls -la "$PROJECT_ROOT/bin/"*.exe 2>/dev/null || echo "  (no .exe files found)"
        exit 1
    fi

    local EXE_SIZE=$(stat -c%s "$EXE_FILE" 2>/dev/null || echo 0)
    local EXE_SIZE_MB=$(echo "scale=1; ${EXE_SIZE} / 1048576" | bc 2>/dev/null || echo "?")
    echo "  Built: $(basename "$EXE_FILE") (${EXE_SIZE_MB} MB)"

    # Run tests if enabled
    if [ "$WITH_TESTS" = "yes" ]; then
        echo ""
        echo "[2/2] Running automated tests..."
        echo "  $EXE_FILE --test"
        echo ""
        "$EXE_FILE" --test 2>&1
        local TEST_EXIT=$?
        echo ""
        if [ $TEST_EXIT -eq 0 ]; then
            echo "========================================="
            echo "  ✅ ALL TESTS PASSED"
            echo "========================================="
        else
            echo "========================================="
            echo "  ❌ TESTS FAILED (exit code: $TEST_EXIT)"
            echo "========================================="
            exit $TEST_EXIT
        fi
    else
        echo ""
        echo "========================================="
        echo "  Build Complete (manual launch)"
        echo "========================================="
        echo "  Binary: $EXE_FILE"
        echo "  Run:    $EXE_FILE"
        echo ""
    fi
}

# ============================================================
#  OHOS Cross-Compile Build
# ============================================================
do_ohos_build() {
    local PROFILE="$1"
    local RENDER_VULKAN="${2:-yes}"
    local RENDER_GLES3="${3:-yes}"
    local EXPORT_TEMPLATE="${4:-false}"

    # ---- Auto-detect HarmonyOS SDK ----
    if [ -n "${OHOS_SDK_HOME:-}" ]; then
        SDK_PATH_RAW="$OHOS_SDK_HOME/default/openharmony"
    else
        for candidate in \
            "$HOME/AppData/Local/Huawei/Sdk/default/openharmony" \
            "/d/Program Files/Huawei/DevEco Studio/sdk/default/openharmony" \
            "/c/Users/${USERNAME:-${USER:-}}/AppData/Local/Huawei/Sdk/default/openharmony"; do
            if [ -d "$candidate" ]; then
                SDK_PATH_RAW="$candidate"
                break
            fi
        done
    fi

    if [ -z "${SDK_PATH_RAW:-}" ]; then
        echo "ERROR: Cannot find HarmonyOS SDK. Set OHOS_SDK_HOME environment variable."
        exit 1
    fi

    if command -v cygpath &>/dev/null; then
        SDK_PATH="$(cygpath -w "$SDK_PATH_RAW" 2>/dev/null || echo "$SDK_PATH_RAW")"
    else
        SDK_PATH="$SDK_PATH_RAW"
    fi
    export OPENHARMONY_SDK_PATH="$SDK_PATH"

    # ---- Build profiles ----
    declare -A PROFILE_NAME PROFILE_TARGET PROFILE_DEBUG PROFILE_OPTIMIZE PROFILE_DEV

    PROFILE_NAME["debug"]="Debug"
    PROFILE_TARGET["debug"]="editor"
    PROFILE_DEBUG["debug"]="yes"
    PROFILE_OPTIMIZE["debug"]="none"
    PROFILE_DEV["debug"]="no"

    PROFILE_NAME["release-debug"]="Release-Debug"
    PROFILE_TARGET["release-debug"]="editor"
    PROFILE_DEBUG["release-debug"]="yes"
    PROFILE_OPTIMIZE["release-debug"]="speed"
    PROFILE_DEV["release-debug"]="no"

    PROFILE_NAME["release"]="Release"
    PROFILE_TARGET["release"]="template_release"
    PROFILE_DEBUG["release"]="no"
    PROFILE_OPTIMIZE["release"]="speed"
    PROFILE_DEV["release"]="no"

    local TARGET="${PROFILE_TARGET[$PROFILE]}"
    local DEBUG_SYMBOLS="${PROFILE_DEBUG[$PROFILE]}"
    local OPTIMIZE="${PROFILE_OPTIMIZE[$PROFILE]}"
    local DEV_BUILD="${PROFILE_DEV[$PROFILE]}"

    # Detect existing .so for size comparison
    local SO_FILE="$PROJECT_ROOT/bin/openharmony_editor_arm64-v8a.so"
    local SO_SIZE_BEFORE=""
    if [ -f "$SO_FILE" ]; then
        SO_SIZE_BEFORE=$(stat -c%s "$SO_FILE" 2>/dev/null || echo 0)
    fi

    local TOTAL_STEPS=3
    if $EXPORT_TEMPLATE; then
        TOTAL_STEPS=4
    fi

    echo ""
    echo "========================================="
    echo "  Build Configuration"
    echo "========================================="
    echo "  Project:      harmonyos-godot"
    echo "  Profile:      ${PROFILE_NAME[$PROFILE]}"
    echo "  Target:       ${TARGET}"
    echo "  Debug symbols: ${DEBUG_SYMBOLS}"
    echo "  Optimization: ${OPTIMIZE}"
    echo "  Vulkan:       ${RENDER_VULKAN}"
    echo "  GLES3:        ${RENDER_GLES3}"
    echo "  Parallel jobs: ${JOBS}"
    echo "  SDK:          ${SDK_PATH}"
    echo "========================================="
    echo ""

    local SCONS_ARGS=(
        "platform=openharmony"
        "target=${TARGET}"
        "debug_symbols=${DEBUG_SYMBOLS}"
        "optimize=${OPTIMIZE}"
        "dev_build=${DEV_BUILD}"
        "vulkan=${RENDER_VULKAN}"
        "ohos_opengl3=${RENDER_GLES3}"
        "-j${JOBS}"
        "OPENHARMONY_SDK_PATH=${SDK_PATH}"
        "module_zip_enabled=yes"
    )

    # Step 1: Build engine .so
    echo "[1/$TOTAL_STEPS] Building engine .so..."
    echo "  scons ${SCONS_ARGS[*]}"
    echo ""

    cd "$PROJECT_ROOT"
    local START_TIME=$(date +%s)
    python -m SCons "${SCONS_ARGS[@]}"
    local BUILD_TIME=$(($(date +%s) - START_TIME))
    echo ""
    echo "  Build finished in ${BUILD_TIME}s"

    # Locate output .so
    if [ "$TARGET" = "template_release" ]; then
        local SO_PATTERNS=(
            "$PROJECT_ROOT/bin/openharmony_release_arm64-v8a.so"
            "$PROJECT_ROOT/bin/openharmony_template_release_arm64-v8a.so"
            "$PROJECT_ROOT/bin/libgodot*arm64*.so"
        )
    else
        local SO_PATTERNS=(
            "$PROJECT_ROOT/bin/openharmony_editor_arm64-v8a.so"
            "$PROJECT_ROOT/bin/libgodot.openharmony.editor.arm64-v8a.so"
            "$PROJECT_ROOT/bin/openharmony_template_debug_arm64-v8a.so"
            "$PROJECT_ROOT/bin/libgodot*arm64*.so"
        )
    fi

    SO_FILE=""
    for pattern in "${SO_PATTERNS[@]}"; do
        for f in $pattern; do
            if [ -f "$f" ]; then
                SO_FILE="$f"
                break 2
            fi
        done
    done

    if [ -z "$SO_FILE" ]; then
        echo "ERROR: Could not find built .so file."
        ls -la "$PROJECT_ROOT/bin/"*.so 2>/dev/null || echo "  (no .so files found)"
        exit 1
    fi

    local SO_SIZE=$(stat -c%s "$SO_FILE" 2>/dev/null || echo 0)
    local SO_SIZE_MB=$(echo "scale=1; ${SO_SIZE} / 1048576" | bc 2>/dev/null || echo "?")
    echo "  Built: $(basename "$SO_FILE") (${SO_SIZE_MB} MB)"

    # Step 2: Copy .so to template
    echo ""
    echo "[2/$TOTAL_STEPS] Copying libgodot.so to template..."
    local TEMPLATE_LIBS="$PROJECT_ROOT/platform/openharmony/template/entry/libs/arm64-v8a"
    mkdir -p "$TEMPLATE_LIBS"
    cp "$SO_FILE" "$TEMPLATE_LIBS/libgodot.so"
    echo "  Copied → $TEMPLATE_LIBS/libgodot.so"

    # Step 3: Copy bridge header
    echo ""
    echo "[3/$TOTAL_STEPS] Copying bridge header to template..."
    local TEMPLATE_INCLUDE="$PROJECT_ROOT/platform/openharmony/template/entry/src/main/cpp/include"
    mkdir -p "$TEMPLATE_INCLUDE"
    cp "$PROJECT_ROOT/platform/openharmony/bridge_openharmony.h" "$TEMPLATE_INCLUDE/napi_bridge.h"
    cp "$PROJECT_ROOT/platform/openharmony/platform_config.h" "$TEMPLATE_INCLUDE/platform_config.h"
    echo "  Copied bridge headers → $TEMPLATE_INCLUDE/"

    # Step 4: Export template zip (optional)
    if $EXPORT_TEMPLATE; then
        echo ""
        echo "[4/$TOTAL_STEPS] Packaging export template zip..."
        local TEMPLATE_DIR="$PROJECT_ROOT/platform/openharmony/template"
        local RAWFILE_DIR="$TEMPLATE_DIR/entry/src/main/resources/rawfile"
        local TEMPLATE_ZIP="$RAWFILE_DIR/openharmony_debug_arm64-v8a.zip"
        mkdir -p "$RAWFILE_DIR"
        rm -f "$TEMPLATE_ZIP" "$RAWFILE_DIR/openharmony_release_arm64-v8a.zip"
        cd "$TEMPLATE_DIR"
        7z a -tzip "$TEMPLATE_ZIP" . -xr!.hvigor/ -xr!.idea/ -xr!entry/build/ -xr!entry/.cxx/ -xr!oh_modules/ -xr!openspec/ -xr!entry/src/main/resources/rawfile/*.zip >/dev/null
        local ZIP_SIZE=$(stat -c%s "$TEMPLATE_ZIP" 2>/dev/null || echo 0)
        echo "  Created: $TEMPLATE_ZIP ($(( ZIP_SIZE / 1024 )) KB)"
        cp "$TEMPLATE_ZIP" "$RAWFILE_DIR/openharmony_release_arm64-v8a.zip"
        cd "$PROJECT_ROOT"
    fi

    # Done
    echo ""
    echo "========================================="
    echo "  Build Complete!"
    echo "========================================="
    echo "  Profile:    ${PROFILE_NAME[$PROFILE]}"
    echo "  SO:         $(basename "$SO_FILE") (${SO_SIZE_MB} MB)"
    echo "  Build time: ${BUILD_TIME}s"
    echo ""

    if [ -n "${SO_SIZE_BEFORE:-}" ] && [ "$SO_SIZE_BEFORE" != "0" ]; then
        local SIZE_DIFF=$(( SO_SIZE - SO_SIZE_BEFORE ))
        local SIZE_DIFF_MB=$(( SIZE_DIFF / 1048576 ))
        echo "  Size delta: ${SIZE_DIFF_MB} MB"
    fi
    echo ""
}

# ============================================================
#  Clean — remove SCons build artifacts
# ============================================================
do_clean() {
    echo ""
    echo "========================================="
    echo "  Cleaning build artifacts"
    echo "========================================="
    echo "  Removing SCons cache and build outputs..."
    echo ""

    cd "$PROJECT_ROOT"
    python -m SCons --clean platform=windows target=editor tests=yes accesskit=no d3d12=no angle=no 2>/dev/null || true
    python -m SCons --clean platform=openharmony target=editor 2>/dev/null || true

    # Also clean any leftover .sconsign.dblite cache
    rm -f "$PROJECT_ROOT/.sconsign.dblite" 2>/dev/null || true
    rm -rf "$PROJECT_ROOT/bin/obj/" 2>/dev/null || true

    echo ""
    echo "  ✅ Clean complete."
    echo ""
}

# ============================================================
#  Main — Argument Dispatch
# ============================================================

case "${1:-}" in
    "" )
        # No args → default: OHOS release-debug
        do_ohos_build "release-debug"
        exit 0
        ;;
    gui|menu )
        show_gui_menu
        exit 0
        ;;
    -h|--help|help )
        show_help
        exit 0
        ;;
    clean )
        do_clean
        exit 0
        ;;
    test )
        do_test_build "yes"
        exit 0
        ;;
    windows-editor|win-editor )
        do_test_build "no"
        exit 0
        ;;
    debug|release-debug|release )
        do_ohos_build "$1"
        exit 0
        ;;
    * )
        case "$1" in
            1) do_ohos_build "debug"; exit 0 ;;
            2) do_ohos_build "release-debug"; exit 0 ;;
            3) do_ohos_build "release"; exit 0 ;;
            *)
                echo "ERROR: Unknown argument '$1'"
                echo "Usage: $0 [gui|clean|test|windows-editor|debug|release-debug|release|--help]"
                echo "       $0  (no args → default: OHOS release-debug)"
                exit 1
                ;;
        esac
        ;;
esac

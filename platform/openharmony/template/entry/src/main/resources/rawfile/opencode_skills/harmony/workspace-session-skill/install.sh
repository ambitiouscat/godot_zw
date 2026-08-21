#!/bin/bash
# Workspace Session Skill - Cross-Platform Symlink Installer
# Usage: ./install.sh [--platform PLATFORM] [--all] [--uninstall] [--dry-run]
#
# This script creates symbolic links from agent plugin directories to this skill.
# Benefits: Single source of truth, updates automatically propagate to all agents.

SKILL_NAME="workspace"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
PLATFORM=""
DRY_RUN=false
INSTALL_ALL=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --all)
            INSTALL_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --platform PLATFORM  Install to specific platform"
            echo "  --all                Install to all detected platforms"
            echo "  --uninstall          Remove symlinks"
            echo "  --dry-run            Show what would be done"
            echo "  -h, --help           Show this help"
            echo ""
            echo "Platforms: claude-code, cursor, opencode, codex, gemini"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Platform definitions
# Format: "name|plugin_dir|symlink_path"
get_platform_config() {
    local platform=$1
    case $platform in
        claude-code)
            echo "claude-code|$HOME/.claude/plugins|$HOME/.claude/plugins/$SKILL_NAME"
            ;;
        cursor)
            echo "cursor|$HOME/.cursor/plugins|$HOME/.cursor/plugins/$SKILL_NAME"
            ;;
        opencode)
            echo "opencode|$HOME/.config/opencode/skills|$HOME/.config/opencode/skills/$SKILL_NAME"
            ;;
        codex)
            echo "codex|$HOME/.agents/skills|$HOME/.agents/skills/$SKILL_NAME"
            ;;
        gemini)
            echo "gemini|$HOME/.gemini/skills|$HOME/.gemini/skills/$SKILL_NAME"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Detect installed platforms
detect_platforms() {
    local platforms=()
    [[ -d "$HOME/.claude" ]] && platforms+=("claude-code")
    [[ -d "$HOME/.cursor" ]] && platforms+=("cursor")
    [[ -d "$HOME/.config/opencode" ]] && platforms+=("opencode")
    [[ -d "$HOME/.gemini" ]] && platforms+=("gemini")
    # Codex uses .agents which always exists
    platforms+=("codex")
    echo "${platforms[@]}"
}

# Detect Windows
is_windows() {
    [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]
}

# Convert Unix path to Windows path
to_windows_path() {
    local unix_path=$1
    if command -v cygpath &>/dev/null; then
        cygpath -w "$unix_path"
    else
        echo "$unix_path" | sed 's|^/\([a-z]\)/|\U\1:/|' | sed 's|/|\\|g'
    fi
}

# Create symlink (cross-platform)
create_symlink() {
    local platform=$1
    local config=$(get_platform_config "$platform")

    if [[ -z "$config" ]]; then
        echo -e "${RED}✗${NC} Unknown platform: $platform"
        return 1
    fi

    IFS='|' read -r name plugin_dir symlink_path <<< "$config"

    if [ "$DRY_RUN" = true ]; then
        if [ "$UNINSTALL" = true ]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would remove: $symlink_path"
        else
            echo -e "${YELLOW}[DRY-RUN]${NC} Would create: $symlink_path -> $SCRIPT_DIR"
        fi
        return 0
    fi

    # Create plugin directory if needed
    if [[ ! -d "$plugin_dir" ]]; then
        mkdir -p "$plugin_dir" 2>/dev/null
        echo -e "${BLUE}ℹ${NC} Created directory: $plugin_dir"
    fi

    # Remove existing symlink or directory
    if [[ -L "$symlink_path" ]] || [[ -d "$symlink_path" ]]; then
        if [ "$UNINSTALL" = true ]; then
            rm -rf "$symlink_path"
            echo -e "${GREEN}✓${NC} Removed: $symlink_path"
            return 0
        else
            rm -rf "$symlink_path" 2>/dev/null
            echo -e "${BLUE}ℹ${NC} Removed existing: $symlink_path"
        fi
    fi

    if [ "$UNINSTALL" = true ]; then
        echo -e "${GREEN}✓${NC} Uninstalled from: $name"
        return 0
    fi

    # Create symlink (platform-specific)
    if is_windows; then
        # Windows: use PowerShell Junction
        local win_target=$(cygpath -w "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR" | sed 's|^/\([a-z]\)/|\U\1:/|' | sed 's|/|\\|g')
        local win_link=$(cygpath -w "$symlink_path" 2>/dev/null || echo "$symlink_path" | sed 's|^/\([a-z]\)/|\U\1:/|' | sed 's|/|\\|g')
        if powershell -Command "New-Item -ItemType Junction -Path '$win_link' -Target '$win_target' -Force" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Installed to $name: $symlink_path"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to create junction: $symlink_path"
            return 1
        fi
    else
        # Unix: use ln -s
        if ln -s "$SCRIPT_DIR" "$symlink_path" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Installed to $name: $symlink_path"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to create symlink: $symlink_path"
            return 1
        fi
    fi
}

# Register plugin in installed_plugins.json (Claude Code only)
register_plugin() {
    local plugin_name="workspace@local"
    local install_path="$HOME/.claude/plugins/$SKILL_NAME"
    local installed_plugins="$HOME/.claude/plugins/installed_plugins.json"

    if [[ ! -f "$installed_plugins" ]]; then
        return 0
    fi

    # Check if already registered
    if grep -q "\"workspace@local\"" "$installed_plugins" 2>/dev/null; then
        echo -e "${BLUE}ℹ${NC} Plugin already registered in installed_plugins.json"
        return 0
    fi

    # Get version from plugin.json
    local version="4.1.0"
    if [[ -f "$SCRIPT_DIR/.claude-plugin/plugin.json" ]]; then
        version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$SCRIPT_DIR/.claude-plugin/plugin.json" | head -1 | cut -d'"' -f4)
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local win_path=$(cygpath -w "$install_path" 2>/dev/null || echo "$install_path")

    # Add entry using node for JSON manipulation
    node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$installed_plugins', 'utf8'));
data.plugins['workspace@local'] = [{
    scope: 'user',
    installPath: '$win_path'.replace(/\//g, '\\\\'),
    version: '$version',
    installedAt: '$timestamp',
    lastUpdated: '$timestamp'
}];
fs.writeFileSync('$installed_plugins', JSON.stringify(data, null, 2));
" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} Registered in installed_plugins.json"
    else
        echo -e "${YELLOW}!${NC} Could not register in installed_plugins.json"
    fi
}

# Unregister plugin from installed_plugins.json
unregister_plugin() {
    local installed_plugins="$HOME/.claude/plugins/installed_plugins.json"

    if [[ ! -f "$installed_plugins" ]]; then
        return 0
    fi

    node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$installed_plugins', 'utf8'));
delete data.plugins['workspace@local'];
fs.writeFileSync('$installed_plugins', JSON.stringify(data, null, 2));
" 2>/dev/null

    echo -e "${GREEN}✓${NC} Unregistered from installed_plugins.json"
}

# Main
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Workspace Session Skill - Symlink Installer v4.1.0"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo -e "Source: ${BLUE}$SCRIPT_DIR${NC}"
    echo ""

    local platforms=()

    if [ "$INSTALL_ALL" = true ]; then
        platforms=("claude-code" "cursor" "opencode" "codex" "gemini")
    elif [ -n "$PLATFORM" ]; then
        platforms=("$PLATFORM")
    else
        # Auto-detect
        platforms=$(detect_platforms)
        echo -e "Detected platforms: ${BLUE}${platforms}${NC}"
        echo ""
    fi

    if [ "$UNINSTALL" = true ]; then
        echo -e "${YELLOW}Uninstall mode${NC}"
    fi
    echo ""

    local success=0
    local failed=0

    for p in $platforms; do
        if create_symlink "$p"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    # Register/unregister for Claude Code
    if [[ " $platforms " =~ " claude-code " ]] || [[ -z "$PLATFORM" && -d "$HOME/.claude" ]]; then
        if [ "$UNINSTALL" = true ]; then
            unregister_plugin
        elif [ "$success" -gt 0 ]; then
            register_plugin
        fi
    fi

    echo ""
    echo "───────────────────────────────────────────────────────────────"

    if [ "$UNINSTALL" = true ]; then
        echo -e "Uninstalled from ${GREEN}$success${NC} platform(s)"
    else
        echo -e "Installed to ${GREEN}$success${NC} platform(s), ${RED}$failed${NC} failed"
    fi

    if [ "$failed" -gt 0 ]; then
        echo ""
        echo "Tip: Use --dry-run to preview actions"
    fi

    echo "═══════════════════════════════════════════════════════════════"

    if [ "$UNINSTALL" != true ] && [ "$success" -gt 0 ]; then
        echo ""
        echo "Usage:"
        echo "  /workspace start        # 开始工作会话"
        echo "  /workspace save         # 保存进度"
        echo "  /workspace continue     # 继续上次会话"
        echo "  /workspace end          # 结束工作会话"
        echo ""
        echo "Natural language: 开始工作、保存工作、继续工作、结束工作"
        echo ""
        echo "Configuration: ~/.claude/skills_settings.json"
        echo ""
        echo -e "${YELLOW}Note: Restart Claude Code for hooks to take effect${NC}"
        echo "═══════════════════════════════════════════════════════════════"
    fi
}

main
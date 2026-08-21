# workspace-session-skill

A workspace session management skill for AI Agents to persist work state, record key conversations, and track task progress across sessions.

## Features

- 🔄 **Cross-session State Persistence** - Seamlessly continue work in new sessions
- 📝 **Smart Note Management** - Three-tier structure: daily notes, task notes, project notes
- 📊 **Project Overview Notes** - Local Markdown project progress tracking
- 🔗 **Bidirectional References** - Jump between task notes and project notes
- ⏰ **Auto-save** - Cron-based automatic progress saving
- 🖥️ **Multi-Agent Support** - Claude Code, Cursor, Gemini CLI, OpenCode, etc.
- 📦 **Dual Storage Mode** - Trilium MCP / Local Markdown fallback

## Quick Start

### Installation

```bash
# Clone to skill directory
git clone https://gitee.com/ambitiouscat/workspace-session-skill.git \
  ~/.claude/skills/workspace-session-skill

# Or use install script
cd workspace-session-skill
./install.sh
```

### Configuration

Use `skills_settings.json` (same directory as settings.json):

```json
{
  "workspaceSession": {
    "daily_notes": {
      "root": "trilium:YOUR_NOTE_ID",
      "root_path": "#root/path/to/note"
    },
    "project_notes": {
      "root": "trilium:YOUR_NOTE_ID",
      "root_path": "#root/path/to/note"
    }
  }
}
```

**Configuration Location**:
1. `~/.agents/skills_settings.json` ← **Single source of truth**
2. `.workspace-session-skill/config.json` ← Project local (auto-sync)

> **Local Config Sync**: When starting work, configuration is automatically synced to the project's `.workspace-session-skill/config.json`.

Without configuration, local path `.workspace-session-skill/notes/` is used automatically.

### Usage

```
/workspace start            # Start work session (ask project/simple task)
/workspace save             # Save current progress
/workspace continue         # Continue previous session
/workspace new-task name    # Create task note
/workspace status           # Show session status
/workspace end              # End work session
```

Natural language: `开始工作`, `保存工作`, `继续工作`, `结束工作`

## Documentation Structure

```
workspace-session-skill/
├── skill.md                    # Core skill definition (concise)
├── settings.json               # Configuration template
├── skills_settings.json.example # Configuration example
├── commands/
│   └── workspace.md            # Slash command definition
├── references/                 # Detailed reference docs
│   ├── README.md               # Documentation navigation
│   ├── configuration.md        # Configuration management
│   ├── workflow.md             # Workflow details
│   ├── notes-management.md     # Notes management
│   ├── session-format.md       # Session file format
│   ├── autosave.md             # Auto-save mechanism
│   ├── trilium-integration.md  # Trilium integration
│   ├── project-overview.md     # Project overview notes
│   └── flowcharts.md           # Flowcharts
```

## Reference Documentation

Start from `references/README.md`, read as needed:

| Document | Purpose |
|----------|---------|
| configuration.md | Configuration management details |
| workflow.md | Detailed workflow steps |
| notes-management.md | Notes hierarchy and management |
| flowcharts.md | Visual flowcharts |

## Version

See [CHANGELOG.md](CHANGELOG.md)

## License

MIT License
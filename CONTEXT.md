# Domain Model & Context (GDAI / Godot HarmonyOS)

## Overview
GDAI is an integrated Godot 4.7 Game Engine and AI Assistant platform for HarmonyOS NEXT, providing live MCP editor tooling, GDScript 2.0 type-safe code generation, and multi-skill agent workflows.

## Core Concepts
- **Editor Ability**: The native HarmonyOS UIAbility hosting Godot editor and embedded Webview.
- **MCP Gateway**: In-engine WebSocket MCP server (port 6510) providing live scene inspection, node creation, property modification, and project execution.
- **OpenCode Formal Runtime**: On-device Node.js runtime executing subagents, skill loaders, and AI developer workflows.
- **GGD-Protocol (v1)**: The 6-stage lifecycle for Godot game generation and diagnostics.

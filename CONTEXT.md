# Domain Model & Context (GDAI / Godot HarmonyOS)

## Overview
GDAI is an integrated Godot 4.7 Game Engine and AI Assistant platform for HarmonyOS NEXT, providing live MCP editor tooling, GDScript 2.0 type-safe code generation, and multi-skill agent workflows.

## Language

**Real Run**:
A complete game execution whose gameplay scripts, engine services, input, rendering, and lifecycle behave as they do outside the editor, independent of how its output is presented.
_Avoid_: Simulation, runtime preview, real simulation

**Run Presentation**:
The system-managed way a Real Run is shown to the developer, such as floating, split-screen, or fullscreen.
_Avoid_: Run mode, simulation mode

**Floating Real Run**:
A Real Run presented in a separate resizable window while the editor remains visible.
_Avoid_: Embedded Game View, floating simulation

**Split Real Run**:
A Real Run presented alongside the editor using the device's split-screen window arrangement.
_Avoid_: Embedded run, split simulation

**Windowed Real Run**:
An AI-safe Run Presentation policy that keeps the editor visible by selecting a supported non-fullscreen presentation and fails when none is available.
_Avoid_: Window, auto run, fullscreen fallback

**Embedded Game View**:
A Real Run whose independently executing game surface is hosted inside the editor's Game View region.
_Avoid_: SubViewport simulation, viewport preview

**Run Session**:
One identity-correlated lifecycle of a Real Run, from its start request through readiness, execution, and termination.
_Avoid_: Window instance, process flag

**Presentation Capability**:
Runtime-confirmed support for a Run Presentation on the current device and system configuration.
_Avoid_: Manifest declaration, assumed platform support

**Authoritative Game Capture**:
An image captured from the active Real Run's root game viewport and correlated to its Run Session.
_Avoid_: Editor screenshot, window screenshot, fallback capture

## Core Concepts
- **Editor Ability**: The native HarmonyOS UIAbility hosting Godot editor and embedded Webview.
- **MCP Gateway**: In-engine WebSocket MCP server (port 6510) providing live scene inspection, node creation, property modification, and project execution.
- **OpenCode Formal Runtime**: On-device Node.js runtime executing subagents, skill loaders, and AI developer workflows.
- **GGD-Protocol (v1)**: The 6-stage lifecycle for Godot game generation and diagnostics.

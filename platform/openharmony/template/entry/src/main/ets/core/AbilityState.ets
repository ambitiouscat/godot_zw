/**************************************************************************/
/*  AbilityState.ets                                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

/**
 * Shared module-level state for ability mode and parameters.
 *
 * Because abilities run in separate processes via the `process` attribute,
 * each process has its own isolated copy of these module-level globals.
 * The active ability sets these via setters during onCreate(); BridgeCallbacks
 * reads them via getters before engine initialization.
 */
let g_godotMode: string = 'pm'
let g_projectPath: string | null = null
let g_restartArgs: string[] | null = null

/**
 * Correlation envelope for one authoritative GameAbility launch.
 *
 * This module is process-local by design.  EditorAbility records the envelope
 * while launching GameAbility; GameAbility reconstructs the same envelope from
 * its Want parameters before it reports lifecycle events back to EditorAbility.
 */
export interface RuntimeLaunchMetadata {
  sessionId: string
  operationId: string
  bootNonce: string
}

let g_runtimeLaunchMetadata: RuntimeLaunchMetadata | null = null

export function setGodotMode(mode: string): void {
  g_godotMode = mode
}

export function getGodotMode(): string {
  return g_godotMode
}

export function setProjectPath(path: string | null): void {
  g_projectPath = path
}

export function getProjectPath(): string | null {
  return g_projectPath
}

export function setRestartArgs(args: string[] | null): void {
  g_restartArgs = args
}

export function getRestartArgs(): string[] | null {
  return g_restartArgs
}

export function setRuntimeLaunchMetadata(sessionId: string, operationId: string, bootNonce: string): void {
  g_runtimeLaunchMetadata = {
    sessionId: sessionId,
    operationId: operationId,
    bootNonce: bootNonce
  }
}

export function getRuntimeLaunchMetadata(): RuntimeLaunchMetadata | null {
  return g_runtimeLaunchMetadata
}

export function clearRuntimeLaunchMetadata(): void {
  g_runtimeLaunchMetadata = null
}

// Track whether Editor has launched GameAbility.
// Used by onForeground() fallback to detect if Game was running before
// Editor was backgrounded (e.g., when user X-closes Game window).
let g_gameLaunched: boolean = false

export function setGameLaunched(launched: boolean): void {
  g_gameLaunched = launched
}

export function isGameLaunched(): boolean {
  return g_gameLaunched
}

/**************************************************************************/
/*  EditorAbility.ets                                                      */
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

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import plugin from 'libentry.so';
import { Logger } from '../core/Logger';
import { setGodotMode, setProjectPath, setRestartArgs, setGameLaunched } from '../core/AbilityState';
import { BridgeCallbacks } from '../core/BridgeCallbacks';
import { GodotMcpInstaller } from '../core/GodotMcpInstaller';
import { GodotMcpServerGateway } from '../core/GodotMcpServerGateway';

const logger = new Logger('EditorAbility')

export default class EditorAbility extends UIAbility {

  // Shared reset logic — idempotent via C++ atomic flag
  private resetEditorRunState(): void {
    setGameLaunched(false)
    try {
      plugin.resetEditorRunState();
      logger.info('Editor run state reset');
    } catch (e) {
      logger.error('resetEditorRunState failed', e);
    }
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (e) {
      logger.error('Failed to set color mode', e);
    }
    logger.info('Ability onCreate');

    // Start Godot MCP gateway hub on 6510
    void GodotMcpServerGateway.getInstance().start(6510);

    // Default mode: editor
    setGodotMode('editor');

    // Game death detection is handled by startAbilityForResult in BridgeCallbacks.ets.
    // Layer 2 (onForeground) and Layer 3 (onNewWant) provide fallback coverage.

    // Read Want parameters from launching intent
    if (want.parameters) {
      let targetProj: string | null = null;
      if (want.parameters['projectPath']) {
        targetProj = want.parameters['projectPath'] as string;
        setProjectPath(targetProj);
        logger.info('Project path received', targetProj);
      }
      if (want.parameters['restartArgs']) {
        const args = want.parameters['restartArgs'] as string[];
        setRestartArgs(args);
        logger.info('Restart args received');
        if (!targetProj) {
          const pathIdx = args.indexOf('--path');
          if (pathIdx >= 0 && pathIdx + 1 < args.length) {
            targetProj = args[pathIdx + 1];
          }
        }
      } else if (targetProj) {
        setRestartArgs(['--rendering-driver', 'opengl3', '--path', targetProj, '--editor']);
        logger.info('Generated default restartArgs for project', targetProj);
      }
      if (targetProj) {
        void GodotMcpInstaller.ensureInstalled(this.context, targetProj);
      }
      if (want.parameters['godotMode']) {
        setGodotMode(want.parameters['godotMode'] as string);
        logger.info('Godot mode override', want.parameters['godotMode'] as string);
      }
    }
  }

  onDestroy(): void {
    logger.info('Ability onDestroy');
    void GodotMcpServerGateway.getInstance().stop();
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    logger.info('Ability onNewWant');
    if (want.parameters) {
      // Layer 3: Best-effort notification from GameAbility (onWindowStageDestroy)
      if (want.parameters['gameDied']) {
        logger.info('GameAbility death notification via onNewWant — resetting editor run state');
        this.resetEditorRunState();
        return;
      }
      if (want.parameters['godotMode']) {
        setGodotMode(want.parameters['godotMode'] as string);
        logger.info('Godot mode restored in onNewWant', want.parameters['godotMode'] as string);
      }
      if (want.parameters['restartArgs']) {
        setRestartArgs(want.parameters['restartArgs'] as string[]);
        logger.info('Restart args restored in onNewWant');
      }
    }
  }

  onForeground(): void {
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    logger.info('Ability onBackground');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Ability onWindowStageCreate');

    try {
      windowStage.on('windowStageEvent', (data) => {
        plugin.sendWindowEvent(data);
      });
    } catch (e) {
      logger.error('Failed to register window stage event', e);
    }

    windowStage.loadContent('pages/GameWindow', (err) => {
      if (err.code) {
        logger.error('Failed to load the content', err);
        return;
      }
      logger.info('Succeeded in loading the content.');
      try {
        const win = windowStage.getMainWindowSync()
        BridgeCallbacks.mainWindow = win
        const deviceType = deviceInfo.deviceType
        if (canIUse('SystemCapability.Window.SessionManager')) {
          if (deviceType === '2in1') {
            win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).then(() => {
              logger.info('Maximized for 2in1')
            }).catch((e: Error) => {
              logger.error('Failed to maximize window', e);
            })
          } else if (deviceType === 'phone' || deviceType === 'tablet') {
            win.setWindowLayoutFullScreen(true).catch((e: Error) => {
              logger.error('Failed to set full screen', e);
            })
            win.setSpecificSystemBarEnabled('status', false).catch((e: Error) => {
              logger.error('Failed to set status bar', e);
            })
            win.setSpecificSystemBarEnabled('navigationIndicator', false).catch((e: Error) => {
              logger.error('Failed to set nav indicator', e);
            })
          } else {
            logger.error('Do not support this device type');
          }
        }
      } catch (e) {
        logger.error('Failed to set window properties', e);
      }
    });
  }

  onWindowStageDestroy(): void {
    logger.info('Ability onWindowStageDestroy');
  }
}

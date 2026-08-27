/**************************************************************************/
/*  GameAbility.ets                                                        */
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
import {
  clearRuntimeLaunchMetadata,
  getGodotMode,
  getRuntimeLaunchMetadata,
  setGodotMode,
  setProjectPath,
  setRestartArgs,
  setRuntimeLaunchMetadata
} from '../core/AbilityState';
import { BridgeCallbacks } from '../core/BridgeCallbacks';
import { GodotMcpInstaller } from '../core/GodotMcpInstaller';
import { GodotMcpServerGateway } from '../core/GodotMcpServerGateway';

const logger = new Logger('GameAbility')

export default class GameAbility extends UIAbility {
  private async acknowledgeStopAndTerminate(): Promise<void> {
    const acknowledged = await BridgeCallbacks.publishGameRuntimeLifecycle('REAL_STOP_ACK', 'editor_stop_requested');
    if (!acknowledged) {
      // Do not terminate before the only correlated stop acknowledgement has
      // reached the editor loopback gateway. The caller can retry stop; the
      // startAbilityForResult fallback still covers an external process kill.
      logger.error('GameAbility stop acknowledgement was not delivered; refusing to terminate');
      return;
    }
    try {
      // EditorAbility launches us with startAbilityForResult(). Pair that API
      // with terminateSelfWithResult() so the editor receives an OS-confirmed
      // completion and can publish the authoritative REAL_EXIT event.
      await this.context.terminateSelfWithResult({ resultCode: 0 });
    } catch (e) {
      logger.error('Failed to terminate GameAbility after stop acknowledgement', e);
    }
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (e) {
      logger.error('Failed to set color mode', e);
    }
    logger.info('Ability onCreate');

    // Default mode: game
    setGodotMode('game');
    clearRuntimeLaunchMetadata();
    BridgeCallbacks.resetGameLifecycleReadiness();

    // Read Want parameters from launching intent
    if (want.parameters) {
      if (want.parameters['projectPath']) {
        const projectPath = want.parameters['projectPath'] as string;
        setProjectPath(projectPath);
        logger.info('Project path received', projectPath);
        void GodotMcpInstaller.ensureInstalled(this.context, projectPath);
      }
      if (want.parameters['restartArgs']) {
        setRestartArgs(want.parameters['restartArgs'] as string[]);
        logger.info('Restart args received');
      }
      if (want.parameters['godotMode']) {
        setGodotMode(want.parameters['godotMode'] as string);
        logger.info('Godot mode override', want.parameters['godotMode'] as string);
      }
      const sessionId = String(want.parameters['session_id'] || '');
      const operationId = String(want.parameters['operation_id'] || '');
      const bootNonce = String(want.parameters['boot_nonce'] || '');
      if (sessionId.length > 0 && operationId.length > 0 && bootNonce.length > 0) {
        setRuntimeLaunchMetadata(sessionId, operationId, bootNonce);
        logger.info(`Authoritative runtime correlation received for session ${sessionId}`);
      } else {
        logger.warn('GameAbility started without an authoritative runtime correlation envelope');
      }
    }

    // Start Godot MCP Gateway for Editor mode
    if (getGodotMode() === 'editor') {
      void GodotMcpServerGateway.getInstance().start(6510);
    }
  }

  onDestroy(): void {
    logger.info('Ability onDestroy');
    void GodotMcpServerGateway.getInstance().stop();
    setGodotMode('pm');
    setProjectPath(null);
    setRestartArgs(null);
    clearRuntimeLaunchMetadata();
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    logger.info('Ability onNewWant');
    if (want.parameters) {
      // Handle kill signal from Editor
      if (want.parameters['key'] === 'kill') {
        const metadata = getRuntimeLaunchMetadata();
        const requestedSession = String(want.parameters['session_id'] || '');
        const requestedOperation = String(want.parameters['operation_id'] || '');
        const requestedNonce = String(want.parameters['boot_nonce'] || '');
        if (!metadata || requestedSession !== metadata.sessionId ||
            requestedOperation !== metadata.operationId || requestedNonce !== metadata.bootNonce) {
          logger.error('Ignored uncorrelated or stale GameAbility kill request');
          return;
        }
        logger.info('Kill signal received, terminating GameAbility');
        void this.acknowledgeStopAndTerminate();
        return;
      }
      if (want.parameters['projectPath']) {
        setProjectPath(want.parameters['projectPath'] as string);
        logger.info('New project path received in onNewWant', want.parameters['projectPath'] as string);
      }
      if (want.parameters['restartArgs']) {
        setRestartArgs(want.parameters['restartArgs'] as string[]);
        logger.info('New restart args received in onNewWant');
      }
      if (want.parameters['godotMode']) {
        setGodotMode(want.parameters['godotMode'] as string);
        logger.info('Godot mode updated in onNewWant', want.parameters['godotMode'] as string);
      }
    }
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
          if (deviceType === 'phone' || deviceType === 'tablet') {
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
    // This event has the full session envelope and is the primary normal-exit
    // signal. startAbilityForResult remains the crash/system-kill fallback.
    void BridgeCallbacks.publishGameRuntimeLifecycle('REAL_EXIT', 'window_stage_destroyed');
  }

  onForeground(): void {
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    logger.info('Ability onBackground');
  }
}

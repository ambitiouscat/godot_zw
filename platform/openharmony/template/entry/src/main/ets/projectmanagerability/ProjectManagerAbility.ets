/**************************************************************************/
/*  ProjectManagerAbility.ets                                              */
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
import { setGodotMode, setProjectPath, setRestartArgs } from '../core/AbilityState';
import { BridgeCallbacks } from '../core/BridgeCallbacks';

const logger = new Logger('ProjectManagerAbility')

export default class ProjectManagerAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (e) {
      logger.error('Failed to set color mode', e);
    }
    logger.info('Ability onCreate');

    // Default mode: project manager
    setGodotMode('pm');

    // Read Want parameters from launching intent
    if (want.parameters) {
      if (want.parameters['projectPath']) {
        setProjectPath(want.parameters['projectPath'] as string);
        logger.info('Project path received', want.parameters['projectPath'] as string);
      }
      if (want.parameters['restartArgs']) {
        setRestartArgs(want.parameters['restartArgs'] as string[]);
        logger.info('Restart args received');
      }
      if (want.parameters['godotMode']) {
        setGodotMode(want.parameters['godotMode'] as string);
        logger.info('Godot mode received', want.parameters['godotMode'] as string);
      }
    }
  }

  onDestroy(): void {
    logger.info('Ability onDestroy');
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
        logger.info('PM window setup: deviceType=' + deviceType + ', canIUse= ' + canIUse('SystemCapability.Window.SessionManager'))
        if (canIUse('SystemCapability.Window.SessionManager')) {
          if (deviceType === '2in1') {
            win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).then(() => {
              logger.info('PM maximized for 2in1')
            }).catch((e: Error) => {
              logger.error('Failed to maximize PM window', e);
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

  onForeground(): void {
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    logger.info('Ability onBackground');
  }
}

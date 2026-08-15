import { common } from '@kit.AbilityKit';
import { Logger } from './Logger';

const logger = new Logger('GodotMcpInstaller');

export class GodotMcpInstaller {
  /**
   * Godot MCP addon is now virtually mounted in-memory via PackedData (Virtual Pack Source).
   * No physical files are written to the user's project directory (0 disk pollution).
   */
  static async ensureInstalled(_context: common.UIAbilityContext, _projectDir: string): Promise<boolean> {
    logger.info('Godot MCP addon is virtually mounted in-memory by engine (0 disk pollution)');
    return true;
  }
}

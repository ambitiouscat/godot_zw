import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Logger } from './Logger';

const logger = new Logger('PermissionManager')

export class PermissionManager {
  private context: common.UIAbilityContext

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  /**
   * Request permissions and return comma-separated list of granted permissions.
   * Reads the permission list from the "user_permissions" string resource.
   */
  async requestPermissions(): Promise<string> {
    let userPermissions: string;
    try {
      userPermissions =
        this.context.resourceManager.getStringSync($r("app.string.user_permissions").id);
    } catch (e) {
      logger.error('Failed to read user_permissions string', e);
      return "";
    }
    let permissionList: Array<Permissions> = [];
    userPermissions.split(",").forEach((value) => {
      permissionList.push(value.trim() as Permissions)
    })

    if (permissionList.length === 0) {
      return ""
    }

    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let data = await atManager.requestPermissionsFromUser(this.context, permissionList);
      let grantStatus: Array<number> = data.authResults;
      let allowed: Array<string> = []
      for (let i = 0; i < grantStatus.length; i++) {
        if (grantStatus[i] === 0) {
          allowed.push(permissionList[i])
        }
      }
      return allowed.join(",")
    } catch (e) {
      logger.error('Failed to request permissions', e)
      return ""
    }
  }
}

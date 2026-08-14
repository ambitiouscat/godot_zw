import { Environment } from '@kit.CoreFileKit';
import plugin from 'libentry.so';
import { Logger } from './Logger';

const logger = new Logger('StandardDirProvider')

/**
 * Injects standard directory paths as XDG environment variables.
 * Uses HarmonyOS Environment API on 2in1 (pre-authorized, no permission dialog).
 * On non-2in1 devices, gracefully leaves env vars unset.
 */
export function injectStandardDirs(): void {
  if (!canIUse('SystemCapability.FileManagement.File.Environment.FolderObtain')) {
    logger.info('Environment.FolderObtain not available on this device')
    return
  }

  try {
    const desktop = Environment.getUserDesktopDir()
    if (desktop.length > 0) {
      plugin.setEnv('XDG_DESKTOP_DIR', desktop)
      logger.info('XDG_DESKTOP_DIR=' + desktop)
    }
  } catch (e) {
    logger.warn('Desktop dir not available', e)
  }

  try {
    const documents = Environment.getUserDocumentDir()
    if (documents.length > 0) {
      plugin.setEnv('XDG_DOCUMENTS_DIR', documents)
      logger.info('XDG_DOCUMENTS_DIR=' + documents)
    }
  } catch (e) {
    logger.warn('Documents dir not available', e)
  }

  try {
    const downloads = Environment.getUserDownloadDir()
    if (downloads.length > 0) {
      plugin.setEnv('XDG_DOWNLOAD_DIR', downloads)
      logger.info('XDG_DOWNLOAD_DIR=' + downloads)
    }
  } catch (e) {
    logger.warn('Downloads dir not available', e)
  }
}

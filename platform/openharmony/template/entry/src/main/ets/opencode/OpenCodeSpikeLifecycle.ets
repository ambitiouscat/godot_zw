import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { OpenCodeFormalRuntimeController } from './OpenCodeFormalRuntimeController';
import type { OpenCodeFormalChangedPathDispatcher } from './OpenCodeFormalChangedPathDispatcher';
import type {
  OpenCodePanelNavigation,
  OpenCodePanelSessionController,
  OpenCodePanelSnapshot
} from './OpenCodePanelContract';
import {
  OPENCODE_HARMONY_BUILD_MODE,
  OPENCODE_HARMONY_ENABLED,
  OPENCODE_HARMONY_FORMAL_RUNTIME_SELECTED,
  OPENCODE_HARMONY_MINIMAL_RUNTIME,
  OPENCODE_HARMONY_RUNTIME_SELECTION
} from './OpenCodeSpikeBuildConfig';

const DOMAIN = 0x0000;
const COMPILE_SDK_VERSION = '6.1.0.105';
const COMPILE_SDK_API_VERSION = 23;
const TARGET_API_VERSION = 20;

export interface OpenCodeSpikeLifecycleSnapshot {
  enabled: boolean;
  buildMode: string;
  runtimeSelection: string;
  phase: string;
  foreground: boolean;
  controllerReady: boolean;
  errorCode: string;
  panel: OpenCodePanelSnapshot | undefined;
}

export class OpenCodeSpikeLifecycleError extends Error {
  readonly code: string;
  readonly phase: string;

  constructor(code: string, phase: string, message: string) {
    super(message);
    this.code = code;
    this.phase = phase;
  }
}

/**
 * Owns only the editor-side lifetime of the selected local runtime.
 *
 * Native controllers are dynamically imported after the build selection is
 * checked, so normal editor builds never evaluate either Native library.
 * Formal runtime startup remains lazy and is attached to the upstream panel
 * bootstrap without evaluating the rollback controller or native library.
 */
export class OpenCodeSpikeLifecycle {
  private static readonly INSTANCE: OpenCodeSpikeLifecycle = new OpenCodeSpikeLifecycle();
  private formalRuntimeController?: OpenCodeFormalRuntimeController;
  private formalChangedPathDispatcher?: OpenCodeFormalChangedPathDispatcher;
  private formalPanelUnsubscribe?: () => void;
  private panelController?: OpenCodePanelSessionController;
  private initialization?: Promise<void>;
  private destruction?: Promise<void>;
  private projectRoot: string = '';
  private phase: string = OPENCODE_HARMONY_ENABLED ? 'uninitialized' : 'disabled';
  private foreground: boolean = false;
  private errorCode: string = 'none';

  static getInstance(): OpenCodeSpikeLifecycle {
    return OpenCodeSpikeLifecycle.INSTANCE;
  }

  onCreate(context: common.UIAbilityContext, projectRoot: string = ''): void {
    if (!OPENCODE_HARMONY_ENABLED) {
      this.publishState('disabled', false, 'none');
      hilog.info(DOMAIN, 'OpenCodeRuntime',
        'LIFECYCLE_CREATE skipped buildMode=%{public}s', OPENCODE_HARMONY_BUILD_MODE);
      return;
    }
    if (!OPENCODE_HARMONY_FORMAL_RUNTIME_SELECTED &&
      OPENCODE_HARMONY_RUNTIME_SELECTION !== OPENCODE_HARMONY_MINIMAL_RUNTIME) {
      this.publishState('error', false, 'RUNTIME_SELECTION_INVALID');
      hilog.error(DOMAIN, 'OpenCodeRuntime',
        'LIFECYCLE_CREATE_FAILED code=%{public}s', 'RUNTIME_SELECTION_INVALID');
      return;
    }
    if (this.initialization !== undefined) return;

    this.projectRoot = projectRoot;
    this.initialization = OPENCODE_HARMONY_FORMAL_RUNTIME_SELECTED ?
      this.initializeFormalRuntimeController(context) :
      this.initializeRuntimeController(context);
    // UIAbility.onCreate is synchronous. Keep initialization asynchronous and
    // attach a rejection handler so a load failure is reported as state rather
    // than becoming an unhandled Promise that can disturb editor startup.
    this.initialization.catch(() => {
      // initializeRuntimeController already records a bounded structured error.
    });
  }

  onForeground(): void {
    if (!OPENCODE_HARMONY_ENABLED) return;
    this.panelController?.onForeground();
    this.publishState(this.currentControllerPhase(), true, this.errorCode);
    hilog.info(DOMAIN, 'OpenCodeRuntime', 'LIFECYCLE_FOREGROUND phase=%{public}s',
      this.phase);
  }

  onBackground(): void {
    if (!OPENCODE_HARMONY_ENABLED) return;
    this.panelController?.onBackground();
    this.publishState(this.currentControllerPhase(), false, this.errorCode);
    hilog.info(DOMAIN, 'OpenCodeRuntime', 'LIFECYCLE_BACKGROUND phase=%{public}s',
      this.phase);
  }

  onDestroy(): Promise<void> {
    if (!OPENCODE_HARMONY_ENABLED) {
      this.publishState('disabled', false, 'none');
      return Promise.resolve();
    }
    if (this.destruction !== undefined) return this.destruction;

    this.destruction = this.destroyRuntimeController();
    return this.destruction;
  }

  getSnapshot(): OpenCodeSpikeLifecycleSnapshot {
    return {
      enabled: OPENCODE_HARMONY_ENABLED,
      buildMode: OPENCODE_HARMONY_BUILD_MODE,
      runtimeSelection: OPENCODE_HARMONY_RUNTIME_SELECTION,
      phase: this.phase,
      foreground: this.foreground,
      controllerReady: this.formalRuntimeController !== undefined,
      errorCode: this.errorCode,
      panel: this.panelController?.getSnapshot()
    };
  }

  getProjectRoot(): string {
    return this.projectRoot;
  }

  async activatePanel(): Promise<OpenCodePanelNavigation> {
    const panelController = await this.requirePanelController();
    return panelController.activate();
  }

  async retryPanel(): Promise<OpenCodePanelNavigation> {
    const panelController = await this.requirePanelController();
    return panelController.retry();
  }

  setPanelVisible(visible: boolean): void {
    this.panelController?.setVisible(visible);
  }

  async stopPanel(): Promise<void> {
    if (this.panelController === undefined) return;
    await this.panelController.stop();
  }

  updateProjectRoot(projectRoot: string): void {
    this.projectRoot = projectRoot;
    if (this.panelController !== undefined) {
      this.panelController.setProjectRoot(projectRoot);
    } else {
      this.formalRuntimeController?.updateAuthorizedProjectRoot(projectRoot);
    }
  }

  async requireFormalRuntimeController(): Promise<OpenCodeFormalRuntimeController> {
    if (!OPENCODE_HARMONY_ENABLED) {
      throw new OpenCodeSpikeLifecycleError('SPIKE_DISABLED', 'disabled',
        'OpenCode runtime is disabled for this editor build');
    }
    if (!OPENCODE_HARMONY_FORMAL_RUNTIME_SELECTED) {
      throw new OpenCodeSpikeLifecycleError('FORMAL_RUNTIME_NOT_SELECTED',
        this.phase,
        'The formal upstream runtime is not selected for this editor build');
    }
    await this.awaitInitialization();
    if (this.formalRuntimeController === undefined) {
      throw new OpenCodeSpikeLifecycleError('FORMAL_CONTROLLER_UNAVAILABLE',
        this.phase,
        'The formal upstream runtime controller is unavailable');
    }
    return this.formalRuntimeController;
  }

  async requirePanelController(): Promise<OpenCodePanelSessionController> {
    await this.requireFormalRuntimeController();
    if (this.panelController === undefined) {
      throw new OpenCodeSpikeLifecycleError('PANEL_CONTROLLER_UNAVAILABLE', this.phase,
        'OpenCode panel controller is unavailable');
    }
    return this.panelController;
  }

  private async destroyRuntimeController(): Promise<void> {
    this.publishState('destroying', false, this.errorCode);
    try {
      if (this.initialization !== undefined) {
        try {
          await this.initialization;
        } catch (_) {
          // Initialization already recorded a structured failure. Destruction
          // must still clear the singleton state and remain safe to await.
        }
      }
      if (this.panelController !== undefined) {
        await this.panelController.shutdown();
      } else if (this.formalRuntimeController !== undefined) {
        await this.formalRuntimeController.shutdownIfRunning();
      }
      hilog.info(DOMAIN, 'OpenCodeRuntime', 'LIFECYCLE_DESTROY complete');
    } catch (error) {
      this.errorCode = 'CONTROLLER_SHUTDOWN_FAILED';
      hilog.error(DOMAIN, 'OpenCodeRuntime',
        'LIFECYCLE_DESTROY_FAILED code=%{public}s type=%{public}s',
        this.errorCode, error instanceof Error ? error.name : 'unknown');
    } finally {
      this.formalPanelUnsubscribe?.();
      this.formalPanelUnsubscribe = undefined;
      this.formalChangedPathDispatcher?.dispose();
      this.formalChangedPathDispatcher = undefined;
      this.panelController = undefined;
      this.formalRuntimeController = undefined;
      this.projectRoot = '';
      this.initialization = undefined;
      this.destruction = undefined;
      this.publishState('destroyed', false, this.errorCode);
    }
  }

  private async initializeRuntimeController(context: common.UIAbilityContext): Promise<void> {
    return this.initializeFormalRuntimeController(context);
  }

  private async initializeFormalRuntimeController(context: common.UIAbilityContext):
    Promise<void> {
    this.publishState('formal-initializing', this.foreground, 'none');
    try {
      const runtimeModule = await import('./OpenCodeFormalRuntimeController');
      this.formalRuntimeController =
        new runtimeModule.OpenCodeFormalRuntimeController(
          context.filesDir,
          context.cacheDir,
          context.tempDir,
          this.projectRoot
        );
      const panelModule = await import('./OpenCodeFormalPanelController');
      const assetModule = await import('./OpenCodeFormalAssetInstaller');
      const formalPanel = new panelModule.OpenCodeFormalPanelController(
        context.filesDir,
        this.formalRuntimeController,
        new assetModule.OpenCodeFormalAssetInstaller(context)
      );
      this.panelController = formalPanel;
      const skillsModule = await import('./OpenCodeSkillsInstaller');
      new skillsModule.OpenCodeSkillsInstaller(context).prepare()
        .then((result): void => {
          hilog.info(DOMAIN, 'OpenCodeRuntime',
            'SKILLS_READY files=%{public}d reused=%{public}s',
            result.files, String(result.reused));
        })
        .catch((error: Object): void => {
          let code = 'UNKNOWN';
          if (error instanceof skillsModule.OpenCodeSkillsInstallerError) {
            code = error.code;
          }
          hilog.error(DOMAIN, 'OpenCodeRuntime',
            'SKILLS_INSTALL_ERROR code=%{public}s', code);
        });
      const changedPathModule =
        await import('./OpenCodeFormalChangedPathDispatcher');
      this.formalChangedPathDispatcher =
        new changedPathModule.OpenCodeFormalChangedPathDispatcher(
          context.eventHub,
          this.formalRuntimeController,
          (): string => this.projectRoot,
          (event): void => formalPanel.handleRuntimeHostEvent(event)
        );
      this.formalPanelUnsubscribe = formalPanel.subscribe((snapshot): void => {
        if (snapshot.ready && snapshot.generation > 0) {
          this.formalChangedPathDispatcher?.start(snapshot.generation);
        } else {
          this.formalChangedPathDispatcher?.stop();
        }
      });
      if (this.foreground) this.panelController.onForeground();
      this.publishState('formal-idle', this.foreground, 'none');
      hilog.info(DOMAIN, 'OpenCodeRuntime',
        'LIFECYCLE_CREATE formal-ready buildMode=%{public}s',
        OPENCODE_HARMONY_BUILD_MODE);
    } catch (error) {
      this.formalPanelUnsubscribe?.();
      this.formalPanelUnsubscribe = undefined;
      this.formalChangedPathDispatcher?.dispose();
      this.formalChangedPathDispatcher = undefined;
      const lifecycleError = error instanceof OpenCodeSpikeLifecycleError ? error :
        new OpenCodeSpikeLifecycleError(
          'FORMAL_CONTROLLER_IMPORT_FAILED',
          'formal-initializing',
          'The formal upstream runtime controller could not be loaded');
      this.publishState('error', this.foreground, lifecycleError.code);
      hilog.error(DOMAIN, 'OpenCodeRuntime',
        'LIFECYCLE_CREATE_FAILED code=%{public}s type=%{public}s',
        lifecycleError.code, error instanceof Error ? error.name : 'unknown');
      throw lifecycleError;
    }
  }

  private async awaitInitialization(): Promise<void> {
    if (this.initialization === undefined) {
      throw new OpenCodeSpikeLifecycleError('CONTROLLER_NOT_INITIALIZED', this.phase,
        'OpenCode runtime controller has not been attached to EditorAbility');
    }
    try {
      await this.initialization;
    } catch (error) {
      if (error instanceof OpenCodeSpikeLifecycleError) throw error;
      throw new OpenCodeSpikeLifecycleError('CONTROLLER_INITIALIZATION_FAILED', this.phase,
        'OpenCode runtime controller initialization failed');
    }
  }

  private currentControllerPhase(): string {
    if (this.formalRuntimeController !== undefined) {
      return this.formalRuntimeController.getPhase();
    }
    return this.phase;
  }

  private publishState(phase: string, foreground: boolean, errorCode: string): void {
    this.phase = phase;
    this.foreground = foreground;
    this.errorCode = errorCode;
    AppStorage.setOrCreate('openCodeRuntimePhase', phase);
    AppStorage.setOrCreate('openCodeRuntimeForeground', foreground);
    AppStorage.setOrCreate('openCodeRuntimeErrorCode', errorCode);
  }
}

import { common } from '@kit.AbilityKit';
import plugin from 'libentry.so';
import type {
  OpenCodePanelNavigation,
  OpenCodePanelSnapshot
} from './OpenCodePanelContract';
import { OpenCodePanelError } from './OpenCodePanelContract';
import {
  OpenCodeBridgeDispatcher,
  OpenCodeBridgeRequestTracker,
  OpenCodeBridgeProtocolError
} from './OpenCodeBridgeProtocol';
import type {
  OpenCodeBridgeCancellation
} from './OpenCodeBridgeProtocol';
import {
  openCodeBridgeEvents
} from './OpenCodeBridgeTransport';
import type {
  OpenCodeBridgeChannel,
  OpenCodeBridgeWireEventCallback
} from './OpenCodeBridgeTransport';
import type { OpenCodePanelBounds } from './OpenCodePanelGeometry';
import { OpenCodeContextCollector } from './OpenCodeContextCollector';
import type { OpenCodeEditorContextMethod } from './OpenCodeEditorContext';
import { OpenCodeEditorActionExecutor } from './OpenCodeEditorActionExecutor';
import type { OpenCodeEditorActionMethod } from './OpenCodeEditorAction';
import { OpenCodeSpikeLifecycle, OpenCodeSpikeLifecycleError } from './OpenCodeSpikeLifecycle';
import { RuntimeLifecycleError } from './RuntimeLifecycleError';

const MAX_SURFACE_COORDINATE = 32768;
const MAX_SURFACE_EXTENT = 16384;

interface OpenCodePanelBoundsPayload {
  bounds?: OpenCodePanelBounds;
}

interface OpenCodePanelPhaseResult {
  phase: string;
  generation?: number;
}

interface OpenCodeRuntimeStatusPayload {
  phase: string;
  visible: boolean;
  ready: boolean;
  generation: number;
  errorCode: string;
  errorSummary: string;
  retryable: boolean;
}

interface OpenCodePatchPathPayload {
  path?: string;
}

interface OpenCodePatchProposalPayload {
  proposalId: string;
  path: string;
}

export type OpenCodePanelShowSurface =
  (navigation: OpenCodePanelNavigation, bounds: OpenCodePanelBounds) => void;
export type OpenCodePanelUpdateSurface = (bounds: OpenCodePanelBounds) => void;
export type OpenCodePanelHideSurface = () => void;

export interface OpenCodePanelBridgeHostOptions {
  channel?: OpenCodeBridgeChannel;
  panelLifecycle?: boolean;
  runtimeStatus?: boolean;
}

export class OpenCodePanelBridgeHost {
  private readonly eventHub: common.EventHub;
  private readonly dispatcher: OpenCodeBridgeDispatcher;
  private readonly statusTracker: OpenCodeBridgeRequestTracker;
  private readonly fromWebCallback: OpenCodeBridgeWireEventCallback;
  private readonly showSurface: OpenCodePanelShowSurface;
  private readonly updateSurface: OpenCodePanelUpdateSurface;
  private readonly hideSurface: OpenCodePanelHideSurface;
  private readonly contextCollector: OpenCodeContextCollector;
  private readonly actionExecutor: OpenCodeEditorActionExecutor;
  private readonly fromWebEvent: string;
  private readonly toWebEvent: string;
  private readonly panelLifecycle: boolean;
  private readonly runtimeStatus: boolean;
  private latestBounds?: OpenCodePanelBounds;
  private requestedVisible: boolean = false;
  private disposed: boolean = false;
  private panelStateUnsubscribe?: () => void;

  constructor(panelInstanceId: string, eventHub: common.EventHub,
    showSurface: OpenCodePanelShowSurface,
    updateSurface: OpenCodePanelUpdateSurface,
    hideSurface: OpenCodePanelHideSurface,
    options: OpenCodePanelBridgeHostOptions = {}) {
    this.eventHub = eventHub;
    this.showSurface = showSurface;
    this.updateSurface = updateSurface;
    this.hideSurface = hideSurface;
    const channel = options.channel === 'sdk-client' ? 'sdk-client' : 'panel';
    const events = openCodeBridgeEvents(channel);
    this.fromWebEvent = events.fromWeb;
    this.toWebEvent = events.toWeb;
    this.panelLifecycle = options.panelLifecycle !== false;
    this.runtimeStatus = options.runtimeStatus !== false;
    this.contextCollector = new OpenCodeContextCollector(eventHub, (): string => {
      return OpenCodeSpikeLifecycle.getInstance().getProjectRoot();
    });
    this.actionExecutor = new OpenCodeEditorActionExecutor(eventHub, (): string => {
      return OpenCodeSpikeLifecycle.getInstance().getProjectRoot();
    });
    this.dispatcher = new OpenCodeBridgeDispatcher(panelInstanceId);
    this.statusTracker = new OpenCodeBridgeRequestTracker(
      panelInstanceId,
      (wireMessage: string): void => {
        this.eventHub.emit(this.toWebEvent, wireMessage);
      }
    );
    this.registerHandlers();
    this.fromWebCallback = (wireMessage: string): void => {
      this.handleIncoming(wireMessage);
    };
    this.eventHub.on(this.fromWebEvent, this.fromWebCallback);
    if (this.runtimeStatus) this.attachPanelStateObserver();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.requestedVisible = false;
    this.dispatcher.dispose();
    this.statusTracker.dispose();
    this.panelStateUnsubscribe?.();
    this.panelStateUnsubscribe = undefined;
    this.contextCollector.dispose();
    this.actionExecutor.dispose();
    try {
      this.eventHub.off(this.fromWebEvent, this.fromWebCallback);
    } catch (_) {
      // The owning EventHub can already be torn down during ability destroy.
    }
    this.hideSurface();
  }

  private registerHandlers(): void {
    if (this.panelLifecycle) {
      this.dispatcher.register('editor.panel.activate',
      async (payload: Object | undefined,
        cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        const bounds = this.requireBounds(payload);
        this.latestBounds = bounds;
        this.requestedVisible = true;
        try {
          const navigation = await OpenCodeSpikeLifecycle.getInstance().activatePanel();
          if (cancellation.isCancelled() || !this.requestedVisible || this.disposed) {
            OpenCodeSpikeLifecycle.getInstance().setPanelVisible(false);
            this.hideSurface();
            if (cancellation.isCancelled()) {
              await OpenCodeSpikeLifecycle.getInstance().stopPanel();
            }
            return undefined;
          }
          this.showSurface(navigation, this.latestBounds === undefined ? bounds : this.latestBounds);
          const result: OpenCodePanelPhaseResult = {
            phase: 'ready',
            generation: navigation.generation
          };
          return result;
        } catch (error) {
          throw this.normalizePanelError(error);
        }
      });

    this.dispatcher.register('editor.panel.retry',
      async (payload: Object | undefined,
        cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        const bounds = this.requireBounds(payload);
        this.latestBounds = bounds;
        this.requestedVisible = true;
        try {
          const navigation = await OpenCodeSpikeLifecycle.getInstance().retryPanel();
          if (cancellation.isCancelled() || !this.requestedVisible || this.disposed) {
            OpenCodeSpikeLifecycle.getInstance().setPanelVisible(false);
            this.hideSurface();
            if (cancellation.isCancelled()) {
              await OpenCodeSpikeLifecycle.getInstance().stopPanel();
            }
            return undefined;
          }
          this.showSurface(navigation, this.latestBounds === undefined ? bounds : this.latestBounds);
          const result: OpenCodePanelPhaseResult = {
            phase: 'ready',
            generation: navigation.generation
          };
          return result;
        } catch (error) {
          throw this.normalizePanelError(error);
        }
      });

    this.dispatcher.register('editor.panel.geometry',
      async (payload: Object | undefined): Promise<Object | undefined> => {
        const bounds = this.requireBounds(payload);
        this.latestBounds = bounds;
        if (this.requestedVisible) this.updateSurface(bounds);
        const result: OpenCodePanelPhaseResult = {
          phase: this.requestedVisible ? 'visible' : 'hidden'
        };
        return result;
      });

    this.dispatcher.register('editor.panel.hide',
      async (): Promise<Object | undefined> => {
        this.requestedVisible = false;
        OpenCodeSpikeLifecycle.getInstance().setPanelVisible(false);
        this.hideSurface();
        const result: OpenCodePanelPhaseResult = { phase: 'hidden' };
        return result;
      });

    this.dispatcher.register('editor.panel.stop',
      async (): Promise<Object | undefined> => {
        this.requestedVisible = false;
        this.hideSurface();
        try {
          await OpenCodeSpikeLifecycle.getInstance().stopPanel();
          const result: OpenCodePanelPhaseResult = { phase: 'idle' };
          return result;
        } catch (error) {
          throw this.normalizePanelError(error);
        }
      });

      this.dispatcher.register('editor.panel.probe-failure',
      async (payload: Object | undefined,
        cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        if (payload !== undefined) {
          throw new OpenCodeBridgeProtocolError(
            'PANEL_FAILURE_PROBE_PAYLOAD_INVALID',
            'The asynchronous failure probe does not accept a payload'
          );
        }
        if (cancellation.isCancelled()) return undefined;
        try {
          const panelController =
            await OpenCodeSpikeLifecycle.getInstance().requirePanelController();
          const result = await panelController.runAsyncFailureProbe();
          return cancellation.isCancelled() ? undefined : result;
        } catch (error) {
          throw this.normalizePanelError(error);
        }
        });
    }

    this.registerContextHandler('context.snapshot');
    this.registerContextHandler('context.active-project');
    this.registerContextHandler('context.active-script');
    this.registerContextHandler('context.selection');
    this.registerContextHandler('context.active-scene');
    this.registerContextHandler('context.scene-tree');
    this.registerContextHandler('context.selected-node');
    this.registerContextHandler('context.resource-references');

    this.registerActionHandler('editor.open-file');
    this.registerActionHandler('editor.position-cursor');
    this.registerActionHandler('editor.refresh-resource');
    this.registerActionHandler('editor.select-scene-node');

    this.dispatcher.register('opencode.patch.propose',
      async (_payload: Object | undefined,
        _cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        return undefined;
      });

    this.dispatcher.register('opencode.patch.accept',
      async (_payload: Object | undefined,
        _cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        return undefined;
      });

    this.dispatcher.register('opencode.patch.reject',
      async (_payload: Object | undefined,
        _cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        return undefined;
      });
  }

  private registerContextHandler(method: OpenCodeEditorContextMethod): void {
    this.dispatcher.register(method,
      async (payload: Object | undefined,
        cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        return this.contextCollector.collect(method, payload, cancellation);
      });
  }

  private registerActionHandler(method: OpenCodeEditorActionMethod): void {
    this.dispatcher.register(method,
      async (payload: Object | undefined,
        cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> => {
        return this.actionExecutor.execute(method, payload, cancellation);
      });
  }

  private handleIncoming(wireMessage: string): void {
    if (this.disposed) return;
    if (this.statusTracker.handleIncoming(wireMessage)) return;
    this.dispatcher.handleIncoming(wireMessage).then((response: string | undefined): void => {
      if (this.disposed || response === undefined) return;
      try {
        this.eventHub.emit(this.toWebEvent, response);
      } catch (_) {
        // The versioned request will time out on the Web side if delivery fails.
      }
    }).catch((): void => {
      // Dispatcher failures are already converted to structured responses.
    });
  }

  private attachPanelStateObserver(): void {
    OpenCodeSpikeLifecycle.getInstance().requirePanelController()
      .then((panelController): void => {
        if (this.disposed) return;
        this.panelStateUnsubscribe = panelController.subscribe(
          (snapshot: OpenCodePanelSnapshot): void => {
            this.publishRuntimeStatus(snapshot);
          }
        );
      })
      .catch((): void => {
        // Lifecycle initialization reports its own bounded structured error.
      });
  }

  private publishRuntimeStatus(snapshot: OpenCodePanelSnapshot): void {
    if (this.disposed) return;
    if (snapshot.phase === 'failed') this.hideSurface();
    const payload: OpenCodeRuntimeStatusPayload = {
      phase: snapshot.phase,
      visible: snapshot.visible,
      ready: snapshot.ready,
      generation: snapshot.generation,
      errorCode: snapshot.errorCode,
      errorSummary: snapshot.errorSummary,
      retryable: snapshot.retryable
    };
    this.statusTracker.request('runtime.status', payload, 1000).catch((): void => {
      // Runtime status is advisory; a stale or hidden Web panel may not reply.
    });
  }

  private requireBounds(payload: Object | undefined): OpenCodePanelBounds {
    if (payload === undefined) {
      throw new OpenCodeBridgeProtocolError(
        'PANEL_BOUNDS_REQUIRED',
        'The OpenCode panel bounds are required'
      );
    }
    const document = payload as OpenCodePanelBoundsPayload;
    const bounds = document.bounds;
    if (bounds === undefined ||
      !Number.isInteger(bounds.left) || !Number.isInteger(bounds.top) ||
      !Number.isInteger(bounds.width) || !Number.isInteger(bounds.height) ||
      bounds.left < 0 || bounds.top < 0 ||
      bounds.left > MAX_SURFACE_COORDINATE || bounds.top > MAX_SURFACE_COORDINATE ||
      bounds.width < 1 || bounds.height < 1 ||
      bounds.width > MAX_SURFACE_EXTENT || bounds.height > MAX_SURFACE_EXTENT) {
      throw new OpenCodeBridgeProtocolError(
        'PANEL_BOUNDS_INVALID',
        'The OpenCode panel bounds are invalid'
      );
    }
    return {
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height
    };
  }

  private requirePatchPath(payload: Object | undefined): string {
    if (payload === undefined || Object.keys(payload).length !== 1) {
      throw new OpenCodeBridgeProtocolError(
        'HARMONY_AUTHORIZED_PATH_INVALID',
        'The authorized script path is invalid'
      );
    }
    const document = payload as OpenCodePatchPathPayload;
    if (typeof document.path !== 'string') {
      throw new OpenCodeBridgeProtocolError(
        'HARMONY_AUTHORIZED_PATH_INVALID',
        'The authorized script path is invalid'
      );
    }
    return document.path;
  }

  private requirePatchProposal(payload: Object | undefined): OpenCodePatchProposalPayload {
    if (payload === undefined || Object.keys(payload).length !== 2) {
      throw new OpenCodeBridgeProtocolError(
        'HARMONY_AUTHORIZED_PATCH_ID_INVALID',
        'The authorized patch request is invalid'
      );
    }
    const document = payload as OpenCodePatchProposalPayload;
    if (typeof document.proposalId !== 'string' || typeof document.path !== 'string') {
      throw new OpenCodeBridgeProtocolError(
        'HARMONY_AUTHORIZED_PATCH_ID_INVALID',
        'The authorized patch request is invalid'
      );
    }
    return {
      proposalId: document.proposalId,
      path: document.path
    };
  }

  private normalizePanelError(error: Object): OpenCodeBridgeProtocolError {
    if (error instanceof OpenCodeBridgeProtocolError) return error;
    if (error instanceof OpenCodePanelError) {
      return new OpenCodeBridgeProtocolError(error.code, error.message, error.retryable);
    }
    if (error instanceof OpenCodeSpikeLifecycleError) {
      return new OpenCodeBridgeProtocolError(error.code, error.message, true);
    }
    return new OpenCodeBridgeProtocolError(
      'PANEL_START_FAILED',
      'The local OpenCode panel could not be started',
      true
    );
  }

  private normalizePatchError(error: Object): OpenCodeBridgeProtocolError {
    if (error instanceof OpenCodeBridgeProtocolError) return error;
    if (error instanceof RuntimeLifecycleError) {
      return new OpenCodeBridgeProtocolError(
        error.code,
        'The OpenCode authorized patch request failed',
        error.code === 'HARMONY_AUTHORIZED_RUNTIME_NOT_READY' ||
          error.code === 'HARMONY_AUTHORIZED_REQUEST_FAILED'
      );
    }
    if (error instanceof OpenCodeSpikeLifecycleError) {
      return new OpenCodeBridgeProtocolError(error.code, error.message, true);
    }
    return new OpenCodeBridgeProtocolError(
      'HARMONY_AUTHORIZED_REQUEST_FAILED',
      'The OpenCode authorized patch request failed',
      true
    );
  }
}

export class HarmonyOpenCodeBridgeProxy {
  getEditorContext(): string {
    try {
      return plugin.getEditorContext();
    } catch (e) {
      return JSON.stringify({ has_context: false, error: String(e) });
    }
  }

  applyScriptChanges(filePath: string, newContent: string): boolean {
    try {
      return plugin.applyScriptChanges(filePath, newContent);
    } catch (e) {
      return false;
    }
  }
}

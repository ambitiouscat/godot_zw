import {
  OPENCODE_BRIDGE_PROTOCOL,
  OPENCODE_BRIDGE_VERSION,
  OpenCodeBridgeProtocolError,
  parseOpenCodeBridgeEnvelope,
  serializeOpenCodeBridgeEnvelope
} from './OpenCodeBridgeProtocol';
import type { OpenCodeBridgeEnvelope } from './OpenCodeBridgeProtocol';

export const OPENCODE_BRIDGE_FROM_WEB_EVENT =
  'opencode.editor-bridge.v1.from-web';
export const OPENCODE_BRIDGE_TO_WEB_EVENT =
  'opencode.editor-bridge.v1.to-web';
export const OPENCODE_SDK_CLIENT_BRIDGE_FROM_WEB_EVENT =
  'opencode.editor-bridge.v1.sdk-client.from-web';
export const OPENCODE_SDK_CLIENT_BRIDGE_TO_WEB_EVENT =
  'opencode.editor-bridge.v1.sdk-client.to-web';
export const OPENCODE_BRIDGE_BOOTSTRAP =
  '__init_opencode_editor_bridge_v1__';

export type OpenCodeBridgeChannel = 'panel' | 'sdk-client';

export type OpenCodeBridgeWireEventCallback = (wireMessage: string) => void;

const PANEL_TO_HOST_METHODS: string[] = [
  'editor.panel.activate',
  'editor.panel.retry',
  'editor.panel.geometry',
  'editor.panel.hide',
  'editor.panel.stop',
  'editor.panel.probe-failure',
  'context.snapshot',
  'context.active-project',
  'context.active-script',
  'context.selection',
  'context.active-scene',
  'context.scene-tree',
  'context.selected-node',
  'context.resource-references',
  'editor.open-file',
  'editor.position-cursor',
  'editor.refresh-resource',
  'editor.select-scene-node',
  'opencode.patch.propose',
  'opencode.patch.accept',
  'opencode.patch.reject'
];
const HOST_TO_PANEL_METHODS: string[] = [
  'runtime.status',
  'project.changed'
];
const HOST_TO_SDK_CLIENT_METHODS: string[] = [
  'runtime.status'
];
const SDK_CLIENT_TO_HOST_METHODS: string[] = [
  'context.snapshot',
  'context.active-project',
  'context.active-script',
  'context.selection',
  'context.active-scene',
  'context.scene-tree',
  'context.selected-node',
  'context.resource-references',
  'editor.open-file',
  'editor.position-cursor',
  'editor.refresh-resource',
  'editor.select-scene-node',
  'opencode.patch.propose',
  'opencode.patch.accept',
  'opencode.patch.reject'
];

let panelInstanceSequence: number = 0;

export interface OpenCodeBridgeEventHubPort {
  on(event: string, callback: OpenCodeBridgeWireEventCallback): void;
  off(event: string, callback: OpenCodeBridgeWireEventCallback): void;
  emit(event: string, wireMessage: string): void;
}

export interface OpenCodeBridgeWebMessagePort {
  onMessageEvent(callback: (message: string | ArrayBuffer) => void): void;
  postMessageEvent(message: string): void;
  close(): void;
}

export interface OpenCodeBridgeTransportStats {
  fromWeb: number;
  toWeb: number;
  droppedInvalid: number;
  droppedDirection: number;
  droppedDisposed: number;
  sendFailures: number;
}

export interface OpenCodeBridgeBootstrapDocument {
  name: string;
  protocol: string;
  version: number;
  panelInstanceId: string;
  scope?: OpenCodeBridgeChannel;
}

export function createOpenCodeBridgePanelInstanceId(): string {
  panelInstanceSequence += 1;
  return `panel:${Date.now().toString(36)}:${panelInstanceSequence.toString(36)}`;
}

export function serializeOpenCodeBridgeBootstrap(
  panelInstanceId: string,
  scope: OpenCodeBridgeChannel = 'panel'
): string {
  validatePanelInstanceId(panelInstanceId);
  const document: OpenCodeBridgeBootstrapDocument = {
    name: OPENCODE_BRIDGE_BOOTSTRAP,
    protocol: OPENCODE_BRIDGE_PROTOCOL,
    version: OPENCODE_BRIDGE_VERSION,
    panelInstanceId,
    ...(scope === 'sdk-client' ? { scope } : {})
  };
  return JSON.stringify(document);
}

export class OpenCodeBridgeEventHubTransport {
  private readonly panelInstanceId: string;
  private readonly eventHub: OpenCodeBridgeEventHubPort;
  private readonly webPort: OpenCodeBridgeWebMessagePort;
  private readonly channel: OpenCodeBridgeChannel;
  private readonly fromWebEvent: string;
  private readonly toWebEvent: string;
  private readonly hostToWebCallback: OpenCodeBridgeWireEventCallback;
  private readonly stats: OpenCodeBridgeTransportStats = {
    fromWeb: 0,
    toWeb: 0,
    droppedInvalid: 0,
    droppedDirection: 0,
    droppedDisposed: 0,
    sendFailures: 0
  };
  private disposed: boolean = false;

  constructor(
    panelInstanceId: string,
    eventHub: OpenCodeBridgeEventHubPort,
    webPort: OpenCodeBridgeWebMessagePort,
    channel: OpenCodeBridgeChannel = 'panel'
  ) {
    validatePanelInstanceId(panelInstanceId);
    this.panelInstanceId = panelInstanceId;
    this.eventHub = eventHub;
    this.webPort = webPort;
    this.channel = channel;
    const events = openCodeBridgeEvents(channel);
    this.fromWebEvent = events.fromWeb;
    this.toWebEvent = events.toWeb;
    this.hostToWebCallback = (wireMessage: string): void => {
      this.forwardHostMessage(wireMessage);
    };

    this.webPort.onMessageEvent((message: string | ArrayBuffer): void => {
      this.forwardWebMessage(message);
    });
    this.eventHub.on(this.toWebEvent, this.hostToWebCallback);
  }

  getPanelInstanceId(): string {
    return this.panelInstanceId;
  }

  getBootstrapMessage(): string {
    return serializeOpenCodeBridgeBootstrap(this.panelInstanceId, this.channel);
  }

  getStats(): OpenCodeBridgeTransportStats {
    return {
      fromWeb: this.stats.fromWeb,
      toWeb: this.stats.toWeb,
      droppedInvalid: this.stats.droppedInvalid,
      droppedDirection: this.stats.droppedDirection,
      droppedDisposed: this.stats.droppedDisposed,
      sendFailures: this.stats.sendFailures
    };
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    try {
      this.eventHub.off(this.toWebEvent, this.hostToWebCallback);
    } catch (_) {
      this.stats.sendFailures += 1;
    }
    try {
      this.webPort.close();
    } catch (_) {
      this.stats.sendFailures += 1;
    }
  }

  private forwardWebMessage(message: string | ArrayBuffer): void {
    if (this.disposed) {
      this.stats.droppedDisposed += 1;
      return;
    }
    if (typeof message !== 'string') {
      this.stats.droppedInvalid += 1;
      return;
    }

    const envelope = this.parseExpectedEnvelope(message);
    if (envelope === undefined) return;
    if (!isAllowedDirection(envelope, true, this.channel)) {
      this.stats.droppedDirection += 1;
      return;
    }
    this.stats.fromWeb += 1;
    try {
      this.eventHub.emit(this.fromWebEvent, message);
    } catch (_) {
      this.stats.fromWeb -= 1;
      this.stats.sendFailures += 1;
    }
  }

  private forwardHostMessage(wireMessage: string): void {
    if (this.disposed) {
      this.stats.droppedDisposed += 1;
      return;
    }
    if (typeof wireMessage !== 'string') {
      this.stats.droppedInvalid += 1;
      return;
    }

    const envelope = this.parseExpectedEnvelope(wireMessage);
    if (envelope === undefined) return;
    if (!isAllowedDirection(envelope, false, this.channel)) {
      this.stats.droppedDirection += 1;
      return;
    }

    try {
      this.webPort.postMessageEvent(wireMessage);
      this.stats.toWeb += 1;
    } catch (_) {
      this.stats.sendFailures += 1;
    }
  }

  private parseExpectedEnvelope(
    wireMessage: string
  ): OpenCodeBridgeEnvelope | undefined {
    try {
      return parseOpenCodeBridgeEnvelope(wireMessage, this.panelInstanceId);
    } catch (_) {
      this.stats.droppedInvalid += 1;
      return undefined;
    }
  }
}

function isAllowedDirection(
  envelope: OpenCodeBridgeEnvelope,
  fromWeb: boolean,
  channel: OpenCodeBridgeChannel
): boolean {
  if (envelope.kind !== 'request') return true;
  if (fromWeb) {
    return (channel === 'sdk-client' ? SDK_CLIENT_TO_HOST_METHODS : PANEL_TO_HOST_METHODS)
      .includes(envelope.method);
  }
  return (channel === 'sdk-client' ? HOST_TO_SDK_CLIENT_METHODS : HOST_TO_PANEL_METHODS)
    .includes(envelope.method);
}

export function openCodeBridgeEvents(channel: OpenCodeBridgeChannel): {
  fromWeb: string;
  toWeb: string;
} {
  if (channel === 'sdk-client') {
    return {
      fromWeb: OPENCODE_SDK_CLIENT_BRIDGE_FROM_WEB_EVENT,
      toWeb: OPENCODE_SDK_CLIENT_BRIDGE_TO_WEB_EVENT
    };
  }
  return {
    fromWeb: OPENCODE_BRIDGE_FROM_WEB_EVENT,
    toWeb: OPENCODE_BRIDGE_TO_WEB_EVENT
  };
}

function validatePanelInstanceId(panelInstanceId: string): void {
  const validationEnvelope: OpenCodeBridgeEnvelope = {
    protocol: OPENCODE_BRIDGE_PROTOCOL,
    version: OPENCODE_BRIDGE_VERSION,
    panelInstanceId,
    kind: 'cancel',
    requestId: 'transport:bootstrap',
    reason: 'transport-bootstrap'
  };
  try {
    serializeOpenCodeBridgeEnvelope(validationEnvelope);
  } catch (_) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_PANEL_INVALID',
      'The OpenCode editor bridge panel instance is invalid'
    );
  }
}

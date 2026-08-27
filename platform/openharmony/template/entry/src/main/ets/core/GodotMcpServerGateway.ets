import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Logger } from './Logger';

const logger = new Logger('GodotMcpServerGateway');

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/**
 * Pure TypeScript SHA-1 implementation for RFC 6455 Sec-WebSocket-Accept calculation.
 * Self-contained without platform/SDK API variance.
 */
function sha1(input: string): Uint8Array {
  const utf8: Uint8Array = new util.TextEncoder().encodeInto(input);
  const msgLen: number = utf8.length;
  const wordCount = ((msgLen + 8) >> 6) + 1;
  const words = new Int32Array(wordCount * 16);

  for (let i = 0; i < msgLen; i++) {
    words[i >> 2] |= utf8[i] << (24 - (i % 4) * 8);
  }
  words[msgLen >> 2] |= 0x80 << (24 - (msgLen % 4) * 8);
  words[wordCount * 16 - 1] = msgLen * 8;

  let h0 = 0x67452301;
  let h1 = 0xEFCDAB89;
  let h2 = 0x98BADCFE;
  let h3 = 0x10325476;
  let h4 = 0xC3D2E1F0;

  const w = new Int32Array(80);

  for (let i = 0; i < words.length; i += 16) {
    for (let t = 0; t < 16; t++) {
      w[t] = words[i + t];
    }
    for (let t = 16; t < 80; t++) {
      const v = w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16];
      w[t] = (v << 1) | (v >>> 31);
    }

    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;

    for (let t = 0; t < 80; t++) {
      let f = 0;
      let k = 0;
      if (t < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5A827999;
      } else if (t < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (t < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }

      const temp = (((a << 5) | (a >>> 27)) + f + e + k + w[t]) | 0;
      e = d;
      d = c;
      c = (b << 30) | (b >>> 2);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) | 0;
    h1 = (h1 + b) | 0;
    h2 = (h2 + c) | 0;
    h3 = (h3 + d) | 0;
    h4 = (h4 + e) | 0;
  }

  const out = new Uint8Array(20);
  const hs = [h0, h1, h2, h3, h4];
  for (let i = 0; i < 5; i++) {
    out[i * 4] = (hs[i] >>> 24) & 0xff;
    out[i * 4 + 1] = (hs[i] >>> 16) & 0xff;
    out[i * 4 + 2] = (hs[i] >>> 8) & 0xff;
    out[i * 4 + 3] = hs[i] & 0xff;
  }
  return out;
}

function base64Encode(bytes: Uint8Array): string {
  const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  const len = bytes.length;
  for (let i = 0; i < len; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < len ? bytes[i + 1] : 0;
    const b2 = i + 2 < len ? bytes[i + 2] : 0;

    result += base64Chars.charAt((b0 >> 2) & 0x3f);
    result += base64Chars.charAt(((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0f));
    result += i + 1 < len ? base64Chars.charAt(((b1 & 0x0f) << 2) | ((b2 >> 6) & 0x03)) : '=';
    result += i + 2 < len ? base64Chars.charAt(b2 & 0x3f) : '=';
  }
  return result;
}

interface PendingCommand {
  resolve: (res: Record<string, Object>) => void;
  reject: (err: Error) => void;
  timeoutId: number;
}

interface JsonRpcPongResult {
  pong: boolean;
}

interface JsonRpcPingPong {
  jsonrpc: string;
  method?: string;
  id?: string;
  result?: JsonRpcPongResult;
}

interface JsonRpcAuthParams {
  token: string;
}

interface JsonRpcAuthMessage {
  jsonrpc: string;
  id: string;
  method: string;
  params: JsonRpcAuthParams;
}

interface JsonRpcErrorPayload {
  code: number;
  message: string;
}

interface JsonRpcErrorResponse {
  jsonrpc: string;
  id: string;
  error: JsonRpcErrorPayload;
}

/**
 * Lifecycle facts emitted by GameAbility and consumed by the editor-resident
 * Godot MCP plugin. The correlation values are required; events missing one
 * cannot change editor runtime state.
 */
export interface RuntimeLifecycleEvent {
  type: string;
  session_id: string;
  operation_id: string;
  boot_nonce: string;
  event_id: string;
  timestamp_ms: number;
  source: string;
  details?: Record<string, Object>;
}

interface ClientConnectionState {
  client: socket.TCPSocketConnection;
  isHandshakeComplete: boolean;
  isEngine: boolean;
  isRawTcp: boolean;
  rxBuffer: Uint8Array;
}

/**
 * Dedicated local 6510 WebSocket server gateway hub.
 * Serves as the multi-client middle bridge between Godot's websocket_server.gd client and OpenCode's AI engine.
 */
export class GodotMcpServerGateway {
  private static instance: GodotMcpServerGateway | null = null;
  private tcpServer: socket.TCPSocketServer | null = null;
  private clients: Map<socket.TCPSocketConnection, ClientConnectionState> = new Map();
  private engineClient: socket.TCPSocketConnection | null = null;
  private isRunning: boolean = false;
  private requestIdCounter: number = 1000;
  private pendingCommands: Map<string, PendingCommand> = new Map();
  private forwardedRequests: Map<string, socket.TCPSocketConnection> = new Map();
  private textDecoder = new util.TextDecoder();
  private textEncoder = new util.TextEncoder();
  private pendingRuntimeLifecycleEvents: RuntimeLifecycleEvent[] = [];

  private heartbeatTimerId: number = -1;

  public static getInstance(): GodotMcpServerGateway {
    if (!GodotMcpServerGateway.instance) {
      GodotMcpServerGateway.instance = new GodotMcpServerGateway();
    }
    return GodotMcpServerGateway.instance;
  }

  /**
   * GameAbility must not use startAbility(EditorAbility) for lifecycle events:
   * that can foreground the editor and immediately steal focus from the game.
   * The editor process already owns this loopback gateway, so GameAbility uses
   * a short-lived raw TCP JSON-RPC connection instead. The server forwards the
   * request only to the editor's authenticated Godot websocket client. A TCP
   * write is not considered delivery: the caller waits for the matching
   * JSON-RPC result with result.accepted === true.
   */
  public static async publishRuntimeLifecycleToEditor(
    type: string,
    sessionId: string,
    operationId: string,
    bootNonce: string,
    details?: Record<string, Object>
  ): Promise<boolean> {
    const validToken = (value: string): boolean => value.length > 0 && value.length <= 160 && /^[A-Za-z0-9._:-]+$/.test(value);
    const validType = type === 'REAL_READY' || type === 'REAL_STOP_ACK' || type === 'REAL_EXIT' || type === 'ABRUPT_EXIT';
    if (!validType || !validToken(sessionId) || !validToken(operationId) || !validToken(bootNonce)) {
      logger.error(`Rejected malformed GameAbility lifecycle event type=${type}`);
      return false;
    }

    const client = socket.constructTCPSocketInstance();
    const requestId = `runtime_lifecycle_${Date.now()}_${Math.floor(Math.random() * 0x7fffffff)}`;
    let resolveAcknowledgement: ((accepted: boolean) => void) | null = null;
    let acknowledgementSettled = false;
    let acknowledgementTimeoutId: number = -1;
    const acknowledgementDecoder = new util.TextDecoder();
    let acknowledgementBuffer = '';
    const finishAcknowledgement = (accepted: boolean): void => {
      if (acknowledgementSettled) {
        return;
      }
      acknowledgementSettled = true;
      if (acknowledgementTimeoutId !== -1) {
        clearTimeout(acknowledgementTimeoutId);
        acknowledgementTimeoutId = -1;
      }
      if (resolveAcknowledgement) {
        resolveAcknowledgement(accepted);
      }
    };
    client.on('message', (value: socket.SocketMessageInfo) => {
      try {
        acknowledgementBuffer += acknowledgementDecoder.decodeToString(new Uint8Array(value.message));
        const lines = acknowledgementBuffer.split('\n');
        acknowledgementBuffer = lines.pop() || '';
        for (let index = 0; index < lines.length; index++) {
          const responseText = lines[index].trim();
          if (responseText.length === 0) {
            continue;
          }
          const response = JSON.parse(responseText) as Record<string, Object>;
          if (String(response['id'] || '') !== requestId) {
            continue;
          }
          const result = response['result'] as Record<string, Object> | undefined;
          finishAcknowledgement(result !== undefined && result['accepted'] === true);
          return;
        }
      } catch (e) {
        logger.error('Failed to parse runtime_lifecycle acknowledgement', e);
        finishAcknowledgement(false);
      }
    });
    client.on('error', (_e: Error) => finishAcknowledgement(false));
    client.on('close', () => finishAcknowledgement(false));
    const acknowledgement = new Promise<boolean>((resolve) => {
      resolveAcknowledgement = resolve;
      acknowledgementTimeoutId = setTimeout(() => finishAcknowledgement(false), 1500);
    });
    try {
      const event: RuntimeLifecycleEvent = {
        type: type,
        session_id: sessionId,
        operation_id: operationId,
        boot_nonce: bootNonce,
        event_id: `ohos_game_${Date.now()}_${Math.floor(Math.random() * 0x7fffffff)}`,
        timestamp_ms: Date.now(),
        source: 'game_ability'
      };
      if (details) {
        event.details = details;
      }
      await client.connect({
        address: { address: '127.0.0.1', port: 6510, family: 1 },
        timeout: 1000
      });
      await client.send({ data: JSON.stringify({ jsonrpc: '2.0', id: requestId, method: 'runtime_lifecycle', params: event }) + '\n', encoding: 'utf-8' });
      const accepted = await acknowledgement;
      if (accepted) {
        logger.info(`Editor MCP accepted GameAbility lifecycle event ${type} for ${sessionId}`);
      } else {
        logger.error(`Editor MCP did not accept GameAbility lifecycle event ${type} for ${sessionId}`);
      }
      return accepted;
    } catch (e) {
      logger.error(`Failed to deliver GameAbility lifecycle event ${type} to editor loopback gateway`, e);
      return false;
    } finally {
      try {
        await client.close();
      } catch (_e) {}
    }
  }

  public isGodotConnected(): boolean {
    if (!this.engineClient) return false;
    const state = this.clients.get(this.engineClient);
    return state !== undefined && state.isHandshakeComplete;
  }

  /**
   * Send an authoritative GameAbility lifecycle fact to the editor websocket.
   * No event is inferred from focus, window visibility, or screen capture.
   */
  public publishRuntimeLifecycle(
    type: string,
    sessionId: string,
    operationId: string,
    bootNonce: string,
    details?: Record<string, Object>
  ): void {
    if (!this.isRuntimeLifecycleType(type) ||
        !this.isCorrelationToken(sessionId) ||
        !this.isCorrelationToken(operationId) ||
        !this.isCorrelationToken(bootNonce)) {
      logger.error(`Rejected malformed runtime lifecycle event type=${type}`);
      return;
    }

    const event: RuntimeLifecycleEvent = {
      type: type,
      session_id: sessionId,
      operation_id: operationId,
      boot_nonce: bootNonce,
      event_id: `ohos_${Date.now()}_${++this.requestIdCounter}`,
      timestamp_ms: Date.now(),
      source: 'game_ability'
    };
    if (details) {
      event.details = details;
    }
    if (!this.sendRuntimeLifecycleEvent(event)) {
      if (this.pendingRuntimeLifecycleEvents.length >= 32) {
        this.pendingRuntimeLifecycleEvents.shift();
      }
      this.pendingRuntimeLifecycleEvents.push(event);
      logger.warn(`Queued runtime lifecycle event ${type}; editor MCP websocket is unavailable`);
    }
  }

  private isCorrelationToken(value: string): boolean {
    return value.length > 0 && value.length <= 160 && /^[A-Za-z0-9._:-]+$/.test(value);
  }

  private isRuntimeLifecycleType(type: string): boolean {
    return type === 'REAL_READY' || type === 'REAL_STOP_ACK' || type === 'REAL_EXIT' || type === 'ABRUPT_EXIT';
  }

  private sendRuntimeLifecycleEvent(event: RuntimeLifecycleEvent): boolean {
    if (!this.engineClient || !this.isGodotConnected()) {
      return false;
    }
    const payload = JSON.stringify({
      jsonrpc: '2.0',
      method: 'runtime_lifecycle',
      params: event
    });
    const bytes: Uint8Array = this.textEncoder.encodeInto(payload);
    this.sendWebSocketFrame(this.engineClient, 0x01, bytes);
    logger.info(`Published runtime lifecycle event ${event.type} for ${event.session_id}`);
    return true;
  }

  private flushRuntimeLifecycleEvents(): void {
    if (!this.isGodotConnected() || this.pendingRuntimeLifecycleEvents.length === 0) {
      return;
    }
    const pending = this.pendingRuntimeLifecycleEvents;
    this.pendingRuntimeLifecycleEvents = [];
    for (let i = 0; i < pending.length; i++) {
      if (!this.sendRuntimeLifecycleEvent(pending[i])) {
        this.pendingRuntimeLifecycleEvents.push(pending[i]);
        for (let j = i + 1; j < pending.length; j++) {
          this.pendingRuntimeLifecycleEvents.push(pending[j]);
        }
        return;
      }
    }
  }

  public async start(port: number = 6510): Promise<void> {
    if (this.isRunning) {
      logger.info(`GodotMcpServerGateway already running on port ${port}`);
      return;
    }
    try {
      this.tcpServer = socket.constructTCPSocketServerInstance();
      this.tcpServer.on('connect', (client: socket.TCPSocketConnection) => {
        this.handleNewConnection(client);
      });

      const netAddr: socket.NetAddress = {
        address: '127.0.0.1',
        port: port,
        family: 1
      };
      await this.tcpServer.listen(netAddr);
      this.isRunning = true;
      logger.info(`GodotMcpServerGateway successfully listening on 127.0.0.1:${port}`);
    } catch (err) {
      logger.error('Failed to start GodotMcpServerGateway', err);
    }
  }

  public async stop(): Promise<void> {
    this.isRunning = false;
    this.stopHeartbeat();
    this.clients.forEach((_state: ClientConnectionState, conn: socket.TCPSocketConnection) => {
      try {
        conn.close();
      } catch (_e) {}
    });
    this.clients.clear();
    this.engineClient = null;
    this.forwardedRequests.clear();
    this.pendingCommands.clear();
    this.pendingRuntimeLifecycleEvents = [];
    if (this.tcpServer) {
      try {
        this.tcpServer.close();
      } catch (_e) {}
      this.tcpServer = null;
    }
    logger.info('GodotMcpServerGateway stopped');
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimerId = setInterval(() => {
      if (this.engineClient && this.isGodotConnected()) {
        const pingObj: JsonRpcPingPong = {
          jsonrpc: '2.0',
          method: 'ping'
        };
        const pingBytes: Uint8Array = this.textEncoder.encodeInto(JSON.stringify(pingObj));
        this.sendWebSocketFrame(this.engineClient, 0x01, pingBytes);
      }
    }, 10000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimerId !== -1) {
      clearInterval(this.heartbeatTimerId);
      this.heartbeatTimerId = -1;
    }
  }

  private handleNewConnection(client: socket.TCPSocketConnection): void {
    logger.info('New client connection received on 6510 gateway, awaiting WS handshake');
    const state: ClientConnectionState = {
      client: client,
      isHandshakeComplete: false,
      isEngine: false,
      isRawTcp: false,
      rxBuffer: new Uint8Array(0)
    };
    this.clients.set(client, state);

    client.on('message', (value: socket.SocketMessageInfo) => {
      this.handleSocketData(client, value.message);
    });

    client.on('close', () => {
      logger.info('Client disconnected from 6510 gateway');
      this.clients.delete(client);
      if (this.engineClient === client) {
        this.engineClient = null;
        // Reject all in-flight forwarded requests immediately to prevent caller timeouts
        this.forwardedRequests.forEach((callerConn: socket.TCPSocketConnection, reqId: string) => {
          const errPayload: JsonRpcErrorPayload = {
            code: -32000,
            message: 'Godot Engine MCP disconnected while executing this command'
          };
          const errRespObj: JsonRpcErrorResponse = {
            jsonrpc: '2.0',
            id: reqId,
            error: errPayload
          };
          const errResp = JSON.stringify(errRespObj);
          const errBytes: Uint8Array = this.textEncoder.encodeInto(errResp);
          this.sendResponseToClient(callerConn, errResp, errBytes);
        });
        this.forwardedRequests.clear();

        // Check if there is another engine client
        this.clients.forEach((st: ClientConnectionState, conn: socket.TCPSocketConnection) => {
          if (st.isEngine && st.isHandshakeComplete) {
            this.engineClient = conn;
          }
        });
      }
    });

    client.on('error', (err) => {
      logger.error('Client socket error on 6510 gateway', err);
    });
  }

  private handleSocketData(client: socket.TCPSocketConnection, data: ArrayBuffer): void {
    const state = this.clients.get(client);
    if (!state) return;

    const newChunk = new Uint8Array(data);
    let allBytes: Uint8Array;
    if (!state.rxBuffer || state.rxBuffer.length === 0) {
      allBytes = newChunk;
    } else {
      allBytes = new Uint8Array(state.rxBuffer.length + newChunk.length);
      allBytes.set(state.rxBuffer, 0);
      allBytes.set(newChunk, state.rxBuffer.length);
    }

    if (state.isRawTcp) {
      const reqText = this.textDecoder.decodeToString(allBytes);
      const lines = reqText.split('\n');
      if (lines.length > 1) {
        for (let i = 0; i < lines.length - 1; i++) {
          const line = lines[i].trim();
          if (line.length > 0) {
            const lineBytes: Uint8Array = this.textEncoder.encodeInto(line);
            this.handleJsonRpcMessage(client, line, lineBytes);
          }
        }
        state.rxBuffer = this.textEncoder.encodeInto(lines[lines.length - 1]);
      } else {
        state.rxBuffer = allBytes;
      }
      return;
    }

    if (!state.isHandshakeComplete) {
      const reqText = this.textDecoder.decodeToString(allBytes);
      const trimmed = reqText.trim();
      if (trimmed.startsWith('{')) {
        state.isRawTcp = true;
        state.isHandshakeComplete = true;
        logger.info('Raw TCP JSON-RPC client connected on 6510 gateway');
        const lines = reqText.split('\n');
        if (lines.length > 1) {
          for (let i = 0; i < lines.length - 1; i++) {
            const line = lines[i].trim();
            if (line.length > 0) {
              const lineBytes: Uint8Array = this.textEncoder.encodeInto(line);
              this.handleJsonRpcMessage(client, line, lineBytes);
            }
          }
          state.rxBuffer = this.textEncoder.encodeInto(lines[lines.length - 1]);
        } else {
          state.rxBuffer = allBytes;
        }
        return;
      }

      // Process HTTP Handshake
      const lowerReq = reqText.toLowerCase();
      if (lowerReq.includes('upgrade: websocket') || lowerReq.includes('sec-websocket-key')) {
        const keyMatch = reqText.match(/sec-websocket-key:\s*([^\r\n\s]+)/i);
        if (keyMatch && keyMatch[1]) {
          const clientKey = keyMatch[1].trim();
          const acceptKey = base64Encode(sha1(clientKey + WS_GUID));

          const response =
            'HTTP/1.1 101 Switching Protocols\r\n' +
            'Upgrade: websocket\r\n' +
            'Connection: Upgrade\r\n' +
            `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`;

          try {
            client.send({ data: response });
            state.isHandshakeComplete = true;
            state.isEngine = true;
            this.engineClient = client;
            state.rxBuffer = new Uint8Array(0);
            this.startHeartbeat();
            this.flushRuntimeLifecycleEvents();
            logger.info(`WebSocket handshake completed on 6510 gateway (total clients: ${this.clients.size})`);
          } catch (e) {
            logger.error('Failed to send handshake response', e);
          }
        }
      }
      return;
    }

    // Process WebSocket Frames
    state.rxBuffer = this.decodeWebSocketFrames(client, allBytes);
  }

  private decodeWebSocketFrames(client: socket.TCPSocketConnection, bytes: Uint8Array): Uint8Array {
    let offset = 0;
    while (offset < bytes.length) {
      const frameStart = offset;
      if (offset + 2 > bytes.length) {
        return bytes.subarray(frameStart);
      }
      const b0 = bytes[offset++];
      const b1 = bytes[offset++];

      const opcode = b0 & 0x0f;
      const isMasked = (b1 & 0x80) !== 0;
      let payloadLen = b1 & 0x7f;

      if (payloadLen === 126) {
        if (offset + 2 > bytes.length) {
          return bytes.subarray(frameStart);
        }
        payloadLen = (bytes[offset] << 8) | bytes[offset + 1];
        offset += 2;
      } else if (payloadLen === 127) {
        if (offset + 8 > bytes.length) {
          return bytes.subarray(frameStart);
        }
        payloadLen = ((bytes[offset + 4] << 24) >>> 0) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7];
        offset += 8;
      }

      let maskKey: Uint8Array | null = null;
      if (isMasked) {
        if (offset + 4 > bytes.length) {
          return bytes.subarray(frameStart);
        }
        maskKey = bytes.subarray(offset, offset + 4);
        offset += 4;
      }

      if (offset + payloadLen > bytes.length) {
        return bytes.subarray(frameStart);
      }
      const payload = bytes.subarray(offset, offset + payloadLen);
      offset += payloadLen;

      const unmasked = new Uint8Array(payload.length);
      for (let i = 0; i < payload.length; i++) {
        unmasked[i] = maskKey ? payload[i] ^ maskKey[i % 4] : payload[i];
      }

      // Handle Opcode
      if (opcode === 0x01) {
        // Text frame (JSON-RPC)
        const text = this.textDecoder.decodeToString(unmasked);
        this.handleJsonRpcMessage(client, text, unmasked);
      } else if (opcode === 0x08) {
        // Close frame
        try {
          client.close();
        } catch (_e) {}
      } else if (opcode === 0x09) {
        // Ping frame -> reply with Pong
        this.sendWebSocketFrame(client, 0x0a, unmasked);
      }
    }
    return new Uint8Array(0);
  }

  private sendResponseToClient(client: socket.TCPSocketConnection, text: string, rawBytes: Uint8Array): void {
    const state = this.clients.get(client);
    if (!state) return;
    if (state.isRawTcp) {
      try {
        client.send({ data: text + '\n' });
      } catch (e) {
        logger.error('Failed to send raw TCP response', e);
      }
    } else {
      this.sendWebSocketFrame(client, 0x01, rawBytes);
    }
  }

  private handleJsonRpcMessage(client: socket.TCPSocketConnection, text: string, rawPayloadBytes: Uint8Array): void {
    try {
      const msg = JSON.parse(text) as Record<string, Object>;
      const method = String(msg['method'] || '');
      const id = String(msg['id'] || '');
      const state = this.clients.get(client);

      // Handle pong from Godot
      if (method === 'pong') {
        if (state) {
          state.isEngine = true;
          this.engineClient = client;
        }
        this.flushRuntimeLifecycleEvents();
        return;
      }

      // Handle Godot MCP addon auth_required or engine_ready message
      if (method === 'auth_required' || method === 'engine_ready') {
        if (state) {
          state.isEngine = true;
          this.engineClient = client;
        }
        if (method === 'auth_required') {
          // Immediately authenticate Godot addon with empty token
          const authParams: JsonRpcAuthParams = { token: '' };
          const authMsg: JsonRpcAuthMessage = {
            jsonrpc: '2.0',
            id: 'auth_init',
            method: 'auth',
            params: authParams
          };
          const authPayload = JSON.stringify(authMsg);
          const authBytes: Uint8Array = this.textEncoder.encodeInto(authPayload);
          this.sendWebSocketFrame(client, 0x01, authBytes);
        }
        logger.info(`Godot MCP Engine identified (${method}) and ready on 6510`);
        this.flushRuntimeLifecycleEvents();
        return;
      }

      // Respond immediately to Godot ping message with protocol-compliant JSON-RPC pong
      if (method === 'ping') {
        if (state) {
          state.isEngine = true;
          this.engineClient = client;
        }
        let pongResponse = '';
        if (id && id.length > 0) {
          const res: JsonRpcPongResult = { pong: true };
          const pongObj: JsonRpcPingPong = {
            jsonrpc: '2.0',
            id: id,
            result: res
          };
          pongResponse = JSON.stringify(pongObj);
        } else {
          const pongObj: JsonRpcPingPong = {
            jsonrpc: '2.0',
            method: 'pong'
          };
          pongResponse = JSON.stringify(pongObj);
        }
        const pongBytes: Uint8Array = this.textEncoder.encodeInto(pongResponse);
        this.sendWebSocketFrame(client, 0x01, pongBytes);
        return;
      }

      const paramsObj = msg['params'] as Record<string, Object> | undefined;
      if (method === 'runtime_lifecycle') {
        const eventType = String(paramsObj?.['type'] || '');
        const sessionId = String(paramsObj?.['session_id'] || '');
        const operationId = String(paramsObj?.['operation_id'] || '');
        const bootNonce = String(paramsObj?.['boot_nonce'] || '');
        const source = String(paramsObj?.['source'] || '');
        if (!state?.isRawTcp || !this.isRuntimeLifecycleType(eventType) ||
            !this.isCorrelationToken(sessionId) || !this.isCorrelationToken(operationId) ||
            !this.isCorrelationToken(bootNonce) || source !== 'game_ability') {
          logger.error('Rejected malformed or non-loopback runtime_lifecycle notification');
          return;
        }
      }
      // Method request from a caller (OpenCode, UI, etc.)
      if (method.length > 0) {
        if (this.engineClient && this.engineClient !== client) {
          if (id.length > 0) {
            this.forwardedRequests.set(id, client);
          }
          this.sendWebSocketFrame(this.engineClient, 0x01, rawPayloadBytes);
        } else if (this.engineClient === client) {
          // Message from engine client (notification/event)
          logger.info(`Engine event: ${method}`);
        } else {
          // No engine connected to execute the tool
          if (id.length > 0) {
            const errPayload: JsonRpcErrorPayload = {
              code: -32000,
              message: 'Godot Engine MCP is not connected on port 6510'
            };
            const errRespObj: JsonRpcErrorResponse = {
              jsonrpc: '2.0',
              id: id,
              error: errPayload
            };
            const errResp = JSON.stringify(errRespObj);
            const errBytes: Uint8Array = this.textEncoder.encodeInto(errResp);
            this.sendResponseToClient(client, errResp, errBytes);
          }
        }
        return;
      }

      // Response to a pending command (has id and result/error)
      if (id.length > 0) {
        if (this.pendingCommands.has(id)) {
          const pending = this.pendingCommands.get(id)!;
          clearTimeout(pending.timeoutId);
          this.pendingCommands.delete(id);
          pending.resolve(msg);
        } else if (this.forwardedRequests.has(id)) {
          const callerConn = this.forwardedRequests.get(id)!;
          this.forwardedRequests.delete(id);
          this.sendResponseToClient(callerConn, text, rawPayloadBytes);
        }
      }
    } catch (e) {
      logger.error('Failed to parse incoming JSON-RPC on 6510 gateway', e);
    }
  }

  public sendWebSocketFrame(client: socket.TCPSocketConnection | null, opcode: number, payloadBytes: Uint8Array): void {
    if (!client) return;
    const state = this.clients.get(client);
    if (!state || !state.isHandshakeComplete) return;

    const len = payloadBytes.length;
    let headerLen = 2;
    if (len >= 126 && len <= 65535) headerLen = 4;
    else if (len > 65535) headerLen = 10;

    const frame = new Uint8Array(headerLen + len);
    frame[0] = 0x80 | (opcode & 0x0f); // FIN + opcode

    if (len < 126) {
      frame[1] = len;
      frame.set(payloadBytes, 2);
    } else if (len <= 65535) {
      frame[1] = 126;
      frame[2] = (len >> 8) & 0xff;
      frame[3] = len & 0xff;
      frame.set(payloadBytes, 4);
    } else {
      frame[1] = 127;
      frame[2] = 0; frame[3] = 0; frame[4] = 0; frame[5] = 0;
      frame[6] = (len >> 24) & 0xff;
      frame[7] = (len >> 16) & 0xff;
      frame[8] = (len >> 8) & 0xff;
      frame[9] = len & 0xff;
      frame.set(payloadBytes, 10);
    }

    try {
      client.send({ data: frame.buffer.slice(frame.byteOffset, frame.byteOffset + frame.byteLength) as ArrayBuffer });
    } catch (e) {
      logger.error('Failed to send WebSocket frame to client', e);
    }
  }

  /**
   * Dispatch a tool command to Godot MCP plugin and await the JSON-RPC response.
   */
  public async executeGodotCommand(method: string, params: Record<string, Object> = {}, timeoutMs: number = 5000): Promise<Record<string, Object>> {
    if (!this.isGodotConnected() || !this.engineClient) {
      throw new Error('Godot MCP Pro is not connected on port 6510');
    }

    const reqId = `gw_${++this.requestIdCounter}`;
    const payload = JSON.stringify({
      jsonrpc: '2.0',
      id: reqId,
      method: method,
      params: params
    });

    return new Promise<Record<string, Object>>((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        this.pendingCommands.delete(reqId);
        reject(new Error(`Command ${method} timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      const pending: PendingCommand = {
        resolve: resolve,
        reject: reject,
        timeoutId: timeoutId
      };
      this.pendingCommands.set(reqId, pending);

      const bytes: Uint8Array = this.textEncoder.encodeInto(payload);
      this.sendWebSocketFrame(this.engineClient, 0x01, bytes);
    });
  }

}

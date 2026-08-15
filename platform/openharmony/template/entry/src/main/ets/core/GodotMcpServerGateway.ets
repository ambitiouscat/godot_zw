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
  const utf8 = new util.TextEncoder().encodeInto(input);
  const msgLen = utf8.length;
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

/**
 * Dedicated local 6505 WebSocket server gateway.
 * Serves as the middle bridge between Godot's websocket_server.gd client and OpenCode's AI engine.
 */
export class GodotMcpServerGateway {
  private static instance: GodotMcpServerGateway | null = null;
  private tcpServer: socket.TCPSocketServer | null = null;
  private activeClient: socket.TCPSocketConnection | null = null;
  private isHandshakeComplete: boolean = false;
  private isRunning: boolean = false;
  private requestIdCounter: number = 1000;
  private pendingCommands: Map<string, PendingCommand> = new Map();
  private textDecoder = new util.TextDecoder();
  private textEncoder = new util.TextEncoder();

  private heartbeatTimerId: number = -1;

  public static getInstance(): GodotMcpServerGateway {
    if (!GodotMcpServerGateway.instance) {
      GodotMcpServerGateway.instance = new GodotMcpServerGateway();
    }
    return GodotMcpServerGateway.instance;
  }

  public isGodotConnected(): boolean {
    return this.activeClient !== null && this.isHandshakeComplete;
  }

  public async start(port: number = 6505): Promise<void> {
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
    if (this.activeClient) {
      try {
        this.activeClient.close();
      } catch (_e) {}
      this.activeClient = null;
      this.isHandshakeComplete = false;
    }
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
      if (this.isGodotConnected()) {
        const pingObj: JsonRpcPingPong = {
          jsonrpc: '2.0',
          method: 'ping'
        };
        const pingBytes = this.textEncoder.encodeInto(JSON.stringify(pingObj));
        this.sendWebSocketFrame(0x01, pingBytes);
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
    logger.info('Godot client connected to 6505 gateway, awaiting WS handshake');
    this.stopHeartbeat();
    if (this.activeClient && this.activeClient !== client) {
      try {
        this.activeClient.close();
      } catch (_e) {}
    }
    this.activeClient = client;
    this.isHandshakeComplete = false;

    client.on('message', (value: socket.SocketMessageInfo) => {
      this.handleSocketData(value.message);
    });

    client.on('close', () => {
      logger.info('Godot client disconnected from 6505 gateway');
      this.stopHeartbeat();
      if (this.activeClient === client) {
        this.activeClient = null;
        this.isHandshakeComplete = false;
      }
    });

    client.on('error', (err) => {
      logger.error('Godot client socket error', err);
    });
  }

  private handleSocketData(data: ArrayBuffer): void {
    if (!this.isHandshakeComplete) {
      // Process HTTP Handshake
      const reqText = this.textDecoder.decodeToString(new Uint8Array(data));
      if (reqText.includes('Upgrade: websocket') || reqText.includes('Upgrade: WebSocket')) {
        const keyMatch = reqText.match(/Sec-WebSocket-Key:\s*([^\r\n]+)/i);
        if (keyMatch && keyMatch[1]) {
          const clientKey = keyMatch[1].trim();
          const acceptKey = base64Encode(sha1(clientKey + WS_GUID));

          const response =
            'HTTP/1.1 101 Switching Protocols\r\n' +
            'Upgrade: websocket\r\n' +
            'Connection: Upgrade\r\n' +
            `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`;

          const respBytes = this.textEncoder.encodeInto(response);
          this.activeClient?.send({ data: respBytes.buffer as ArrayBuffer });
          this.isHandshakeComplete = true;
          this.startHeartbeat();
          logger.info('WebSocket handshake completed with Godot MCP Pro plugin on 6505');
        }
      }
      return;
    }

    // Process WebSocket Frames
    this.decodeWebSocketFrames(new Uint8Array(data));
  }

  private decodeWebSocketFrames(bytes: Uint8Array): void {
    let offset = 0;
    while (offset < bytes.length) {
      if (offset + 2 > bytes.length) break;
      const b0 = bytes[offset++];
      const b1 = bytes[offset++];

      const opcode = b0 & 0x0f;
      const isMasked = (b1 & 0x80) !== 0;
      let payloadLen = b1 & 0x7f;

      if (payloadLen === 126) {
        if (offset + 2 > bytes.length) break;
        payloadLen = (bytes[offset] << 8) | bytes[offset + 1];
        offset += 2;
      } else if (payloadLen === 127) {
        offset += 8; // 64-bit len (simplified)
      }

      let maskKey: Uint8Array | null = null;
      if (isMasked) {
        if (offset + 4 > bytes.length) break;
        maskKey = bytes.subarray(offset, offset + 4);
        offset += 4;
      }

      if (offset + payloadLen > bytes.length) break;
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
        this.handleJsonRpcMessage(text);
      } else if (opcode === 0x08) {
        // Close frame
        this.activeClient?.close();
      } else if (opcode === 0x09) {
        // Ping frame -> reply with Pong
        this.sendWebSocketFrame(0x0a, unmasked);
      }
    }
  }

  private handleJsonRpcMessage(text: string): void {
    try {
      const msg = JSON.parse(text) as Record<string, Object>;
      const method = String(msg['method'] || '');
      const id = String(msg['id'] || '');

      // Handle pong from Godot
      if (method === 'pong') {
        return;
      }

      // Respond immediately to Godot ping message with protocol-compliant JSON-RPC pong
      if (method === 'ping') {
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
        const pongBytes = this.textEncoder.encodeInto(pongResponse);
        this.sendWebSocketFrame(0x01, pongBytes);
        return;
      }

      if (id && this.pendingCommands.has(id)) {
        const pending = this.pendingCommands.get(id)!;
        clearTimeout(pending.timeoutId);
        this.pendingCommands.delete(id);
        pending.resolve(msg);
      }
    } catch (e) {
      logger.error('Failed to parse incoming JSON-RPC from Godot', e);
    }
  }

  public sendWebSocketFrame(opcode: number, payloadBytes: Uint8Array): void {
    if (!this.activeClient || !this.isHandshakeComplete) return;

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

    this.activeClient.send({ data: frame.buffer as ArrayBuffer });
  }

  /**
   * Dispatch a tool command to Godot MCP plugin and await the JSON-RPC response.
   */
  public async executeGodotCommand(method: string, params: Record<string, Object> = {}, timeoutMs: number = 30000): Promise<Record<string, Object>> {
    if (!this.isGodotConnected()) {
      throw new Error('Godot MCP Pro is not connected on port 6505');
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

      this.pendingCommands.set(reqId, {
        resolve: resolve,
        reject: reject,
        timeoutId: timeoutId
      });

      const bytes = this.textEncoder.encodeInto(payload);
      this.sendWebSocketFrame(0x01, bytes);
    });
  }
}

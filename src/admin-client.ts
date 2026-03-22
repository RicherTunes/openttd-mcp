/**
 * OpenTTD Admin Port TCP client.
 * Handles connection, X25519 PAKE authentication, packet framing,
 * streaming encryption, and event dispatch.
 * Includes auto-reconnect and TCP keepalive for stability.
 */

import * as net from "node:net";
import * as fs from "node:fs";
import { EventEmitter } from "node:events";

const DEBUG_ENABLED = process.env.OPENTTD_DEBUG === "true";
const LOG_FILE = process.env.OPENTTD_DEBUG_LOG || (process.platform === "win32" ? "" : "/tmp/openttd-mcp-debug.log");

function debugLog(msg: string) {
  if (!DEBUG_ENABLED || !LOG_FILE) return;
  try {
    const ts = new Date().toISOString();
    fs.appendFileSync(LOG_FILE, `[${ts}] ${msg}\n`);
  } catch {
    // Silently ignore logging failures
  }
}
import { PacketReader } from "./protocol/reader.js";
import {
  AdminPacketType,
  ServerPacketType,
  AdminUpdateType,
  AdminUpdateFrequency,
  DestType,
  NetworkAction,
} from "./protocol/types.js";
import {
  buildJoinPacket,
  buildJoinSecurePacket,
  buildAuthResponsePacket,
  buildQuitPacket,
  buildUpdateFrequencyPacket,
  buildPollPacket,
  buildChatPacket,
  buildRconPacket,
  buildGameScriptPacket,
  buildPingPacket,
  parseServerProtocol,
  parseServerWelcome,
  parseServerDate,
  parseClientInfo,
  parseClientJoin,
  parseClientUpdate,
  parseClientQuit,
  parseClientError,
  parseCompanyInfo,
  parseCompanyUpdate,
  parseCompanyNew,
  parseCompanyRemove,
  parseCompanyEconomy,
  parseCompanyStats,
  parseChatMessage,
  parseRconResponse,
  parseRconEnd,
  parseConsoleMessage,
  parseGameScriptMessage,
  parsePongMessage,
  parseServerError,
  parseAuthRequest,
  parseEnableEncryption,
  ottdDateToString,
  type ServerWelcome,
  type ServerProtocol,
  type CompanyInfo,
  type ClientInfo,
  type CompanyEconomy,
  type CompanyStats,
} from "./protocol/packets.js";
import {
  ensureSodiumReady,
  computePakeResponse,
  NetworkAuthMethod,
  StreamingAead,
} from "./protocol/crypto.js";
import type { GameScriptCommand, GameScriptResponse } from "./types/openttd.js";

export interface AdminClientOptions {
  host: string;
  port: number;
  password: string;
  botName?: string;
  botVersion?: string;
}

interface PendingRcon {
  lines: string[];
  resolve: (lines: string[]) => void;
  reject: (error: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

interface PendingGameScript {
  resolve: (response: GameScriptResponse) => void;
  reject: (error: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

export class AdminClient extends EventEmitter {
  private socket: net.Socket | null = null;
  private recvBuffer: Buffer = Buffer.alloc(0);
  private connected: boolean = false;
  private authenticated: boolean = false;

  // Encryption state
  private encryptionEnabled: boolean = false;
  private sendEncryption: StreamingAead | null = null;
  private recvEncryption: StreamingAead | null = null;
  // Store derived keys during auth handshake (before encryption is enabled)
  private pendingEncryptionKeys: {
    clientToServer: Buffer;
    serverToClient: Buffer;
  } | null = null;

  // Server state
  public serverInfo: ServerWelcome | null = null;
  public protocol: ServerProtocol | null = null;
  public companies: Map<number, CompanyInfo> = new Map();
  public clients: Map<number, ClientInfo> = new Map();
  public currentDate: number = 0;
  public currentDateStr: string = "";

  // Pending RCON commands
  private pendingRcon: PendingRcon | null = null;

  // Pending GameScript commands (only one in flight at a time)
  private pendingGameScript: Map<string, PendingGameScript> = new Map();
  private gsCommandCounter: number = 0;
  private gsQueue: Array<{
    id: string;
    command: GameScriptCommand;
    timeoutMs: number;
    resolve: (response: GameScriptResponse) => void;
    reject: (error: Error) => void;
  }> = [];
  private gsInFlight: boolean = false;

  // Keepalive
  private pingInterval: ReturnType<typeof setInterval> | null = null;

  // Auto-reconnect
  private lastOptions: AdminClientOptions | null = null;
  private reconnecting: boolean = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private intentionalDisconnect: boolean = false;

  // Chunked GameScript response accumulator
  private gsChunkBuffers: Map<
    string,
    { chunks: GameScriptResponse[]; total: number }
  > = new Map();

  get isConnected(): boolean {
    return this.connected && this.authenticated;
  }

  async connect(options: AdminClientOptions): Promise<ServerWelcome> {
    // Ensure libsodium is ready
    await ensureSodiumReady();

    // Cancel any pending reconnect first - prevents race conditions
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.reconnecting = false;

    // Clean up any existing socket (connected or not)
    if (this.socket) {
      this.intentionalDisconnect = true;
      this.cleanupSocket();
      this.intentionalDisconnect = false;
    }

    // Store for auto-reconnect
    this.lastOptions = options;

    return new Promise((resolve, reject) => {
      let settled = false;
      const settle = () => {
        settled = true;
      };

      const socket = new net.Socket();
      this.socket = socket;

      // Enable TCP keepalive - detect dead connections faster
      socket.setKeepAlive(true, 10000);
      socket.setNoDelay(true);

      const connectTimeout = setTimeout(() => {
        if (!settled) {
          settle();
          socket.destroy();
          reject(new Error("Connection timeout (10s)"));
        }
      }, 10000);

      socket.connect(options.port, options.host, () => {
        this.connected = true;
        // Use secure join (X25519 PAKE) — OpenTTD 14+
        const supportedMethods =
          (1 << NetworkAuthMethod.X25519_PAKE) |
          (1 << NetworkAuthMethod.X25519_KEY_EXCHANGE_ONLY);
        const joinPacket = buildJoinSecurePacket(
          options.botName ?? "ClaudeMCP",
          options.botVersion ?? "1.0.0",
          supportedMethods
        );
        this.rawWrite(joinPacket);
      });

      socket.on("data", (data: Buffer) => {
        this.recvBuffer = Buffer.concat([this.recvBuffer, data]);
        this.processBuffer();
      });

      socket.on("error", (err) => {
        debugLog(`Socket error: ${err.message} (authenticated=${this.authenticated})`);
        clearTimeout(connectTimeout);
        const wasAuthenticated = this.authenticated;
        this.cleanupSocket();
        if (!wasAuthenticated) {
          if (!settled) {
            settle();
            reject(new Error(`Connection error: ${err.message}`));
          }
        } else {
          this.emit("error", err);
          this.scheduleReconnect();
        }
      });

      socket.on("close", () => {
        debugLog(`Socket closed (authenticated=${this.authenticated}, intentional=${this.intentionalDisconnect})`);
        clearTimeout(connectTimeout);
        const wasAuthenticated = this.authenticated;
        this.cleanupSocket();
        this.emit("close");
        if (wasAuthenticated && !this.intentionalDisconnect) {
          this.scheduleReconnect();
        } else if (!wasAuthenticated && !settled) {
          settle();
          reject(
            new Error("Connection closed before authentication completed")
          );
        }
      });

      // Handle secure auth: SERVER_AUTH_REQUEST → compute PAKE → ADMIN_AUTH_RESPONSE
      const onAuthRequest = (authReq: {
        method: number;
        serverPublicKey: Buffer;
        nonce: Buffer;
      }) => {
        debugLog(`Auth request: method=${authReq.method}`);
        try {
          const pake = computePakeResponse(
            authReq.serverPublicKey,
            authReq.nonce,
            options.password
          );
          // Store keys for enabling encryption later
          this.pendingEncryptionKeys = {
            clientToServer: pake.clientToServerKey,
            serverToClient: pake.serverToClientKey,
          };
          const authPacket = buildAuthResponsePacket(
            pake.clientPublicKey,
            pake.mac,
            pake.encryptedMessage
          );
          this.rawWrite(authPacket);
        } catch (err) {
          debugLog(`PAKE computation failed: ${err}`);
          if (!settled) {
            settle();
            reject(
              new Error(
                `Authentication failed: ${err instanceof Error ? err.message : String(err)}`
              )
            );
          }
        }
      };

      // Handle encryption enable: SERVER_ENABLE_ENCRYPTION → switch to encrypted I/O
      const onEnableEncryption = (encryptionNonce: Buffer) => {
        debugLog("Enabling encryption");
        if (this.pendingEncryptionKeys) {
          this.sendEncryption = new StreamingAead(
            this.pendingEncryptionKeys.clientToServer,
            encryptionNonce
          );
          this.recvEncryption = new StreamingAead(
            this.pendingEncryptionKeys.serverToClient,
            encryptionNonce
          );
          this.encryptionEnabled = true;
          this.pendingEncryptionKeys = null;
          debugLog("Encryption enabled");
        }
      };

      const onWelcome = (welcome: ServerWelcome) => {
        clearTimeout(connectTimeout);
        this.removeListener("_authRequest", onAuthRequest);
        this.removeListener("_enableEncryption", onEnableEncryption);
        this.removeListener("_welcome", onWelcome);
        this.removeListener("_authFailed", onAuthFailed);
        if (!settled) {
          settle();
          this.authenticated = true;
          this.serverInfo = welcome;
          this.setupSubscriptions();
          this.startKeepalive();
          resolve(welcome);
        }
      };

      const onAuthFailed = (err: Error) => {
        clearTimeout(connectTimeout);
        this.removeListener("_authRequest", onAuthRequest);
        this.removeListener("_enableEncryption", onEnableEncryption);
        this.removeListener("_welcome", onWelcome);
        this.removeListener("_authFailed", onAuthFailed);
        if (!settled) {
          settle();
          reject(err);
        }
      };

      this.on("_authRequest", onAuthRequest);
      this.on("_enableEncryption", onEnableEncryption);
      this.on("_welcome", onWelcome);
      this.on("_authFailed", onAuthFailed);
    });
  }

  /** Auto-reconnect with stored credentials */
  async reconnect(): Promise<ServerWelcome> {
    if (!this.lastOptions) {
      throw new Error("No previous connection to reconnect to");
    }
    return this.connect(this.lastOptions);
  }

  private scheduleReconnect(): void {
    if (this.reconnecting || this.intentionalDisconnect || !this.lastOptions)
      return;
    this.reconnecting = true;

    const tryReconnect = async (
      delay: number,
      maxRetries: number,
      retryNum: number
    ) => {
      if (this.isConnected || this.intentionalDisconnect) {
        this.reconnecting = false;
        return;
      }
      if (retryNum >= maxRetries) {
        this.reconnecting = false;
        this.emit("reconnectFailed");
        return;
      }

      this.reconnectTimer = setTimeout(async () => {
        try {
          await this.connect(this.lastOptions!);
          this.reconnecting = false;
          this.emit("reconnected");
        } catch {
          const nextDelay = Math.min(delay * 2, 16000);
          tryReconnect(nextDelay, maxRetries, retryNum + 1);
        }
      }, delay);
    };

    tryReconnect(1000, 5, 0);
  }

  async disconnect(): Promise<void> {
    this.intentionalDisconnect = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.reconnecting = false;

    if (this.socket && this.connected) {
      try {
        this.safeWrite(buildQuitPacket());
      } catch {
        // ignore write errors during disconnect
      }
    }
    this.cleanupSocket();
    this.cleanup();
    this.intentionalDisconnect = false;
  }

  /** Raw write — no encryption (used during auth handshake) */
  private rawWrite(data: Buffer): boolean {
    if (!this.socket || !this.connected) return false;
    try {
      this.socket.write(data);
      return true;
    } catch {
      this.cleanupSocket();
      this.scheduleReconnect();
      return false;
    }
  }

  /**
   * Safe write — encrypts the packet if encryption is enabled.
   * After encryption: [size(2)] [MAC(16)] [encrypted(type + payload)]
   * The size field is NOT encrypted (needed for framing), but type + payload ARE.
   */
  private safeWrite(data: Buffer): boolean {
    if (!this.socket || !this.connected) return false;
    try {
      if (this.encryptionEnabled && this.sendEncryption) {
        // Encrypt type + payload (everything after the 2-byte size field)
        const typeAndPayload = data.subarray(2);
        const encrypted = this.sendEncryption.encrypt(typeAndPayload);
        // encrypted = MAC(16) + ciphertext
        // New packet: [new_size(2)] [MAC(16)] [ciphertext]
        const newSize = 2 + encrypted.length;
        const header = Buffer.alloc(2);
        header.writeUInt16LE(newSize, 0);
        this.socket.write(Buffer.concat([header, encrypted]));
      } else {
        this.socket.write(data);
      }
      return true;
    } catch {
      this.cleanupSocket();
      this.scheduleReconnect();
      return false;
    }
  }

  private cleanupSocket(): void {
    this.connected = false;
    this.authenticated = false;
    this.encryptionEnabled = false;
    this.sendEncryption = null;
    this.recvEncryption = null;
    this.pendingEncryptionKeys = null;
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
    if (this.socket) {
      this.socket.removeAllListeners();
      this.socket.destroy();
      this.socket = null;
    }
    this.recvBuffer = Buffer.alloc(0);

    // Reject pending operations
    if (this.pendingRcon) {
      this.pendingRcon.reject(new Error("Connection closed"));
      clearTimeout(this.pendingRcon.timeout);
      this.pendingRcon = null;
    }
    for (const [, pending] of this.pendingGameScript) {
      pending.reject(new Error("Connection closed"));
      clearTimeout(pending.timeout);
    }
    this.pendingGameScript.clear();
    this.gsChunkBuffers.clear();

    // Reject queued commands
    for (const queued of this.gsQueue) {
      queued.reject(new Error("Connection closed"));
    }
    this.gsQueue = [];
    this.gsInFlight = false;
  }

  private cleanup(): void {
    this.cleanupSocket();
    this.companies.clear();
    this.clients.clear();
    this.serverInfo = null;
    this.protocol = null;
  }

  private setupSubscriptions(): void {
    if (!this.socket) return;

    // Send subscriptions one at a time with small delays to avoid overwhelming the server
    const subscriptions: [AdminUpdateType, AdminUpdateFrequency][] = [
      [AdminUpdateType.GAMESCRIPT, AdminUpdateFrequency.AUTOMATIC],
      [AdminUpdateType.DATE, AdminUpdateFrequency.DAILY],
      [AdminUpdateType.CLIENT_INFO, AdminUpdateFrequency.AUTOMATIC],
      [AdminUpdateType.COMPANY_INFO, AdminUpdateFrequency.AUTOMATIC],
      [AdminUpdateType.CHAT, AdminUpdateFrequency.AUTOMATIC],
      [AdminUpdateType.CONSOLE, AdminUpdateFrequency.AUTOMATIC],
    ];

    for (const [type, freq] of subscriptions) {
      this.safeWrite(buildUpdateFrequencyPacket(type, freq));
    }

    // Poll initial state
    setTimeout(() => {
      this.safeWrite(buildPollPacket(AdminUpdateType.DATE));
      this.safeWrite(buildPollPacket(AdminUpdateType.CLIENT_INFO));
      this.safeWrite(buildPollPacket(AdminUpdateType.COMPANY_INFO));
    }, 500);
  }

  private startKeepalive(): void {
    if (this.pingInterval) clearInterval(this.pingInterval);
    this.pingInterval = setInterval(() => {
      if (this.socket && this.connected) {
        this.safeWrite(buildPingPacket((Date.now() & 0xffffffff) >>> 0));
      }
    }, 15000);
  }

  private processBuffer(): void {
    while (this.recvBuffer.length >= 2) {
      const size = this.recvBuffer.readUInt16LE(0);
      if (size < 3) {
        this.recvBuffer = this.recvBuffer.subarray(1);
        continue;
      }
      if (this.recvBuffer.length < size) {
        break;
      }

      // Extract the body (everything after the 2-byte size field)
      const body = this.recvBuffer.subarray(2, size);
      this.recvBuffer = this.recvBuffer.subarray(size);

      let packetType: number;
      let payload: Buffer;

      if (this.encryptionEnabled && this.recvEncryption) {
        // Encrypted: body = MAC(16) + ciphertext
        // Decrypt to get type(1) + payload
        try {
          const decrypted = this.recvEncryption.decrypt(body);
          packetType = decrypted[0];
          payload = decrypted.subarray(1);
        } catch (err) {
          this.emit(
            "error",
            new Error(`Decryption failed: ${err}`)
          );
          continue;
        }
      } else {
        // Unencrypted: body = type(1) + payload
        packetType = body[0];
        payload = body.subarray(1);
      }

      debugLog(`Recv packet type=${packetType} payload=${payload.length}bytes`);
      try {
        this.handlePacket(packetType, payload);
      } catch (err) {
        debugLog(`Packet parse error (type ${packetType}, ${payload.length} bytes): ${err}`);
        this.emit(
          "error",
          new Error(`Packet parse error (type ${packetType}): ${err}`)
        );
      }
    }
  }

  private handlePacket(type: number, payload: Buffer): void {
    const reader = new PacketReader(payload);

    switch (type) {
      case ServerPacketType.SERVER_AUTH_REQUEST: {
        const authReq = parseAuthRequest(reader);
        this.emit("_authRequest", authReq);
        break;
      }
      case ServerPacketType.SERVER_ENABLE_ENCRYPTION: {
        const { encryptionNonce } = parseEnableEncryption(reader);
        this.emit("_enableEncryption", encryptionNonce);
        break;
      }
      case ServerPacketType.SERVER_PROTOCOL: {
        this.protocol = parseServerProtocol(reader);
        break;
      }
      case ServerPacketType.SERVER_WELCOME: {
        const welcome = parseServerWelcome(reader);
        this.serverInfo = welcome;
        this.emit("_welcome", welcome);
        this.emit("welcome", welcome);
        break;
      }
      case ServerPacketType.SERVER_DATE: {
        const { date } = parseServerDate(reader);
        this.currentDate = date;
        this.currentDateStr = ottdDateToString(date);
        this.emit("date", this.currentDateStr);
        break;
      }
      case ServerPacketType.SERVER_CLIENT_JOIN: {
        const { clientId } = parseClientJoin(reader);
        if (this.socket) {
          this.safeWrite(
            buildPollPacket(AdminUpdateType.CLIENT_INFO, clientId)
          );
        }
        this.emit("clientJoin", clientId);
        break;
      }
      case ServerPacketType.SERVER_CLIENT_INFO: {
        const info = parseClientInfo(reader);
        this.clients.set(info.clientId, info);
        this.emit("clientInfo", info);
        break;
      }
      case ServerPacketType.SERVER_CLIENT_UPDATE: {
        const update = parseClientUpdate(reader);
        const existing = this.clients.get(update.clientId);
        if (existing) {
          existing.name = update.name;
          existing.companyId = update.companyId;
        }
        this.emit("clientUpdate", update);
        break;
      }
      case ServerPacketType.SERVER_CLIENT_QUIT: {
        const { clientId } = parseClientQuit(reader);
        this.clients.delete(clientId);
        this.emit("clientQuit", clientId);
        break;
      }
      case ServerPacketType.SERVER_CLIENT_ERROR: {
        const err = parseClientError(reader);
        this.clients.delete(err.clientId);
        this.emit("clientError", err);
        break;
      }
      case ServerPacketType.SERVER_COMPANY_NEW: {
        const { companyId } = parseCompanyNew(reader);
        if (this.socket) {
          this.safeWrite(
            buildPollPacket(AdminUpdateType.COMPANY_INFO, companyId)
          );
        }
        this.emit("companyNew", companyId);
        break;
      }
      case ServerPacketType.SERVER_COMPANY_INFO: {
        const info = parseCompanyInfo(reader);
        this.companies.set(info.companyId, info);
        this.emit("companyInfo", info);
        break;
      }
      case ServerPacketType.SERVER_COMPANY_UPDATE: {
        const update = parseCompanyUpdate(reader);
        const existing = this.companies.get(update.companyId);
        if (existing) {
          existing.name = update.name;
          existing.president = update.president;
          existing.colour = update.colour;
          existing.passworded = update.passworded;
        }
        this.emit("companyUpdate", update);
        break;
      }
      case ServerPacketType.SERVER_COMPANY_REMOVE: {
        const remove = parseCompanyRemove(reader);
        this.companies.delete(remove.companyId);
        this.emit("companyRemove", remove);
        break;
      }
      case ServerPacketType.SERVER_COMPANY_ECONOMY: {
        const economy = parseCompanyEconomy(reader);
        this.emit("companyEconomy", economy);
        break;
      }
      case ServerPacketType.SERVER_COMPANY_STATS: {
        const stats = parseCompanyStats(reader);
        this.emit("companyStats", stats);
        break;
      }
      case ServerPacketType.SERVER_CHAT: {
        const chat = parseChatMessage(reader);
        this.emit("chat", chat);
        break;
      }
      case ServerPacketType.SERVER_RCON: {
        const rcon = parseRconResponse(reader);
        if (this.pendingRcon) {
          this.pendingRcon.lines.push(rcon.output);
        }
        this.emit("rcon", rcon);
        break;
      }
      case ServerPacketType.SERVER_RCON_END: {
        parseRconEnd(reader);
        if (this.pendingRcon) {
          clearTimeout(this.pendingRcon.timeout);
          this.pendingRcon.resolve(this.pendingRcon.lines);
          this.pendingRcon = null;
        }
        break;
      }
      case ServerPacketType.SERVER_CONSOLE: {
        const console = parseConsoleMessage(reader);
        this.emit("console", console);
        break;
      }
      case ServerPacketType.SERVER_GAMESCRIPT: {
        const gs = parseGameScriptMessage(reader);
        try {
          const response = JSON.parse(gs.json) as GameScriptResponse;

          if (response.id && (response as any)._chunk !== undefined) {
            this.handleChunkedResponse(response);
            break;
          }

          if (response.id && this.pendingGameScript.has(response.id)) {
            const pending = this.pendingGameScript.get(response.id)!;
            clearTimeout(pending.timeout);
            this.pendingGameScript.delete(response.id);
            pending.resolve(response);
          }
        } catch {
          // Not a JSON response or not matching our format
        }
        this.emit("gamescript", gs);
        break;
      }
      case ServerPacketType.SERVER_PONG: {
        const pong = parsePongMessage(reader);
        this.emit("pong", pong);
        break;
      }
      case ServerPacketType.SERVER_NEWGAME: {
        this.companies.clear();
        this.clients.clear();
        this.currentDate = 0;
        this.currentDateStr = "";
        this.emit("newgame");
        this.setupSubscriptions();
        break;
      }
      case ServerPacketType.SERVER_SHUTDOWN: {
        this.emit("shutdown");
        this.cleanupSocket();
        break;
      }
      case ServerPacketType.SERVER_FULL: {
        this.emit("_authFailed", new Error("Server is full"));
        break;
      }
      case ServerPacketType.SERVER_BANNED: {
        this.emit("_authFailed", new Error("Banned from server"));
        break;
      }
      case ServerPacketType.SERVER_ERROR: {
        const err = parseServerError(reader);
        if (!this.authenticated) {
          this.emit(
            "_authFailed",
            new Error(`Server error: code ${err.errorCode} (wrong password?)`)
          );
        }
        this.emit("serverError", err);
        break;
      }
    }
  }

  /** Handle chunked GameScript responses */
  private handleChunkedResponse(chunk: any): void {
    const id = chunk.id as string;
    const chunkIdx = chunk._chunk as number;
    const totalChunks = chunk._total as number;

    if (!this.gsChunkBuffers.has(id)) {
      this.gsChunkBuffers.set(id, {
        chunks: new Array(totalChunks),
        total: totalChunks,
      });
    }

    const buf = this.gsChunkBuffers.get(id)!;
    buf.chunks[chunkIdx] = chunk;

    const received = buf.chunks.filter((c) => c != null).length;
    if (received === buf.total) {
      this.gsChunkBuffers.delete(id);

      const mergedResult: any[] = [];
      for (const c of buf.chunks) {
        if (c.result && Array.isArray(c.result)) {
          mergedResult.push(...c.result);
        }
      }

      const finalResponse: GameScriptResponse = {
        id,
        success: true,
        result: mergedResult,
      };

      if (this.pendingGameScript.has(id)) {
        const pending = this.pendingGameScript.get(id)!;
        clearTimeout(pending.timeout);
        this.pendingGameScript.delete(id);
        pending.resolve(finalResponse);
      }
    }
  }

  // ============ Public API ============

  /** Ensure we're connected, always do a fresh reconnect if dropped */
  async ensureConnected(): Promise<void> {
    if (this.isConnected) return;
    if (this.lastOptions) {
      await this.reconnect();
    } else {
      throw new Error("Not connected to server. Use connect_to_server first.");
    }
  }

  /** Execute an RCON command */
  async executeRcon(
    command: string,
    timeoutMs: number = 10000
  ): Promise<string[]> {
    await this.ensureConnected();
    if (!this.socket) throw new Error("Not connected to server");
    if (this.pendingRcon) {
      throw new Error("Another RCON command is already pending");
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (this.pendingRcon) {
          resolve(this.pendingRcon.lines);
          this.pendingRcon = null;
        }
      }, timeoutMs);

      this.pendingRcon = { lines: [], resolve, reject, timeout };
      this.safeWrite(buildRconPacket(command));
    });
  }

  /** Send a chat message */
  async sendChat(
    message: string,
    destType: DestType = DestType.BROADCAST,
    dest: number = 0
  ): Promise<void> {
    await this.ensureConnected();
    this.safeWrite(buildChatPacket(NetworkAction.CHAT, destType, dest, message));
  }

  /**
   * Send a JSON command to the GameScript.
   * Commands are serialized — only one is in flight at a time to prevent
   * overwhelming the GameScript's opcode budget and freezing the game.
   */
  async sendGameScriptCommand(
    action: string,
    params: Record<string, unknown> = {},
    timeoutMs: number = 30000
  ): Promise<GameScriptResponse> {
    await this.ensureConnected();
    if (!this.socket) throw new Error("Not connected to server");

    const id = `mcp_${++this.gsCommandCounter}`;
    const command: GameScriptCommand = { id, action, params };

    return new Promise((resolve, reject) => {
      this.gsQueue.push({ id, command, timeoutMs, resolve, reject });
      this.processGsQueue();
    });
  }

  /** Process the next queued GameScript command if none is in flight. */
  private processGsQueue(): void {
    if (this.gsInFlight || this.gsQueue.length === 0) return;
    if (!this.socket || !this.connected) return;

    this.gsInFlight = true;
    const { id, command, timeoutMs, resolve, reject } = this.gsQueue.shift()!;

    const onDone = () => {
      this.gsInFlight = false;
      this.processGsQueue();
    };

    const timeout = setTimeout(() => {
      this.pendingGameScript.delete(id);
      this.gsChunkBuffers.delete(id);
      onDone();
      reject(
        new Error(
          `GameScript command "${command.action}" timed out after ${timeoutMs}ms. Is the ClaudeMCP GameScript loaded?`
        )
      );
    }, timeoutMs);

    this.pendingGameScript.set(id, {
      resolve: (response) => {
        clearTimeout(timeout);
        onDone();
        resolve(response);
      },
      reject: (error) => {
        clearTimeout(timeout);
        onDone();
        reject(error);
      },
      timeout,
    });

    this.safeWrite(buildGameScriptPacket(JSON.stringify(command)));
  }

  /**
   * Poll company economy data.
   * Note: Uses a fixed 1s timeout to collect responses. This is a simplistic approach;
   * a more robust implementation would track expected response count and resolve early.
   */
  async pollCompanyEconomy(companyId?: number): Promise<CompanyEconomy[]> {
    await this.ensureConnected();

    return new Promise((resolve) => {
      const results: CompanyEconomy[] = [];
      const handler = (economy: CompanyEconomy) => {
        results.push(economy);
      };

      this.on("companyEconomy", handler);
      this.safeWrite(
        buildPollPacket(
          AdminUpdateType.COMPANY_ECONOMY,
          companyId ?? 0xffffffff
        )
      );

      setTimeout(() => {
        this.removeListener("companyEconomy", handler);
        resolve(results);
      }, 1000);
    });
  }

  /**
   * Poll company stats.
   * Note: Uses a fixed 1s timeout to collect responses. This is a simplistic approach;
   * a more robust implementation would track expected response count and resolve early.
   */
  async pollCompanyStats(companyId?: number): Promise<CompanyStats[]> {
    await this.ensureConnected();

    return new Promise((resolve) => {
      const results: CompanyStats[] = [];
      const handler = (stats: CompanyStats) => {
        results.push(stats);
      };

      this.on("companyStats", handler);
      this.safeWrite(
        buildPollPacket(AdminUpdateType.COMPANY_STATS, companyId ?? 0xffffffff)
      );

      setTimeout(() => {
        this.removeListener("companyStats", handler);
        resolve(results);
      }, 1000);
    });
  }

  /** Poll for fresh date */
  pollDate(): void {
    if (this.isConnected && this.socket) {
      this.safeWrite(buildPollPacket(AdminUpdateType.DATE));
    }
  }

  /** Refresh company list */
  refreshCompanies(): void {
    if (this.isConnected && this.socket) {
      this.safeWrite(buildPollPacket(AdminUpdateType.COMPANY_INFO));
    }
  }

  /** Refresh client list */
  refreshClients(): void {
    if (this.isConnected && this.socket) {
      this.safeWrite(buildPollPacket(AdminUpdateType.CLIENT_INFO));
    }
  }
}

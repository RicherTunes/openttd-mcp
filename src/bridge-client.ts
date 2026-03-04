/**
 * HTTP bridge client - drop-in replacement for AdminClient.
 *
 * Instead of managing a TCP connection to OpenTTD directly, this client
 * talks to the persistent bridge-server.ts process via HTTP.
 * All public properties/methods mirror AdminClient's interface.
 */

import type {
  ServerWelcome,
  CompanyInfo,
  ClientInfo,
  CompanyEconomy,
  CompanyStats,
} from "./protocol/packets.js";
import type { DestType } from "./protocol/types.js";
import type { GameScriptResponse } from "./types/openttd.js";

export interface BridgeClientOptions {
  host: string;
  port: number;
  password: string;
  botName?: string;
  botVersion?: string;
}

export class BridgeClient {
  private baseUrl: string;

  // Cached state (refreshed on key operations)
  public serverInfo: ServerWelcome | null = null;
  public companies: Map<number, CompanyInfo> = new Map();
  public clients: Map<number, ClientInfo> = new Map();
  public currentDate: number = 0;
  public currentDateStr: string = "";

  private _connected: boolean = false;

  constructor(bridgeUrl: string = "http://127.0.0.1:13977") {
    this.baseUrl = bridgeUrl;
  }

  get isConnected(): boolean {
    return this._connected;
  }

  // ============ HTTP helpers ============

  private async post(path: string, body?: Record<string, unknown>): Promise<unknown> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json() as Record<string, unknown>;
    if (!res.ok) {
      throw new Error((json.error as string) ?? `HTTP ${res.status}`);
    }
    return json;
  }

  private async get(path: string): Promise<Record<string, unknown>> {
    const res = await fetch(`${this.baseUrl}${path}`);
    const json = await res.json() as Record<string, unknown>;
    if (!res.ok) {
      throw new Error((json.error as string) ?? `HTTP ${res.status}`);
    }
    return json;
  }

  private updateStateFromStatus(data: Record<string, unknown>): void {
    this._connected = data.connected as boolean;
    if (data.serverInfo) {
      this.serverInfo = data.serverInfo as ServerWelcome;
    }
    if (data.currentDate !== undefined) {
      this.currentDate = data.currentDate as number;
    }
    if (data.currentDateStr !== undefined) {
      this.currentDateStr = data.currentDateStr as string;
    }
    if (Array.isArray(data.companies)) {
      this.companies.clear();
      for (const c of data.companies as CompanyInfo[]) {
        this.companies.set(c.companyId, c);
      }
    }
    if (Array.isArray(data.clients)) {
      this.clients.clear();
      for (const c of data.clients as ClientInfo[]) {
        this.clients.set(c.clientId, c);
      }
    }
  }

  // ============ Public API (mirrors AdminClient) ============

  async connect(options: BridgeClientOptions): Promise<ServerWelcome> {
    const result = await this.post("/connect", {
      host: options.host,
      port: options.port,
      password: options.password,
      botName: options.botName,
      botVersion: options.botVersion,
    }) as { success: boolean; welcome: ServerWelcome };

    this._connected = true;
    this.serverInfo = result.welcome;

    // Refresh full state
    await this.refreshState();

    return result.welcome;
  }

  async reconnect(): Promise<ServerWelcome> {
    // The bridge maintains connection state - just refresh our cache
    const status = await this.get("/status");
    this.updateStateFromStatus(status);
    if (!this._connected) {
      throw new Error("Bridge is not connected to OpenTTD");
    }
    return this.serverInfo!;
  }

  async disconnect(): Promise<void> {
    await this.post("/disconnect");
    this._connected = false;
    this.serverInfo = null;
    this.companies.clear();
    this.clients.clear();
  }

  async ensureConnected(): Promise<void> {
    // Check bridge connection status and refresh cache
    try {
      const status = await this.get("/status");
      this.updateStateFromStatus(status);
    } catch {
      throw new Error(
        "Cannot reach bridge server. Is it running? Start it with: npm run bridge -- --password <pw>"
      );
    }
    if (!this._connected) {
      throw new Error(
        "Bridge is not connected to OpenTTD. Use connect_to_server first."
      );
    }
  }

  async executeRcon(command: string, timeoutMs: number = 10000): Promise<string[]> {
    const result = await this.post("/rcon", { command, timeoutMs }) as { lines: string[] };
    return result.lines;
  }

  async sendChat(
    message: string,
    destType?: DestType,
    dest: number = 0
  ): Promise<void> {
    await this.post("/chat", { message, destType, dest });
  }

  async sendGameScriptCommand(
    action: string,
    params: Record<string, unknown> = {},
    timeoutMs: number = 30000
  ): Promise<GameScriptResponse> {
    const result = await this.post("/gamescript", {
      action,
      params,
      timeoutMs,
    }) as GameScriptResponse;
    return result;
  }

  async pollCompanyEconomy(companyId?: number): Promise<CompanyEconomy[]> {
    const path = companyId !== undefined
      ? `/companies/${companyId}/economy`
      : "/companies/all/economy";
    const result = await this.get(path) as { economies: CompanyEconomy[] };
    return result.economies;
  }

  async pollCompanyStats(companyId?: number): Promise<CompanyStats[]> {
    const path = companyId !== undefined
      ? `/companies/${companyId}/stats`
      : "/companies/all/stats";
    const result = await this.get(path) as { stats: CompanyStats[] };
    return result.stats;
  }

  pollDate(): void {
    // Fire-and-forget: refresh date from bridge
    this.get("/date")
      .then((data) => {
        if (data.currentDate !== undefined) {
          this.currentDate = data.currentDate as number;
        }
        if (data.currentDateStr !== undefined) {
          this.currentDateStr = data.currentDateStr as string;
        }
      })
      .catch(() => {
        // Silently ignore - date will be stale
      });
  }

  refreshCompanies(): void {
    // Fire-and-forget: refresh companies from bridge
    this.get("/companies")
      .then((data) => {
        if (Array.isArray(data.companies)) {
          this.companies.clear();
          for (const c of data.companies as CompanyInfo[]) {
            this.companies.set(c.companyId, c);
          }
        }
      })
      .catch(() => {
        // Silently ignore
      });
  }

  refreshClients(): void {
    // Fire-and-forget: refresh clients from bridge
    this.get("/clients")
      .then((data) => {
        if (Array.isArray(data.clients)) {
          this.clients.clear();
          for (const c of data.clients as ClientInfo[]) {
            this.clients.set(c.clientId, c);
          }
        }
      })
      .catch(() => {
        // Silently ignore
      });
  }

  /** Fetch full state from bridge */
  private async refreshState(): Promise<void> {
    const status = await this.get("/status");
    this.updateStateFromStatus(status);
  }
}

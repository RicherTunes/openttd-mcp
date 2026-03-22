#!/usr/bin/env node

/**
 * Persistent HTTP bridge server for OpenTTD admin port.
 *
 * Runs as a standalone process that maintains a long-lived TCP connection
 * to OpenTTD. MCP tools connect to this bridge via HTTP instead of
 * managing the TCP connection directly.
 *
 * Usage: node build/bridge-server.js [--host 127.0.0.1] [--port 3977] [--password claude] [--http-port 13977]
 */

import * as http from "node:http";
import { AdminClient, type AdminClientOptions } from "./admin-client.js";
import type { DestType } from "./protocol/types.js";

const DEFAULT_HTTP_PORT = 13977;

// BigInt JSON serialization
function jsonReplacer(_key: string, value: unknown): unknown {
  if (typeof value === "bigint") return value.toString();
  return value;
}

function respond(res: http.ServerResponse, status: number, body: unknown): void {
  const json = JSON.stringify(body, jsonReplacer);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(json);
}

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let totalSize = 0;
    const MAX_BODY = 1024 * 1024; // 1MB limit
    req.on("data", (chunk: Buffer) => {
      totalSize += chunk.length;
      if (totalSize > MAX_BODY) {
        req.destroy();
        reject(new Error("Request body too large"));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString()));
    req.on("error", reject);
  });
}

async function parseJsonBody(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  const raw = await readBody(req);
  if (!raw) return {};
  return JSON.parse(raw) as Record<string, unknown>;
}

function mapToArray<V>(map: Map<number, V>): V[] {
  return Array.from(map.values());
}

// Parse CLI arguments
function parseArgs(): { host?: string; port?: number; password?: string; httpPort: number } {
  const args = process.argv.slice(2);
  const result: { host?: string; port?: number; password?: string; httpPort: number } = {
    httpPort: DEFAULT_HTTP_PORT,
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--host":
        result.host = args[++i];
        break;
      case "--port":
        result.port = parseInt(args[++i], 10);
        break;
      case "--password":
        result.password = args[++i];
        break;
      case "--http-port":
        result.httpPort = parseInt(args[++i], 10);
        break;
    }
  }

  return result;
}

// Circular buffer for console alerts
interface Alert {
  timestamp: number;
  message: string;
}
const alerts: Alert[] = [];
const MAX_ALERTS = 100;

async function main(): Promise<void> {
  const args = parseArgs();
  const client = new AdminClient();

  // Track connection state for logging
  client.on("reconnected", () => {
    console.log("[bridge] Reconnected to OpenTTD");
  });
  client.on("close", () => {
    console.log("[bridge] Connection closed");
  });

  // Buffer console messages as alerts
  client.on("console", (msg: { origin?: string; message?: string; output?: string }) => {
    const message = msg.message || msg.output || String(msg);
    alerts.push({ timestamp: Date.now(), message });
    if (alerts.length > MAX_ALERTS) alerts.shift();
  });

  // Route handler
  // TODO: Add authentication (e.g., API key via OPENTTD_BRIDGE_KEY env var)
  // Currently trusts all connections from localhost (127.0.0.1)
  async function handleRequest(
    req: http.IncomingMessage,
    res: http.ServerResponse
  ): Promise<void> {
    const url = new URL(req.url ?? "/", `http://localhost:${args.httpPort}`);
    const path = url.pathname;
    const method = req.method ?? "GET";

    try {
      // POST /connect
      if (method === "POST" && path === "/connect") {
        const body = await parseJsonBody(req);
        const options: AdminClientOptions = {
          host: (body.host as string) ?? "127.0.0.1",
          port: (body.port as number) ?? 3977,
          password: body.password as string,
          botName: (body.botName as string) ?? "ClaudeMCP",
          botVersion: (body.botVersion as string) ?? "1.0.0",
        };
        const welcome = await client.connect(options);
        console.log(`[bridge] Connected to "${welcome.serverName}"`);
        respond(res, 200, { success: true, welcome });
        return;
      }

      // POST /disconnect
      if (method === "POST" && path === "/disconnect") {
        await client.disconnect();
        console.log("[bridge] Disconnected");
        respond(res, 200, { success: true });
        return;
      }

      // GET /status
      if (method === "GET" && path === "/status") {
        respond(res, 200, {
          connected: client.isConnected,
          serverInfo: client.serverInfo,
          currentDate: client.currentDate,
          currentDateStr: client.currentDateStr,
          companies: mapToArray(client.companies),
          clients: mapToArray(client.clients),
        });
        return;
      }

      // GET /date
      if (method === "GET" && path === "/date") {
        client.pollDate();
        await new Promise((r) => setTimeout(r, 200));
        respond(res, 200, {
          currentDate: client.currentDate,
          currentDateStr: client.currentDateStr,
        });
        return;
      }

      // GET /companies
      if (method === "GET" && path === "/companies") {
        client.refreshCompanies();
        await new Promise((r) => setTimeout(r, 500));
        respond(res, 200, { companies: mapToArray(client.companies) });
        return;
      }

      // GET /companies/:id/economy
      const economyMatch = path.match(/^\/companies\/(\d+)\/economy$/);
      if (method === "GET" && economyMatch) {
        const companyId = parseInt(economyMatch[1], 10);
        const economies = await client.pollCompanyEconomy(companyId);
        respond(res, 200, { economies });
        return;
      }

      // GET /companies/:id/stats
      const statsMatch = path.match(/^\/companies\/(\d+)\/stats$/);
      if (method === "GET" && statsMatch) {
        const companyId = parseInt(statsMatch[1], 10);
        const stats = await client.pollCompanyStats(companyId);
        respond(res, 200, { stats });
        return;
      }

      // GET /companies/all/economy
      if (method === "GET" && path === "/companies/all/economy") {
        const economies = await client.pollCompanyEconomy();
        respond(res, 200, { economies });
        return;
      }

      // GET /companies/all/stats
      if (method === "GET" && path === "/companies/all/stats") {
        const stats = await client.pollCompanyStats();
        respond(res, 200, { stats });
        return;
      }

      // GET /clients
      if (method === "GET" && path === "/clients") {
        client.refreshClients();
        await new Promise((r) => setTimeout(r, 500));
        respond(res, 200, { clients: mapToArray(client.clients) });
        return;
      }

      // POST /rcon
      if (method === "POST" && path === "/rcon") {
        const body = await parseJsonBody(req);
        const command = body.command as string;
        const timeoutMs = (body.timeoutMs as number) ?? 10000;
        const lines = await client.executeRcon(command, timeoutMs);
        respond(res, 200, { lines });
        return;
      }

      // POST /chat
      if (method === "POST" && path === "/chat") {
        const body = await parseJsonBody(req);
        const message = body.message as string;
        const destType = body.destType as DestType | undefined;
        const dest = (body.dest as number) ?? 0;
        await client.sendChat(message, destType, dest);
        respond(res, 200, { success: true });
        return;
      }

      // POST /gamescript
      if (method === "POST" && path === "/gamescript") {
        const body = await parseJsonBody(req);
        const action = body.action as string;
        const params = (body.params as Record<string, unknown>) ?? {};
        const timeoutMs = (body.timeoutMs as number) ?? 30000;
        const response = await client.sendGameScriptCommand(action, params, timeoutMs);
        respond(res, 200, response);
        return;
      }

      // GET /alerts
      if (method === "GET" && path === "/alerts") {
        const since = url.searchParams.get("since");
        const clear = url.searchParams.get("clear");
        let filtered = alerts;
        if (since) {
          const sinceTs = parseInt(since, 10);
          filtered = alerts.filter((a) => a.timestamp > sinceTs);
        }
        const result = [...filtered];
        if (clear === "true") {
          alerts.length = 0;
        }
        respond(res, 200, { alerts: result });
        return;
      }

      // 404
      respond(res, 404, { error: `Not found: ${method} ${path}` });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`[bridge] Error handling ${method} ${path}: ${message}`);
      respond(res, 500, { error: message });
    }
  }

  // Create HTTP server
  const httpServer = http.createServer(handleRequest);

  httpServer.listen(args.httpPort, "127.0.0.1", () => {
    console.log(`[bridge] HTTP bridge listening on http://127.0.0.1:${args.httpPort}`);
  });

  // Auto-connect if credentials provided
  if (args.password) {
    try {
      const welcome = await client.connect({
        host: args.host ?? "127.0.0.1",
        port: args.port ?? 3977,
        password: args.password,
      });
      console.log(`[bridge] Connected to "${welcome.serverName}"`);
    } catch (err) {
      console.error(`[bridge] Auto-connect failed: ${err instanceof Error ? err.message : err}`);
      console.log("[bridge] Waiting for POST /connect...");
    }
  } else {
    console.log("[bridge] No --password provided. Waiting for POST /connect...");
  }

  // Graceful shutdown
  const shutdown = async () => {
    console.log("\n[bridge] Shutting down...");
    await client.disconnect();
    httpServer.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

// Prevent unhandled rejections from crashing the bridge
process.on("unhandledRejection", (reason) => {
  console.error("[bridge] Unhandled rejection:", reason);
});

main().catch((err) => {
  console.error("[bridge] Fatal error:", err);
  process.exit(1);
});

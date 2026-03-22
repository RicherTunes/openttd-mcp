#!/usr/bin/env node

/**
 * OpenTTD MCP Server - Entry point.
 * Runs on stdio transport for use with Claude Desktop / Claude Code.
 *
 * Auto-starts the bridge server if not already running.
 */

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.js";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

async function ensureBridge(): Promise<void> {
  const bridgeUrl =
    process.env.OPENTTD_BRIDGE_URL ?? "http://127.0.0.1:13977";

  // Check if bridge is already running
  try {
    const res = await fetch(`${bridgeUrl}/status`);
    if (res.ok) {
      console.error("[mcp] Bridge server already running");
      return;
    }
  } catch {
    // Not running — will start it
  }

  console.error("[mcp] Starting bridge server...");

  const __filename = fileURLToPath(import.meta.url);
  const bridgePath = join(dirname(__filename), "bridge-server.js");

  const child = spawn(process.execPath, [bridgePath], {
    stdio: "ignore",
    detached: true,
  });
  child.unref();

  // Wait for bridge to become ready (up to 5 seconds)
  for (let i = 0; i < 20; i++) {
    await new Promise((r) => setTimeout(r, 250));
    try {
      const res = await fetch(`${bridgeUrl}/status`);
      if (res.ok) {
        console.error(`[mcp] Bridge server started (PID: ${child.pid})`);
        return;
      }
    } catch {
      // Still starting...
    }
  }

  console.error(
    "[mcp] Warning: bridge server may not have started. Tools will retry on use."
  );
}

async function main(): Promise<void> {
  await ensureBridge();

  const { server } = createServer();
  const transport = new StdioServerTransport();

  await server.connect(transport);
  console.error("OpenTTD MCP Server running on stdio (bridge mode)");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});

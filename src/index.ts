#!/usr/bin/env node

/**
 * OpenTTD MCP Server - Entry point.
 * Runs on stdio transport for use with Claude Desktop / Claude Code.
 *
 * This process is stateless - the persistent bridge-server.ts holds
 * the actual TCP connection to OpenTTD. Start the bridge first:
 *   npm run bridge -- --password <your_password>
 */

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.js";

async function main(): Promise<void> {
  const { server } = createServer();
  const transport = new StdioServerTransport();

  await server.connect(transport);
  console.error("OpenTTD MCP Server running on stdio (bridge mode)");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});

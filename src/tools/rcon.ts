/**
 * Raw RCON tool - execute any console command.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";

export function registerRconTools(
  server: McpServer,
  client: AdminClient
): void {
  server.registerTool(
    "execute_rcon",
    {
      description:
        "Execute a raw console command on the OpenTTD server via RCON. Useful for any command not covered by dedicated tools. Common commands: status, clients, companies, list_cmds, resetengines, scrollto <tile>, content download, etc.",
      inputSchema: {
        command: z.string().describe("Console command to execute"),
      },
    },
    async ({ command }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      try {
        const lines = await client.executeRcon(command);
        const output = lines.join("\n");
        return {
          content: [
            {
              type: "text",
              text: output || "(no output)",
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `RCON error: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

/**
 * Client/player information tools.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";
import { COMPANY_SPECTATOR } from "../protocol/types.js";

export function registerClientTools(
  server: McpServer,
  client: AdminClient
): void {
  server.registerTool(
    "get_clients",
    {
      description:
        "List all connected players/clients with their names, company assignments, and connection info.",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }

      client.refreshClients();
      await new Promise((r) => setTimeout(r, 500));

      const clients = Array.from(client.clients.values()).map((c) => ({
        clientId: c.clientId,
        name: c.name,
        companyId:
          c.companyId === COMPANY_SPECTATOR ? "spectator" : c.companyId,
        hostname: c.hostname,
      }));

      return {
        content: [
          {
            type: "text",
            text:
              clients.length > 0
                ? JSON.stringify(clients, null, 2)
                : "No clients connected.",
          },
        ],
      };
    }
  );

  server.registerTool(
    "kick_player",
    {
      description: "Kick a player from the server.",
      inputSchema: {
        client_id: z.number().describe("Client ID to kick"),
        reason: z
          .string()
          .default("Kicked by admin")
          .describe("Kick reason message"),
      },
    },
    async ({ client_id, reason }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon(`kick ${client_id} "${reason}"`);
      return {
        content: [
          {
            type: "text",
            text: lines.join("\n") || `Kicked client ${client_id}.`,
          },
        ],
      };
    }
  );
}

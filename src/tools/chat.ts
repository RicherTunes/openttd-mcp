/**
 * Chat tools - send messages to the server.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";
import { DestType } from "../protocol/types.js";

export function registerChatTools(
  server: McpServer,
  client: AdminClient
): void {
  server.registerTool(
    "send_chat",
    {
      description:
        "Send a chat message to the OpenTTD server. Can broadcast to all, send to a team, or send to a specific client.",
      inputSchema: {
        message: z.string().describe("Message to send"),
        dest_type: z
          .enum(["broadcast", "team", "client"])
          .default("broadcast")
          .describe("Destination type"),
        dest_id: z
          .number()
          .default(0)
          .describe("Destination ID (company ID for team, client ID for client)"),
      },
    },
    async ({ message, dest_type, dest_id }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }

      const destTypeMap: Record<string, DestType> = {
        broadcast: DestType.BROADCAST,
        team: DestType.TEAM,
        client: DestType.CLIENT,
      };

      await client.sendChat(message, destTypeMap[dest_type], dest_id);
      return {
        content: [
          {
            type: "text",
            text: `Chat sent (${dest_type}): ${message}`,
          },
        ],
      };
    }
  );
}

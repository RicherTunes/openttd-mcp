/**
 * Connection management tools - connect/disconnect to OpenTTD server.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";
import { DEFAULT_ADMIN_PORT } from "../protocol/types.js";
import { LANDSCAPES } from "../types/openttd.js";

export function registerConnectionTools(
  server: McpServer,
  client: AdminClient
): void {
  server.registerTool(
    "connect_to_server",
    {
      description:
        "Connect to a running OpenTTD server via the admin port. The connection is PERSISTENT — do NOT disconnect between tool calls. Connect once and use all tools freely. The server must have admin_password set in openttd.cfg.",
      inputSchema: {
        host: z
          .string()
          .default("127.0.0.1")
          .describe("Server hostname or IP"),
        port: z
          .number()
          .default(DEFAULT_ADMIN_PORT)
          .describe("Admin port (default 3977)"),
        password: z.string().describe("Admin password from openttd.cfg"),
      },
    },
    async ({ host, port, password }) => {
      try {
        const welcome = await client.connect({ host, port, password });
        const landscape =
          LANDSCAPES[welcome.landscape] ?? `unknown(${welcome.landscape})`;
        return {
          content: [
            {
              type: "text",
              text: [
                `Connected to "${welcome.serverName}"`,
                `Version: ${welcome.networkRevision}`,
                `Map: ${welcome.mapName} (${welcome.mapSizeX}x${welcome.mapSizeY})`,
                `Landscape: ${landscape}`,
                `Dedicated: ${welcome.dedicated}`,
                "",
                "Connection established. You can now use game management and building tools.",
                "Make sure the ClaudeMCP GameScript is loaded for building/vehicle commands.",
              ].join("\n"),
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to connect: ${err instanceof Error ? err.message : String(err)}\n\nTroubleshooting:\n1. Is OpenTTD running and hosting a multiplayer server?\n2. Is admin_password set in openttd.cfg?\n3. Is the admin port (default 3977) accessible?`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "disconnect",
    {
      description: "Disconnect from the OpenTTD server. WARNING: Do NOT call this during normal gameplay! The connection is persistent and shared. Only disconnect if you are completely done playing and want to release the admin port.",
      inputSchema: {},
    },
    async () => {
      await client.disconnect();
      return {
        content: [{ type: "text", text: "Disconnected from server." }],
      };
    }
  );

  server.registerTool(
    "get_connection_status",
    {
      description: "Check if we are connected to an OpenTTD server.",
      inputSchema: {},
    },
    async () => {
      if (client.isConnected && client.serverInfo) {
        return {
          content: [
            {
              type: "text",
              text: [
                `Connected: yes`,
                `Server: ${client.serverInfo.serverName}`,
                `Version: ${client.serverInfo.networkRevision}`,
                `Map: ${client.serverInfo.mapSizeX}x${client.serverInfo.mapSizeY}`,
                `Date: ${client.currentDateStr || "unknown"}`,
                `Companies: ${client.companies.size}`,
                `Clients: ${client.clients.size}`,
              ].join("\n"),
            },
          ],
        };
      }
      return {
        content: [
          {
            type: "text",
            text: "Not connected. Use connect_to_server to connect.",
          },
        ],
      };
    }
  );
}

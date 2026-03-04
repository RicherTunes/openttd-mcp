/**
 * Server info and game date tools.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";
import { LANDSCAPES, COLOUR_NAMES } from "../types/openttd.js";
import { ottdDateToString } from "../protocol/packets.js";

export function registerServerInfoTools(
  server: McpServer,
  client: AdminClient
): void {
  server.registerTool(
    "get_server_info",
    {
      description:
        "Get detailed information about the connected OpenTTD server including map size, version, landscape type, and more.",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected || !client.serverInfo) {
        return {
          content: [{ type: "text", text: "Not connected to server." }],
        };
      }
      const info = client.serverInfo;
      const landscape = LANDSCAPES[info.landscape] ?? `unknown(${info.landscape})`;
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                serverName: info.serverName,
                version: info.networkRevision,
                dedicated: info.dedicated,
                mapName: info.mapName,
                mapSeed: info.mapSeed,
                landscape,
                startDate: ottdDateToString(info.startDate),
                mapSizeX: info.mapSizeX,
                mapSizeY: info.mapSizeY,
                currentDate: client.currentDateStr,
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );

  server.registerTool(
    "get_game_date",
    {
      description: "Get the current in-game date.",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected) {
        return {
          content: [{ type: "text", text: "Not connected to server." }],
        };
      }
      client.pollDate();
      // Small delay to let the response arrive
      await new Promise((r) => setTimeout(r, 200));
      return {
        content: [
          {
            type: "text",
            text: `Current game date: ${client.currentDateStr}`,
          },
        ],
      };
    }
  );
}

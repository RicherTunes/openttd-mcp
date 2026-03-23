/**
 * Server info and game date tools.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";
import { GameScriptBridge } from "../gamescript/bridge.js";
import { LANDSCAPES, COLOUR_NAMES } from "../types/openttd.js";
import { ottdDateToString } from "../protocol/packets.js";

/** Keywords that indicate actionable game alerts */
const ALERT_KEYWORDS = ["lost", "order", "broke", "old", "profit", "crash"];

export function registerServerInfoTools(
  server: McpServer,
  client: AdminClient,
  bridge: GameScriptBridge
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
      // Try to get current date from GameScript (more reliable than admin port polling)
      let currentDate = client.currentDateStr;
      if (!currentDate) {
        try {
          const dateResult = await bridge.execute("get_date", {});
          const dateInfo = dateResult as { date_string: string };
          currentDate = dateInfo.date_string;
        } catch {
          // Fall back to cached value (may be empty)
        }
      }
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
                currentDate,
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
      // Primary: use GameScript get_date command (reliable, works with encryption)
      try {
        const result = await bridge.execute("get_date", {});
        const dateInfo = result as { year: number; month: number; day: number; date_string: string };
        return {
          content: [
            {
              type: "text",
              text: `Current game date: ${dateInfo.date_string}`,
            },
          ],
        };
      } catch {
        // Fallback: admin port date polling
        client.pollDate();
        await new Promise((r) => setTimeout(r, 200));
        const dateStr = client.currentDateStr || "(unavailable)";
        return {
          content: [
            {
              type: "text",
              text: `Current game date: ${dateStr}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_alerts",
    {
      description:
        "Get recent game notifications (vehicle lost, broken down, too few orders, etc.). Filters to only show actionable messages.",
      inputSchema: {
        since: z
          .number()
          .optional()
          .describe("Unix timestamp (ms) - only return alerts after this time"),
        clear: z
          .boolean()
          .optional()
          .describe("Clear the alerts buffer after reading"),
      },
    },
    async ({ since, clear }) => {
      try {
        // client is actually a BridgeClient at runtime (cast via any in server.ts)
        const bridgeClient = client as unknown as {
          getAlerts(since?: number, clear?: boolean): Promise<Array<{ timestamp: number; message: string }>>;
        };
        const alerts = await bridgeClient.getAlerts(since, clear);

        // Filter to actionable messages
        const actionable = alerts.filter((a) =>
          ALERT_KEYWORDS.some((kw) => a.message.toLowerCase().includes(kw))
        );

        if (actionable.length === 0) {
          return {
            content: [
              {
                type: "text",
                text: `No actionable alerts.${alerts.length > 0 ? ` (${alerts.length} total console messages filtered out)` : ""}`,
              },
            ],
          };
        }

        const lines = actionable.map((a) => {
          const date = new Date(a.timestamp).toISOString();
          return `[${date}] ${a.message}`;
        });
        return {
          content: [
            {
              type: "text",
              text: `${actionable.length} alert(s):\n${lines.join("\n")}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to get alerts: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_game_status",
    {
      description:
        "Get a composite game status in one call: vehicle counts by state (running/stopped/loading/broken) and station count. Requires ClaudeMCP GameScript to be loaded. More efficient than calling multiple tools separately. Use periodically to monitor your transport empire.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute("get_game_status", {
          company_id,
        });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to get game status: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

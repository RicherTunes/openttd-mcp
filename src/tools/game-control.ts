/**
 * Game control tools - pause, save, load, new game.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";

export function registerGameControlTools(
  server: McpServer,
  client: AdminClient
): void {
  server.registerTool(
    "pause_game",
    {
      description: "Pause the game.",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon("pause");
      return {
        content: [
          { type: "text", text: lines.join("\n") || "Game paused." },
        ],
      };
    }
  );

  server.registerTool(
    "unpause_game",
    {
      description: "Unpause the game.",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon("unpause");
      return {
        content: [
          { type: "text", text: lines.join("\n") || "Game unpaused." },
        ],
      };
    }
  );

  server.registerTool(
    "save_game",
    {
      description: "Save the current game.",
      inputSchema: {
        filename: z
          .string()
          .default("claude_save")
          .describe("Save file name (without extension)"),
      },
    },
    async ({ filename }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon(`save ${filename}`);
      return {
        content: [
          {
            type: "text",
            text: lines.join("\n") || `Game saved as "${filename}".`,
          },
        ],
      };
    }
  );

  server.registerTool(
    "load_game",
    {
      description: "Load a saved game.",
      inputSchema: {
        filename: z.string().describe("Save file path to load"),
      },
    },
    async ({ filename }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon(`load ${filename}`);
      return {
        content: [
          {
            type: "text",
            text: lines.join("\n") || `Loading "${filename}"...`,
          },
        ],
      };
    }
  );

  server.registerTool(
    "new_game",
    {
      description: "Start a new random game. WARNING: This will end the current game!",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon("newgame");
      return {
        content: [
          {
            type: "text",
            text: lines.join("\n") || "Starting new game...",
          },
        ],
      };
    }
  );

  server.registerTool(
    "change_setting",
    {
      description:
        "Change a game setting at runtime via console. Example settings: max_trains, max_roadveh, town_growth_rate, etc.",
      inputSchema: {
        setting: z.string().describe("Setting name"),
        value: z.string().describe("New value"),
      },
    },
    async ({ setting, value }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }
      const lines = await client.executeRcon(`setting ${setting} ${value}`);
      return {
        content: [
          {
            type: "text",
            text: lines.join("\n") || `Setting ${setting} = ${value}`,
          },
        ],
      };
    }
  );
}

/**
 * Building tools - construct infrastructure via the GameScript bridge.
 * These send JSON commands to the in-game ClaudeMCP GameScript.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { GameScriptBridge } from "../gamescript/bridge.js";

export function registerBuildingTools(
  server: McpServer,
  bridge: GameScriptBridge
): void {
  server.registerTool(
    "build_rail",
    {
      description:
        "Build a rail track segment between two adjacent tiles. For longer routes, call this multiple times. Use get_engines to find available rail types.",
      inputSchema: {
        company_id: z.number().describe("Company ID that will own the track"),
        from_x: z.number().describe("Start tile X coordinate"),
        from_y: z.number().describe("Start tile Y coordinate"),
        to_x: z.number().describe("End tile X coordinate"),
        to_y: z.number().describe("End tile Y coordinate"),
        rail_type: z
          .number()
          .default(0)
          .describe("Rail type ID (0 = default rail, use get_engines to find types)"),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, rail_type }) => {
      try {
        const result = await bridge.execute("build_rail", {
          company_id,
          from_x,
          from_y,
          to_x,
          to_y,
          rail_type,
        });
        return {
          content: [
            {
              type: "text",
              text: `Rail built from (${from_x},${from_y}) to (${to_x},${to_y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build rail: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_rail_station",
    {
      description:
        "Build a train station. Must be built on rail track. Use direction 0 for NE-SW or 1 for NW-SE orientation.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Station tile X coordinate"),
        y: z.number().describe("Station tile Y coordinate"),
        rail_type: z.number().default(0).describe("Rail type ID"),
        direction: z
          .number()
          .min(0)
          .max(1)
          .describe("0 = NE-SW, 1 = NW-SE"),
        num_platforms: z.number().min(1).max(8).default(2).describe("Number of platforms"),
        platform_length: z
          .number()
          .min(1)
          .max(7)
          .default(5)
          .describe("Length of each platform in tiles"),
      },
    },
    async ({ company_id, x, y, rail_type, direction, num_platforms, platform_length }) => {
      try {
        const result = await bridge.execute("build_rail_station", {
          company_id,
          x,
          y,
          rail_type,
          direction,
          num_platforms,
          platform_length,
        });
        return {
          content: [
            {
              type: "text",
              text: `Train station built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build station: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_rail_depot",
    {
      description:
        "Build a rail depot. Needed to buy trains. The depot faces the direction specified.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Depot tile X coordinate"),
        y: z.number().describe("Depot tile Y coordinate"),
        rail_type: z.number().default(0).describe("Rail type ID"),
        direction: z
          .number()
          .min(0)
          .max(3)
          .describe("Direction the depot faces: 0=NE, 1=SE, 2=SW, 3=NW"),
      },
    },
    async ({ company_id, x, y, rail_type, direction }) => {
      try {
        const result = await bridge.execute("build_rail_depot", {
          company_id,
          x,
          y,
          rail_type,
          direction,
        });
        return {
          content: [
            {
              type: "text",
              text: `Rail depot built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build depot: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_road",
    {
      description:
        "Build a road between two tiles. Works for adjacent tiles. For longer roads, call multiple times or use build_road_route for pathfound routes.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        from_x: z.number().describe("Start tile X coordinate"),
        from_y: z.number().describe("Start tile Y coordinate"),
        to_x: z.number().describe("End tile X coordinate"),
        to_y: z.number().describe("End tile Y coordinate"),
        road_type: z.number().default(0).describe("Road type ID (0 = normal road)"),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, road_type }) => {
      try {
        const result = await bridge.execute("build_road", {
          company_id,
          from_x,
          from_y,
          to_x,
          to_y,
          road_type,
        });
        return {
          content: [
            {
              type: "text",
              text: `Road built from (${from_x},${from_y}) to (${to_x},${to_y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build road: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_road_depot",
    {
      description:
        "Build a road vehicle depot. Needed to buy road vehicles (buses, trucks).",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Depot tile X coordinate"),
        y: z.number().describe("Depot tile Y coordinate"),
        road_type: z.number().default(0).describe("Road type ID"),
        direction: z
          .number()
          .min(0)
          .max(3)
          .describe("Direction: 0=NE, 1=SE, 2=SW, 3=NW"),
      },
    },
    async ({ company_id, x, y, road_type, direction }) => {
      try {
        const result = await bridge.execute("build_road_depot", {
          company_id,
          x,
          y,
          road_type,
          direction,
        });
        return {
          content: [
            {
              type: "text",
              text: `Road depot built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build road depot: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_road_stop",
    {
      description:
        "RECOMMENDED: Use is_drive_through=true for reliable stops. Regular bay stops are unreliable. Drive-through stops must be placed ON existing road tiles. Use find_drive_through_spots to find suitable locations. If ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION, try the other direction.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Stop tile X coordinate"),
        y: z.number().describe("Stop tile Y coordinate"),
        road_type: z.number().default(0).describe("Road type ID"),
        is_truck_stop: z
          .boolean()
          .default(false)
          .describe("true for truck stop, false for bus stop"),
        is_drive_through: z
          .boolean()
          .default(false)
          .describe("true for drive-through stop"),
        direction: z.number().min(0).max(1).default(0).describe("0=NE-SW, 1=NW-SE"),
      },
    },
    async ({ company_id, x, y, road_type, is_truck_stop, is_drive_through, direction }) => {
      try {
        const result = await bridge.execute("build_road_stop", {
          company_id,
          x,
          y,
          road_type,
          is_truck_stop,
          is_drive_through,
          direction,
        });
        const stopType = is_truck_stop ? "Truck stop" : "Bus stop";
        return {
          content: [
            {
              type: "text",
              text: `${stopType} built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build stop: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_airport",
    {
      description:
        "Build an airport. Use get_engines with vehicle_type='aircraft' to find available airport types.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Airport top-left tile X coordinate"),
        y: z.number().describe("Airport top-left tile Y coordinate"),
        airport_type: z
          .number()
          .default(0)
          .describe("Airport type ID (0=small, 1=city, 2=heliport, etc.)"),
      },
    },
    async ({ company_id, x, y, airport_type }) => {
      try {
        const result = await bridge.execute("build_airport", {
          company_id,
          x,
          y,
          airport_type,
        });
        return {
          content: [
            {
              type: "text",
              text: `Airport built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build airport: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_dock",
    {
      description: "Build a ship dock on a coastal tile.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Dock tile X coordinate (must be on coast)"),
        y: z.number().describe("Dock tile Y coordinate"),
      },
    },
    async ({ company_id, x, y }) => {
      try {
        const result = await bridge.execute("build_dock", {
          company_id,
          x,
          y,
        });
        return {
          content: [
            {
              type: "text",
              text: `Dock built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build dock: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_bridge",
    {
      description:
        "Build a bridge between two tiles. The tiles must be at the same height and the gap must be bridgeable.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        bridge_type: z.number().default(0).describe("Bridge type ID"),
        start_x: z.number().describe("Start tile X"),
        start_y: z.number().describe("Start tile Y"),
        end_x: z.number().describe("End tile X"),
        end_y: z.number().describe("End tile Y"),
        transport_type: z
          .enum(["road", "rail", "water"])
          .default("road")
          .describe("What kind of bridge"),
      },
    },
    async ({ company_id, bridge_type, start_x, start_y, end_x, end_y, transport_type }) => {
      try {
        const result = await bridge.execute("build_bridge", {
          company_id,
          bridge_type,
          start_x,
          start_y,
          end_x,
          end_y,
          transport_type,
        });
        return {
          content: [
            {
              type: "text",
              text: `Bridge built from (${start_x},${start_y}) to (${end_x},${end_y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build bridge: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_tunnel",
    {
      description:
        "Build a tunnel starting from the given tile. OpenTTD automatically finds the exit on the other side of the hill.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Tunnel entrance tile X"),
        y: z.number().describe("Tunnel entrance tile Y"),
        transport_type: z
          .enum(["road", "rail"])
          .default("rail")
          .describe("Tunnel type"),
      },
    },
    async ({ company_id, x, y, transport_type }) => {
      try {
        const result = await bridge.execute("build_tunnel", {
          company_id,
          x,
          y,
          transport_type,
        });
        return {
          content: [
            {
              type: "text",
              text: `Tunnel built from (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build tunnel: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "demolish_tile",
    {
      description:
        "Demolish/clear everything on a tile. Use with caution - this removes buildings, tracks, roads, etc.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Tile X coordinate"),
        y: z.number().describe("Tile Y coordinate"),
      },
    },
    async ({ company_id, x, y }) => {
      try {
        const result = await bridge.execute("demolish_tile", {
          company_id,
          x,
          y,
        });
        return {
          content: [
            {
              type: "text",
              text: `Tile (${x},${y}) demolished. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to demolish: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_rail_signal",
    {
      description:
        "Build a signal on a rail tile. Signals control train traffic flow.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Tile X coordinate (must have rail)"),
        y: z.number().describe("Tile Y coordinate"),
        signal_type: z
          .number()
          .default(0)
          .describe("Signal type: 0=normal, 1=entry, 2=exit, 3=combo, 4=path, 5=one-way path"),
      },
    },
    async ({ company_id, x, y, signal_type }) => {
      try {
        const result = await bridge.execute("build_rail_signal", {
          company_id,
          x,
          y,
          signal_type,
        });
        return {
          content: [
            {
              type: "text",
              text: `Signal built at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build signal: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  // =================================================================
  // Advanced Rail Tools (A* Pathfinding)
  // =================================================================

  server.registerTool(
    "build_rail_route",
    {
      description:
        "Build a pathfound rail route between two points using A* pathfinding. Automatically routes around water, buildings, and terrain. Builds curved track where needed. Returns the path for use with auto_signal_route.",
      inputSchema: {
        company_id: z.number().describe("Company ID that will own the track"),
        from_x: z.number().describe("Start tile X coordinate"),
        from_y: z.number().describe("Start tile Y coordinate"),
        to_x: z.number().describe("End tile X coordinate"),
        to_y: z.number().describe("End tile Y coordinate"),
        rail_type: z
          .number()
          .default(0)
          .describe("Rail type ID (0 = default rail)"),
        max_iterations: z
          .number()
          .default(50000)
          .describe(
            "Maximum A* iterations (increase for very long routes, default 50000)"
          ),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, rail_type, max_iterations }) => {
      try {
        const result = await bridge.execute(
          "build_rail_route",
          { company_id, from_x, from_y, to_x, to_y, rail_type, max_iterations },
          120000
        );
        return {
          content: [
            {
              type: "text",
              text: `Rail route built. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build rail route: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_road_route",
    {
      description:
        "Build a pathfound road route between two points using A* pathfinding. Automatically routes around water, buildings, and terrain. Can demolish buildings as a last resort. Much more reliable than manual build_road calls in dense towns.",
      inputSchema: {
        company_id: z.number().describe("Company ID that will own the road"),
        from_x: z.number().describe("Start tile X coordinate"),
        from_y: z.number().describe("Start tile Y coordinate"),
        to_x: z.number().describe("End tile X coordinate"),
        to_y: z.number().describe("End tile Y coordinate"),
        road_type: z
          .number()
          .default(0)
          .describe("Road type ID (0 = normal road)"),
        max_iterations: z
          .number()
          .default(10000)
          .describe(
            "Maximum A* iterations (increase for very long routes, default 10000)"
          ),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, road_type, max_iterations }) => {
      try {
        const result = await bridge.execute(
          "build_road_route",
          { company_id, from_x, from_y, to_x, to_y, road_type, max_iterations },
          120000
        );
        return {
          content: [
            {
              type: "text",
              text: `Road route built. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to build road route: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "auto_signal_route",
    {
      description:
        "Automatically place signals at regular intervals along a rail route. Use after build_rail_route. Takes the path array from build_rail_route result.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        path: z
          .array(
            z.object({
              x: z.number(),
              y: z.number(),
              dir: z.number(),
            })
          )
          .describe("Path array from build_rail_route result"),
        signal_type: z
          .number()
          .default(5)
          .describe(
            "Signal type: 0=normal, 1=entry, 2=exit, 3=combo, 4=path, 5=one-way path (recommended)"
          ),
        interval: z
          .number()
          .default(5)
          .describe("Place a signal every N tiles (default 5)"),
      },
    },
    async ({ company_id, path, signal_type, interval }) => {
      try {
        const result = await bridge.execute(
          "build_signals_on_route",
          { company_id, path, signal_type, interval },
          30000
        );
        return {
          content: [
            {
              type: "text",
              text: `Signals placed. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to place signals: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "connect_industries",
    {
      description:
        "Connect two industries with a complete truck route. Automatically builds road, drive-through truck stops, depot, buys trucks, and sets orders. Use get_industries to find industry IDs and get_engines for truck engine IDs.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        source_id: z.number().describe("Source industry ID (produces cargo)"),
        dest_id: z.number().describe("Destination industry ID (accepts cargo)"),
        engine_id: z
          .number()
          .optional()
          .describe(
            "Truck engine ID (from get_engines). Omit to skip truck purchase."
          ),
        truck_count: z
          .number()
          .default(2)
          .describe("Number of trucks to buy (default 2)"),
        road_type: z
          .number()
          .default(0)
          .describe("Road type ID (0 = normal road)"),
      },
    },
    async ({ company_id, source_id, dest_id, engine_id, truck_count, road_type }) => {
      try {
        const params: Record<string, unknown> = {
          company_id,
          source_id,
          dest_id,
          truck_count,
          road_type,
        };
        if (engine_id !== undefined) params.engine_id = engine_id;

        const result = await bridge.execute(
          "connect_industries",
          params,
          120000
        );
        return {
          content: [
            {
              type: "text",
              text: `Industry route established! ${JSON.stringify(result, null, 2)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to connect industries: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "connect_towns_rail",
    {
      description:
        "High-level tool: connects two towns with a complete rail service. Automatically finds station locations, pathfinds an A* route, builds rail with curves, places signals, builds a depot, buys a train with wagons, sets up orders, and starts the train. One command for a full rail connection.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        town_a_id: z.number().describe("First town ID"),
        town_b_id: z.number().describe("Second town ID"),
        rail_type: z.number().default(0).describe("Rail type ID"),
        engine_id: z
          .number()
          .optional()
          .describe(
            "Engine ID for the train (from get_engines). Omit to skip train purchase."
          ),
        wagon_id: z
          .number()
          .optional()
          .describe(
            "Wagon ID for passenger/cargo wagons (from get_engines, filter is_wagon=true)"
          ),
        wagon_count: z
          .number()
          .default(3)
          .describe("Number of wagons to attach (default 3)"),
        platform_length: z
          .number()
          .default(5)
          .describe("Station platform length in tiles (default 5)"),
        num_platforms: z
          .number()
          .default(2)
          .describe("Number of station platforms (default 2)"),
      },
    },
    async ({
      company_id,
      town_a_id,
      town_b_id,
      rail_type,
      engine_id,
      wagon_id,
      wagon_count,
      platform_length,
      num_platforms,
    }) => {
      try {
        const params: Record<string, unknown> = {
          company_id,
          town_a_id,
          town_b_id,
          rail_type,
          platform_length,
          num_platforms,
        };
        if (engine_id !== undefined) params.engine_id = engine_id;
        if (wagon_id !== undefined) params.wagon_id = wagon_id;
        if (wagon_count !== undefined) params.wagon_count = wagon_count;

        const result = await bridge.execute(
          "connect_towns_rail",
          params,
          120000
        );
        return {
          content: [
            {
              type: "text",
              text: `Rail connection established! ${JSON.stringify(result, null, 2)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to connect towns: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

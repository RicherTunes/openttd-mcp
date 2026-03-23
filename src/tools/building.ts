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
        "Build a rail track segment between two adjacent tiles. Requires ClaudeMCP GameScript to be loaded. For longer routes, call this multiple times or use build_rail_route for A* pathfinding. Use get_rail_types to find available rail types. On failure: if ERR_AREA_NOT_CLEAR, a building is in the way — try an adjacent tile or use demolish_tile. If ERR_LAND_SLOPED_WRONG, use terraform to level terrain first.",
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
        "Build a train station. Requires ClaudeMCP GameScript to be loaded. Both directions (0=NE-SW, 1=NW-SE) are tried automatically if the first fails. Must be placed on flat, clear terrain — use find_rail_station_spot to find suitable locations. On failure: if ERR_AREA_NOT_CLEAR, use terraform to level the area or try a different spot from find_rail_station_spot.",
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
        "Build a rail depot. Requires ClaudeMCP GameScript to be loaded. Needed to buy trains — use buy_vehicle with the depot coordinates afterward. Direction is auto-detected — all 4 directions are tried automatically if the specified one fails. On failure: if ERR_AREA_NOT_CLEAR, try an adjacent tile or use demolish_tile. If ERR_LAND_SLOPED_WRONG, use terraform to level terrain.",
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
        "Build a road between two tiles. Requires ClaudeMCP GameScript to be loaded. Works for adjacent tiles only. For longer roads, use build_road_line (straight) or build_road_route (A* pathfinding). On failure: if ERR_AREA_NOT_CLEAR, a building is in the way — try an adjacent tile or use demolish_tile. If ERR_LAND_SLOPED_WRONG, use terraform to level terrain.",
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
        "Build a road vehicle depot. Requires ClaudeMCP GameScript to be loaded. Needed to buy road vehicles (buses, trucks) — use buy_vehicle with the depot coordinates afterward. Direction is auto-detected — all 4 directions are tried automatically if the specified one fails. Use find_depot_spots to find suitable locations near a town. On failure: if ERR_AREA_NOT_CLEAR, try an adjacent tile or use demolish_tile.",
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
        "Build a bus or truck stop. Requires ClaudeMCP GameScript to be loaded. RECOMMENDED: Use is_drive_through=true for reliable stops — regular bay stops are unreliable. Drive-through stops must be placed ON existing road tiles. Use find_drive_through_spots to find suitable locations. On failure: if ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION, try the other direction (0 vs 1). If ERR_AREA_NOT_CLEAR, the tile is occupied — pick another spot from find_drive_through_spots.",
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
        "Build an airport. Requires ClaudeMCP GameScript to be loaded. Airports need a large flat area — use survey_area to find clear terrain first. On failure: if ERR_AREA_NOT_CLEAR, the area has obstacles — use terraform to level it or find a different location. If ERR_LOCAL_AUTHORITY_REFUSES, plant_trees near the town to improve rating first.",
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
      description: "Build a ship dock on a coastal tile. Requires ClaudeMCP GameScript to be loaded. The tile must be adjacent to water. On failure: if ERR_AREA_NOT_CLEAR, the tile is occupied. If ERR_LAND_SLOPED_WRONG, the tile is not on a coast — use get_tile_info to find coastal tiles nearby.",
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
        "Build a bridge between two tiles. Requires ClaudeMCP GameScript to be loaded. Tiles must be at the same height, in a straight line (same X or same Y), and the gap must be bridgeable. On failure: if ERR_LAND_SLOPED_WRONG, the endpoints are at different heights — use terraform to level them. If the bridge is too long, try bridge_type with higher ID for longer span bridges.",
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
        "Build a tunnel starting from the given tile. Requires ClaudeMCP GameScript to be loaded. OpenTTD automatically finds the exit on the other side of the hill. The entrance tile must be on a slope facing into the hill. On failure: if the tunnel is too long or has no valid exit, try a different approach angle or use a bridge instead.",
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
        "Demolish/clear everything on a tile. Requires ClaudeMCP GameScript to be loaded. Use with caution — this removes buildings, tracks, roads, etc. Demolishing town buildings lowers your town rating. If ERR_LOCAL_AUTHORITY_REFUSES, your rating is too low — use plant_trees to improve it first.",
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
        "Build a signal on a rail tile. Requires ClaudeMCP GameScript to be loaded. Signals control train traffic flow. For auto-placing signals along a route, use auto_signal_route instead. Recommended: type 5 (one-way path signal) for most use cases. On failure: the tile must have rail track — use get_tile_info to verify.",
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
        "Build a pathfound rail route between two points using A* pathfinding. Requires ClaudeMCP GameScript to be loaded. Game must be unpaused for A* pathfinding to work. Automatically routes around water, buildings, and terrain. Builds curved track where needed. Returns the path array — pass it to auto_signal_route to place signals along the route. On failure: increase max_iterations for very long routes, or try different start/end points.",
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
        "Build a pathfound road route between two points using A* pathfinding. Requires ClaudeMCP GameScript to be loaded. Game must be unpaused for A* pathfinding to work. Automatically routes around water, buildings, and terrain. Can demolish buildings as a last resort. Much more reliable than manual build_road calls in dense towns. On failure: increase max_iterations for very long routes, or try different start/end points.",
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
        "Automatically place signals at regular intervals along a rail route. Requires ClaudeMCP GameScript to be loaded. Use after build_rail_route — pass the path array from its result. Recommended signal_type=5 (one-way path signal) for most routes. On failure: ensure the path array is valid and came from a successful build_rail_route call.",
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
        "Connect two industries with a complete truck route. Requires ClaudeMCP GameScript to be loaded. Game must be unpaused for A* pathfinding to work. Automatically builds road, drive-through truck stops, depot, buys trucks, and sets orders. Use get_industries to find industry IDs and get_engines(vehicle_type='road') for truck engine IDs. On failure: check that the industries exist and are not already fully served. If road pathfinding fails, the industries may be too far apart or separated by water.",
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
        "High-level tool: connects two towns with a complete rail service. Requires ClaudeMCP GameScript to be loaded. Game must be unpaused for A* pathfinding to work. Automatically finds station locations, pathfinds an A* route, builds rail with curves, places signals, builds a depot, buys a train with wagons, sets up orders, and starts the train. One command for a full rail connection. Use get_towns to find town IDs and get_engines(vehicle_type='train') for engine/wagon IDs. On failure: towns may be too far apart or terrain impassable — try connect_towns_bus for a simpler road connection.",
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

  server.registerTool(
    "demolish_and_build_road",
    {
      description:
        "Atomically demolish tiles and build road in the same game tick. Requires ClaudeMCP GameScript to be loaded. Prevents towns from rebuilding before road is placed. Pass an array of tile coordinates — each tile is demolished then road is built to the next tile. Use when build_road_route cannot route through dense towns. On failure: if ERR_LOCAL_AUTHORITY_REFUSES, your town rating is too low — use plant_trees first.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        tiles: z
          .array(z.object({ x: z.number(), y: z.number() }))
          .describe("Array of tile coordinates to demolish and connect with road (max 50)"),
        road_type: z.number().default(0).describe("Road type ID"),
      },
    },
    async ({ company_id, tiles, road_type }) => {
      try {
        const result = await bridge.execute("demolish_and_build_road", {
          company_id,
          tiles,
          road_type,
        });
        return {
          content: [
            { type: "text", text: JSON.stringify((result as any).result ?? result, null, 2) },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "terraform",
    {
      description:
        "Modify terrain. Requires ClaudeMCP GameScript to be loaded. raise/lower changes height by one step, level flattens area to center tile height. Use before building on hilly terrain — especially before build_rail_station or build_airport. On failure: if the tile has a building or structure on it, use demolish_tile first.",
      inputSchema: {
        company_id: z.number().describe("Company ID that will pay for terraforming"),
        x: z.number().describe("Center tile X coordinate"),
        y: z.number().describe("Center tile Y coordinate"),
        action: z
          .enum(["raise", "lower", "level"])
          .default("level")
          .describe("Terraform action: raise, lower, or level"),
        radius: z
          .number()
          .default(0)
          .describe("Radius around center tile to terraform (0 = single tile)"),
      },
    },
    async ({ company_id, x, y, action, radius }) => {
      try {
        const result = await bridge.execute("terraform", {
          company_id,
          x,
          y,
          action,
          radius,
        });
        return {
          content: [
            {
              type: "text",
              text: `Terraform ${action} at (${x},${y}) radius=${radius}. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to terraform: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "check_industry_catchment",
    {
      description:
        "Check if a tile is within an industry's station catchment area. Requires ClaudeMCP GameScript to be loaded. Also finds the best nearby tile (road or buildable) that IS within catchment. Use before placing truck stops to ensure cargo will be accepted. The returned best_spot can be used directly with build_road_stop.",
      inputSchema: {
        industry_id: z.number().describe("Industry ID"),
        x: z.number().describe("Tile X to check"),
        y: z.number().describe("Tile Y to check"),
      },
    },
    async ({ industry_id, x, y }) => {
      try {
        const result = await bridge.execute("check_industry_catchment", {
          industry_id,
          x,
          y,
        });
        const r = (result as any).result ?? result;
        const lines = [
          `Industry: ${r.industry_name} (${r.industry_id})`,
          `Checking tile (${r.check_x}, ${r.check_y}): distance=${r.distance}, in_catchment=${r.in_catchment}`,
        ];
        if (r.best_spot) {
          lines.push(
            `Best spot in catchment: (${r.best_spot.x}, ${r.best_spot.y}) dist=${r.best_spot.distance} is_road=${r.best_spot.is_road}`
          );
        } else {
          lines.push("No suitable spot found in catchment area");
        }
        return { content: [{ type: "text", text: lines.join("\n") }] };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "remove_station",
    {
      description:
        "Remove a station/stop at a tile by demolishing it. Requires ClaudeMCP GameScript to be loaded. Make sure no vehicles are currently loading at the station. Use get_stations to find station tile coordinates.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Station tile X coordinate"),
        y: z.number().describe("Station tile Y coordinate"),
      },
    },
    async ({ company_id, x, y }) => {
      try {
        const result = await bridge.execute("remove_station", {
          company_id,
          x,
          y,
        });
        return {
          content: [
            {
              type: "text",
              text: `Station removed at (${x},${y}). ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to remove station: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "connect_towns_bus",
    {
      description:
        "Connect two towns with a complete bus route. Requires ClaudeMCP GameScript to be loaded. Game must be unpaused for A* pathfinding to work. Automatically finds drive-through stop locations on town roads, builds connecting road, depot, buys buses, and sets orders. Use get_towns to find town IDs and get_engines(vehicle_type='road') for bus engine IDs. On failure: towns may be too far apart — try reducing the distance or check that a road can physically connect them.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        town_a_id: z.number().describe("First town ID"),
        town_b_id: z.number().describe("Second town ID"),
        bus_count: z
          .number()
          .default(2)
          .describe("Number of buses to buy (default 2)"),
        engine_id: z
          .number()
          .optional()
          .describe(
            "Bus engine ID (from get_engines). Omit to auto-find first available bus engine."
          ),
        road_type: z
          .number()
          .default(0)
          .describe("Road type ID (0 = normal road)"),
      },
    },
    async ({ company_id, town_a_id, town_b_id, bus_count, engine_id, road_type }) => {
      try {
        const params: Record<string, unknown> = {
          company_id,
          town_a_id,
          town_b_id,
          bus_count,
          road_type,
        };
        if (engine_id !== undefined) params.engine_id = engine_id;

        const result = await bridge.execute(
          "connect_towns_bus",
          params,
          120000
        );
        return {
          content: [
            {
              type: "text",
              text: `Bus route established! ${JSON.stringify(result, null, 2)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to connect towns with bus route: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

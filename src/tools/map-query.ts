/**
 * Map query tools - get information about towns, industries, tiles, engines, cargo.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { GameScriptBridge } from "../gamescript/bridge.js";
import { AdminClient } from "../admin-client.js";

export function registerMapQueryTools(
  server: McpServer,
  bridge: GameScriptBridge,
  client: AdminClient
): void {
  server.registerTool(
    "get_map_size",
    {
      description:
        "Get the map dimensions. Tile coordinates range from (0,0) to (mapSizeX-1, mapSizeY-1).",
      inputSchema: {},
    },
    async () => {
      if (client.isConnected && client.serverInfo) {
        return {
          content: [
            {
              type: "text",
              text: `Map size: ${client.serverInfo.mapSizeX} x ${client.serverInfo.mapSizeY} tiles`,
            },
          ],
        };
      }
      try {
        const result = await bridge.execute("get_map_size");
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_towns",
    {
      description:
        "List all towns on the map with their names, population, and tile coordinates. Essential for planning routes.",
      inputSchema: {},
    },
    async () => {
      try {
        const result = await bridge.execute("get_towns");
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
              text: `Failed to get towns: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_town_info",
    {
      description:
        "Get detailed information about a specific town including population, growth rate, buildings, and authority rating.",
      inputSchema: {
        town_id: z.number().describe("Town ID"),
      },
    },
    async ({ town_id }) => {
      try {
        const result = await bridge.execute("get_town_info", { town_id });
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_industries",
    {
      description:
        "List all industries on the map with their types, locations, and production data. Essential for planning cargo routes.",
      inputSchema: {},
    },
    async () => {
      try {
        const result = await bridge.execute("get_industries");
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
              text: `Failed to get industries: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_industry_info",
    {
      description:
        "Get detailed info about a specific industry including production rates, accepted cargo, and nearby stations.",
      inputSchema: {
        industry_id: z.number().describe("Industry ID"),
      },
    },
    async ({ industry_id }) => {
      try {
        const result = await bridge.execute("get_industry_info", {
          industry_id,
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_tile_info",
    {
      description:
        "Get information about a specific map tile: terrain type, height, slope, owner, and what is built on it.",
      inputSchema: {
        x: z.number().describe("Tile X coordinate"),
        y: z.number().describe("Tile Y coordinate"),
      },
    },
    async ({ x, y }) => {
      try {
        const result = await bridge.execute("get_tile_info", { x, y });
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_engines",
    {
      description:
        "List available vehicle engines that can be purchased. Filter by vehicle type to see trains, road vehicles, ships, or aircraft.",
      inputSchema: {
        vehicle_type: z
          .enum(["train", "road", "ship", "aircraft"])
          .describe("Vehicle type to list engines for"),
      },
    },
    async ({ vehicle_type }) => {
      try {
        const result = await bridge.execute("get_engines", { vehicle_type });
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_cargo_types",
    {
      description:
        "List all cargo types in the game (passengers, coal, mail, goods, etc.) with their IDs and properties.",
      inputSchema: {},
    },
    async () => {
      try {
        const result = await bridge.execute("get_cargo_types");
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_stations",
    {
      description:
        "List all stations owned by a company with their locations and cargo waiting.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute("get_stations", { company_id });
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_rail_types",
    {
      description: "List available rail types (normal rail, electric, monorail, maglev).",
      inputSchema: {},
    },
    async () => {
      try {
        const result = await bridge.execute("get_rail_types");
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_road_types",
    {
      description: "List available road types (road, tram, etc.).",
      inputSchema: {},
    },
    async () => {
      try {
        const result = await bridge.execute("get_road_types");
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_tiles",
    {
      description:
        "Query multiple tiles at once (batch). More efficient than calling get_tile_info repeatedly. Returns terrain, height, slope, owner, and build info for each tile.",
      inputSchema: {
        tiles: z
          .array(
            z.object({
              x: z.number().describe("Tile X coordinate"),
              y: z.number().describe("Tile Y coordinate"),
            })
          )
          .max(50)
          .describe("Array of tile coordinates to query (max 50)"),
      },
    },
    async ({ tiles }) => {
      try {
        const result = await bridge.execute("get_tiles", { tiles });
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  // =====================================================================
  // SMART QUERY TOOLS
  // =====================================================================

  server.registerTool(
    "scan_town_area",
    {
      description:
        "Scan tiles around a town center and classify each as buildable, road, building, or water. Returns counts and coordinate lists. Use this to understand town layout before building.",
      inputSchema: {
        town_id: z.number().describe("Town ID"),
        radius: z
          .number()
          .optional()
          .describe("Scan radius around town center (default 15)"),
      },
    },
    async ({ town_id, radius }) => {
      try {
        const params: Record<string, unknown> = { town_id };
        if (radius !== undefined) params.radius = radius;
        const result = await bridge.execute("scan_town_area", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "find_bus_stop_spots",
    {
      description:
        "Find tiles suitable for bus stops: buildable AND adjacent to an existing road. Returns candidates sorted by distance from town center, with adjacent road coordinates.",
      inputSchema: {
        town_id: z.number().describe("Town ID"),
        radius: z
          .number()
          .optional()
          .describe("Search radius around town center (default 15)"),
        max_results: z
          .number()
          .optional()
          .describe("Maximum results to return (default 10)"),
      },
    },
    async ({ town_id, radius, max_results }) => {
      try {
        const params: Record<string, unknown> = { town_id };
        if (radius !== undefined) params.radius = radius;
        if (max_results !== undefined) params.max_results = max_results;
        const result = await bridge.execute("find_bus_stop_spots", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "find_drive_through_spots",
    {
      description:
        "Find road tiles suitable for drive-through bus/truck stops. Drive-through stops avoid direction issues and are placed on existing roads.",
      inputSchema: {
        town_id: z.number().describe("Town ID"),
        radius: z
          .number()
          .optional()
          .describe("Search radius around town center (default 15)"),
        max_results: z
          .number()
          .optional()
          .describe("Maximum results to return (default 10)"),
      },
    },
    async ({ town_id, radius, max_results }) => {
      try {
        const params: Record<string, unknown> = { town_id };
        if (radius !== undefined) params.radius = radius;
        if (max_results !== undefined) params.max_results = max_results;
        const result = await bridge.execute("find_drive_through_spots", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "find_depot_spots",
    {
      description:
        "Find tiles suitable for road depots: buildable AND adjacent to an existing road. Returns candidates with depot_direction (0=NE, 1=SE, 2=SW, 3=NW) indicating which way the depot should face.",
      inputSchema: {
        town_id: z.number().describe("Town ID"),
        radius: z
          .number()
          .optional()
          .describe("Search radius around town center (default 15)"),
        max_results: z
          .number()
          .optional()
          .describe("Maximum results to return (default 5)"),
      },
    },
    async ({ town_id, radius, max_results }) => {
      try {
        const params: Record<string, unknown> = { town_id };
        if (radius !== undefined) params.radius = radius;
        if (max_results !== undefined) params.max_results = max_results;
        const result = await bridge.execute("find_depot_spots", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  // =====================================================================
  // RAIL TOOLS
  // =====================================================================

  server.registerTool(
    "find_rail_station_spot",
    {
      description:
        "Find a flat buildable area near a town suitable for a train station. Returns candidates with x, y, direction (0=NE-SW along X, 1=NW-SE along Y), and elevation.",
      inputSchema: {
        town_id: z.number().describe("Town ID"),
        platform_length: z
          .number()
          .optional()
          .describe("Platform length in tiles (default 5)"),
        num_platforms: z
          .number()
          .optional()
          .describe("Number of platforms (default 2)"),
        max_distance: z
          .number()
          .optional()
          .describe("Max search distance from town center (default 20)"),
        max_results: z
          .number()
          .optional()
          .describe("Max results (default 5)"),
      },
    },
    async ({ town_id, platform_length, num_platforms, max_distance, max_results }) => {
      try {
        const params: Record<string, unknown> = { town_id };
        if (platform_length !== undefined) params.platform_length = platform_length;
        if (num_platforms !== undefined) params.num_platforms = num_platforms;
        if (max_distance !== undefined) params.max_distance = max_distance;
        if (max_results !== undefined) params.max_results = max_results;
        const result = await bridge.execute("find_rail_station_spot", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [
            { type: "text", text: `Failed: ${err instanceof Error ? err.message : String(err)}` },
          ],
        };
      }
    }
  );

  server.registerTool(
    "survey_line",
    {
      description:
        "Survey terrain along a straight line (same X or same Y) between two points. Returns height, slope, buildability, water for each tile. Use to plan rail routes.",
      inputSchema: {
        from_x: z.number().describe("Start X"),
        from_y: z.number().describe("Start Y"),
        to_x: z.number().describe("End X"),
        to_y: z.number().describe("End Y"),
      },
    },
    async ({ from_x, from_y, to_x, to_y }) => {
      try {
        const result = await bridge.execute("survey_line", {
          from_x, from_y, to_x, to_y,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [
            { type: "text", text: `Failed: ${err instanceof Error ? err.message : String(err)}` },
          ],
        };
      }
    }
  );

  server.registerTool(
    "survey_area",
    {
      description:
        "Survey a rectangular area of the map. Returns ASCII grid maps showing terrain types and heights. Legend: .=flat buildable, /=sloped, ~=water, #=building, +=road, r=rail, T=town center. Use to plan rail routes and station placement by visualizing terrain, obstacles, and height changes.",
      inputSchema: {
        from_x: z.number().describe("Left X coordinate"),
        from_y: z.number().describe("Top Y coordinate"),
        to_x: z.number().describe("Right X coordinate"),
        to_y: z.number().describe("Bottom Y coordinate"),
      },
    },
    async ({ from_x, from_y, to_x, to_y }) => {
      try {
        const result = await bridge.execute("survey_area", {
          from_x, from_y, to_x, to_y,
        }) as { result?: { terrain?: string[]; heights?: string[]; from_x?: number; from_y?: number; width?: number; height?: number; min_height?: number; max_height?: number; counts?: Record<string, number>; legend?: string } };
        // Format the grids nicely with axis labels
        if (result?.result?.terrain) {
          const r = result.result;
          const yStart = r.from_y!;

          let terrainMap = "TERRAIN MAP:\n";
          let heightMap = "\nHEIGHT MAP:\n";
          for (let i = 0; i < r.terrain!.length; i++) {
            const yLabel = String(yStart + i).padStart(4);
            terrainMap += `${yLabel} ${r.terrain![i]}\n`;
            heightMap += `${yLabel} ${r.heights![i]}\n`;
          }

          return {
            content: [{
              type: "text" as const,
              text: terrainMap + heightMap +
                `\nLegend: ${r.legend}` +
                `\nSize: ${r.width}x${r.height} | Heights: ${r.min_height}-${r.max_height}` +
                `\nCounts: ${JSON.stringify(r.counts)}`,
            }],
          };
        }
        return {
          content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{
            type: "text" as const,
            text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
          }],
        };
      }
    }
  );

  server.registerTool(
    "build_rail_line",
    {
      description:
        "Build rail track along a straight line (same X or same Y). Returns count of built segments and list of failures with error messages.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        from_x: z.number().describe("Start X"),
        from_y: z.number().describe("Start Y"),
        to_x: z.number().describe("End X"),
        to_y: z.number().describe("End Y"),
        rail_type: z.number().optional().describe("Rail type ID (default 0)"),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, rail_type }) => {
      try {
        const params: Record<string, unknown> = {
          company_id, from_x, from_y, to_x, to_y,
        };
        if (rail_type !== undefined) params.rail_type = rail_type;
        const result = await bridge.execute("build_rail_line", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [
            { type: "text", text: `Failed: ${err instanceof Error ? err.message : String(err)}` },
          ],
        };
      }
    }
  );

  server.registerTool(
    "build_road_line",
    {
      description:
        "Build road along a straight line (same X or same Y). Returns count of built segments, failures, and auto-connected endpoints. For L-shaped routes, call twice.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        from_x: z.number().describe("Start X"),
        from_y: z.number().describe("Start Y"),
        to_x: z.number().describe("End X"),
        to_y: z.number().describe("End Y"),
        road_type: z.number().optional().describe("Road type ID (default 0)"),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, road_type }) => {
      try {
        const params: Record<string, unknown> = {
          company_id, from_x, from_y, to_x, to_y,
        };
        if (road_type !== undefined) params.road_type = road_type;
        const result = await bridge.execute("build_road_line", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [
            { type: "text", text: `Failed: ${err instanceof Error ? err.message : String(err)}` },
          ],
        };
      }
    }
  );

  server.registerTool(
    "check_road_connection",
    {
      description:
        "Check if two tiles are connected by road using BFS pathfinding (max 2000 tiles). Returns whether a road path exists between the two points.",
      inputSchema: {
        from_x: z.number().describe("Start tile X coordinate"),
        from_y: z.number().describe("Start tile Y coordinate"),
        to_x: z.number().describe("End tile X coordinate"),
        to_y: z.number().describe("End tile Y coordinate"),
      },
    },
    async ({ from_x, from_y, to_x, to_y }) => {
      try {
        const result = await bridge.execute("check_road_connection", {
          from_x, from_y, to_x, to_y,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [
            { type: "text", text: `Failed: ${err instanceof Error ? err.message : String(err)}` },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_tile_range",
    {
      description:
        "Query a rectangular area of tiles. Returns a compact ASCII grid showing terrain types (. buildable, R road, * our road, # building, ~ water, S our stop) plus height grid. Max 20x20. Ideal for surveying an area before building.",
      inputSchema: {
        from_x: z.number().describe("Left X coordinate of the area"),
        from_y: z.number().describe("Top Y coordinate of the area"),
        to_x: z.number().describe("Right X coordinate of the area"),
        to_y: z.number().describe("Bottom Y coordinate of the area"),
      },
    },
    async ({ from_x, from_y, to_x, to_y }) => {
      try {
        const result = await bridge.execute("get_tile_range", {
          from_x, from_y, to_x, to_y,
        }, 30000);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (err) {
        return {
          content: [
            { type: "text", text: `Failed: ${err instanceof Error ? err.message : String(err)}` },
          ],
        };
      }
    }
  );

  // =====================================================================
  // TOWN RATING & TREES
  // =====================================================================

  server.registerTool(
    "get_town_rating",
    {
      description:
        "Get a company's rating with a specific town. Rating affects what you can build in the town's authority area. Returns numeric rating and label (outstanding/good/mediocre/poor/appalling/hostile).",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        town_id: z.number().describe("Town ID"),
      },
    },
    async ({ company_id, town_id }) => {
      try {
        const result = await bridge.execute("get_town_rating", {
          company_id,
          town_id,
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "plant_trees",
    {
      description:
        "Plant trees around a location. Trees improve the local authority rating with nearby towns. Useful before building stations if your rating is too low.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        x: z.number().describe("Center X coordinate"),
        y: z.number().describe("Center Y coordinate"),
        radius: z
          .number()
          .optional()
          .describe("Planting radius (default 3)"),
      },
    },
    async ({ company_id, x, y, radius }) => {
      try {
        const params: Record<string, unknown> = { company_id, x, y };
        if (radius !== undefined) params.radius = radius;
        const result = await bridge.execute("plant_trees", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "estimate_route_profit",
    {
      description:
        "Estimate annual profit for a cargo route before building. Shows revenue per trip, trips per year, costs, payback period. Helps decide which routes to build.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        from_x: z.number().describe("Source tile X coordinate"),
        from_y: z.number().describe("Source tile Y coordinate"),
        to_x: z.number().describe("Destination tile X coordinate"),
        to_y: z.number().describe("Destination tile Y coordinate"),
        cargo_id: z
          .number()
          .default(1)
          .describe("Cargo type ID (default 1 = coal). Use get_cargo_types to see all."),
        engine_id: z
          .number()
          .optional()
          .describe("Engine ID to use for vehicle stats. Omit for rough estimate with defaults."),
      },
    },
    async ({ company_id, from_x, from_y, to_x, to_y, cargo_id, engine_id }) => {
      try {
        const params: Record<string, unknown> = {
          company_id,
          from_x,
          from_y,
          to_x,
          to_y,
          cargo_id,
        };
        if (engine_id !== undefined) params.engine_id = engine_id;
        const result = await bridge.execute("estimate_route_profit", params);
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
              text: `Failed to estimate route profit: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_station_cargo",
    {
      description:
        "Get cargo waiting at a station. Shows each cargo type with amount waiting and station rating for that cargo. Use to monitor station performance.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        station_id: z.number().describe("Station ID"),
      },
    },
    async ({ company_id, station_id }) => {
      try {
        const result = await bridge.execute("get_station_cargo", {
          company_id,
          station_id,
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  // =====================================================================
  // SUBSIDIES, MAP OVERVIEW, CARGO PAYMENT RATES
  // =====================================================================

  server.registerTool(
    "get_subsidies",
    {
      description:
        "List available and awarded subsidies. Subsidies offer bonus payment for specific cargo routes. Prioritize these for maximum profit.",
      inputSchema: {},
    },
    async () => {
      try {
        const result = await bridge.execute("get_subsidies");
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_map_overview",
    {
      description:
        "Get a high-level summary of the game: date, map size, town count, population, industries by type, subsidies, and company stats. One call to understand the entire game.",
      inputSchema: {
        company_id: z
          .number()
          .optional()
          .describe(
            "Company ID to include company stats (money, loan, vehicles, stations)"
          ),
      },
    },
    async ({ company_id }) => {
      try {
        const params: Record<string, unknown> = {};
        if (company_id !== undefined) params.company_id = company_id;
        const result = await bridge.execute("get_map_overview", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_cargo_payment_rates",
    {
      description:
        "Calculate cargo payment rates sorted by profitability. Shows expected income per 100 units at given distance and transit time. Use to pick the most profitable cargo routes.",
      inputSchema: {
        distance: z
          .number()
          .optional()
          .describe("Distance in tiles for income calculation (default 50)"),
        days_transit: z
          .number()
          .optional()
          .describe(
            "Days in transit for income calculation (default 30)"
          ),
      },
    },
    async ({ distance, days_transit }) => {
      try {
        const params: Record<string, unknown> = {};
        if (distance !== undefined) params.distance = distance;
        if (days_transit !== undefined) params.days_transit = days_transit;
        const result = await bridge.execute("get_cargo_payment_rates", params);
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
              text: `Failed: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  // =====================================================================
  // DIAGNOSTICS & FLEET MANAGEMENT
  // =====================================================================

  server.registerTool(
    "find_route_opportunities",
    {
      description:
        "Find the best unserved routes on the map. Scans for close industry pairs (coal->power, farm->factory, etc.) and nearby big town pairs for bus routes. Returns opportunities sorted by type with distances.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        max_results: z
          .number()
          .optional()
          .describe("Maximum industry route results (default 5)"),
      },
    },
    async ({ company_id, max_results }) => {
      try {
        const params: Record<string, unknown> = { company_id };
        if (max_results !== undefined) params.max_results = max_results;
        const result = await bridge.execute(
          "find_route_opportunities",
          params
        );
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
              text: `Failed to find route opportunities: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_waiting_cargo",
    {
      description:
        "List all stations with cargo waiting for pickup. Identifies bottlenecks where more vehicles are needed. Shows cargo types and amounts per station.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute("get_waiting_cargo", {
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
              text: `Failed to get waiting cargo: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

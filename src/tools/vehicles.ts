/**
 * Vehicle management tools - buy, sell, start, stop, orders.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { GameScriptBridge } from "../gamescript/bridge.js";

export function registerVehicleTools(
  server: McpServer,
  bridge: GameScriptBridge
): void {
  server.registerTool(
    "buy_vehicle",
    {
      description:
        "Buy a vehicle at a depot. The vehicle starts stopped. Use get_engines to find available engine IDs. The depot must exist at the specified tile.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        depot_x: z.number().describe("Depot tile X coordinate"),
        depot_y: z.number().describe("Depot tile Y coordinate"),
        engine_id: z.number().describe("Engine ID to buy (from get_engines)"),
      },
    },
    async ({ company_id, depot_x, depot_y, engine_id }) => {
      try {
        const result = await bridge.execute("buy_vehicle", {
          company_id,
          depot_x,
          depot_y,
          engine_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle purchased. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to buy vehicle: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "sell_vehicle",
    {
      description: "Sell a vehicle. The vehicle must be stopped in a depot.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID to sell"),
      },
    },
    async ({ company_id, vehicle_id }) => {
      try {
        const result = await bridge.execute("sell_vehicle", {
          company_id,
          vehicle_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle ${vehicle_id} sold. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to sell vehicle: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "start_vehicle",
    {
      description: "Start a stopped vehicle.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID to start"),
      },
    },
    async ({ company_id, vehicle_id }) => {
      try {
        const result = await bridge.execute("start_vehicle", {
          company_id,
          vehicle_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle ${vehicle_id} started. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to start vehicle: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "stop_vehicle",
    {
      description: "Stop a running vehicle.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID to stop"),
      },
    },
    async ({ company_id, vehicle_id }) => {
      try {
        const result = await bridge.execute("stop_vehicle", {
          company_id,
          vehicle_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle ${vehicle_id} stopped. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to stop vehicle: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "send_vehicle_to_depot",
    {
      description: "Send a vehicle to the nearest depot.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID"),
      },
    },
    async ({ company_id, vehicle_id }) => {
      try {
        const result = await bridge.execute("send_to_depot", {
          company_id,
          vehicle_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle ${vehicle_id} sent to depot. ${JSON.stringify(result)}`,
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
    "clone_vehicle",
    {
      description:
        "Clone a vehicle, copying its orders. The clone will be created at the same depot.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID to clone"),
        share_orders: z
          .boolean()
          .default(true)
          .describe("Share orders with original (true) or copy independently (false)"),
      },
    },
    async ({ company_id, vehicle_id, share_orders }) => {
      try {
        const result = await bridge.execute("clone_vehicle", {
          company_id,
          vehicle_id,
          share_orders,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle ${vehicle_id} cloned. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to clone: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "add_vehicle_order",
    {
      description:
        "Add an order to a vehicle's order list. Orders tell vehicles where to go and what to do at each stop.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID"),
        station_id: z.number().describe("Station ID to visit"),
        order_flags: z
          .number()
          .default(0)
          .describe("Order flags: 0=normal, 1=full load, 2=unload all, etc."),
        order_position: z
          .number()
          .optional()
          .describe("Position in order list (omit to append)"),
      },
    },
    async ({ company_id, vehicle_id, station_id, order_flags, order_position }) => {
      try {
        const result = await bridge.execute("add_order", {
          company_id,
          vehicle_id,
          station_id,
          order_flags,
          order_position,
        });
        return {
          content: [
            {
              type: "text",
              text: `Order added to vehicle ${vehicle_id}. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to add order: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "clear_vehicle_orders",
    {
      description:
        "Remove all orders from a vehicle. Useful when changing routes or rebuilding stops.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID to clear orders from"),
      },
    },
    async ({ company_id, vehicle_id }) => {
      try {
        const result = await bridge.execute("clear_vehicle_orders", {
          company_id,
          vehicle_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Orders cleared for vehicle ${vehicle_id}. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to clear orders: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_vehicle_orders",
    {
      description: "Get the order list for a vehicle.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID"),
      },
    },
    async ({ company_id, vehicle_id }) => {
      try {
        const result = await bridge.execute("get_orders", {
          company_id,
          vehicle_id,
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
              text: `Failed to get orders: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "get_vehicles",
    {
      description:
        "List all vehicles for a company, optionally filtered by type (train, road, ship, aircraft).",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_type: z
          .enum(["train", "road", "ship", "aircraft"])
          .optional()
          .describe("Filter by vehicle type"),
      },
    },
    async ({ company_id, vehicle_type }) => {
      try {
        const result = await bridge.execute("get_vehicles", {
          company_id,
          vehicle_type,
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
              text: `Failed to get vehicles: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "refit_vehicle",
    {
      description:
        "Refit a vehicle to carry a different cargo type. Vehicle must be stopped in a depot.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
        vehicle_id: z.number().describe("Vehicle ID"),
        cargo_id: z.number().describe("Cargo type ID (from get_cargo_types)"),
      },
    },
    async ({ company_id, vehicle_id, cargo_id }) => {
      try {
        const result = await bridge.execute("refit_vehicle", {
          company_id,
          vehicle_id,
          cargo_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `Vehicle ${vehicle_id} refitted. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to refit: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "stop_all_vehicles",
    {
      description:
        "Emergency: send ALL company vehicles to their nearest depot. Useful for stopping operations quickly.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute("stop_all_vehicles", {
          company_id,
        });
        return {
          content: [
            {
              type: "text",
              text: `All vehicles sent to depot. ${JSON.stringify(result)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to stop all vehicles: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "diagnose_vehicles",
    {
      description:
        "Diagnose ALL vehicle problems in one call. Identifies: stuck/lost vehicles, too few orders, aging fleet, unprofitable routes, breakdowns, crashes. Returns summary counts and problem details.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute("diagnose_vehicles", {
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
              text: `Failed to diagnose vehicles: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  server.registerTool(
    "replace_old_vehicles",
    {
      description:
        "Find and replace aging vehicles (>80% max age). Vehicles already in depot are sold and replaced with same engine type, orders restored. Vehicles still running are sent to depot — run again later to complete replacement.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute(
          "replace_old_vehicles",
          { company_id },
          120000
        );
        return {
          content: [
            {
              type: "text",
              text: `Vehicle replacement complete. ${JSON.stringify(result, null, 2)}`,
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: `Failed to replace vehicles: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

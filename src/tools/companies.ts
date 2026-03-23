/**
 * Company information tools.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AdminClient } from "../admin-client.js";
import { GameScriptBridge } from "../gamescript/bridge.js";
import { COLOUR_NAMES } from "../types/openttd.js";

// OpenTTD stores money in GBP (base unit). Client displays with currency multiplier.
// Set OPENTTD_CURRENCY env var to match your in-game currency setting.
const CURRENCY = process.env.OPENTTD_CURRENCY ?? "GBP";
const CURRENCY_RATES: Record<string, { symbol: string; rate: number }> = {
  GBP: { symbol: "£", rate: 1 },
  USD: { symbol: "$", rate: 2 },
  EUR: { symbol: "€", rate: 2 },
};
const { symbol: CURRENCY_SYMBOL, rate: CURRENCY_RATE } = CURRENCY_RATES[CURRENCY] ?? { symbol: "£", rate: 1 };

function formatMoney(baseAmount: number | string | bigint): string {
  const num = typeof baseAmount === "bigint" ? Number(baseAmount) : typeof baseAmount === "string" ? parseInt(baseAmount, 10) : baseAmount;
  return `${CURRENCY_SYMBOL}${(num * CURRENCY_RATE).toLocaleString()}`;
}

export function registerCompanyTools(
  server: McpServer,
  client: AdminClient,
  bridge: GameScriptBridge
): void {
  server.registerTool(
    "get_companies",
    {
      description:
        "List all companies in the current game with their names, presidents, colours, and whether they are AI-controlled.",
      inputSchema: {},
    },
    async () => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }

      client.refreshCompanies();
      await new Promise((r) => setTimeout(r, 500));

      const companies = Array.from(client.companies.values()).map((c) => ({
        id: c.companyId,
        name: c.name,
        president: c.president,
        colour: COLOUR_NAMES[c.colour] ?? `unknown(${c.colour})`,
        passworded: c.passworded,
        inauguratedYear: c.inauguratedYear,
        ai: c.ai,
      }));

      if (companies.length === 0) {
        return {
          content: [
            {
              type: "text",
              text: "No companies found. Start a company in the game first.",
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(companies, null, 2),
          },
        ],
      };
    }
  );

  server.registerTool(
    "get_company_economy",
    {
      description:
        "Get financial data for companies: money, loan, income, delivered cargo, and quarterly history.",
      inputSchema: {
        company_id: z
          .number()
          .optional()
          .describe("Company ID (omit for all companies)"),
      },
    },
    async ({ company_id }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }

      const economies = await client.pollCompanyEconomy(company_id);

      const formatted = economies.map((e) => ({
        companyId: e.companyId,
        money: formatMoney(e.money),
        currentLoan: formatMoney(e.currentLoan),
        income: formatMoney(e.income),
        deliveredCargo: e.deliveredCargo,
        quarters: e.quarters.map((q) => ({
          companyValue: q.companyValue.toString(),
          performance: q.performance,
          deliveredCargo: q.deliveredCargo,
        })),
      }));

      return {
        content: [
          {
            type: "text",
            text:
              formatted.length > 0
                ? JSON.stringify(formatted, null, 2)
                : "No economy data available.",
          },
        ],
      };
    }
  );

  server.registerTool(
    "get_company_stats",
    {
      description:
        "Get vehicle and station counts for companies, broken down by type (trains, road vehicles, ships, aircraft).",
      inputSchema: {
        company_id: z
          .number()
          .optional()
          .describe("Company ID (omit for all companies)"),
      },
    },
    async ({ company_id }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }

      const stats = await client.pollCompanyStats(company_id);

      return {
        content: [
          {
            type: "text",
            text:
              stats.length > 0
                ? JSON.stringify(stats, null, 2)
                : "No stats data available.",
          },
        ],
      };
    }
  );

  server.registerTool(
    "reset_company",
    {
      description:
        "Delete/reset a company. WARNING: This permanently removes the company and all its assets!",
      inputSchema: {
        company_id: z.number().describe("Company ID to reset (0-14)"),
      },
    },
    async ({ company_id }) => {
      if (!client.isConnected) {
        return { content: [{ type: "text", text: "Not connected." }] };
      }

      // OpenTTD uses 1-based company IDs in RCON
      const lines = await client.executeRcon(
        `reset_company ${company_id + 1}`
      );
      return {
        content: [
          {
            type: "text",
            text: lines.join("\n") || `Company ${company_id} reset.`,
          },
        ],
      };
    }
  );

  server.registerTool(
    "get_company_info",
    {
      description:
        "Get detailed company information: name, money, loan, quarterly income/expenses, company value.",
      inputSchema: {
        company_id: z.number().describe("Company ID"),
      },
    },
    async ({ company_id }) => {
      try {
        const result = await bridge.execute("get_company_info", {
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
              text: `Failed to get company info: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

/**
 * Setup tools - install GameScript, configure OpenTTD, launch the game.
 *
 * These tools handle the one-time setup so Claude can get a game running
 * without the user needing to do manual file copying or config editing.
 */

import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { spawn, execSync } from "node:child_process";
import {
  existsSync,
  copyFileSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  readdirSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

/** OpenTTD user data directory (where openttd.cfg and game scripts live). */
function getOpenTTDDataDir(): string {
  if (process.platform === "win32") {
    // Check standard Documents path first
    const standard = join(homedir(), "Documents", "OpenTTD");
    if (existsSync(standard)) return standard;

    // OneDrive-redirected Documents folders
    const home = homedir();
    try {
      for (const entry of readdirSync(home)) {
        if (entry.startsWith("OneDrive")) {
          const candidate = join(home, entry, "Documents", "OpenTTD");
          if (existsSync(candidate)) return candidate;
        }
      }
    } catch {
      // Fall through
    }

    return standard; // Fallback to default
  }
  if (process.platform === "darwin") {
    return join(homedir(), "Documents", "OpenTTD");
  }
  return join(homedir(), ".openttd");
}

/** Project root (two levels up from build/tools/). */
function getProjectRoot(): string {
  const __filename = fileURLToPath(import.meta.url);
  return join(dirname(__filename), "..", "..");
}

export function registerSetupTools(server: McpServer): void {
  // ---- install_gamescript ----
  server.registerTool(
    "install_gamescript",
    {
      description:
        "Install the ClaudeMCP GameScript into OpenTTD. Copies info.nut and main.nut to the game scripts directory. Run once before playing.",
      inputSchema: {},
    },
    async () => {
      const ottdDir = getOpenTTDDataDir();
      const targetDir = join(ottdDir, "game", "ClaudeMCP");
      const sourceDir = join(getProjectRoot(), "gamescript");

      if (!existsSync(join(sourceDir, "info.nut"))) {
        return {
          content: [
            {
              type: "text" as const,
              text: `GameScript source not found at ${sourceDir}. Is the project cloned correctly?`,
            },
          ],
        };
      }

      try {
        mkdirSync(targetDir, { recursive: true });
        copyFileSync(join(sourceDir, "info.nut"), join(targetDir, "info.nut"));
        copyFileSync(
          join(sourceDir, "main.nut"),
          join(targetDir, "main.nut")
        );

        return {
          content: [
            {
              type: "text" as const,
              text: [
                `GameScript installed to ${targetDir}`,
                "",
                "Files copied:",
                "  - info.nut",
                "  - main.nut",
                "",
                'In OpenTTD: New Game > AI/Game Script Settings > Game Script > select "ClaudeMCP".',
              ].join("\n"),
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to install GameScript: ${err instanceof Error ? err.message : String(err)}\n\nManual install: copy gamescript/*.nut to ${targetDir}`,
            },
          ],
        };
      }
    }
  );

  // ---- setup_openttd ----
  server.registerTool(
    "setup_openttd",
    {
      description:
        "Configure openttd.cfg for MCP use: sets the admin password and admin port so the bridge can connect. OpenTTD must have been launched at least once to generate the config file.",
      inputSchema: {
        password: z
          .string()
          .default("claude")
          .describe("Admin password to set"),
        admin_port: z
          .number()
          .default(3977)
          .describe("Admin port (default 3977)"),
      },
    },
    async ({ password, admin_port }) => {
      const configPath = join(getOpenTTDDataDir(), "openttd.cfg");

      if (!existsSync(configPath)) {
        return {
          content: [
            {
              type: "text" as const,
              text: `openttd.cfg not found at ${configPath}.\nLaunch OpenTTD once first to generate it, then run this tool again.`,
            },
          ],
        };
      }

      try {
        let config = readFileSync(configPath, "utf8");

        // Update or insert admin_password
        if (/^admin_password\s*=/m.test(config)) {
          config = config.replace(
            /^admin_password\s*=.*/m,
            `admin_password = ${password}`
          );
        } else if (/^\[network\]/m.test(config)) {
          config = config.replace(
            /^\[network\]/m,
            `[network]\nadmin_password = ${password}`
          );
        } else {
          config += `\n[network]\nadmin_password = ${password}\n`;
        }

        // Update or insert server_admin_port
        if (/^server_admin_port\s*=/m.test(config)) {
          config = config.replace(
            /^server_admin_port\s*=.*/m,
            `server_admin_port = ${admin_port}`
          );
        } else if (/^admin_password\s*=/m.test(config)) {
          config = config.replace(
            /^admin_password\s*=.*/m,
            (match) => `${match}\nserver_admin_port = ${admin_port}`
          );
        }

        // Update or insert script_max_opcode_till_suspend
        if (/^script_max_opcode_till_suspend\s*=/m.test(config)) {
          config = config.replace(
            /^script_max_opcode_till_suspend\s*=.*/m,
            "script_max_opcode_till_suspend = 250000"
          );
        } else if (/^\[script\]/m.test(config)) {
          config = config.replace(
            /^\[script\]/m,
            "[script]\nscript_max_opcode_till_suspend = 250000"
          );
        }

        writeFileSync(configPath, config);

        return {
          content: [
            {
              type: "text" as const,
              text: [
                "openttd.cfg updated:",
                `  admin_password = ${password}`,
                `  server_admin_port = ${admin_port}`,
                `  script_max_opcode_till_suspend = 250000`,
                "",
                "Restart OpenTTD for changes to take effect.",
              ].join("\n"),
            },
          ],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to update config: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );

  // ---- launch_openttd ----
  server.registerTool(
    "launch_openttd",
    {
      description:
        "Find and launch OpenTTD. In dedicated mode (-D) a server starts immediately with the admin port available. In GUI mode the user starts a game manually. Set OPENTTD_PATH env var to override auto-detection.",
      inputSchema: {
        dedicated: z
          .boolean()
          .default(false)
          .describe(
            "Launch as a headless dedicated server (game starts immediately, admin port available right away)"
          ),
        openttd_path: z
          .string()
          .optional()
          .describe(
            "Path to the openttd executable. Auto-detected if omitted."
          ),
      },
    },
    async ({ dedicated, openttd_path }) => {
      let exePath = openttd_path ?? process.env.OPENTTD_PATH;

      if (!exePath) {
        const candidates: string[] =
          process.platform === "win32"
            ? [
                join("C:", "Program Files", "OpenTTD", "openttd.exe"),
                join("C:", "Program Files (x86)", "OpenTTD", "openttd.exe"),
                join(
                  "C:",
                  "Program Files (x86)",
                  "Steam",
                  "steamapps",
                  "common",
                  "OpenTTD",
                  "openttd.exe"
                ),
                join(
                  "C:",
                  "Program Files",
                  "Steam",
                  "steamapps",
                  "common",
                  "OpenTTD",
                  "openttd.exe"
                ),
                join(
                  homedir(),
                  "AppData",
                  "Local",
                  "Microsoft",
                  "WindowsApps",
                  "openttd.exe"
                ),
              ]
            : process.platform === "darwin"
              ? ["/Applications/OpenTTD.app/Contents/MacOS/openttd"]
              : [
                  "/usr/bin/openttd",
                  "/usr/games/openttd",
                  "/usr/local/bin/openttd",
                  "/snap/bin/openttd",
                ];

        for (const candidate of candidates) {
          if (existsSync(candidate)) {
            exePath = candidate;
            break;
          }
        }
      }

      if (!exePath || !existsSync(exePath)) {
        return {
          content: [
            {
              type: "text" as const,
              text: [
                "Could not find the OpenTTD executable.",
                "",
                "Provide the path explicitly:",
                '  launch_openttd(openttd_path: "C:\\\\path\\\\to\\\\openttd.exe")',
                "",
                "Or set the OPENTTD_PATH environment variable in your MCP config.",
              ].join("\n"),
            },
          ],
        };
      }

      try {
        const args: string[] = dedicated ? ["-D"] : [];

        const child = spawn(exePath, args, {
          detached: true,
          stdio: "ignore",
        });
        child.unref();

        const mode = dedicated ? "dedicated server" : "GUI";
        const lines = [`OpenTTD launched in ${mode} mode (PID: ${child.pid}).`];

        if (dedicated) {
          lines.push(
            "",
            "The server is starting. Use connect_to_server with your admin password to connect.",
            "Then use new_game if you want a fresh map."
          );
        } else {
          lines.push(
            "",
            "Next steps:",
            "1. In OpenTTD: New Game > AI/Game Script Settings > Game Script > select ClaudeMCP",
            "2. Start a new game",
            "3. Multiplayer > Start Server",
            "4. Then use connect_to_server to connect"
          );
        }

        return {
          content: [{ type: "text" as const, text: lines.join("\n") }],
        };
      } catch (err) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to launch OpenTTD: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    }
  );
}

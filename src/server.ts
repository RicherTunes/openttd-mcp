/**
 * MCP Server setup - registers all tools with the MCP server.
 *
 * Tools connect to the persistent bridge-server process via HTTP.
 * The bridge holds the actual TCP connection to OpenTTD.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { BridgeClient } from "./bridge-client.js";
import { GameScriptBridge } from "./gamescript/bridge.js";
import { registerConnectionTools } from "./tools/connection.js";
import { registerServerInfoTools } from "./tools/server-info.js";
import { registerGameControlTools } from "./tools/game-control.js";
import { registerRconTools } from "./tools/rcon.js";
import { registerChatTools } from "./tools/chat.js";
import { registerCompanyTools } from "./tools/companies.js";
import { registerClientTools } from "./tools/clients.js";
import { registerBuildingTools } from "./tools/building.js";
import { registerVehicleTools } from "./tools/vehicles.js";
import { registerMapQueryTools } from "./tools/map-query.js";
import { registerSetupTools } from "./tools/setup.js";

export function createServer(): {
  server: McpServer;
  client: BridgeClient;
} {
  const server = new McpServer({
    name: "openttd-mcp",
    version: "1.0.0",
  });

  const bridgeUrl = process.env.OPENTTD_BRIDGE_URL ?? "http://127.0.0.1:13977";
  const client = new BridgeClient(bridgeUrl);
  // Cast to any for tool registration - BridgeClient has the same public interface as AdminClient
  const adminClient = client as any;
  const bridge = new GameScriptBridge(adminClient);

  // Register all tool groups (adminClient cast satisfies AdminClient type for tools)
  registerConnectionTools(server, adminClient);
  registerServerInfoTools(server, adminClient, bridge);
  registerGameControlTools(server, adminClient);
  registerRconTools(server, adminClient);
  registerChatTools(server, adminClient);
  registerCompanyTools(server, adminClient);
  registerClientTools(server, adminClient);
  registerBuildingTools(server, bridge);
  registerVehicleTools(server, bridge);
  registerMapQueryTools(server, bridge, adminClient);
  registerSetupTools(server);

  // Setup guide resource
  server.registerResource(
    "setup-guide",
    "openttd://setup-guide",
    {
      title: "OpenTTD MCP Setup Guide",
      description:
        "Instructions for configuring OpenTTD to work with the MCP server",
      mimeType: "text/plain",
    },
    async () => ({
      contents: [
        {
          uri: "openttd://setup-guide",
          text: SETUP_GUIDE,
        },
      ],
    })
  );

  return { server, client };
}

const SETUP_GUIDE = `
OpenTTD MCP Server - Setup Guide
=================================

1. CONFIGURE OPENTTD
   Edit your openttd.cfg file:
   - macOS: ~/Documents/OpenTTD/openttd.cfg
   - Linux: ~/.openttd/openttd.cfg
   - Windows: Documents/OpenTTD/openttd.cfg

   Add/modify these settings in the [network] section:

   [network]
   admin_password = your_password_here
   server_admin_port = 3977

2. INSTALL THE GAMESCRIPT
   Copy the 'gamescript' folder from this project to your OpenTTD game scripts directory:
   - macOS: ~/Documents/OpenTTD/game/ClaudeMCP/
   - Linux: ~/.openttd/game/ClaudeMCP/
   - Windows: Documents/OpenTTD/game/ClaudeMCP/

   The folder should contain:
   - info.nut
   - main.nut

3. START A GAME WITH THE GAMESCRIPT
   a. Open OpenTTD
   b. Go to: New Game -> AI/Game Script Settings -> Game Script -> Select "ClaudeMCP"
   c. Start the game
   d. Then: Multiplayer -> Start Server (you can play solo on this server)

   OR if already in a game:
   a. Open the console (~)
   b. Type: start_server
   c. Make sure admin_password is set

4. CONNECT VIA MCP
   Use the connect_to_server tool with:
   - host: 127.0.0.1 (or your server's IP)
   - port: 3977
   - password: your_password_here

5. START PLAYING!
   - Use get_towns and get_industries to see what's on the map
   - Use get_engines to see available vehicles
   - Build transport routes with build_rail, build_road, etc.
   - Buy vehicles and set up orders
   - Monitor your company with get_company_economy

TROUBLESHOOTING
- "Connection refused": OpenTTD isn't running as a server, or admin_password isn't set
- "GameScript command timed out": The ClaudeMCP GameScript isn't loaded. Check AI/Game Script settings.
- Building fails: Make sure you're using the correct company_id (usually 0 for the first company)
`;

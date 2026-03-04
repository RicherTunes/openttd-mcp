# OpenTTD MCP Server

An MCP (Model Context Protocol) server that lets AI assistants play [OpenTTD](https://www.openttd.org). Build transport networks, manage vehicles, and run a logistics empire — all through natural language.

```
Claude AI ──stdio──> MCP Server ──HTTP──> Bridge Server ──TCP──> OpenTTD
                    (stateless)          (persistent)         (admin port)
```

## What can it do?

The server exposes **60+ tools** across game management, construction, and vehicle operations:

- **Map intelligence** — query towns, industries, terrain; scan areas for build sites; A* pathfinding for rail routes
- **Construction** — build rail, road, stations, depots, airports, docks, bridges, tunnels; auto-signal placement
- **Vehicles** — buy, sell, clone, refit; set orders; manage fleets of trains, buses, trucks, ships, aircraft
- **Game admin** — connect, pause/unpause, save/load, RCON commands, chat, company/client management
- **High-level automation** — `connect_towns_rail` builds a complete rail link (stations, track, signals, depot, train, orders) in one call

## Prerequisites

- [OpenTTD](https://www.openttd.org/downloads/openttd-releases/latest) (version 14+)
- [Node.js](https://nodejs.org) (v18+)

## Setup

### 1. Install dependencies

```bash
git clone https://github.com/inewlegend/openttd-mcp.git
cd openttd-mcp
npm install
npm run build
```

### 2. Install the GameScript

Copy the `gamescript` folder contents to your OpenTTD game scripts directory:

| Platform | Path |
|----------|------|
| macOS | `~/Documents/OpenTTD/game/ClaudeMCP/` |
| Linux | `~/.openttd/game/ClaudeMCP/` |
| Windows | `Documents\OpenTTD\game\ClaudeMCP\` |

The folder should contain `info.nut` and `main.nut`.

### 3. Configure OpenTTD

Edit your `openttd.cfg` and set an admin password:

```ini
[network]
admin_password = your_password_here
server_admin_port = 3977
```

### 4. Start a game with the GameScript

1. Open OpenTTD
2. Go to **New Game > AI/Game Script Settings > Game Script** and select **ClaudeMCP**
3. Start the game
4. Host a server: **Multiplayer > Start Server** (you can play solo)

### 5. Add to Claude Code

Add to your MCP settings (`~/.claude.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "openttd": {
      "command": "node",
      "args": ["/absolute/path/to/openttd-mcp/build/index.js"]
    }
  }
}
```

### 6. Start the bridge server

The bridge server maintains the persistent TCP connection to OpenTTD. Start it before using the MCP tools:

```bash
npm run bridge
```

Runs on `http://127.0.0.1:13977` by default.

### 7. Connect and play

Ask Claude to connect to your server with your admin password, then start building!

## Architecture

| Layer | Role | Transport |
|-------|------|-----------|
| **MCP Server** (`src/index.ts`) | Exposes tools to Claude via MCP protocol | stdio |
| **Bridge Server** (`src/bridge-server.ts`) | Holds persistent TCP connection to OpenTTD; REST API for the MCP server | HTTP :13977 |
| **GameScript** (`gamescript/main.nut`) | Executes in-game commands (building, vehicles, queries) inside OpenTTD | Admin port TCP :3977 |

The bridge server is separate so the MCP server can restart without dropping the OpenTTD connection. The GameScript runs inside OpenTTD's Squirrel VM and handles actual game API calls — it receives JSON commands over the admin port and streams back results.

### Protocol details

- **Authentication:** X25519 PAKE with XChaCha20-Poly1305 AEAD encryption
- **Command format:** JSON over admin port GameScript messages
- **Large responses** are automatically chunked to respect packet size limits
- **Auto-reconnect** with exponential backoff (up to 5 retries)

## Tools Reference

### Connection & Admin
| Tool | Description |
|------|-------------|
| `connect_to_server` | Connect to OpenTTD admin port |
| `disconnect` | Disconnect from server |
| `get_connection_status` | Check connection state |
| `get_server_info` | Server version, map size, landscape |
| `get_game_date` | Current in-game date |
| `pause_game` / `unpause_game` | Pause control |
| `save_game` / `load_game` / `new_game` | Game management |
| `change_setting` | Modify runtime settings |
| `execute_rcon` | Raw console commands |
| `send_chat` | Chat (broadcast, team, or client) |

### Companies & Clients
| Tool | Description |
|------|-------------|
| `get_companies` | List all companies |
| `get_company_economy` | Financial data and quarterly history |
| `get_company_stats` | Vehicle and station counts by type |
| `reset_company` | Delete a company |
| `get_clients` | List connected players |
| `kick_player` | Kick a client |

### Map & Planning
| Tool | Description |
|------|-------------|
| `get_map_size` | Map dimensions |
| `get_towns` / `get_town_info` | Town locations, population, growth |
| `get_industries` / `get_industry_info` | Industry locations and production |
| `get_tile_info` | Terrain type, height, slope, owner |
| `get_engines` | Available vehicles by type |
| `get_cargo_types` | All cargo types and properties |
| `get_stations` | Company stations with waiting cargo |
| `get_rail_types` / `get_road_types` | Available infrastructure types |
| `scan_town_area` | Classify tiles around a town center |
| `find_bus_stop_spots` | Buildable tiles adjacent to roads |
| `find_depot_spots` | Suitable spots for road depots |
| `find_rail_station_spot` | Flat areas for train stations |
| `survey_line` / `survey_area` | Terrain surveys with ASCII visualization |

### Building
| Tool | Description |
|------|-------------|
| `build_rail` / `build_rail_line` | Rail track (single segment or straight line) |
| `build_rail_route` | A* pathfound rail route around obstacles |
| `build_rail_station` | Train stations with configurable platforms |
| `build_rail_depot` | Train depots |
| `build_rail_signal` | Signals (normal, path, entry/exit/combo) |
| `auto_signal_route` | Auto-place signals along a built route |
| `connect_towns_rail` | Complete rail connection in one call |
| `build_road` / `build_road_line` | Road segments or straight lines |
| `build_road_depot` | Road vehicle depots |
| `build_road_stop` | Bus stops and truck loading bays |
| `build_airport` | Airports |
| `build_dock` | Ship docks |
| `build_bridge` | Road, rail, or water bridges |
| `build_tunnel` | Road or rail tunnels |
| `demolish_tile` | Clear a tile |

### Vehicles
| Tool | Description |
|------|-------------|
| `buy_vehicle` | Purchase at a depot |
| `sell_vehicle` | Sell (must be stopped in depot) |
| `start_vehicle` / `stop_vehicle` | Start or stop a vehicle |
| `send_vehicle_to_depot` | Route to nearest depot |
| `clone_vehicle` | Clone with shared or independent orders |
| `refit_vehicle` | Change cargo type |
| `add_vehicle_order` | Add a stop to the order list |
| `get_vehicle_orders` | View current orders |
| `get_vehicles` | List all vehicles, filterable by type |

## Example session

> **You:** Connect those three towns with bus routes
>
> **Claude:** *finds bus stop locations near town centers, builds stops and a depot, lays roads between towns (routing around buildings), buys two Thunder Buses, sets circular orders, starts them running*

> **You:** Now connect the two biggest cities with a passenger rail line
>
> **Claude:** *finds flat station sites, builds A* pathfound rail route with signals every 5 tiles, places stations and a depot, buys a train with passenger wagons, sets shuttle orders, starts the train*

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Connection refused | OpenTTD isn't hosting a server, or `admin_password` isn't set in `openttd.cfg` |
| GameScript command timed out | ClaudeMCP GameScript isn't loaded — check AI/Game Script Settings |
| Building fails | Verify `company_id` (usually `0` for the first company) |
| Bridge server won't start | Check that port 13977 is available |

## License

MIT

# OpenTTD MCP - AI Agent Guide

An MCP (Model Context Protocol) server that lets AI agents play OpenTTD. Build transport networks, manage vehicles, and control the game through 60+ tools.

## Architecture

```
AI Agent (Claude) ──stdio──▶ MCP Server ──HTTP──▶ Bridge Server ──TCP──▶ OpenTTD
                              (stateless)        (port 13977)         (port 3977)
                                                  persistent          GameScript
                                                  connection          executes cmds
```

**Three layers:**

1. **MCP Server** (`src/index.ts`) — Stateless process started by Claude Code/Desktop. Exposes tools via stdio.
2. **Bridge Server** (`src/bridge-server.ts`) — Persistent HTTP server that maintains TCP connection to OpenTTD's admin port. Must be running before using tools.
3. **GameScript** (`gamescript/main.nut`) — Squirrel script running inside OpenTTD. Receives JSON commands, executes game actions, returns results.

## Setup

### 1. OpenTTD Configuration

Edit `~/Documents/OpenTTD/openttd.cfg`:

```ini
[network]
admin_password = claude
server_admin_port = 3977
```

### 2. Install GameScript

Copy the `gamescript/` folder contents to `~/Documents/OpenTTD/game/ClaudeMCP/`:

```bash
cp gamescript/info.nut ~/Documents/OpenTTD/game/ClaudeMCP/info.nut
cp gamescript/main.nut ~/Documents/OpenTTD/game/ClaudeMCP/main.nut
```

Then in OpenTTD: **AI/Game Script Settings > GameScript > ClaudeMCP**.

### 3. Build & Run

```bash
npm install
npm run build

# Start the bridge (keep running in a separate terminal)
npm run bridge -- --password claude

# MCP server is started automatically by Claude Code/Desktop
```

### 4. Claude Code Configuration

Add to your MCP settings:

```json
{
  "mcpServers": {
    "openttd": {
      "command": "node",
      "args": ["/path/to/openttd-mcp/build/index.js"]
    }
  }
}
```

### 5. Start a Game

In OpenTTD: **Multiplayer > Start Server** (or single player, then host). The bridge connects automatically if `--password` is provided.

## Tool Reference

### Connection & Server

| Tool | Description |
|------|-------------|
| `connect_to_server` | Connect to OpenTTD admin port |
| `disconnect` | Disconnect from server |
| `get_connection_status` | Check connection state (reads cached state) |
| `get_server_info` | Map size, version, landscape type |
| `get_game_date` | Current in-game date |

### Game Control

| Tool | Description |
|------|-------------|
| `pause_game` / `unpause_game` | Pause/resume |
| `save_game` | Save with filename |
| `load_game` | Load saved game |
| `new_game` | Start new random game (ends current!) |
| `change_setting` | Modify runtime settings (max_trains, etc.) |
| `execute_rcon` | Execute raw console command |
| `send_chat` | Send chat message (broadcast/team/client) |

### Companies & Players

| Tool | Description |
|------|-------------|
| `get_companies` | List all companies |
| `get_company_economy` | Money, loans, income, cargo delivered |
| `get_company_stats` | Vehicle/station counts by type |
| `reset_company` | Delete a company (destructive!) |
| `get_clients` | List connected players |
| `kick_player` | Remove player from server |

### Map & Terrain

| Tool | Description |
|------|-------------|
| `get_map_size` | Map dimensions |
| `get_tile_info` | Single tile: terrain, height, slope, owner |
| `get_towns` | All towns with population and coordinates |
| `get_town_info` | Detailed town data (growth, buildings, authority) |
| `get_industries` | All industries with production data |
| `get_industry_info` | Industry details, accepted/produced cargo |
| `get_engines` | Available vehicles by type (train/road/ship/aircraft) |
| `get_cargo_types` | All cargo types in the game |
| `get_stations` | Company's stations with cargo waiting |
| `get_rail_types` | Available rail types (normal, electric, mono, maglev) |
| `get_road_types` | Available road types |

### Smart Queries (Planning)

| Tool | Description |
|------|-------------|
| `scan_town_area` | Classify tiles around town (buildable/road/building/water) |
| `find_bus_stop_spots` | Find tiles suitable for bus stops (buildable + adjacent to road) |
| `find_depot_spots` | Find tiles suitable for depots (buildable + adjacent to road) |
| `find_rail_station_spot` | Find flat area near town for train station |
| `survey_line` | Terrain profile along a straight line (height, slope per tile) |
| `survey_area` | ASCII grid map of rectangular region. Shows terrain types and heights |

`survey_area` is the most powerful planning tool. It returns an ASCII map:
```
Legend: . = flat buildable, / = sloped, ~ = water, # = building, + = road, r = rail, T = town center
```

### Building Infrastructure

| Tool | Description |
|------|-------------|
| `build_rail` | Single rail segment between adjacent tiles |
| `build_rail_line` | Rail along a straight line (same X or same Y) |
| `build_rail_route` | A* pathfound rail route around obstacles |
| `build_rail_station` | Train station (configurable platforms/length) |
| `build_rail_depot` | Rail vehicle depot |
| `build_rail_signal` | Signal on rail tile (normal/path/one-way) |
| `auto_signal_route` | Place signals at intervals along a route |
| `build_road` | Single road segment between adjacent tiles |
| `build_road_line` | Road along a straight line (same X or same Y) |
| `build_road_depot` | Road vehicle depot (auto-connects to adjacent road) |
| `build_road_stop` | Bus stop or truck bay (auto-connects to adjacent road) |
| `build_airport` | Airport (small/city/heliport) |
| `build_dock` | Ship dock on coastal tile |
| `build_bridge` | Bridge (road/rail/water) |
| `build_tunnel` | Tunnel (road/rail) |
| `demolish_tile` | Clear/demolish everything on a tile |
| `connect_towns_rail` | High-level: complete rail connection between two towns |

`connect_towns_rail` is the most powerful building tool. In a single call it: finds station spots, builds stations, pathfinds & builds rail, places signals, builds depot, buys a train with wagons, sets orders, and starts the train.

### Vehicles

| Tool | Description |
|------|-------------|
| `buy_vehicle` | Purchase at depot (engine ID from `get_engines`) |
| `sell_vehicle` | Sell vehicle (must be stopped in depot) |
| `start_vehicle` / `stop_vehicle` | Start/stop vehicle |
| `send_vehicle_to_depot` | Route vehicle to nearest depot |
| `clone_vehicle` | Duplicate vehicle with shared or copied orders |
| `refit_vehicle` | Change cargo type (vehicle must be in depot) |
| `add_vehicle_order` | Add a station stop to vehicle's route |
| `get_vehicle_orders` | Get vehicle's current order list |
| `get_vehicles` | List all vehicles (filter by type) |

## Common Workflows

### Bus Service Between Towns

1. **Survey the area** — `survey_area` to see terrain, roads, obstacles
2. **Find spots** — `find_bus_stop_spots` for each town, `find_depot_spots` for one town
3. **Build depot** — `build_road_depot` (auto-connects to adjacent road)
4. **Build stops** — `build_road_stop` at each town (use drive-through on existing road for best results)
5. **Connect with road** — `build_road_line` for straight segments between towns
6. **Buy bus** — `buy_vehicle` with a bus engine ID from `get_engines(vehicle_type="road")`
7. **Set orders** — `add_vehicle_order` for each stop
8. **Start** — `start_vehicle`
9. **Clone** — `clone_vehicle` to add more buses on the same route

### Rail Connection Between Towns

**Quick way** — `connect_towns_rail` does everything in one call.

**Manual way:**
1. `find_rail_station_spot` for both towns
2. `build_rail_station` at each spot
3. `build_rail_route` to pathfind and build track between stations
4. `auto_signal_route` to place signals on the route
5. `build_rail_depot` near one station
6. `buy_vehicle` for engine, then wagons (auto-attach)
7. `add_vehicle_order` for both stations
8. `start_vehicle`

### Reloading GameScript After Changes

When you modify `gamescript/main.nut`:

```bash
# 1. Copy to game folder
cp gamescript/main.nut ~/Documents/OpenTTD/game/ClaudeMCP/main.nut

# 2. In-game via tools:
execute_rcon("rescan_game")
save_game("reload_save")
execute_rcon("load 2")      # loads first save in list

# 3. Bridge crashes on game reload — restart it:
npm run bridge -- --password claude
```

## Important Notes

### Road Building
- `build_road_stop` and `build_road_depot` auto-connect to adjacent road tiles
- Drive-through bus stops must be built ON existing road tiles
- Bay stops are built on empty tiles but need explicit road connection
- `build_road_line` builds straight roads in a single call (avoids dozens of individual `build_road` calls)

### Rail Building
- OpenTTD 15 GS API: `RAILTRACK_NE_SW = 1`, `RAILTRACK_NW_SE = 2` (not 0 and 1!)
- Station direction 0 = NE-SW (along X axis), 1 = NW-SE (along Y axis)
- A* pathfinder works well for distances up to ~30 tiles; may timeout for 150+ tiles
- Wagons auto-attach to trains when bought at the same depot

### Bridge Server
- Must be running before using any tools
- Crashes when game is saved/loaded via RCON — restart after every reload
- `get_connection_status` reads cached local state, may not reflect actual server state

### Survey Area Limits
- Maximum 50x50 tiles per call
- For larger areas, make multiple calls to tile the region

## Project Structure

```
openttd-mcp/
  src/
    index.ts              # MCP server entry (stdio transport)
    server.ts             # Tool registration
    bridge-server.ts      # Persistent HTTP bridge
    bridge-client.ts      # HTTP client for MCP->bridge
    admin-client.ts       # OpenTTD admin port TCP client
    protocol/             # Admin port protocol (X25519 PAKE auth)
    gamescript/bridge.ts   # JSON command/response wrapper
    types/openttd.ts      # Enums and interfaces
    tools/
      connection.ts       # connect, disconnect, status
      server-info.ts      # server info, game date
      game-control.ts     # pause, save, load, settings
      rcon.ts             # raw console commands
      chat.ts             # chat messages
      companies.ts        # company management
      clients.ts          # player management
      building.ts         # all infrastructure building
      vehicles.ts         # vehicle operations
      map-query.ts        # map data, smart queries, line builders
  gamescript/
    info.nut              # GameScript metadata (name, version, API 15)
    main.nut              # Command dispatcher & implementations (~2000 lines)
  package.json
  tsconfig.json
```

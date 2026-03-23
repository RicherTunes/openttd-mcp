# AI Game Loop — Autonomous Play Cycle

Run one cycle of the autonomous game loop. Use `/loop 2m /game-loop` for continuous play.

IMPORTANT: All tool calls below are MCP tools (use them directly via the openttd MCP server). Do NOT use execute_rcon for these — they are NOT console commands.

Currency: All money values are in the game's currency. Check the OPENTTD_CURRENCY environment variable (default: USD). Display amounts with $ prefix.

## The Loop

### Step 1: Situational Awareness
Call these MCP tools ONE AT A TIME (not in parallel, they go through a serial queue):
1. Call MCP tool `get_map_overview` with `company_id: 0` — returns date, money, fleet size, industry counts
2. Call MCP tool `diagnose_vehicles` with `company_id: 0` — returns any vehicle problems

If not connected, call MCP tool `connect_to_server` with `password: "claude"` first. Do NOT call `disconnect` — the connection is persistent.

### Step 2: Fix Problems (if any diagnosed)
- STUCK/LOST vehicles: Call MCP tool `stop_all_vehicles` with `company_id: 0`, then rebuild stops as drive-through
- TOO_FEW_ORDERS: Call MCP tool `add_vehicle_order` for each vehicle
- AGING: Call MCP tool `replace_old_vehicles` with `company_id: 0`
- UNPROFITABLE: Call MCP tool `send_vehicle_to_depot`, then `sell_vehicle`

### Step 3: Optimize Existing Routes
1. Call MCP tool `get_waiting_cargo` with `company_id: 0` — find stations with cargo piling up
2. If waiting cargo > 100 at any station: buy more vehicles for that route

### Step 4: Expand (only if money > 30,000)
1. Call MCP tool `find_route_opportunities` with `company_id: 0` — best unserved routes
2. Call MCP tool `get_subsidies` — any bonus routes available?
3. Pick the best opportunity
4. Call MCP tool `estimate_route_profit` to verify it's worth building
5. If profitable, build manually step-by-step (do NOT use connect_industries or connect_towns_bus — they are disabled):
   a. Call `get_tile_info` on tiles near source industry to find a flat buildable tile
   b. Call `build_road_line` to build road from source area to destination area (L-shaped: horizontal then vertical)
   c. Call `find_drive_through_spots` near source to find a road tile for a stop
   d. Call `build_road_stop` with `is_drive_through: true, is_truck_stop: true` (try direction 0, if fails try 1)
   e. Repeat c-d near destination
   f. Call `find_depot_spots` near source, then `build_road_depot`
   g. Call `buy_vehicle` at the depot with the chosen engine_id
   h. Call `get_stations` to find station IDs for the two stops
   i. Call `add_vehicle_order` twice: source station (order_flags: 1 = full load), dest station (order_flags: 2 = unload)
   j. Call `start_vehicle`
   k. Repeat g-j for additional trucks

### Step 5: Financial Management
1. Call MCP tool `get_company_info` with `company_id: 0` — check finances
2. If money > loan * 2: Call MCP tool `set_loan` with `company_id: 0, action: "repay"`
3. If money < 5000 and loan < max: Call MCP tool `set_loan` with `company_id: 0, action: "borrow"`

### Key Rules
- ALL tools above are MCP tools — call them directly, NEVER via execute_rcon
- NEVER call `disconnect` during gameplay — the connection is persistent and shared
- NEVER send multiple MCP tool calls in parallel — they go through a serial GameScript queue
- Always use drive-through stops (is_drive_through: true)
- Check `diagnose_vehicles` before expanding — fix problems first
- Don't build if money < 20,000 (keep reserves)
- Coal routes are the safest first investment
- Subsidized routes give 2x payment — prioritize them
- Display all money values with $ prefix (game currency is USD)

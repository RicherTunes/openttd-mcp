# Build Bus Route Between Towns

Set up a complete bus service between two towns. Provide town names or IDs as argument: `$ARGUMENTS`

## Strategy

Use an expert sub-agent to research the best approach before building.

### Phase 1: Research (use Agent tool with WebSearch)
- Search for "OpenTTD bus route strategy" to find optimal stop placement and vehicle count
- Key insight: place stops near town CENTER for maximum passenger catchment
- Drive-through stops on existing roads avoid building through dense town centers

### Phase 2: Find Towns
1. Use `get_towns` to list all towns with populations and coordinates.
2. If no towns specified in arguments, pick the two closest towns with population > 500.
3. Calculate Manhattan distance between candidates. Ideal range: 20-60 tiles for buses.

### Phase 3: Build Infrastructure

**CRITICAL LEARNINGS:**
- **Stop direction matters!** Direction 0=NE-SW, 1=NW-SE. The stop MUST face the road it connects to.
  - If adjacent road is to the NORTH (lower Y) or SOUTH (higher Y): use direction 0 (NE-SW)
  - If adjacent road is to the WEST (lower X) or EAST (higher X): use direction 1 (NW-SE)
  - Getting this wrong means vehicles can see the stop but never enter it — they appear "lost"
- **Drive-through stops** (`is_drive_through=true`) avoid direction issues entirely. Prefer these when possible.
- **ERR_AREA_NOT_CLEAR on road tiles** means the road already exists (town road). This is FINE — don't try to rebuild.
- **Towns rebuild buildings within one tick** after demolishing. You CANNOT demolish then build road in separate calls.
- **Town roads connect most of the town internally.** Don't build redundant road through towns. Instead, place stops adjacent to EXISTING town roads.

For each town:
1. Use `find_bus_stop_spots` to find buildable tiles adjacent to roads.
2. Pick the spot closest to town center.
3. **Match the direction to the adjacent road position:**
   - `adjacent_road_y < stop_y` or `adjacent_road_y > stop_y` → direction=0
   - `adjacent_road_x < stop_x` or `adjacent_road_x > stop_x` → direction=1
4. Use `build_road_stop` with correct `direction` and `company_id=0`.

Then:
5. Use `find_depot_spots` near one of the towns.
6. Use `build_road_depot` to build a depot.
7. Connect stops with road using `build_road_line` ONLY in open areas between towns.
   - Do NOT try to build through town centers — use existing town roads.
   - For L-shaped routes between towns, call twice (horizontal then vertical).
   - If road building fails (ERR_AREA_NOT_CLEAR), the road likely already exists (town road) — this is OK.
   - If terrain blocks (ERR_LAND_SLOPED_WRONG), offset the route by 1-2 tiles.

### Phase 4: Vehicles
1. Use `get_engines` with `vehicle_type="road"` to find available buses (cargo_type=0 = passengers).
2. Use `buy_vehicle` at the depot with the bus engine_id.
3. Use `get_stations` to find station IDs for the two bus stops.
4. Use `add_vehicle_order` twice to create a shuttle route (station A → station B).
   - For passengers: order_flags=0 (normal, don't wait for full load)
5. Use `start_vehicle` to begin service.
6. Buy 1-2 more buses for the same route (towns > 1000 pop need 2-3 buses).

### Phase 5: Verify
1. Wait ~30 seconds game time.
2. Use `get_vehicles` to check:
   - `speed > 0` means vehicle is moving (good)
   - `speed = 0` + `state = 0` (running) means STUCK or LOST — check road connections
   - `state = 3` (at station) means loading — working correctly
   - `cargo_loaded > 0` means carrying passengers
3. Use `get_company_economy` to check if `deliveredCargo` is increasing.

## Vehicle States Reference
| State | Meaning |
|-------|---------|
| 0 | Running (moving or pathfinding) |
| 1 | Stopped manually |
| 2 | In depot |
| 3 | At station (loading/unloading) |
| 4 | Broken down |
| 5 | Crashed |

## Common Issues
- **Vehicle lost**: Stop direction doesn't match road approach. Rebuild stop with correct direction.
- **ERR_AREA_NOT_CLEAR**: Buildings or existing roads. For roads, this is fine. For buildings, route around.
- **Towns rebuild instantly**: Can't demolish + build in separate ticks. Use outskirt routes instead.
- **No cargo delivered**: Check that vehicles can actually ENTER the stops (direction issue).
- **Buses circling near stop**: Direction mismatch — bus can see the stop but can't enter from its approach angle.

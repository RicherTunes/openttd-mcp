# Build Bus Route Between Towns

Set up a complete bus service between two towns. Provide town names or IDs as argument: `$ARGUMENTS`

## Strategy

Use smart tools to set up bus routes efficiently.

### Phase 1: One-Call Setup (Preferred)
Use `connect_towns_bus(company_id=0, town_a_id=X, town_b_id=Y)` to build an entire bus route in one call — stops, road, depot, buses, orders. This is the fastest and most reliable method.

### Phase 2: Find Towns (if manual setup needed)
1. Use `get_towns` to list all towns with populations and coordinates.
2. If no towns specified in arguments, pick the two closest towns with population > 500.
3. Calculate Manhattan distance between candidates. Ideal range: 20-60 tiles for buses.
4. Use `get_town_rating(company_id=0, town_id=X)` to check your rating before building — low ratings can block construction.

Key insights:
- Place stops near town CENTER for maximum passenger catchment
- Drive-through stops on existing roads avoid building through dense town centers

### Phase 3: Build Infrastructure

**CRITICAL LEARNINGS:**
- **ALWAYS use `is_drive_through=true`. Regular bay stops are unreliable.** Vehicles frequently fail to enter bay stops even with correct direction, appearing "lost" and circling endlessly.
- **Drive-through stops MUST be placed on existing road tiles, not adjacent buildable tiles.** Use `find_drive_through_spots` to locate straight road segments suitable for drive-through placement.
- **If ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION, try the other direction value (0 or 1).** One of the two directions will work on any straight road segment.
- **Junctions/corners may reject both directions — find a straight road segment instead.** Drive-through stops need road on both opposite sides.
- **ERR_AREA_NOT_CLEAR on road tiles** means the road already exists (town road). This is FINE — don't try to rebuild.
- **Towns rebuild buildings within one tick** after demolishing. You CANNOT demolish then build road in separate calls.
- **Town roads connect most of the town internally.** Don't build redundant road through towns. Instead, place drive-through stops on EXISTING town roads.

For each town:
1. Use `find_drive_through_spots` to find road tiles suitable for drive-through stops (preferred).
   - Fallback: use `find_bus_stop_spots` which now includes `recommended_drive_through_dir` for each spot's adjacent road tiles (-1 means no drive-through possible there).
2. Pick the spot closest to town center.
3. Use `build_road_stop` with `is_drive_through=true`, the recommended `direction`, and `company_id=0`.
4. If ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION: try direction 0 if you used 1, or vice versa.
5. If both directions fail: the tile is a junction/corner. Pick the next spot on a straight road segment.

Then:
6. Use `find_depot_spots` near one of the towns.
7. Use `build_road_depot` to build a depot.
8. Connect stops with road using `build_road_line` ONLY in open areas between towns.
   - Do NOT try to build through town centers — use existing town roads.
   - For L-shaped routes between towns, call twice (horizontal then vertical).
   - If road building fails (ERR_AREA_NOT_CLEAR), the road likely already exists (town road) — this is OK.
   - If terrain blocks (ERR_LAND_SLOPED_WRONG), offset the route by 1-2 tiles.

### Phase 4: Vehicles
1. Use `get_engines` with `vehicle_type="road"` to find available buses (cargo_type=0 = passengers).
2. Use `buy_vehicle` at the depot with the bus engine_id.
3. Use `get_stations` to find station IDs for the two bus stops.
4. Use `add_vehicle_order` twice to create a shuttle route (station A -> station B).
   - For passengers: order_flags=0 (normal, don't wait for full load)
5. Use `start_vehicle` to begin service.
6. Buy 1-2 more buses for the same route (towns > 1000 pop need 2-3 buses).

### Phase 5: Verify
1. Wait ~30 seconds game time.
2. Use `get_vehicles` to check:
   - `speed > 0` means vehicle is moving (good)
   - `speed = 0` + `state = 0` (running) means STUCK or LOST — check road connections and stop placement
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

## Town Rating Management
- Use `get_town_rating(company_id=0, town_id=X)` before and after building to monitor your standing.
- If rating drops after demolishing buildings, use `plant_trees(company_id=0, tile_x=X, tile_y=Y)` near the town to recover rating.
- Low town rating can prevent you from building new stations in that town.

## Common Issues
- **Vehicle lost**: Stop is a regular bay stop or drive-through on a junction. Rebuild as drive-through on a straight road segment.
- **ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION**: Try the other direction (0 or 1). If both fail, the tile is a junction — pick a different tile.
- **ERR_AREA_NOT_CLEAR**: Buildings or existing roads. For roads, this is fine. For buildings, route around.
- **Towns rebuild instantly**: Can't demolish + build in separate ticks. Use outskirt routes instead.
- **No cargo delivered**: Check that vehicles can actually ENTER the stops. Use drive-through stops.
- **Buses circling near stop**: Bay stop direction mismatch. Replace with a drive-through stop.

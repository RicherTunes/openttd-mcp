# Build Cargo Route

Set up a truck route to haul cargo between an industry and its consumer. Arguments: `$ARGUMENTS`

## Strategy

Use smart tools to find and validate the best cargo routes before building.

### Phase 1: Route Discovery
1. `find_route_opportunities(company_id=0)` — automatically identifies the best unserved cargo routes, ranked by profitability.
2. `get_cargo_payment_rates()` — check which cargo types pay the most per unit to pick the best cargo.
3. `get_subsidies()` — check for subsidized routes that pay 2x. Prioritize these.
4. `estimate_route_profit` on top candidates — verify profitability before committing money.

### Phase 2: Find Industries
1. Use `get_industries` to list all industries with types and locations.
2. Match source -> destination pairs from the route opportunities identified above.
3. Pick the pair with best balance of distance (30-80 tiles) and production.
4. Use `get_industry_info` on the source to check production levels.
5. Use `check_industry_catchment` to verify that your planned stop placement will actually catch the industry's cargo.

Key profitable routes in temperate:
- Coal Mine -> Power Plant (reliable, always produces)
- Farm -> Factory (grain + livestock)
- Forest -> Sawmill (wood)
- Iron Ore Mine -> Steel Mill
- Oil Wells -> Oil Refinery
- Longer distance = more payment per unit, but slower delivery = less volume

### Phase 3: Build Infrastructure

**ONE-CALL ROUTE SETUP**: Use `connect_industries(company_id=0, source_id=X, dest_id=Y, engine_id=Z)` to build an entire cargo route in one call — stops, road, depot, vehicle, orders. This is the preferred method when available.

**MANUAL BUILD** (fallback if connect_industries fails or for custom setups):

**CRITICAL LEARNINGS:**
- **ALWAYS use `is_drive_through=true`. Regular bay stops are unreliable.** Trucks frequently fail to enter bay stops even with correct direction, appearing "lost" and circling endlessly.
- **Drive-through stops MUST be placed on existing road tiles, not adjacent buildable tiles.** Use `find_drive_through_spots` or check `recommended_drive_through_dir` from `find_bus_stop_spots`.
- **If ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION, try the other direction value (0 or 1).** One of the two directions will work on any straight road segment.
- **Junctions/corners may reject both directions — find a straight road segment instead.**
- **Industry tiles are NOT buildable.** Place truck stops on road tiles near the industry, not on the industry itself.
- **Use `get_tile_info` to find flat, buildable tiles** near industries (slope=0, is_buildable=true).
- **Build road in open terrain between industries** — much easier than through towns.
- **Order flags matter:** source=1 (full load), destination=2 (unload all).

Steps:
1. Build a road near the source industry if none exists. Use `get_tile_info` to find buildable tiles.
2. Use `find_drive_through_spots` near the source to find suitable road tiles for drive-through stops.
   - If no town nearby, build a short road segment (2+ tiles straight) and place the drive-through stop on it.
3. Use `build_road_stop` with `is_truck_stop=true`, `is_drive_through=true`, and the recommended direction.
4. If ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION: try the other direction (0 or 1).
5. Do the same near the destination industry.
6. Build a `build_road_depot` near the source.
7. Connect with `build_road_line` (L-shaped: horizontal then vertical).
   - Open terrain between industries is usually easier than town centers.
   - If slopes block, offset the route by 1-2 tiles.

### Phase 4: Vehicles
1. Use `get_engines` with `vehicle_type="road"` to find trucks.
2. Match the truck's `cargo_type` to the cargo being hauled:
   - cargo_type 0 = passengers, 1 = coal, 2 = mail, 3 = oil
   - cargo_type 4 = livestock, 5 = goods, 6 = grain, 7 = wood
   - cargo_type 8 = iron ore, 9 = steel, 10 = valuables
3. Use `buy_vehicle` with the matching engine_id.
4. Use `get_stations` to get station IDs.
5. Set orders: source station (order_flags=1 for full load) -> destination (order_flags=2 for unload all).
6. Use `start_vehicle`.
7. Buy 2-3 trucks per route for good throughput.

### Phase 5: Monitor
1. Check `get_vehicles` — look for:
   - `cargo_loaded > 0` — truck is carrying cargo (good!)
   - `speed > 0` — truck is moving
   - `speed = 0, state = 0` — truck is STUCK/LOST (rebuild stop as drive-through on straight road)
   - `state = 3` — loading at station (working correctly)
   - `cargo_loaded > 0` but never delivering — stop may be inaccessible, rebuild as drive-through
2. Check `get_company_economy` for `deliveredCargo` increasing.
3. Add more trucks to profitable routes, fix or shut down unprofitable ones.

## Cargo Types Quick Reference
| ID | Cargo | Source | Destination |
|----|-------|--------|-------------|
| 1 | Coal | Coal Mine | Power Plant |
| 3 | Oil | Oil Wells | Oil Refinery |
| 4 | Livestock | Farm | Factory |
| 6 | Grain | Farm | Factory |
| 7 | Wood | Forest | Sawmill |
| 8 | Iron Ore | Iron Ore Mine | Steel Mill |

## Debugging No Deliveries
If `deliveredCargo` stays 0:
1. Check vehicle positions with `get_vehicles` — are they moving?
2. Check `cargo_loaded` — are they picking up cargo?
3. If `speed=0, state=0` near a stop: **stop is inaccessible** — rebuild as drive-through on a straight road segment
4. If trucks moving but never loading: truck stop might be too far from industry
5. If loading but never unloading: check road connection to destination stop
6. If `cargo_loaded > 0` but never delivering: destination stop may be inaccessible — use drive-through

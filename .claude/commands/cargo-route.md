# Build Cargo Route

Set up a truck route to haul cargo between an industry and its consumer. Arguments: `$ARGUMENTS`

## Strategy

Use an expert sub-agent to research optimal cargo routes.

### Phase 1: Research (use Agent with WebSearch)
- Search for "OpenTTD most profitable cargo routes early game"
- Key profitable routes in temperate:
  - Coal Mine → Power Plant (reliable, always produces)
  - Farm → Factory (grain + livestock)
  - Forest → Sawmill (wood)
  - Iron Ore Mine → Steel Mill
  - Oil Wells → Oil Refinery
- Longer distance = more payment per unit, but slower delivery = less volume

### Phase 2: Find Industries
1. Use `get_industries` to list all industries with types and locations.
2. Match source → destination pairs from the profitable routes list above.
3. Pick the pair with best balance of distance (30-80 tiles) and production.
4. Use `get_industry_info` on the source to check production levels.

### Phase 3: Build Infrastructure
1. Find buildable tiles adjacent to source industry using `get_tile_info` on surrounding tiles.
2. Use `build_road_stop` with `is_truck_stop=true` near the source.
3. Do the same near the destination industry.
4. Build a `build_road_depot` near the source.
5. Connect with `build_road_line` (L-shaped: horizontal then vertical).
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
5. Set orders: source station (order_flags=1 for full load) → destination (order_flags=2 for unload all).
6. Use `start_vehicle`.
7. Buy 2-3 trucks per route for good throughput.

### Phase 5: Monitor
1. Check `get_company_economy` for delivered cargo increasing.
2. Check `get_vehicles` for profitability after first deliveries.
3. Add more trucks to profitable routes, shut down unprofitable ones.

## Cargo Types Quick Reference
| ID | Cargo | Source | Destination |
|----|-------|--------|-------------|
| 1 | Coal | Coal Mine | Power Plant |
| 3 | Oil | Oil Wells | Oil Refinery |
| 4 | Livestock | Farm | Factory |
| 6 | Grain | Farm | Factory |
| 7 | Wood | Forest | Sawmill |
| 8 | Iron Ore | Iron Ore Mine | Steel Mill |

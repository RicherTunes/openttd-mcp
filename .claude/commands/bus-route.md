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
For each town:
1. Use `find_bus_stop_spots` to find buildable tiles adjacent to roads.
2. Pick the spot closest to town center.
3. Use `build_road_stop` with `company_id=0` to build the bus stop.

Then:
4. Use `find_depot_spots` near one of the towns.
5. Use `build_road_depot` to build a depot.
6. Connect stops with road using `build_road_line`. For L-shaped routes, call twice (horizontal then vertical).
   - If road building fails (ERR_AREA_NOT_CLEAR), try parallel routes 1-2 tiles offset.
   - If terrain blocks (ERR_LAND_SLOPED_WRONG), try wider detours.

### Phase 4: Vehicles
1. Use `get_engines` with `vehicle_type="road"` to find available buses (cargo_type=0 = passengers).
2. Use `buy_vehicle` at the depot with the bus engine_id.
3. Use `get_stations` to find station IDs for the two bus stops.
4. Use `add_vehicle_order` twice to create a shuttle route (station A → station B).
5. Use `start_vehicle` to begin service.
6. Buy 1-2 more buses for the same route (towns > 1000 pop need 2-3 buses).

### Phase 5: Verify
1. Wait ~30 seconds game time.
2. Use `get_vehicles` to check vehicles aren't lost (should be moving, state changing).
3. Use `get_company_economy` to check if cargo is being delivered.

## Common Issues
- **Vehicle lost**: Road connection is broken. Check with `get_tile_info` along the route.
- **ERR_AREA_NOT_CLEAR**: Buildings in the way. Try adjacent tiles or demolish.
- **Towns rebuild fast**: After demolishing, build road immediately. If it fails, route around.
- **order_flags**: 0=normal (passengers), 1=full load (cargo), 2=unload all (delivery end)

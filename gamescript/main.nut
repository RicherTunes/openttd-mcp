/**
 * ClaudeMCP GameScript v3 - Main logic
 *
 * Receives commands from the MCP server via the admin port event system.
 * Admin sends ADMIN_PACKET_ADMIN_GAMESCRIPT with JSON -> arrives as GSEventAdminPort.
 * GameScript sends responses via GSAdmin.Send(table) -> sent as ADMIN_PACKET_SERVER_GAMESCRIPT.
 *
 * Large responses are automatically chunked to avoid exceeding the admin port
 * packet size limit (~1400 bytes). Each chunk includes _chunk and _total fields
 * so the MCP client can reassemble them.
 *
 * Command format (from admin): { "id": "mcp_1", "action": "build_rail", "params": { ... } }
 * Response format (to admin):  { "id": "mcp_1", "success": true, "result": { ... } }
 * Chunked format:              { "id": "mcp_1", "success": true, "result": [...], "_chunk": 0, "_total": 3 }
 */

class ClaudeMCP extends GSController {
  log_level = 2;

  // Max items per chunk for array responses
  // Each item ~80-150 bytes JSON, keep chunks under ~1200 bytes to be safe
  CHUNK_SIZE = 10;

  // Yield every N iterations to stay under the opcode/tick budget.
  // MUST work with DEFAULT 10,000 opcode limit (don't assume 250k config).
  // 100 iters × 60 ops = 6,000 ops (safe under 10k default).
  // If script_max_opcode_till_suspend = 250000 in config, this is very conservative
  // but safe. Better slow than frozen.
  YIELD_INTERVAL = 100;

  function Start() {
    this.log_level = this.GetSetting("log_level");
    this.Log(1, "ClaudeMCP GameScript v3 started");

    // Main loop - process admin port events
    // NO try/catch anywhere in the GameScript. The Squirrel VM's _can_suspend
    // flag leaks when Script_Suspend (from DoCommands/Sleep) propagates through
    // catch blocks, causing Script_FatalError on subsequent DoCommands.
    // If a command errors, the script dies — but that's better than silently
    // dying and leaving ALL future commands hanging forever.
    while (true) {
      this.HandleEvents();
      this.Sleep(1);
    }
  }

  function HandleEvents() {
    local events_processed = 0;
    while (GSEventController.IsEventWaiting()) {
      local event = GSEventController.GetNextEvent();
      if (event == null) continue;

      // Only handle admin port events
      if (event.GetEventType() != GSEvent.ET_ADMIN_PORT) continue;

      local admin_event = GSEventAdminPort.Convert(event);
      local data = admin_event.GetObject();

      this.Log(3, "Received admin port event");

      if (data == null || !("id" in data) || !("action" in data)) {
        this.Log(1, "Invalid command format - missing id or action");
        continue;
      }

      // NO try/catch here — Sleep() and DoCommands must NOT be inside try blocks
      local cmd_id = data.id;
      local result = this.DispatchCommand(data);
      if (result == null) {
        this.SendResponse(cmd_id, { success = false, error = "Command returned null" });
      } else {
        this.SendResponse(cmd_id, result);
      }

      // Yield between events to avoid opcode overflow from queued commands
      if (++events_processed % 3 == 0) this.Sleep(1);
    }
  }

  /**
   * Send a response, automatically chunking large array results.
   * If the result array has more than CHUNK_SIZE items, it splits into
   * multiple packets with _chunk and _total metadata.
   */
  function SendResponse(id, result) {
    // Check if result contains a large array that needs chunking
    if ("success" in result && result.success &&
        "result" in result && result.result != null &&
        typeof result.result == "array" && result.result.len() > this.CHUNK_SIZE) {

      local arr = result.result;
      local total_chunks = ((arr.len() - 1) / this.CHUNK_SIZE) + 1;

      this.Log(2, "Chunking response for " + id + ": " + arr.len() + " items -> " + total_chunks + " chunks");

      for (local chunk_idx = 0; chunk_idx < total_chunks; chunk_idx++) {
        local start = chunk_idx * this.CHUNK_SIZE;
        local end = start + this.CHUNK_SIZE;
        if (end > arr.len()) end = arr.len();

        local chunk_arr = [];
        for (local i = start; i < end; i++) {
          chunk_arr.append(arr[i]);
        }

        local response = {
          id = id,
          success = true,
          result = chunk_arr,
          _chunk = chunk_idx,
          _total = total_chunks
        };

        GSAdmin.Send(response);
        this.Sleep(1);
      }

      this.Log(3, "Sent " + total_chunks + " chunks for " + id);
      return;
    }

    // Small response - send as single packet
    local response = { id = id };
    if ("success" in result) response.rawset("success", result.success);
    if ("error" in result && result.error != null) response.rawset("error", result.error);
    if ("result" in result && result.result != null) response.rawset("result", result.result);

    GSAdmin.Send(response);
    this.Log(3, "Sent response for " + id);
  }

  function DispatchCommand(cmd) {
    local action = cmd.action;
    local params = ("params" in cmd) ? cmd.params : {};

    // NO try/catch here! Sleep() and DoCommands inside try blocks
    // cause Script_FatalError in OpenTTD's Squirrel VM.
    // Errors propagate to Start()'s try/catch which is OUTSIDE Sleep().
    switch (action) {
        // === Building ===
        case "build_rail":          return this.CmdBuildRail(params);
        case "build_rail_station":  return this.CmdBuildRailStation(params);
        case "build_rail_depot":    return this.CmdBuildRailDepot(params);
        case "build_rail_signal":   return this.CmdBuildRailSignal(params);
        case "build_road":          return this.CmdBuildRoad(params);
        case "build_road_line":     return this.CmdBuildRoadLine(params);
        case "build_road_depot":    return this.CmdBuildRoadDepot(params);
        case "build_road_stop":     return this.CmdBuildRoadStop(params);
        case "build_airport":       return this.CmdBuildAirport(params);
        case "build_dock":          return this.CmdBuildDock(params);
        case "build_bridge":        return this.CmdBuildBridge(params);
        case "build_tunnel":        return this.CmdBuildTunnel(params);
        case "demolish_tile":       return this.CmdDemolishTile(params);

        // === Vehicles ===
        case "buy_vehicle":         return this.CmdBuyVehicle(params);
        case "sell_vehicle":        return this.CmdSellVehicle(params);
        case "start_vehicle":       return this.CmdStartVehicle(params);
        case "stop_vehicle":        return this.CmdStopVehicle(params);
        case "send_to_depot":       return this.CmdSendToDepot(params);
        case "clone_vehicle":       return this.CmdCloneVehicle(params);
        case "refit_vehicle":       return this.CmdRefitVehicle(params);

        // === Orders ===
        case "add_order":           return this.CmdAddOrder(params);
        case "get_orders":          return this.CmdGetOrders(params);
        case "clear_vehicle_orders": return this.CmdClearVehicleOrders(params);

        // === Queries ===
        case "get_towns":           return this.CmdGetTowns();
        case "get_town_info":       return this.CmdGetTownInfo(params);
        case "get_industries":      return this.CmdGetIndustries();
        case "get_industry_info":   return this.CmdGetIndustryInfo(params);
        case "get_map_size":        return this.CmdGetMapSize();
        case "get_tile_info":       return this.CmdGetTileInfo(params);
        case "get_tiles":           return this.CmdGetTiles(params);
        case "get_vehicles":        return this.CmdGetVehicles(params);
        case "get_stations":        return this.CmdGetStations(params);
        case "get_engines":         return this.CmdGetEngines(params);
        case "get_cargo_types":     return this.CmdGetCargoTypes();
        case "get_rail_types":      return this.CmdGetRailTypes();
        case "get_road_types":      return this.CmdGetRoadTypes();

        // === Smart Queries ===
        case "scan_town_area":      return this.CmdScanTownArea(params);
        case "find_bus_stop_spots":        return this.CmdFindBusStopSpots(params);
        case "find_depot_spots":           return this.CmdFindDepotSpots(params);
        case "find_drive_through_spots":   return this.CmdFindDriveThroughSpots(params);

        // === Rail Tools ===
        case "find_rail_station_spot": return this.CmdFindRailStationSpot(params);
        case "survey_line":            return this.CmdSurveyLine(params);
        case "survey_area":            return this.CmdSurveyArea(params);
        case "get_tile_range":         return this.CmdGetTileRange(params);
        case "build_rail_line":        return this.CmdBuildRailLine(params);
        case "attach_wagon":           return this.CmdAttachWagon(params);

        // === Advanced Rail (A* Pathfinding) ===
        case "build_rail_route":        return this.CmdBuildRailRoute(params);
        case "build_signals_on_route":  return this.CmdBuildSignalsOnRoute(params);
        case "connect_towns_rail":      return this.CmdConnectTownsRail(params);

        // === Advanced Road (A* Pathfinding) ===
        case "build_road_route":        return this.CmdBuildRoadRoute(params);

        // === High-Level Auto-Route ===
        case "connect_industries":      return this.CmdConnectIndustries(params);
        case "connect_towns_bus":       return this.CmdConnectTownsBus(params);
        case "replace_old_vehicles":    return this.CmdReplaceOldVehicles(params);

        // === Emergency & Status ===
        case "stop_all_vehicles":       return this.CmdStopAllVehicles(params);
        case "get_game_status":         return this.CmdGetGameStatus(params);
        case "get_date":                return this.CmdGetDate();
        case "check_road_connection":   return this.CmdCheckRoadConnection(params);

        // === Town & Station Info ===
        case "get_town_rating":         return this.CmdGetTownRating(params);
        case "plant_trees":             return this.CmdPlantTrees(params);
        case "get_station_cargo":       return this.CmdGetStationCargo(params);

        // === Economy & Overview ===
        case "get_subsidies":            return this.CmdGetSubsidies(params);
        case "get_map_overview":         return this.CmdGetMapOverview(params);
        case "get_cargo_payment_rates":  return this.CmdGetCargoPaymentRates(params);

        // === Finance ===
        case "set_loan":                return this.CmdSetLoan(params);

        // === Terraform ===
        case "terraform":               return this.CmdTerraform(params);

        // === Route Analysis ===
        case "estimate_route_profit":   return this.CmdEstimateRouteProfit(params);

        // === Company Info ===
        case "get_company_info":        return this.CmdGetCompanyInfo(params);

        // === Atomic Operations ===
        case "demolish_and_build_road": return this.CmdDemolishAndBuildRoad(params);
        case "check_industry_catchment": return this.CmdCheckIndustryCatchment(params);

        // === Diagnostics & Fleet Management ===
        case "diagnose_vehicles":        return this.CmdDiagnoseVehicles(params);
        case "find_route_opportunities": return this.CmdFindRouteOpportunities(params);
        case "get_waiting_cargo":        return this.CmdGetWaitingCargo(params);

        // === Auto-scaling, Fleet Ranking & Station Management ===
        case "auto_add_vehicles": return this.CmdAutoAddVehicles(params);
        case "rank_vehicles":     return this.CmdRankVehicles(params);
        case "remove_station":    return this.CmdRemoveStation(params);

        default:
          return { success = false, error = "Unknown action: " + action };
      }
  }

  // =====================================================================
  // BUILDING COMMANDS
  // =====================================================================

  // BuildRail with 3-tile support: (prev, curr, next) or legacy (from, to)
  // 3-tile mode: prev_x/prev_y, x/y, next_x/next_y - builds rail AT (x,y)
  // Legacy mode: from_x/from_y, to_x/to_y - builds rail on BOTH tiles
  function CmdBuildRail(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    GSRail.SetCurrentRailType(rail_type);

    // 3-tile mode: build rail at (x,y) connecting prev to next
    if ("prev_x" in p && "x" in p && "next_x" in p) {
      local prev = GSMap.GetTileIndex(p.prev_x, p.prev_y);
      local curr = GSMap.GetTileIndex(p.x, p.y);
      local next = GSMap.GetTileIndex(p.next_x, p.next_y);
      if (GSRail.BuildRail(prev, curr, next)) {
        return { success = true, result = { tile = [p.x, p.y] } };
      }
      return { success = false, error = GSError.GetLastErrorString() };
    }

    // Legacy 2-tile mode: build rail on both from and to tiles
    local from_tile = GSMap.GetTileIndex(p.from_x, p.from_y);
    local to_tile = GSMap.GetTileIndex(p.to_x, p.to_y);
    // Compute direction vector
    local dx = p.to_x - p.from_x;
    local dy = p.to_y - p.from_y;
    local before_tile = GSMap.GetTileIndex(p.from_x - dx, p.from_y - dy);
    local after_tile = GSMap.GetTileIndex(p.to_x + dx, p.to_y + dy);
    local ok1 = GSRail.BuildRail(before_tile, from_tile, to_tile);
    local ok2 = GSRail.BuildRail(from_tile, to_tile, after_tile);
    if (ok1 || ok2) {
      return { success = true, result = { from = [p.from_x, p.from_y], to = [p.to_x, p.to_y], built_from = ok1, built_to = ok2 } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  // Map MCP direction (0=NE-SW, 1=NW-SE) to GS RailTrack enum
  function MapRailTrack(dir) {
    if (dir == 1) return GSRail.RAILTRACK_NW_SE;
    return GSRail.RAILTRACK_NE_SW;  // default
  }

  function CmdBuildRailStation(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    local requested_dir = ("direction" in p) ? p.direction : 0;
    local platforms = ("num_platforms" in p) ? p.num_platforms : 2;
    local length = ("platform_length" in p) ? p.platform_length : 5;

    GSRail.SetCurrentRailType(rail_type);

    // Try requested direction first, then the other direction
    local direction = this.MapRailTrack(requested_dir);
    if (GSRail.BuildRailStation(tile, direction, platforms, length, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y], platforms = platforms, length = length, direction = requested_dir } };
    }
    // Auto-try the other direction
    local other_dir = (requested_dir == 0) ? 1 : 0;
    local other_direction = this.MapRailTrack(other_dir);
    if (GSRail.BuildRailStation(tile, other_direction, platforms, length, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y], platforms = platforms, length = length, direction = other_dir, note = "Built in alternate direction" } };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". Both directions failed. The area may not be flat or clear enough for a " + platforms + "x" + length + " station. Use find_rail_station_spot to find suitable locations, or terraform to level the area." };
  }

  function CmdBuildRailDepot(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;

    GSRail.SetCurrentRailType(rail_type);

    // Auto-try all 4 directions before failing
    local depot_ok = false;
    local start_dir = ("direction" in p) ? p.direction : 0;
    for (local i = 0; i < 4 && !depot_ok; i++) {
      local dir = (start_dir + i) % 4;
      local front_tile = this.GetAdjacentTile(tile, dir);
      depot_ok = GSRail.BuildRailDepot(tile, front_tile);
    }
    if (depot_ok) {
      return { success = true, result = { tile = [p.x, p.y] } };
    }
    return { success = false, error = "Failed to build rail depot in any direction. " + GSError.GetLastErrorString() + ". Tile may not be flat or accessible. Try an adjacent tile or use terraform to level the area first." };
  }

  function CmdBuildRailSignal(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local signal_type = ("signal_type" in p) ? p.signal_type : 0;

    if (GSRail.BuildSignal(tile, tile, signal_type)) {
      return { success = true, result = { tile = [p.x, p.y], signal_type = signal_type } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildRoad(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local from_tile = GSMap.GetTileIndex(p.from_x, p.from_y);
    local to_tile = GSMap.GetTileIndex(p.to_x, p.to_y);
    local road_type = ("road_type" in p) ? p.road_type : 0;

    GSRoad.SetCurrentRoadType(road_type);

    if (GSRoad.BuildRoad(from_tile, to_tile)) {
      // Auto-connect both endpoints to adjacent road infrastructure
      local from_connected = this.AutoConnectRoad(from_tile);
      local to_connected = this.AutoConnectRoad(to_tile);
      return { success = true, result = { from = [p.from_x, p.from_y], to = [p.to_x, p.to_y], from_connected = from_connected, to_connected = to_connected } };
    }
    local err = GSError.GetLastErrorString();
    if (err == "ERR_AREA_NOT_CLEAR") {
      return { success = false, error = err + ". A building or structure is on this tile. Try an adjacent tile or use demolish_tile first." };
    }
    if (err == "ERR_LAND_SLOPED_WRONG") {
      return { success = false, error = err + ". Terrain slope prevents building. Try terraform to level the area first." };
    }
    return { success = false, error = err };
  }

  function CmdBuildRoadLine(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local road_type = ("road_type" in p) ? p.road_type : 0;
    GSRoad.SetCurrentRoadType(road_type);

    local x1 = p.from_x, y1 = p.from_y;
    local x2 = p.to_x, y2 = p.to_y;

    if (x1 != x2 && y1 != y2) {
      return { success = false, error = "Only straight lines (same X or same Y) supported. For L-shaped routes, call twice." };
    }
    if (x1 == x2 && y1 == y2) {
      return { success = false, error = "Start and end are the same tile" };
    }

    local built = 0;
    local failed = [];
    local ops = 0;

    if (x1 == x2) {
      // Vertical line
      local step = (y2 > y1) ? 1 : -1;
      for (local y = y1; ; y += step) {
        local from_t = GSMap.GetTileIndex(x1, y);
        local to_t = GSMap.GetTileIndex(x1, y + step);
        if (GSRoad.BuildRoad(from_t, to_t)) {
          built++;
        } else {
          local err = GSError.GetLastErrorString();
          if (err != "ERR_ALREADY_BUILT") {
            failed.append({ x = x1, y = y, error = err });
          } else {
            built++; // already built counts as success
          }
        }
        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        if (y + step == y2) break;
      }
    } else {
      // Horizontal line
      local step = (x2 > x1) ? 1 : -1;
      for (local x = x1; ; x += step) {
        local from_t = GSMap.GetTileIndex(x, y1);
        local to_t = GSMap.GetTileIndex(x + step, y1);
        if (GSRoad.BuildRoad(from_t, to_t)) {
          built++;
        } else {
          local err = GSError.GetLastErrorString();
          if (err != "ERR_ALREADY_BUILT") {
            failed.append({ x = x, y = y1, error = err });
          } else {
            built++;
          }
        }
        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        if (x + step == x2) break;
      }
    }

    if (failed.len() > 20) failed = failed.slice(0, 20);

    // Auto-connect both endpoints to adjacent infrastructure
    local start_tile = GSMap.GetTileIndex(x1, y1);
    local end_tile = GSMap.GetTileIndex(x2, y2);
    local start_connected = this.AutoConnectRoad(start_tile);
    local end_connected = this.AutoConnectRoad(end_tile);

    if (built == 0 && failed.len() > 0) {
      return { success = false, error = "Road could not be built on any tile. Common causes: buildings in the way (try a parallel route 1-2 tiles offset), or terrain too steep (try terraform). First failure: " + failed[0].error, result = {
        built = built, failed = failed, total = built + failed.len()
      }};
    }

    return { success = true, result = {
      built = built, failed = failed, total = built + failed.len(),
      start_connected = start_connected, end_connected = end_connected
    }};
  }

  function CmdBuildRoadDepot(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local road_type = ("road_type" in p) ? p.road_type : 0;

    GSRoad.SetCurrentRoadType(road_type);

    // Auto-try directions: prioritize those where front tile has road
    local depot_ok = false;
    local start_dir = ("direction" in p) ? p.direction : 0;
    // First pass: directions with road
    for (local i = 0; i < 4 && !depot_ok; i++) {
      local dir = (start_dir + i) % 4;
      local front_tile = this.GetAdjacentTile(tile, dir);
      if (GSMap.IsValidTile(front_tile) && GSRoad.IsRoadTile(front_tile)) {
        depot_ok = GSRoad.BuildRoadDepot(tile, front_tile);
      }
    }
    // Second pass: any direction
    for (local i = 0; i < 4 && !depot_ok; i++) {
      local dir = (start_dir + i) % 4;
      local front_tile = this.GetAdjacentTile(tile, dir);
      depot_ok = GSRoad.BuildRoadDepot(tile, front_tile);
    }
    if (depot_ok) {
      local connected = this.AutoConnectRoad(tile);
      return { success = true, result = { tile = [p.x, p.y], connected_to = connected } };
    }
    return { success = false, error = "Failed to build road depot in any direction. " + GSError.GetLastErrorString() + ". Tile may not be flat or adjacent to road. Try an adjacent tile or use find_depot_spots to find suitable locations." };
  }

  function CmdBuildRoadStop(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local road_type = ("road_type" in p) ? p.road_type : 0;
    local is_truck = ("is_truck_stop" in p) ? p.is_truck_stop : false;
    local is_dt = ("is_drive_through" in p) ? p.is_drive_through : false;
    local direction = ("direction" in p) ? p.direction : 0;

    GSRoad.SetCurrentRoadType(road_type);

    local front_tile = this.GetAdjacentTile(tile, direction);
    local road_stop_type = is_truck ? GSRoad.ROADVEHTYPE_TRUCK : GSRoad.ROADVEHTYPE_BUS;

    local ok = false;
    if (is_dt) {
      // Auto-try both directions for drive-through stops
      ok = GSRoad.BuildDriveThroughRoadStation(tile, front_tile, road_stop_type, GSStation.STATION_NEW);
      if (!ok) {
        // Try the other direction
        local other_dir = (direction == 0) ? 1 : 0;
        local other_front = this.GetAdjacentTile(tile, other_dir);
        ok = GSRoad.BuildDriveThroughRoadStation(tile, other_front, road_stop_type, GSStation.STATION_NEW);
      }
    } else {
      ok = GSRoad.BuildRoadStation(tile, front_tile, road_stop_type, GSStation.STATION_NEW);
    }

    if (ok) {
      local connected = this.AutoConnectRoad(tile);
      return { success = true, result = { tile = [p.x, p.y], type = is_truck ? "truck" : "bus", connected_to = connected } };
    }

    local err = GSError.GetLastErrorString();
    if (is_dt) {
      return { success = false, error = err + ". Drive-through stops need a STRAIGHT road tile (not a junction). Use find_drive_through_spots to find suitable tiles." };
    }
    return { success = false, error = err + ". Regular stops need a buildable tile adjacent to road. Use find_bus_stop_spots or find_depot_spots to find suitable locations." };
  }

  function CmdBuildAirport(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local airport_type = ("airport_type" in p) ? p.airport_type : 0;

    if (GSAirport.BuildAirport(tile, airport_type, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y], type = airport_type } };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". Airport needs a large flat area. Types: 0=small (3x4), 1=city (6x6), 2=heliport (1x1), 3=metropolitan (6x6), 4=international (7x7). Use survey_area to check if the area is flat and clear." };
  }

  function CmdBuildDock(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);

    if (GSMarine.BuildDock(tile, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y] } };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". Dock must be built on a coast tile adjacent to water. Use get_tile_info to find coast tiles (is_coast=true)." };
  }

  function CmdBuildBridge(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local start_tile = GSMap.GetTileIndex(p.start_x, p.start_y);
    local end_tile = GSMap.GetTileIndex(p.end_x, p.end_y);
    local bridge_type = ("bridge_type" in p) ? p.bridge_type : 0;
    local transport = ("transport_type" in p) ? p.transport_type : "road";

    local vt = GSVehicle.VT_ROAD;
    if (transport == "rail") vt = GSVehicle.VT_RAIL;
    else if (transport == "water") vt = GSVehicle.VT_WATER;

    if (GSBridge.BuildBridge(vt, bridge_type, start_tile, end_tile)) {
      local result = { start = [p.start_x, p.start_y], end_pos = [p.end_x, p.end_y] };
      // Auto-connect road bridge endpoints to adjacent road infrastructure
      if (transport == "road") {
        GSRoad.SetCurrentRoadType(("road_type" in p) ? p.road_type : 0);
        result.start_connected <- this.AutoConnectRoad(start_tile);
        result.end_connected <- this.AutoConnectRoad(end_tile);
      }
      return { success = true, result = result };
    }
    local err = GSError.GetLastErrorString();
    return { success = false, error = err + ". Check that both endpoints are valid and the gap can be bridged. Endpoints must be on the same axis (same X or same Y). Use get_tile_info to verify terrain. Try bridge_type 0-12 for different lengths." };
  }

  function CmdBuildTunnel(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local transport = ("transport_type" in p) ? p.transport_type : "rail";

    local vt = GSVehicle.VT_RAIL;
    if (transport == "road") vt = GSVehicle.VT_ROAD;

    if (GSTunnel.BuildTunnel(vt, tile)) {
      local exit_tile = GSTunnel.GetOtherTunnelEnd(tile);
      local exit_x = GSMap.GetTileX(exit_tile);
      local exit_y = GSMap.GetTileY(exit_tile);
      local result = { entrance = [p.x, p.y], exit_pos = [exit_x, exit_y] };
      // Auto-connect road tunnel endpoints to adjacent road infrastructure
      if (transport == "road") {
        GSRoad.SetCurrentRoadType(("road_type" in p) ? p.road_type : 0);
        result.entrance_connected <- this.AutoConnectRoad(tile);
        result.exit_connected <- this.AutoConnectRoad(exit_tile);
      }
      return { success = true, result = result };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". Tunnel entrance must be on a slope facing into a hill. Use get_tile_info to check terrain slope, or survey_line to find suitable hillsides." };
  }

  function CmdDemolishTile(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);

    if (GSTile.DemolishTile(tile)) {
      return { success = true, result = { tile = [p.x, p.y] } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  // =====================================================================
  // VEHICLE COMMANDS
  // =====================================================================

  function CmdBuyVehicle(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    if (!("engine_id" in p)) return { success = false, error = "Missing required parameter: engine_id. Use get_engines to find available engine IDs." };
    if (!("depot_x" in p) || !("depot_y" in p)) return { success = false, error = "Missing required parameter: depot_x/depot_y" };
    local company_mode = GSCompanyMode(p.company_id);

    if (!GSEngine.IsValidEngine(p.engine_id)) {
      return { success = false, error = "Invalid engine_id " + p.engine_id + ". Use get_engines to find available engine IDs." };
    }
    if (!GSEngine.IsBuildable(p.engine_id)) {
      return { success = false, error = "Engine " + p.engine_id + " (" + GSEngine.GetName(p.engine_id) + ") is not buildable (may not be available yet or is obsolete). Use get_engines to find currently buildable engines." };
    }

    local depot_tile = GSMap.GetTileIndex(p.depot_x, p.depot_y);

    // For wagons, check if the error string is ERR_NONE after build
    // because wagons auto-attach to trains and the returned ID may
    // not pass IsValidVehicle
    local vehicle_id = GSVehicle.BuildVehicle(depot_tile, p.engine_id);
    if (GSVehicle.IsValidVehicle(vehicle_id)) {
      return { success = true, result = {
        vehicle_id = vehicle_id,
        name = GSVehicle.GetName(vehicle_id)
      }};
    }
    // Wagon may have been built and auto-attached to a train
    local err = GSError.GetLastErrorString();
    if (err == "ERR_NONE" && GSEngine.IsWagon(p.engine_id)) {
      return { success = true, result = {
        vehicle_id = vehicle_id,
        note = "Wagon built and auto-attached to train in depot"
      }};
    }
    return { success = false, error = err };
  }

  function CmdSellVehicle(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    if (!("vehicle_id" in p)) return { success = false, error = "Missing required parameter: vehicle_id" };
    local company_mode = GSCompanyMode(p.company_id);
    if (!GSVehicle.IsValidVehicle(p.vehicle_id)) {
      return { success = false, error = "Invalid vehicle_id " + p.vehicle_id + ". Use get_vehicles to find valid vehicle IDs." };
    }
    if (!GSVehicle.IsStoppedInDepot(p.vehicle_id)) {
      return { success = false, error = "Vehicle must be stopped in depot to sell. Use send_vehicle_to_depot first, wait for it to arrive, then retry." };
    }
    if (GSVehicle.SellVehicle(p.vehicle_id)) {
      return { success = true, result = {} };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdStartVehicle(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    if (GSVehicle.StartStopVehicle(p.vehicle_id)) {
      return { success = true, result = { running = !GSVehicle.IsStoppedInDepot(p.vehicle_id) } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdStopVehicle(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    if (!GSVehicle.IsStoppedInDepot(p.vehicle_id)) {
      if (GSVehicle.StartStopVehicle(p.vehicle_id)) {
        return { success = true, result = {} };
      }
      return { success = false, error = GSError.GetLastErrorString() };
    }
    return { success = true, result = { already_stopped = true } };
  }

  function CmdSendToDepot(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    if (!("vehicle_id" in p)) return { success = false, error = "Missing required parameter: vehicle_id" };
    local company_mode = GSCompanyMode(p.company_id);
    if (!GSVehicle.IsValidVehicle(p.vehicle_id)) {
      return { success = false, error = "Invalid vehicle_id " + p.vehicle_id + ". Use get_vehicles to find valid vehicle IDs." };
    }
    if (GSVehicle.IsStoppedInDepot(p.vehicle_id)) {
      return { success = true, result = { already_in_depot = true } };
    }
    if (GSVehicle.SendVehicleToDepot(p.vehicle_id)) {
      return { success = true, result = {} };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". Vehicle may not be able to find a path to a depot. Check that a depot exists on the vehicle's route." };
  }

  function CmdCloneVehicle(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    if (!("vehicle_id" in p)) return { success = false, error = "Missing required parameter: vehicle_id" };
    local company_mode = GSCompanyMode(p.company_id);
    if (!GSVehicle.IsValidVehicle(p.vehicle_id)) {
      return { success = false, error = "Invalid vehicle_id " + p.vehicle_id + ". Use get_vehicles to find valid vehicle IDs." };
    }
    local depot_tile = GSVehicle.GetLocation(p.vehicle_id);
    local share = ("share_orders" in p) ? p.share_orders : true;

    local clone_id = GSVehicle.CloneVehicle(depot_tile, p.vehicle_id, share);
    if (GSVehicle.IsValidVehicle(clone_id)) {
      return { success = true, result = { vehicle_id = clone_id, name = GSVehicle.GetName(clone_id) } };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". Vehicle must be in or near a depot to clone. Try send_vehicle_to_depot first." };
  }

  function CmdRefitVehicle(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    if (!("vehicle_id" in p)) return { success = false, error = "Missing required parameter: vehicle_id" };
    if (!("cargo_id" in p)) return { success = false, error = "Missing required parameter: cargo_id. Use get_cargo_types to find valid cargo IDs." };
    local company_mode = GSCompanyMode(p.company_id);
    if (!GSVehicle.IsValidVehicle(p.vehicle_id)) {
      return { success = false, error = "Invalid vehicle_id " + p.vehicle_id + ". Use get_vehicles to find valid vehicle IDs." };
    }
    if (!GSVehicle.IsStoppedInDepot(p.vehicle_id)) {
      return { success = false, error = "Vehicle must be stopped in depot to refit. Use send_vehicle_to_depot first, wait for it to arrive, then retry." };
    }
    if (GSVehicle.RefitVehicle(p.vehicle_id, p.cargo_id)) {
      return { success = true, result = {} };
    }
    return { success = false, error = GSError.GetLastErrorString() + ". This vehicle may not support the requested cargo type. Use get_cargo_types to check available cargo types." };
  }

  // =====================================================================
  // ORDER COMMANDS
  // =====================================================================

  function CmdAddOrder(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    if (!("vehicle_id" in p)) return { success = false, error = "Missing required parameter: vehicle_id" };
    if (!("station_id" in p)) return { success = false, error = "Missing required parameter: station_id. Use get_stations to find valid station IDs." };
    local company_mode = GSCompanyMode(p.company_id);
    local flags = ("order_flags" in p) ? p.order_flags : 0;

    if (!GSVehicle.IsValidVehicle(p.vehicle_id)) {
      return { success = false, error = "Invalid vehicle_id " + p.vehicle_id + ". Use get_vehicles to find valid vehicle IDs." };
    }

    if (!GSBaseStation.IsValidBaseStation(p.station_id)) {
      return { success = false, error = "Station ID " + p.station_id + " not found. Use get_stations to find valid station IDs." };
    }

    // GSOrder.AppendOrder expects a tile index, not a station ID
    // Convert station_id to tile location
    local dest = GSStation.GetLocation(p.station_id);
    if (!GSMap.IsValidTile(dest)) {
      return { success = false, error = "Station ID " + p.station_id + " has no valid location. It may have been removed. Use get_stations to find valid station IDs." };
    }

    if (GSOrder.AppendOrder(p.vehicle_id, dest, flags)) {
      return { success = true, result = { order_count = GSOrder.GetOrderCount(p.vehicle_id) } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdGetOrders(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local vehicle_id = p.vehicle_id;
    local count = GSOrder.GetOrderCount(vehicle_id);
    local orders = [];

    for (local i = 0; i < count; i++) {
      local dest = GSOrder.GetOrderDestination(vehicle_id, i);
      orders.append({
        index = i,
        destination = dest,
        flags = GSOrder.GetOrderFlags(vehicle_id, i)
      });
    }

    if (orders.len() > 30) orders = orders.slice(0, 30);

    return { success = true, result = { vehicle_id = vehicle_id, order_count = count, orders = orders } };
  }

  // =====================================================================
  // QUERY COMMANDS
  // =====================================================================

  function CmdGetTowns() {
    local towns = [];
    local town_list = GSTownList();
    local ops = 0;

    local ids = [];
    foreach (town_id, _ in town_list) ids.append(town_id);
    for (local i = 0; i < ids.len(); i++) {
      local town_id = ids[i];
      local loc = GSTown.GetLocation(town_id);
      towns.append({
        id = town_id,
        name = GSTown.GetName(town_id),
        population = GSTown.GetPopulation(town_id),
        x = GSMap.GetTileX(loc),
        y = GSMap.GetTileY(loc)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = towns };
  }

  function CmdGetTownInfo(p) {
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) {
      return { success = false, error = "Invalid town ID" };
    }

    local loc = GSTown.GetLocation(town_id);
    return { success = true, result = {
      id = town_id,
      name = GSTown.GetName(town_id),
      population = GSTown.GetPopulation(town_id),
      houses = GSTown.GetHouseCount(town_id),
      x = GSMap.GetTileX(loc),
      y = GSMap.GetTileY(loc),
      is_city = GSTown.IsCity(town_id),
      growth_rate = GSTown.GetGrowthRate(town_id)
    }};
  }

  function CmdGetIndustries() {
    local industries = [];
    local ind_list = GSIndustryList();
    local ops = 0;

    local ids = [];
    foreach (ind_id, _ in ind_list) ids.append(ind_id);
    for (local i = 0; i < ids.len(); i++) {
      local ind_id = ids[i];
      local loc = GSIndustry.GetLocation(ind_id);
      local ind_type = GSIndustry.GetIndustryType(ind_id);
      industries.append({
        id = ind_id,
        name = GSIndustry.GetName(ind_id),
        type_name = GSIndustryType.GetName(ind_type),
        type_id = ind_type,
        x = GSMap.GetTileX(loc),
        y = GSMap.GetTileY(loc)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = industries };
  }

  function CmdGetIndustryInfo(p) {
    local ind_id = p.industry_id;
    if (!GSIndustry.IsValidIndustry(ind_id)) {
      return { success = false, error = "Invalid industry ID" };
    }

    local loc = GSIndustry.GetLocation(ind_id);
    local ind_type = GSIndustry.GetIndustryType(ind_id);

    local produced = [];
    local cargo_list = GSCargoList();
    local ops = 0;
    local cargo_ids = [];
    foreach (cargo_id, _ in cargo_list) cargo_ids.append(cargo_id);
    for (local i = 0; i < cargo_ids.len(); i++) {
      local cargo_id = cargo_ids[i];
      local last_month = GSIndustry.GetLastMonthProduction(ind_id, cargo_id);
      if (last_month > 0) {
        produced.append({
          cargo_id = cargo_id,
          cargo_name = GSCargo.GetCargoLabel(cargo_id),
          last_month = last_month,
          transported = GSIndustry.GetLastMonthTransported(ind_id, cargo_id)
        });
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = {
      id = ind_id,
      name = GSIndustry.GetName(ind_id),
      type_name = GSIndustryType.GetName(ind_type),
      type_id = ind_type,
      x = GSMap.GetTileX(loc),
      y = GSMap.GetTileY(loc),
      is_processing = GSIndustryType.IsProcessingIndustry(ind_type),
      is_raw = GSIndustryType.IsRawIndustry(ind_type),
      production = produced
    }};
  }

  function CmdGetMapSize() {
    return { success = true, result = {
      size_x = GSMap.GetMapSizeX(),
      size_y = GSMap.GetMapSizeY(),
      max_x = GSMap.GetMapSizeX() - 2,
      max_y = GSMap.GetMapSizeY() - 2
    }};
  }

  function CmdGetTileInfo(p) {
    local tile = GSMap.GetTileIndex(p.x, p.y);
    if (!GSMap.IsValidTile(tile)) {
      return { success = false, error = "Invalid tile coordinates" };
    }

    return { success = true, result = {
      x = p.x,
      y = p.y,
      height = GSTile.GetMaxHeight(tile),
      min_height = GSTile.GetMinHeight(tile),
      slope = GSTile.GetSlope(tile),
      is_water = GSTile.IsWaterTile(tile),
      is_coast = GSTile.IsCoastTile(tile),
      has_tree = GSTile.HasTreeOnTile(tile),
      is_buildable = GSTile.IsBuildable(tile),
      is_road = GSRoad.IsRoadTile(tile),
      is_rail = GSRail.IsRailTile(tile),
      owner = GSTile.GetOwner(tile)
    }};
  }

  // Batch tile query — check multiple tiles in one call
  function CmdGetTiles(p) {
    local tiles = ("tiles" in p) ? p.tiles : [];
    local results = [];
    local ops = 0;

    for (local i = 0; i < tiles.len() && i < 50; i++) {
      local tx = tiles[i].x;
      local ty = tiles[i].y;
      local tile = GSMap.GetTileIndex(tx, ty);
      if (!GSMap.IsValidTile(tile)) {
        results.append({ x = tx, y = ty, valid = false });
      } else {
        results.append({
          x = tx, y = ty, valid = true,
          height = GSTile.GetMaxHeight(tile),
          slope = GSTile.GetSlope(tile),
          is_buildable = GSTile.IsBuildable(tile),
          is_road = GSRoad.IsRoadTile(tile),
          is_water = GSTile.IsWaterTile(tile),
          owner = GSTile.GetOwner(tile)
        });
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = results };
  }

  function CmdGetVehicles(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local vehicles = [];
    local veh_list = GSVehicleList();
    local ops = 0;

    local ids = [];
    foreach (veh_id, _ in veh_list) ids.append(veh_id);
    for (local i = 0; i < ids.len(); i++) {
      local veh_id = ids[i];
      if ("vehicle_type" in p && p.vehicle_type != null) {
        local vt = GSVehicle.GetVehicleType(veh_id);
        local type_name = "";
        switch (vt) {
          case GSVehicle.VT_RAIL:  type_name = "train"; break;
          case GSVehicle.VT_ROAD:  type_name = "road"; break;
          case GSVehicle.VT_WATER: type_name = "ship"; break;
          case GSVehicle.VT_AIR:   type_name = "aircraft"; break;
        }
        if (type_name != p.vehicle_type) continue;
      }

      local loc = GSVehicle.GetLocation(veh_id);
      local cargo_type = GSEngine.GetCargoType(GSVehicle.GetEngineType(veh_id));
      vehicles.append({
        id = veh_id,
        name = GSVehicle.GetName(veh_id),
        type = GSVehicle.GetVehicleType(veh_id),
        x = GSMap.GetTileX(loc),
        y = GSMap.GetTileY(loc),
        engine_id = GSVehicle.GetEngineType(veh_id),
        age = GSVehicle.GetAge(veh_id),
        speed = GSVehicle.GetCurrentSpeed(veh_id),
        cargo_loaded = GSVehicle.GetCargoLoad(veh_id, cargo_type),
        cargo_capacity = GSVehicle.GetCapacity(veh_id, cargo_type),
        profit_this_year = GSVehicle.GetProfitThisYear(veh_id),
        profit_last_year = GSVehicle.GetProfitLastYear(veh_id),
        state = GSVehicle.GetState(veh_id),
        in_depot = GSVehicle.IsStoppedInDepot(veh_id),
        order_count = GSOrder.GetOrderCount(veh_id)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = vehicles };
  }

  function CmdGetStations(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local stations = [];
    local stn_list = GSStationList(GSStation.STATION_ANY);
    local ops = 0;

    local ids = [];
    foreach (stn_id, _ in stn_list) ids.append(stn_id);
    for (local i = 0; i < ids.len(); i++) {
      local stn_id = ids[i];
      local loc = GSBaseStation.GetLocation(stn_id);
      stations.append({
        id = stn_id,
        name = GSBaseStation.GetName(stn_id),
        x = GSMap.GetTileX(loc),
        y = GSMap.GetTileY(loc),
        has_rail = GSStation.HasStationType(stn_id, GSStation.STATION_TRAIN),
        has_truck = GSStation.HasStationType(stn_id, GSStation.STATION_TRUCK_STOP),
        has_bus = GSStation.HasStationType(stn_id, GSStation.STATION_BUS_STOP),
        has_airport = GSStation.HasStationType(stn_id, GSStation.STATION_AIRPORT),
        has_dock = GSStation.HasStationType(stn_id, GSStation.STATION_DOCK)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = stations };
  }

  function CmdGetEngines(p) {
    local engines = [];
    local type_str = ("vehicle_type" in p) ? p.vehicle_type : "train";

    local vt = GSVehicle.VT_RAIL;
    switch (type_str) {
      case "train":    vt = GSVehicle.VT_RAIL; break;
      case "road":     vt = GSVehicle.VT_ROAD; break;
      case "ship":     vt = GSVehicle.VT_WATER; break;
      case "aircraft": vt = GSVehicle.VT_AIR; break;
    }

    local eng_list = GSEngineList(vt);
    local ops = 0;
    local ids = [];
    foreach (eng_id, _ in eng_list) ids.append(eng_id);
    for (local i = 0; i < ids.len(); i++) {
      local eng_id = ids[i];
      if (!GSEngine.IsValidEngine(eng_id)) continue;
      if (!GSEngine.IsBuildable(eng_id)) continue;

      local info = {
        id = eng_id,
        name = GSEngine.GetName(eng_id),
        cargo_type = GSEngine.GetCargoType(eng_id),
        capacity = GSEngine.GetCapacity(eng_id),
        max_speed = GSEngine.GetMaxSpeed(eng_id),
        price = GSEngine.GetPrice(eng_id),
        running_cost = GSEngine.GetRunningCost(eng_id),
        reliability = GSEngine.GetReliability(eng_id)
      };

      // Power, weight, is_wagon are only valid for rail vehicles
      if (vt == GSVehicle.VT_RAIL) {
        info.rawset("power", GSEngine.GetPower(eng_id));
        info.rawset("weight", GSEngine.GetWeight(eng_id));
        info.rawset("is_wagon", GSEngine.IsWagon(eng_id));
      }

      engines.append(info);
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = engines };
  }

  function CmdGetCargoTypes() {
    local cargos = [];
    local cargo_list = GSCargoList();
    local ops = 0;

    local ids = [];
    foreach (cargo_id, _ in cargo_list) ids.append(cargo_id);
    for (local i = 0; i < ids.len(); i++) {
      local cargo_id = ids[i];
      cargos.append({
        id = cargo_id,
        label = GSCargo.GetCargoLabel(cargo_id),
        name = GSCargo.GetName(cargo_id),
        is_freight = GSCargo.IsFreight(cargo_id)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = cargos };
  }

  function CmdGetRailTypes() {
    local types = [];
    local rail_list = GSRailTypeList();
    local ops = 0;

    local ids = [];
    foreach (rail_type, _ in rail_list) ids.append(rail_type);
    for (local i = 0; i < ids.len(); i++) {
      local rail_type = ids[i];
      types.append({
        id = rail_type,
        name = GSRail.GetName(rail_type)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = types };
  }

  function CmdGetRoadTypes() {
    local types = [];
    local road_list = GSRoadTypeList(GSRoad.ROADTRAMTYPES_ROAD);
    local ops = 0;

    local road_ids = [];
    foreach (road_type, _ in road_list) road_ids.append(road_type);
    for (local i = 0; i < road_ids.len(); i++) {
      local road_type = road_ids[i];
      types.append({
        id = road_type,
        name = GSRoad.GetName(road_type),
        is_road = true
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    local tram_list = GSRoadTypeList(GSRoad.ROADTRAMTYPES_TRAM);
    local tram_ids = [];
    foreach (tram_type, _ in tram_list) tram_ids.append(tram_type);
    for (local i = 0; i < tram_ids.len(); i++) {
      local tram_type = tram_ids[i];
      types.append({
        id = tram_type,
        name = GSRoad.GetName(tram_type),
        is_road = false
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = types };
  }

  // =====================================================================
  // SMART QUERY COMMANDS
  // =====================================================================

  /**
   * Check 4 cardinal neighbors for road tiles.
   * Returns array of { nx, ny, dir } where dir matches depot direction convention:
   *   0=NE (+x), 1=SE (+y), 2=SW (-x), 3=NW (-y)
   */
  function GetAdjacentRoads(x, y) {
    local offsets = [
      { dx = 1,  dy = 0,  dir = 0 },  // NE
      { dx = 0,  dy = 1,  dir = 1 },  // SE
      { dx = -1, dy = 0,  dir = 2 },  // SW
      { dx = 0,  dy = -1, dir = 3 },  // NW
    ];
    local results = [];
    foreach (o in offsets) {
      local nx = x + o.dx;
      local ny = y + o.dy;
      local t = GSMap.GetTileIndex(nx, ny);
      if (GSMap.IsValidTile(t) && GSRoad.IsRoadTile(t)) {
        results.append({ nx = nx, ny = ny, dir = o.dir });
      }
    }
    return results;
  }

  /**
   * scan_town_area: Scan tiles around a town center and classify each one.
   * Returns { buildable: [...], roads: [...], buildings: [...], water: [...] }
   */
  function CmdScanTownArea(p) {
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) {
      return { success = false, error = "Invalid town ID" };
    }

    local radius = ("radius" in p) ? p.radius : 15;
    if (radius > 20) radius = 20;
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local buildable = [];
    local roads = [];
    local buildings = [];
    local water = [];
    local ops = 0;

    for (local dy = -radius; dy <= radius; dy++) {
      for (local dx = -radius; dx <= radius; dx++) {
        local x = cx + dx;
        local y = cy + dy;
        local tile = GSMap.GetTileIndex(x, y);
        if (!GSMap.IsValidTile(tile)) continue;

        if (GSTile.IsWaterTile(tile) || GSTile.IsCoastTile(tile)) {
          water.append({ x = x, y = y });
        } else if (GSRoad.IsRoadTile(tile)) {
          roads.append({ x = x, y = y });
        } else if (GSTile.IsBuildable(tile)) {
          buildable.append({
            x = x, y = y,
            height = GSTile.GetMaxHeight(tile),
            slope = GSTile.GetSlope(tile)
          });
        } else {
          buildings.append({ x = x, y = y });
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    // Cap coordinate arrays to avoid exceeding admin port packet size (~1400 bytes)
    local real_buildable = buildable.len();
    local real_roads = roads.len();
    local real_water = water.len();
    local max_coords = 10;
    if (buildable.len() > max_coords) buildable = buildable.slice(0, max_coords);
    if (roads.len() > max_coords) roads = roads.slice(0, max_coords);
    if (water.len() > max_coords) water = water.slice(0, max_coords);

    return { success = true, result = {
      town_name = GSTown.GetName(town_id),
      center_x = cx, center_y = cy,
      radius = radius,
      buildable = buildable,
      roads = roads,
      buildings_count = buildings.len(),
      water = water,
      counts = {
        buildable = real_buildable,
        roads = real_roads,
        buildings = buildings.len(),
        water = real_water
      }
    }};
  }

  /**
   * find_bus_stop_spots: Find tiles suitable for bus stops
   * (buildable AND adjacent to an existing road).
   * Returns sorted by distance from town center.
   */
  function CmdFindBusStopSpots(p) {
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) {
      return { success = false, error = "Invalid town ID" };
    }

    local radius = ("radius" in p) ? p.radius : 15;
    if (radius > 20) radius = 20;
    local max_results = ("max_results" in p) ? p.max_results : 10;
    if (max_results <= 0) return { success = true, result = [] };
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local spots = [];
    local ops = 0;

    // Scan tiles — yield periodically to avoid opcode budget overflow
    for (local dy = -radius; dy <= radius; dy++) {
      for (local dx = -radius; dx <= radius; dx++) {
        local x = cx + dx;
        local y = cy + dy;
        local tile = GSMap.GetTileIndex(x, y);
        if (!GSMap.IsValidTile(tile)) continue;
        if (!GSTile.IsBuildable(tile)) continue;

        local adj = this.GetAdjacentRoads(x, y);
        if (adj.len() == 0) continue;

        local dist = abs(dx) + abs(dy);
        // Auto-detect correct stop direction from adjacent road position
        // Direction 0 = NE-SW (road is on Y axis relative to stop)
        // Direction 1 = NW-SE (road is on X axis relative to stop)
        local stop_dir = (adj[0].nx != x) ? 1 : 0;

        // Check which adjacent road tiles support drive-through stops.
        // Drive-through needs road on BOTH opposite sides of the road tile.
        // For each adjacent road tile, try both directions.
        local dt_dir = -1;
        foreach (a in adj) {
          local rt = GSMap.GetTileIndex(a.nx, a.ny);
          // Direction 0 (NE-SW): needs road at (nx, ny-1) and (nx, ny+1)
          local tn = GSMap.GetTileIndex(a.nx, a.ny - 1);
          local ts = GSMap.GetTileIndex(a.nx, a.ny + 1);
          if (GSMap.IsValidTile(tn) && GSMap.IsValidTile(ts) &&
              (GSRoad.IsRoadTile(tn) || GSRoad.IsDriveThroughRoadStationTile(tn)) &&
              (GSRoad.IsRoadTile(ts) || GSRoad.IsDriveThroughRoadStationTile(ts))) {
            dt_dir = 0;
            break;
          }
          // Direction 1 (NW-SE): needs road at (nx-1, ny) and (nx+1, ny)
          local tw = GSMap.GetTileIndex(a.nx - 1, a.ny);
          local te = GSMap.GetTileIndex(a.nx + 1, a.ny);
          if (GSMap.IsValidTile(tw) && GSMap.IsValidTile(te) &&
              (GSRoad.IsRoadTile(tw) || GSRoad.IsDriveThroughRoadStationTile(tw)) &&
              (GSRoad.IsRoadTile(te) || GSRoad.IsDriveThroughRoadStationTile(te))) {
            dt_dir = 1;
            break;
          }
        }

        local spot = {
          x = x, y = y,
          distance = dist,
          adjacent_road_x = adj[0].nx,
          adjacent_road_y = adj[0].ny,
          adjacent_road_count = adj.len(),
          stop_direction = stop_dir,
          recommended_drive_through_dir = dt_dir
        };

        // Maintain a sorted top-N list instead of collecting all + sorting
        if (spots.len() < max_results) {
          spots.append(spot);
        } else if (dist < spots[spots.len() - 1].distance) {
          spots[spots.len() - 1] = spot;
        } else {
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
          continue;
        }
        // Bubble the new entry into sorted position (max N swaps)
        for (local i = spots.len() - 1; i > 0 && spots[i].distance < spots[i-1].distance; i--) {
          local tmp = spots[i]; spots[i] = spots[i-1]; spots[i-1] = tmp;
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    return { success = true, result = spots };
  }

  /**
   * find_depot_spots: Find tiles suitable for road depots
   * (buildable AND adjacent to road, with depot direction).
   */
  function CmdFindDepotSpots(p) {
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) {
      return { success = false, error = "Invalid town ID" };
    }

    local radius = ("radius" in p) ? p.radius : 15;
    if (radius > 20) radius = 20;
    local max_results = ("max_results" in p) ? p.max_results : 5;
    if (max_results <= 0) return { success = true, result = [] };
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local spots = [];
    local ops = 0;

    for (local dy = -radius; dy <= radius; dy++) {
      for (local dx = -radius; dx <= radius; dx++) {
        local x = cx + dx;
        local y = cy + dy;
        local tile = GSMap.GetTileIndex(x, y);
        if (!GSMap.IsValidTile(tile)) continue;
        if (!GSTile.IsBuildable(tile)) continue;

        local adj = this.GetAdjacentRoads(x, y);
        if (adj.len() == 0) continue;

        local dist = abs(dx) + abs(dy);
        local spot = {
          x = x, y = y,
          distance = dist,
          adjacent_road_x = adj[0].nx,
          adjacent_road_y = adj[0].ny,
          depot_direction = adj[0].dir
        };

        if (spots.len() < max_results) {
          spots.append(spot);
        } else if (dist < spots[spots.len() - 1].distance) {
          spots[spots.len() - 1] = spot;
        } else {
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
          continue;
        }
        for (local i = spots.len() - 1; i > 0 && spots[i].distance < spots[i-1].distance; i--) {
          local tmp = spots[i]; spots[i] = spots[i-1]; spots[i-1] = tmp;
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    return { success = true, result = spots };
  }

  /**
   * find_drive_through_spots: Find road tiles suitable for drive-through stops.
   * Drive-through stops are placed ON existing road tiles that have road on both sides.
   */
  function CmdFindDriveThroughSpots(p) {
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) {
      return { success = false, error = "Invalid town ID" };
    }

    local radius = ("radius" in p) ? p.radius : 15;
    if (radius > 20) radius = 20;
    local max_results = ("max_results" in p) ? p.max_results : 10;
    if (max_results <= 0) return { success = true, result = [] };
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local spots = [];
    local ops = 0;

    for (local dy = -radius; dy <= radius; dy++) {
      for (local dx = -radius; dx <= radius; dx++) {
        local x = cx + dx;
        local y = cy + dy;
        local tile = GSMap.GetTileIndex(x, y);
        if (!GSMap.IsValidTile(tile)) continue;
        if (!GSRoad.IsRoadTile(tile)) continue;

        // Check for drive-through: needs road on opposite sides
        // Direction 0 (NE-SW): check tiles at (x, y-1) and (x, y+1)
        // Direction 1 (NW-SE): check tiles at (x-1, y) and (x+1, y)
        local dir = -1;
        local t_n = GSMap.GetTileIndex(x, y-1);
        local t_s = GSMap.GetTileIndex(x, y+1);
        local t_w = GSMap.GetTileIndex(x-1, y);
        local t_e = GSMap.GetTileIndex(x+1, y);

        local has_ns = GSMap.IsValidTile(t_n) && GSRoad.IsRoadTile(t_n) &&
                       GSMap.IsValidTile(t_s) && GSRoad.IsRoadTile(t_s);
        local has_ew = GSMap.IsValidTile(t_w) && GSRoad.IsRoadTile(t_w) &&
                       GSMap.IsValidTile(t_e) && GSRoad.IsRoadTile(t_e);

        // Junctions (road on all 4 sides) can't have drive-through stops
        if (has_ns && has_ew) continue;
        if (has_ns) dir = 0;
        else if (has_ew) dir = 1;

        if (dir == -1) continue;

        local dist = abs(dx) + abs(dy);
        local spot = {
          x = x, y = y,
          distance = dist,
          direction = dir,
          is_drive_through = true
        };

        if (spots.len() < max_results) {
          spots.append(spot);
        } else if (dist < spots[spots.len() - 1].distance) {
          spots[spots.len() - 1] = spot;
        } else {
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
          continue;
        }
        for (local i = spots.len() - 1; i > 0 && spots[i].distance < spots[i-1].distance; i--) {
          local tmp = spots[i]; spots[i] = spots[i-1]; spots[i-1] = tmp;
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    return { success = true, result = spots };
  }

  // =====================================================================
  // WAGON MANAGEMENT
  // =====================================================================

  function CmdAttachWagon(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local wagon_id = p.wagon_id;
    local train_id = p.train_id;

    if (GSVehicle.MoveWagonChain(wagon_id, 0, train_id, 0)) {
      return { success = true, result = { train_id = train_id } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  // =====================================================================
  // RAIL TOOLS
  // =====================================================================

  /**
   * find_rail_station_spot: Find a flat buildable rectangle near a town
   * suitable for a train station.
   */
  function CmdFindRailStationSpot(p) {
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) {
      return { success = false, error = "Invalid town ID" };
    }

    local plat_len = ("platform_length" in p) ? p.platform_length : 5;
    local num_plat = ("num_platforms" in p) ? p.num_platforms : 2;
    local max_dist = ("max_distance" in p) ? p.max_distance : 20;
    if (max_dist > 20) max_dist = 20;
    local max_results = ("max_results" in p) ? p.max_results : 5;

    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local candidates = [];
    local ops = 0;

    for (local dir = 0; dir <= 1; dir++) {
      local w = (dir == 0) ? plat_len : num_plat;
      local h = (dir == 0) ? num_plat : plat_len;

      for (local dy = -max_dist; dy <= max_dist; dy++) {
        for (local dx = -max_dist; dx <= max_dist; dx++) {
          local sx = cx + dx;
          local sy = cy + dy;

          local base_tile = GSMap.GetTileIndex(sx, sy);
          if (!GSMap.IsValidTile(base_tile)) continue;
          local base_h = GSTile.GetMaxHeight(base_tile);

          local ok = true;
          for (local py = 0; py < h && ok; py++) {
            for (local px = 0; px < w && ok; px++) {
              local t = GSMap.GetTileIndex(sx + px, sy + py);
              if (!GSMap.IsValidTile(t) || !GSTile.IsBuildable(t) ||
                  GSTile.GetMaxHeight(t) != base_h || GSTile.GetSlope(t) != 0) {
                ok = false;
              }
              if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
            }
          }

          if (ok) {
            local dist = abs(dx + w / 2) + abs(dy + h / 2);
            local spot = { x = sx, y = sy, direction = dir, distance = dist, elevation = base_h };
            if (candidates.len() < max_results) {
              candidates.append(spot);
            } else if (dist < candidates[candidates.len() - 1].distance) {
              candidates[candidates.len() - 1] = spot;
            } else {
              if (ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
              continue;
            }
            for (local i = candidates.len() - 1; i > 0 && candidates[i].distance < candidates[i-1].distance; i--) {
              local tmp = candidates[i]; candidates[i] = candidates[i-1]; candidates[i-1] = tmp;
            }
          }

          if (ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        }
      }
    }

    return { success = true, result = candidates };
  }

  /**
   * survey_line: Survey terrain along a straight line between two points.
   * Returns height, slope, buildability for each tile.
   */
  function CmdSurveyLine(p) {
    local x1 = p.from_x;
    local y1 = p.from_y;
    local x2 = p.to_x;
    local y2 = p.to_y;

    if (x1 != x2 && y1 != y2) {
      return { success = false, error = "Only straight lines (same X or same Y) supported" };
    }

    local tiles = [];
    local ops = 0;

    if (x1 == x2 && y1 == y2) {
      local tile = GSMap.GetTileIndex(x1, y1);
      if (GSMap.IsValidTile(tile)) {
        tiles.append({
          x = x1, y = y1,
          height = GSTile.GetMaxHeight(tile),
          slope = GSTile.GetSlope(tile),
          buildable = GSTile.IsBuildable(tile),
          water = GSTile.IsWaterTile(tile)
        });
      }
    } else if (x1 == x2) {
      local step = (y2 > y1) ? 1 : -1;
      for (local y = y1; ; y += step) {
        local tile = GSMap.GetTileIndex(x1, y);
        if (GSMap.IsValidTile(tile)) {
          tiles.append({
            x = x1, y = y,
            height = GSTile.GetMaxHeight(tile),
            slope = GSTile.GetSlope(tile),
            buildable = GSTile.IsBuildable(tile),
            water = GSTile.IsWaterTile(tile)
          });
        }
        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        if (y == y2) break;
      }
    } else {
      local step = (x2 > x1) ? 1 : -1;
      for (local x = x1; ; x += step) {
        local tile = GSMap.GetTileIndex(x, y1);
        if (GSMap.IsValidTile(tile)) {
          tiles.append({
            x = x, y = y1,
            height = GSTile.GetMaxHeight(tile),
            slope = GSTile.GetSlope(tile),
            buildable = GSTile.IsBuildable(tile),
            water = GSTile.IsWaterTile(tile)
          });
        }
        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        if (x == x2) break;
      }
    }

    return { success = true, result = tiles };
  }

  /**
   * survey_area: Survey a rectangular area of the map.
   * Returns ASCII grid maps showing terrain types and heights.
   */
  function CmdSurveyArea(p) {
    local x1 = p.from_x;
    local y1 = p.from_y;
    local x2 = p.to_x;
    local y2 = p.to_y;

    // Ensure x1<=x2, y1<=y2
    if (x1 > x2) { local t = x1; x1 = x2; x2 = t; }
    if (y1 > y2) { local t = y1; y1 = y2; y2 = t; }

    local w = x2 - x1 + 1;
    local h = y2 - y1 + 1;
    if (w > 20 || h > 20) {
      return { success = false, error = "Max 20x20 area" };
    }

    local terrain_rows = [];
    local height_rows = [];
    local counts = {
      buildable_flat = 0, buildable_sloped = 0,
      water = 0, building = 0, road = 0, rail = 0
    };
    local min_h = 99;
    local max_h = 0;

    // Collect town center tiles for marking
    local town_tiles = {};
    local town_list = GSTownList();
    local town_ops = 0;
    local town_ids = [];
    foreach (tid, _ in town_list) town_ids.append(tid);
    for (local i = 0; i < town_ids.len(); i++) {
      local tid = town_ids[i];
      local loc = GSTown.GetLocation(tid);
      local tx = GSMap.GetTileX(loc);
      local ty = GSMap.GetTileY(loc);
      if (tx >= x1 && tx <= x2 && ty >= y1 && ty <= y2) {
        town_tiles[tx + "_" + ty] <- tid;
      }
      if (++town_ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    local ops = 0;
    for (local y = y1; y <= y2; y++) {
      local trow = "";
      local hrow = "";
      for (local x = x1; x <= x2; x++) {
        local tile = GSMap.GetTileIndex(x, y);
        local ht = GSTile.GetMaxHeight(tile);
        if (ht < min_h) min_h = ht;
        if (ht > max_h) max_h = ht;
        hrow += (ht > 9 ? "9" : ht.tostring());

        local key = x + "_" + y;
        if (key in town_tiles) {
          trow += "T";
        } else if (GSTile.IsWaterTile(tile) || GSTile.IsCoastTile(tile)) {
          trow += "~";
          counts.water++;
        } else if (GSRail.IsRailTile(tile)) {
          trow += "r";
          counts.rail++;
        } else if (GSRoad.IsRoadTile(tile)) {
          trow += "+";
          counts.road++;
        } else if (GSTile.IsBuildable(tile)) {
          if (GSTile.GetSlope(tile) == 0) {
            trow += ".";
            counts.buildable_flat++;
          } else {
            trow += "/";
            counts.buildable_sloped++;
          }
        } else {
          trow += "#";
          counts.building++;
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
      terrain_rows.append(trow);
      height_rows.append(hrow);
    }

    return { success = true, result = {
      from_x = x1, from_y = y1, to_x = x2, to_y = y2,
      width = w, height = h,
      terrain = terrain_rows,
      heights = height_rows,
      counts = counts,
      min_height = min_h, max_height = max_h,
      legend = ".: flat buildable, /: sloped buildable, ~: water, #: building, +: road, r: rail, T: town"
    }};
  }

  /**
   * get_tile_range: Compact grid representation of a rectangular area.
   * Returns ASCII grids for tile types and heights, plus road/buildable coordinate lists.
   */
  function CmdGetTileRange(p) {
    local x1 = p.from_x;
    local y1 = p.from_y;
    local x2 = p.to_x;
    local y2 = p.to_y;

    if (x1 > x2) { local t = x1; x1 = x2; x2 = t; }
    if (y1 > y2) { local t = y1; y1 = y2; y2 = t; }

    local w = x2 - x1 + 1;
    local h = y2 - y1 + 1;
    if (w > 20 || h > 20) {
      return { success = false, error = "Max 20x20 area. Use multiple calls for larger regions." };
    }

    // Build compact grid rows:
    // Each row is a string where each char represents a tile type:
    // . = flat buildable, / = sloped buildable, R = road, r = rail
    // ~ = water, # = building/structure, S = station/stop, * = our road
    // Heights as separate grid
    local type_rows = [];
    local height_rows = [];
    // Also collect road tiles and buildable tiles as coordinate lists (capped)
    local roads = [];
    local buildable = [];
    local ops = 0;

    for (local y = y1; y <= y2; y++) {
      local trow = "";
      local hrow = "";
      for (local x = x1; x <= x2; x++) {
        local tile = GSMap.GetTileIndex(x, y);
        local ht = GSTile.GetMaxHeight(tile);
        hrow += (ht > 9 ? "9" : ht.tostring());

        if (GSTile.IsWaterTile(tile) || GSTile.IsCoastTile(tile)) {
          trow += "~";
        } else if (GSRoad.IsRoadTile(tile)) {
          local owner = GSTile.GetOwner(tile);
          if (owner == 0) {
            trow += "*";  // Our road
          } else {
            trow += "R";  // Town/other road
          }
          if (roads.len() < 30) roads.append({ x = x, y = y });
        } else if (GSRail.IsRailTile(tile)) {
          trow += "r";
        } else if (GSTile.IsBuildable(tile)) {
          if (GSTile.GetSlope(tile) == 0) {
            trow += ".";
          } else {
            trow += "/";
          }
          if (buildable.len() < 20) buildable.append({ x = x, y = y, slope = GSTile.GetSlope(tile) });
        } else {
          local owner = GSTile.GetOwner(tile);
          if (owner == 0) {
            trow += "S";  // Our structure (station/depot)
          } else {
            trow += "#";  // Building/other
          }
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
      type_rows.append(trow);
      height_rows.append(hrow);
    }

    return { success = true, result = {
      from_x = x1, from_y = y1, to_x = x2, to_y = y2,
      width = w, height = h,
      grid = type_rows,
      heights = height_rows,
      roads = roads,
      buildable = buildable,
      legend = ". flat, / slope, R road, * our_road, r rail, ~ water, # building, S our_stop"
    }};
  }

  /**
   * build_rail_line: Build rail track along a straight line.
   * Returns count of built segments and list of failures.
   */
  function CmdBuildRailLine(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    GSRail.SetCurrentRailType(rail_type);

    local x1 = p.from_x;
    local y1 = p.from_y;
    local x2 = p.to_x;
    local y2 = p.to_y;

    if (x1 != x2 && y1 != y2) {
      return { success = false, error = "Only straight lines (same X or same Y) supported" };
    }
    if (x1 == x2 && y1 == y2) {
      return { success = false, error = "Start and end are the same tile" };
    }

    local built = 0;
    local failed = [];
    local ops = 0;

    if (x1 == x2) {
      local step = (y2 > y1) ? 1 : -1;
      for (local y = y1; ; y += step) {
        local prev = GSMap.GetTileIndex(x1, y - step);
        local curr = GSMap.GetTileIndex(x1, y);
        local next = GSMap.GetTileIndex(x1, y + step);

        if (GSRail.BuildRail(prev, curr, next)) {
          built++;
        } else {
          failed.append({ x = x1, y = y, error = GSError.GetLastErrorString() });
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        if (y == y2) break;
      }
    } else {
      local step = (x2 > x1) ? 1 : -1;
      for (local x = x1; ; x += step) {
        local prev = GSMap.GetTileIndex(x - step, y1);
        local curr = GSMap.GetTileIndex(x, y1);
        local next = GSMap.GetTileIndex(x + step, y1);

        if (GSRail.BuildRail(prev, curr, next)) {
          built++;
        } else {
          failed.append({ x = x, y = y1, error = GSError.GetLastErrorString() });
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        if (x == x2) break;
      }
    }

    if (failed.len() > 20) failed = failed.slice(0, 20);

    return { success = true, result = { built = built, failed = failed, total = built + failed.len() } };
  }

  // =====================================================================
  // A* PATHFINDING - Min-Heap
  // =====================================================================

  function HeapCreate() { return []; }

  function HeapPush(heap, priority, value) {
    heap.append({ p = priority, v = value });
    local i = heap.len() - 1;
    while (i > 0) {
      local pi = (i - 1) / 2;
      if (heap[pi].p <= heap[i].p) break;
      local tmp = heap[i];
      heap[i] = heap[pi];
      heap[pi] = tmp;
      i = pi;
    }
  }

  function HeapPop(heap) {
    if (heap.len() == 0) return null;
    local result = heap[0];
    local last = heap.pop();
    if (heap.len() == 0) return result;
    heap[0] = last;
    local i = 0;
    while (true) {
      local left = 2 * i + 1;
      local right = 2 * i + 2;
      local smallest = i;
      if (left < heap.len() && heap[left].p < heap[smallest].p) smallest = left;
      if (right < heap.len() && heap[right].p < heap[smallest].p) smallest = right;
      if (smallest == i) break;
      local tmp = heap[i];
      heap[i] = heap[smallest];
      heap[smallest] = tmp;
      i = smallest;
    }
    return result;
  }

  // =====================================================================
  // A* PATHFINDING - Utilities
  // =====================================================================

  // Encode (x, y, dir) into single integer for hash table key
  // Supports maps up to 4096x4096 (12 bits x, 12 bits y, 2 bits dir)
  function EncodeState(x, y, dir) {
    return (x << 14) | (y << 2) | dir;
  }

  // Direction offsets: 0=NE(+x), 1=SE(+y), 2=SW(-x), 3=NW(-y)
  function GetDirDx(dir) {
    if (dir == 0) return 1;
    if (dir == 2) return -1;
    return 0;
  }

  function GetDirDy(dir) {
    if (dir == 1) return 1;
    if (dir == 3) return -1;
    return 0;
  }

  function AStarHeuristic(x, y, gx, gy) {
    local dx = x - gx;
    local dy = y - gy;
    if (dx < 0) dx = -dx;
    if (dy < 0) dy = -dy;
    return dx + dy;
  }

  // =====================================================================
  // A* PATHFINDING - Route Builder
  // =====================================================================

  function CmdBuildRailRoute(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    GSRail.SetCurrentRailType(rail_type);

    local sx = p.from_x, sy = p.from_y;
    local gx = p.to_x,   gy = p.to_y;
    local max_iter = ("max_iterations" in p) ? p.max_iterations : 50000;

    // A* search
    local open = this.HeapCreate();
    local g_score = {};
    local came_from = {};
    local state_info = {};  // key -> {x, y, dir}

    // Seed: try entering the start tile from all 4 directions
    for (local d = 0; d < 4; d++) {
      local key = this.EncodeState(sx, sy, d);
      g_score[key] <- 0;
      state_info[key] <- { x = sx, y = sy, dir = d };
      came_from[key] <- -1;
      local h = this.AStarHeuristic(sx, sy, gx, gy);
      this.HeapPush(open, h, key);
    }

    local iterations = 0;
    local found_key = -1;
    local visited = {};

    while (open.len() > 0 && iterations < max_iter) {
      iterations++;
      if (iterations % this.YIELD_INTERVAL == 0) this.Sleep(1);
      local current = this.HeapPop(open);
      local cur_key = current.v;

      // Skip if already visited with better score
      if (cur_key in visited) continue;
      visited[cur_key] <- true;

      local cur = state_info[cur_key];
      local cur_g = g_score[cur_key];

      // Goal check
      if (cur.x == gx && cur.y == gy) {
        found_key = cur_key;
        break;
      }

      local reverse_dir = (cur.dir + 2) % 4;

      // Try 3 exit directions (not reverse)
      for (local exit_dir = 0; exit_dir < 4; exit_dir++) {
        if (exit_dir == reverse_dir) continue;

        local nx = cur.x + this.GetDirDx(exit_dir);
        local ny = cur.y + this.GetDirDy(exit_dir);

        // Validate next tile
        local next_tile = GSMap.GetTileIndex(nx, ny);
        if (!GSMap.IsValidTile(next_tile)) continue;
        if (GSTile.IsWaterTile(next_tile)) continue;

        local is_buildable = GSTile.IsBuildable(next_tile);
        local has_rail = GSRail.IsRailTile(next_tile);
        if (!is_buildable && !has_rail) continue;

        // Cost: straight=1, turn=3, slope=+5
        local move_cost = (exit_dir == cur.dir) ? 1 : 3;

        local cur_tile = GSMap.GetTileIndex(cur.x, cur.y);
        local cur_h = GSTile.GetMaxHeight(cur_tile);
        local next_h = GSTile.GetMaxHeight(next_tile);
        if (cur_h != next_h) move_cost += 5;

        local next_key = this.EncodeState(nx, ny, exit_dir);
        local tentative_g = cur_g + move_cost;

        if (!(next_key in g_score) || tentative_g < g_score[next_key]) {
          g_score[next_key] <- tentative_g;
          came_from[next_key] <- cur_key;
          state_info[next_key] <- { x = nx, y = ny, dir = exit_dir };
          local f = tentative_g + this.AStarHeuristic(nx, ny, gx, gy);
          this.HeapPush(open, f, next_key);
        }
      }
    }

    if (found_key == -1) {
      return { success = false, error = "No path found after " + iterations + " iterations" };
    }

    // Reconstruct path (append + reverse to avoid O(N²) insert(0,...))
    local path = [];
    local key = found_key;
    while (key != -1) {
      path.append(state_info[key]);
      key = came_from[key];
    }
    // Reverse in-place
    local plen = path.len();
    for (local i = 0; i < plen / 2; i++) {
      local tmp = path[i];
      path[i] = path[plen - 1 - i];
      path[plen - 1 - i] = tmp;
    }

    // Build rail along path
    local built = 0;
    local failures = [];

    for (local i = 0; i < path.len(); i++) {
      if (i % this.YIELD_INTERVAL == 0 && i > 0) this.Sleep(1);
      local prev_tile, cur_tile, next_tile;

      if (i == 0 && path.len() > 1) {
        // First tile: virtual prev from opposite of travel direction
        local opp = (path[0].dir + 2) % 4;
        prev_tile = GSMap.GetTileIndex(path[0].x + this.GetDirDx(opp), path[0].y + this.GetDirDy(opp));
        cur_tile = GSMap.GetTileIndex(path[0].x, path[0].y);
        next_tile = GSMap.GetTileIndex(path[1].x, path[1].y);
      } else if (i == path.len() - 1 && path.len() > 1) {
        // Last tile: virtual next continuing forward
        prev_tile = GSMap.GetTileIndex(path[i-1].x, path[i-1].y);
        cur_tile = GSMap.GetTileIndex(path[i].x, path[i].y);
        next_tile = GSMap.GetTileIndex(path[i].x + this.GetDirDx(path[i].dir), path[i].y + this.GetDirDy(path[i].dir));
      } else if (path.len() == 1) {
        continue;  // Single tile, nothing to build
      } else {
        prev_tile = GSMap.GetTileIndex(path[i-1].x, path[i-1].y);
        cur_tile = GSMap.GetTileIndex(path[i].x, path[i].y);
        next_tile = GSMap.GetTileIndex(path[i+1].x, path[i+1].y);
      }

      if (GSRail.BuildRail(prev_tile, cur_tile, next_tile)) {
        built++;
      } else {
        local err = GSError.GetLastErrorString();
        if (err != "ERR_ALREADY_BUILT") {
          failures.append({ x = path[i].x, y = path[i].y, error = err });
        } else {
          built++;  // Already built counts as success
        }
      }
    }

    // Build path summary (compact: just coordinates)
    local path_coords = [];
    foreach (pt in path) {
      path_coords.append({ x = pt.x, y = pt.y, dir = pt.dir });
    }
    if (path_coords.len() > 50) path_coords = path_coords.slice(0, 50);

    return { success = true, result = {
      path_length = path.len(),
      built = built,
      failed = failures,
      iterations = iterations,
      path = path_coords
    }};
  }

  // =====================================================================
  // A* PATHFINDING - Road Route Builder
  // =====================================================================

  function CmdBuildRoadRoute(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local road_type = ("road_type" in p) ? p.road_type : 0;
    GSRoad.SetCurrentRoadType(road_type);

    local sx = p.from_x, sy = p.from_y;
    local gx = p.to_x,   gy = p.to_y;
    local max_iter = ("max_iterations" in p) ? p.max_iterations : 10000;

    // A* search — state is just (x, y), no direction needed for roads
    local open = this.HeapCreate();
    local g_score = {};
    local came_from = {};
    local state_info = {};  // key -> {x, y}

    // Encode (x, y) into single integer for hash key (no dir for roads)
    // Supports maps up to 4096x4096 (12 bits x, 12 bits y)
    local start_key = (sx << 12) | sy;
    g_score[start_key] <- 0;
    state_info[start_key] <- { x = sx, y = sy };
    came_from[start_key] <- -1;
    local h = this.AStarHeuristic(sx, sy, gx, gy);
    this.HeapPush(open, h, start_key);

    local iterations = 0;
    local found_key = -1;
    local visited = {};
    local ops = 0;

    // Direction offsets: 4 cardinal neighbors
    local dx = [1, 0, -1, 0];
    local dy = [0, 1, 0, -1];

    while (open.len() > 0 && iterations < max_iter) {
      iterations++;
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);

      local current = this.HeapPop(open);
      local cur_key = current.v;

      if (cur_key in visited) continue;
      visited[cur_key] <- true;

      local cur = state_info[cur_key];
      local cur_g = g_score[cur_key];

      // Goal check
      if (cur.x == gx && cur.y == gy) {
        found_key = cur_key;
        break;
      }

      // Determine incoming direction for turn cost
      local prev_dx = 0;
      local prev_dy = 0;
      if (came_from[cur_key] != -1) {
        local prev = state_info[came_from[cur_key]];
        prev_dx = cur.x - prev.x;
        prev_dy = cur.y - prev.y;
      }

      // Try all 4 cardinal neighbors
      for (local d = 0; d < 4; d++) {
        local nx = cur.x + dx[d];
        local ny = cur.y + dy[d];

        local next_tile = GSMap.GetTileIndex(nx, ny);
        if (!GSMap.IsValidTile(next_tile)) continue;
        if (GSTile.IsWaterTile(next_tile)) continue;

        // Check if we can use this tile
        local is_buildable = GSTile.IsBuildable(next_tile);
        local is_road = GSRoad.IsRoadTile(next_tile);
        local needs_demolish = false;

        if (!is_buildable && !is_road) {
          // Try demolish as last resort (skip water, already checked)
          needs_demolish = true;
        }

        // Cost calculation: straight=1, turn=2, slope=+3, demolish=+10
        local is_turn = false;
        if (prev_dx != 0 || prev_dy != 0) {
          is_turn = (dx[d] != prev_dx || dy[d] != prev_dy);
        }
        local move_cost = is_turn ? 2 : 1;

        local cur_tile = GSMap.GetTileIndex(cur.x, cur.y);
        local cur_h = GSTile.GetMaxHeight(cur_tile);
        local next_h = GSTile.GetMaxHeight(next_tile);
        if (cur_h != next_h) move_cost += 3;

        if (needs_demolish) move_cost += 10;

        local next_key = (nx << 12) | ny;
        local tentative_g = cur_g + move_cost;

        if (!(next_key in g_score) || tentative_g < g_score[next_key]) {
          g_score[next_key] <- tentative_g;
          came_from[next_key] <- cur_key;
          state_info[next_key] <- { x = nx, y = ny };
          local f = tentative_g + this.AStarHeuristic(nx, ny, gx, gy);
          this.HeapPush(open, f, next_key);
        }
      }
    }

    if (found_key == -1) {
      return { success = false, error = "No road path found after " + iterations + " iterations" };
    }

    // Reconstruct path (append + reverse to avoid O(N²) insert(0,...))
    local path = [];
    local key = found_key;
    while (key != -1) {
      path.append(state_info[key]);
      key = came_from[key];
    }
    // Reverse in-place
    local plen = path.len();
    for (local i = 0; i < plen / 2; i++) {
      local tmp = path[i];
      path[i] = path[plen - 1 - i];
      path[plen - 1 - i] = tmp;
    }

    // Build road along path
    local built = 0;
    local failures = [];
    ops = 0;

    for (local i = 0; i + 1 < path.len(); i++) {
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);

      local from_tile = GSMap.GetTileIndex(path[i].x, path[i].y);
      local to_tile = GSMap.GetTileIndex(path[i + 1].x, path[i + 1].y);

      // Try demolish if the target tile isn't buildable or road
      local target_buildable = GSTile.IsBuildable(to_tile);
      local target_is_road = GSRoad.IsRoadTile(to_tile);
      if (!target_buildable && !target_is_road) {
        GSTile.DemolishTile(to_tile);
      }

      if (GSRoad.BuildRoad(from_tile, to_tile)) {
        built++;
      } else {
        local err = GSError.GetLastErrorString();
        if (err != "ERR_ALREADY_BUILT") {
          if (failures.len() < 20) {
            failures.append({ x = path[i + 1].x, y = path[i + 1].y, error = err });
          }
        } else {
          built++;  // Already built counts as success
        }
      }
    }

    // Build path summary (cap to 50 entries to avoid packet overflow)
    local path_coords = [];
    foreach (pt in path) {
      path_coords.append({ x = pt.x, y = pt.y });
    }
    if (path_coords.len() > 50) path_coords = path_coords.slice(0, 50);

    // Verify route is actually connected (no gaps from failed segments)
    local connected = (failures.len() == 0);
    if (!connected && failures.len() <= 3 && built > 0) {
      // Few failures — might still be connected via existing road
      connected = true;
    }

    if (!connected) {
      return { success = false, error = "Road built with " + failures.len() + " gaps. Route not connected. Water, steep terrain, or buildings may be blocking.", result = { built = built, failed = failures } };
    }

    return { success = true, result = {
      path_length = path.len(),
      built = built,
      failed = failures,
      iterations = iterations,
      path = path_coords
    }};
  }

  // =====================================================================
  // SIGNAL AUTO-PLACEMENT
  // =====================================================================

  function CmdBuildSignalsOnRoute(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local path = p.path;
    local signal_type = ("signal_type" in p) ? p.signal_type : 5;  // one-way path signal
    local interval = ("interval" in p) ? p.interval : 5;

    local placed = 0;
    local failures = [];
    local ops = 0;

    for (local i = 0; i < path.len(); i += interval) {
      local tile = GSMap.GetTileIndex(path[i].x, path[i].y);

      // Front tile = next tile in direction of travel
      local front_tile;
      if (i + 1 < path.len()) {
        front_tile = GSMap.GetTileIndex(path[i+1].x, path[i+1].y);
      } else {
        front_tile = GSMap.GetTileIndex(
          path[i].x + this.GetDirDx(path[i].dir),
          path[i].y + this.GetDirDy(path[i].dir)
        );
      }

      if (GSRail.BuildSignal(tile, front_tile, signal_type)) {
        placed++;
      } else {
        failures.append({ x = path[i].x, y = path[i].y, error = GSError.GetLastErrorString() });
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    if (failures.len() > 20) failures = failures.slice(0, 20);

    return { success = true, result = { placed = placed, failed = failures } };
  }

  // =====================================================================
  // CONNECT TOWNS - High-Level Rail Service
  // =====================================================================

  function FindBestStationSpot(town_id, plat_len, num_plat, max_dist) {
    local town_loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(town_loc);
    local cy = GSMap.GetTileY(town_loc);
    local best = null;
    local best_dist = 999999;
    local ops = 0;

    for (local dy = -max_dist; dy <= max_dist; dy++) {
      for (local dx = -max_dist; dx <= max_dist; dx++) {
        local bx = cx + dx;
        local by = cy + dy;

        for (local dir = 0; dir < 2; dir++) {
          local w = (dir == 0) ? plat_len : num_plat;
          local h = (dir == 0) ? num_plat : plat_len;
          local ok = true;
          local elev = -1;

          for (local ty = 0; ty < h && ok; ty++) {
            for (local tx = 0; tx < w && ok; tx++) {
              local t = GSMap.GetTileIndex(bx + tx, by + ty);
              if (!GSMap.IsValidTile(t) || !GSTile.IsBuildable(t)) { ok = false; break; }
              if (GSTile.GetSlope(t) != 0) { ok = false; break; }
              local th = GSTile.GetMaxHeight(t);
              if (elev == -1) elev = th;
              else if (th != elev) { ok = false; break; }
              ops++;
            }
          }

          if (ok) {
            local dist = (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy);
            if (dist < best_dist) {
              best_dist = dist;
              best = { x = bx, y = by, dir = dir, elevation = elev };
            }
          }
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }
    return best;
  }

  // Get the tile at the end of a station that faces toward target coordinates
  function GetStationConnectionPoint(spot, plat_len, num_plat, target_x, target_y) {
    local sx = spot.x, sy = spot.y;
    if (spot.dir == 0) {
      // NE-SW: platforms run along X axis
      // Connection at x-1 or x+plat_len
      local left_x = sx - 1;
      local right_x = sx + plat_len;
      local mid_y = sy + num_plat / 2;
      local dl = ((left_x - target_x) < 0 ? -(left_x - target_x) : (left_x - target_x)) +
                 ((mid_y - target_y) < 0 ? -(mid_y - target_y) : (mid_y - target_y));
      local dr = ((right_x - target_x) < 0 ? -(right_x - target_x) : (right_x - target_x)) +
                 ((mid_y - target_y) < 0 ? -(mid_y - target_y) : (mid_y - target_y));
      if (dl < dr) return { x = left_x, y = sy, dir = 2 };  // exit SW (-x)
      else return { x = right_x, y = sy, dir = 0 };  // exit NE (+x)
    } else {
      // NW-SE: platforms run along Y axis
      local top_y = sy - 1;
      local bot_y = sy + plat_len;
      local mid_x = sx + num_plat / 2;
      local dt = ((mid_x - target_x) < 0 ? -(mid_x - target_x) : (mid_x - target_x)) +
                 ((top_y - target_y) < 0 ? -(top_y - target_y) : (top_y - target_y));
      local db = ((mid_x - target_x) < 0 ? -(mid_x - target_x) : (mid_x - target_x)) +
                 ((bot_y - target_y) < 0 ? -(bot_y - target_y) : (bot_y - target_y));
      if (dt < db) return { x = sx, y = top_y, dir = 3 };  // exit NW (-y)
      else return { x = sx, y = bot_y, dir = 1 };  // exit SE (+y)
    }
  }

  // Find a depot spot near a station
  function FindDepotNearStation(spot, plat_len, num_plat) {
    local offsets = [
      { dx = -1, dy = -1 }, { dx = -1, dy = 0 }, { dx = -1, dy = 1 },
      { dx = 0, dy = -1 }, { dx = 0, dy = 1 },
      { dx = 1, dy = -1 }, { dx = 1, dy = 0 }, { dx = 1, dy = 1 }
    ];
    local w = (spot.dir == 0) ? plat_len : num_plat;
    local h = (spot.dir == 0) ? num_plat : plat_len;

    // Check around station edges
    for (local side = 0; side < 4; side++) {
      local tiles_to_check = [];
      if (side == 0) { // left of station
        for (local y = 0; y < h; y++)
          tiles_to_check.append({ x = spot.x - 1, y = spot.y + y });
      } else if (side == 1) { // right of station
        for (local y = 0; y < h; y++)
          tiles_to_check.append({ x = spot.x + w, y = spot.y + y });
      } else if (side == 2) { // above station
        for (local x = 0; x < w; x++)
          tiles_to_check.append({ x = spot.x + x, y = spot.y - 1 });
      } else { // below station
        for (local x = 0; x < w; x++)
          tiles_to_check.append({ x = spot.x + x, y = spot.y + h });
      }

      foreach (tc in tiles_to_check) {
        local t = GSMap.GetTileIndex(tc.x, tc.y);
        if (GSMap.IsValidTile(t) && GSTile.IsBuildable(t)) {
          // Find which direction faces the station track
          local depot_dir;
          if (side == 0) depot_dir = 0;  // face NE (+x) toward station
          else if (side == 1) depot_dir = 2;  // face SW (-x) toward station
          else if (side == 2) depot_dir = 1;  // face SE (+y) toward station
          else depot_dir = 3;  // face NW (-y) toward station
          return { x = tc.x, y = tc.y, dir = depot_dir };
        }
      }
    }
    return null;
  }

  function CmdConnectTownsRail(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    GSRail.SetCurrentRailType(rail_type);

    local town_a = ("town_a_id" in p) ? p.town_a_id : p.town_a;
    local town_b = ("town_b_id" in p) ? p.town_b_id : p.town_b;
    local plat_len = ("platform_length" in p) ? p.platform_length : 5;
    local num_plat = ("num_platforms" in p) ? p.num_platforms : 2;

    if (!GSTown.IsValidTown(town_a) || !GSTown.IsValidTown(town_b)) {
      return { success = false, error = "Invalid town ID" };
    }

    local result = {};
    result.town_a_name <- GSTown.GetName(town_a);
    result.town_b_name <- GSTown.GetName(town_b);

    // Step 1: Find station spots
    local spot_a = this.FindBestStationSpot(town_a, plat_len, num_plat, 20);
    if (spot_a == null) {
      return { success = false, error = "No station spot near " + result.town_a_name };
    }
    local spot_b = this.FindBestStationSpot(town_b, plat_len, num_plat, 20);
    if (spot_b == null) {
      return { success = false, error = "No station spot near " + result.town_b_name };
    }

    result.station_a_spot <- { x = spot_a.x, y = spot_a.y, dir = spot_a.dir };
    result.station_b_spot <- { x = spot_b.x, y = spot_b.y, dir = spot_b.dir };

    this.Sleep(1);

    // Step 2: Build stations (convert MCP dir 0/1 to GS RailTrack enum)
    local sta_tile = GSMap.GetTileIndex(spot_a.x, spot_a.y);
    if (!GSRail.BuildRailStation(sta_tile, this.MapRailTrack(spot_a.dir), num_plat, plat_len, GSStation.STATION_NEW)) {
      return { success = false, error = "Station A failed: " + GSError.GetLastErrorString() };
    }

    this.Sleep(1);

    local stb_tile = GSMap.GetTileIndex(spot_b.x, spot_b.y);
    if (!GSRail.BuildRailStation(stb_tile, this.MapRailTrack(spot_b.dir), num_plat, plat_len, GSStation.STATION_NEW)) {
      return { success = false, error = "Station B failed: " + GSError.GetLastErrorString() };
    }

    this.Sleep(1);

    // Step 3: Calculate connection points (station edges facing each other)
    local town_b_loc = GSTown.GetLocation(town_b);
    local conn_a = this.GetStationConnectionPoint(spot_a, plat_len, num_plat,
      GSMap.GetTileX(town_b_loc), GSMap.GetTileY(town_b_loc));

    local town_a_loc = GSTown.GetLocation(town_a);
    local conn_b = this.GetStationConnectionPoint(spot_b, plat_len, num_plat,
      GSMap.GetTileX(town_a_loc), GSMap.GetTileY(town_a_loc));

    result.connection_a <- conn_a;
    result.connection_b <- conn_b;

    this.Sleep(1);

    // Step 4: Pathfind and build rail
    local route = this.CmdBuildRailRoute({
      company_id = p.company_id,
      from_x = conn_a.x, from_y = conn_a.y,
      to_x = conn_b.x, to_y = conn_b.y,
      rail_type = rail_type,
      max_iterations = ("max_iterations" in p) ? p.max_iterations : 80000
    });

    if (!route.success) {
      result.route_error <- route.error;
      return { success = false, error = "Route failed: " + route.error, result = result };
    }

    result.route_length <- route.result.path_length;
    result.route_built <- route.result.built;
    result.route_iterations <- route.result.iterations;

    this.Sleep(1);

    // Step 5: Place signals
    if (route.result.path.len() > 5) {
      local sig = this.CmdBuildSignalsOnRoute({
        company_id = p.company_id,
        path = route.result.path,
        signal_type = 5,
        interval = 5
      });
      result.signals_placed <- sig.result.placed;
    }

    this.Sleep(1);

    // Step 6: Build depot near station A
    local depot_spot = this.FindDepotNearStation(spot_a, plat_len, num_plat);
    if (depot_spot != null) {
      local depot_tile = GSMap.GetTileIndex(depot_spot.x, depot_spot.y);
      local front_tile = this.GetAdjacentTile(depot_tile, depot_spot.dir);

      // Build connecting rail from depot to station track first
      if (GSRail.BuildRail(depot_tile, front_tile,
          GSMap.GetTileIndex(depot_spot.x + this.GetDirDx(depot_spot.dir), depot_spot.y + this.GetDirDy(depot_spot.dir)))) {
        // fine
      }

      if (GSRail.BuildRailDepot(depot_tile, front_tile)) {
        result.depot <- { x = depot_spot.x, y = depot_spot.y };

        // Step 7: Buy train
        if ("engine_id" in p) {
          local train_id = GSVehicle.BuildVehicle(depot_tile, p.engine_id);
          if (GSVehicle.IsValidVehicle(train_id)) {
            result.train_id <- train_id;

            // Add wagons
            if ("wagon_id" in p) {
              local wcount = ("num_wagons" in p) ? p.num_wagons : (("wagon_count" in p) ? p.wagon_count : 3);
              local wagons_built = 0;
              for (local w = 0; w < wcount; w++) {
                local wag_id = GSVehicle.BuildVehicle(depot_tile, p.wagon_id);
                if (GSVehicle.IsValidVehicle(wag_id)) {
                  wagons_built++;
                }
              }
              result.wagons_built <- wagons_built;
            }

            // Step 8: Set orders
            local stn_a_id = GSStation.GetStationID(sta_tile);
            local stn_b_id = GSStation.GetStationID(stb_tile);
            GSOrder.AppendOrder(train_id, GSStation.GetLocation(stn_a_id), GSOrder.OF_FULL_LOAD_ANY);
            GSOrder.AppendOrder(train_id, GSStation.GetLocation(stn_b_id), GSOrder.OF_FULL_LOAD_ANY);
            result.orders <- "Full load at both stations";

            // Step 9: Start train
            GSVehicle.StartStopVehicle(train_id);
            result.train_started <- true;
          } else {
            result.train_error <- GSError.GetLastErrorString();
          }
        }
      } else {
        result.depot_error <- GSError.GetLastErrorString();
      }
    } else {
      result.depot_error <- "No suitable depot location found";
    }

    return { success = true, result = result };
  }

  // =====================================================================
  // UTILITY
  // =====================================================================

  // Auto-connect a tile to all adjacent road infrastructure (road, stops, depots)
  function AutoConnectRoad(tile) {
    local connected = [];
    for (local d = 0; d < 4; d++) {
      local adj = this.GetAdjacentTile(tile, d);
      if (GSRoad.IsRoadTile(adj) || GSRoad.IsDriveThroughRoadStationTile(adj)
          || GSRoad.IsRoadStationTile(adj) || GSRoad.IsRoadDepotTile(adj)) {
        if (GSRoad.BuildRoad(tile, adj)) {
          connected.append([GSMap.GetTileX(adj), GSMap.GetTileY(adj)]);
        }
      }
    }
    return connected;
  }

  function GetAdjacentTile(tile, direction) {
    switch (direction) {
      case 0: return tile + GSMap.GetTileIndex(1, 0) - GSMap.GetTileIndex(0, 0);
      case 1: return tile + GSMap.GetTileIndex(0, 1) - GSMap.GetTileIndex(0, 0);
      case 2: return tile - (GSMap.GetTileIndex(1, 0) - GSMap.GetTileIndex(0, 0));
      case 3: return tile - (GSMap.GetTileIndex(0, 1) - GSMap.GetTileIndex(0, 0));
    }
    return tile;
  }

  // =====================================================================
  // EMERGENCY & STATUS COMMANDS
  // =====================================================================

  function CmdStopAllVehicles(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local veh_list = GSVehicleList();
    local ids = [];
    foreach (vid, _ in veh_list) ids.append(vid);
    local stopped = 0;
    local ops = 0;
    for (local i = 0; i < ids.len(); i++) {
      local vid = ids[i];
      if (!GSVehicle.IsStoppedInDepot(vid)) {
        GSVehicle.SendVehicleToDepot(vid);
        stopped++;
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }
    return { success = true, result = { sent_to_depot = stopped, total = ids.len() } };
  }

  function CmdGetGameStatus(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local veh_list = GSVehicleList();
    local veh_ids = [];
    foreach (vid, _ in veh_list) veh_ids.append(vid);
    this.Sleep(1);

    local running = 0;
    local stopped = 0;
    local loading = 0;
    local broken = 0;
    local ops = 0;
    for (local i = 0; i < veh_ids.len(); i++) {
      local state = GSVehicle.GetState(veh_ids[i]);
      switch (state) {
        case 0: running++; break;
        case 1: case 2: stopped++; break;
        case 3: loading++; break;
        case 4: broken++; break;
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }
    this.Sleep(1);

    local stn_list = GSStationList(GSStation.STATION_ANY);
    local stn_ids = [];
    foreach (sid, _ in stn_list) stn_ids.append(sid);

    return { success = true, result = {
      vehicle_count = veh_ids.len(),
      vehicles_running = running,
      vehicles_stopped = stopped,
      vehicles_loading = loading,
      vehicles_broken = broken,
      station_count = stn_ids.len()
    }};
  }

  function CmdCheckRoadConnection(p) {
    local from_tile = GSMap.GetTileIndex(p.from_x, p.from_y);
    local to_tile = GSMap.GetTileIndex(p.to_x, p.to_y);

    if (!GSMap.IsValidTile(from_tile) || !GSMap.IsValidTile(to_tile)) {
      return { success = false, error = "Invalid coordinates" };
    }

    local visited = {};
    local queue = [from_tile];
    visited[from_tile] <- true;
    local found = false;
    local checked = 0;
    local max_check = 2000;
    local ops = 0;
    local queue_idx = 0;

    while (queue_idx < queue.len() && checked < max_check) {
      local tile = queue[queue_idx];
      queue_idx++;
      checked++;

      if (tile == to_tile) { found = true; break; }

      // Check 4 neighbors
      local x = GSMap.GetTileX(tile);
      local y = GSMap.GetTileY(tile);
      local neighbors = [
        GSMap.GetTileIndex(x+1, y),
        GSMap.GetTileIndex(x-1, y),
        GSMap.GetTileIndex(x, y+1),
        GSMap.GetTileIndex(x, y-1)
      ];

      foreach (n in neighbors) {
        if (GSMap.IsValidTile(n) && !(n in visited) && GSRoad.IsRoadTile(n)) {
          visited[n] <- true;
          queue.append(n);
        }
      }

      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = {
      connected = found,
      tiles_checked = checked,
      from_x = p.from_x, from_y = p.from_y,
      to_x = p.to_x, to_y = p.to_y
    }};
  }

  function CmdClearVehicleOrders(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local vehicle_id = p.vehicle_id;

    if (!GSVehicle.IsValidVehicle(vehicle_id)) {
      return { success = false, error = "Invalid vehicle ID" };
    }

    local count = GSOrder.GetOrderCount(vehicle_id);
    // Remove orders from the end to avoid index shifting
    for (local i = count - 1; i >= 0; i--) {
      GSOrder.RemoveOrder(vehicle_id, i);
    }

    return { success = true, result = { vehicle_id = vehicle_id, orders_removed = count } };
  }

  function CmdConnectIndustries(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local source_id = p.source_id;
    local dest_id = p.dest_id;
    local cargo_engine_id = ("engine_id" in p) ? p.engine_id : -1;
    local truck_count = ("truck_count" in p) ? p.truck_count : 2;
    local road_type = ("road_type" in p) ? p.road_type : 0;

    if (!GSIndustry.IsValidIndustry(source_id)) return { success = false, error = "Invalid source industry" };
    if (!GSIndustry.IsValidIndustry(dest_id)) return { success = false, error = "Invalid destination industry" };

    local result = {};
    GSRoad.SetCurrentRoadType(road_type);

    // Pre-check: sufficient funds (rough estimate: road + stops + depot + trucks)
    local money = GSCompany.GetBankBalance(GSCompany.COMPANY_SELF);
    local estimated_cost = 20000; // rough minimum for a route
    if (money < estimated_cost) {
      return { success = false, error = "Insufficient funds. Need at least ~$20,000. Current: $" + money + ". Use set_loan to borrow more." };
    }

    // Phase 1: Find buildable tiles near source and destination
    local src_loc = GSIndustry.GetLocation(source_id);
    local dst_loc = GSIndustry.GetLocation(dest_id);
    local src_x = GSMap.GetTileX(src_loc);
    local src_y = GSMap.GetTileY(src_loc);
    local dst_x = GSMap.GetTileX(dst_loc);
    local dst_y = GSMap.GetTileY(dst_loc);

    result.source_name <- GSIndustry.GetName(source_id);
    result.dest_name <- GSIndustry.GetName(dest_id);

    // Find a buildable flat tile near source (scan 8-tile radius)
    local src_spot = this.FindBuildableNear(src_x, src_y, 8);
    if (src_spot == null) return { success = false, error = "No buildable tile near source industry" };
    this.Sleep(1);

    local dst_spot = this.FindBuildableNear(dst_x, dst_y, 8);
    if (dst_spot == null) return { success = false, error = "No buildable tile near destination industry" };
    this.Sleep(1);

    // Phase 2: Build road using A* pathfinding (handles water, buildings, terrain)
    local route_result = this.CmdBuildRoadRoute({
      company_id = p.company_id,
      from_x = src_spot.x, from_y = src_spot.y,
      to_x = dst_spot.x, to_y = dst_spot.y,
      road_type = road_type,
      max_iterations = 10000
    });

    if (!route_result.success) {
      return { success = false, error = "Road pathfinding failed: " + (("error" in route_result) ? route_result.error : "unknown") + ". Industries may be separated by water or impassable terrain." };
    }

    result.road_built <- ("result" in route_result && "built" in route_result.result) ? route_result.result.built : 0;

    // Phase 3: Build drive-through stops on the road
    // Find road tiles near source and dest for drive-through stops
    local src_stop_tile = this.FindRoadTileNear(src_spot.x, src_spot.y, 3);
    local dst_stop_tile = this.FindRoadTileNear(dst_spot.x, dst_spot.y, 3);

    if (src_stop_tile == null || dst_stop_tile == null) {
      return { success = false, error = "Could not find road tiles for stops", road_built = built1 + built2 };
    }
    this.Sleep(1);

    // Try building drive-through truck stops
    // API: BuildDriveThroughRoadStation(tile, front, road_veh_type, station_id)
    // front must be != tile, on the same axis — determines orientation
    local src_tile = GSMap.GetTileIndex(src_stop_tile.x, src_stop_tile.y);
    local src_stop_ok = false;
    // Try front tile in X direction, then Y direction
    local src_fronts = [
      GSMap.GetTileIndex(src_stop_tile.x + 1, src_stop_tile.y),
      GSMap.GetTileIndex(src_stop_tile.x, src_stop_tile.y + 1)
    ];
    for (local dir = 0; dir < src_fronts.len() && !src_stop_ok; dir++) {
      src_stop_ok = GSRoad.BuildDriveThroughRoadStation(
        src_tile, src_fronts[dir], GSRoad.ROADVEHTYPE_TRUCK, GSStation.STATION_NEW
      );
    }
    if (!src_stop_ok) return { success = false, error = "Failed to build source truck stop: " + GSError.GetLastErrorString() };
    this.Sleep(1);

    local dst_tile = GSMap.GetTileIndex(dst_stop_tile.x, dst_stop_tile.y);
    local dst_stop_ok = false;
    local dst_fronts = [
      GSMap.GetTileIndex(dst_stop_tile.x + 1, dst_stop_tile.y),
      GSMap.GetTileIndex(dst_stop_tile.x, dst_stop_tile.y + 1)
    ];
    for (local dir = 0; dir < dst_fronts.len() && !dst_stop_ok; dir++) {
      dst_stop_ok = GSRoad.BuildDriveThroughRoadStation(
        dst_tile, dst_fronts[dir], GSRoad.ROADVEHTYPE_TRUCK, GSStation.STATION_NEW
      );
    }
    if (!dst_stop_ok) return { success = false, error = "Failed to build destination truck stop: " + GSError.GetLastErrorString() };
    this.Sleep(1);

    // Phase 4: Build depot near source
    local depot_spot = this.FindBuildableNear(src_spot.x, src_spot.y, 5);
    if (depot_spot == null) return { success = false, error = "No depot spot" };

    // Build depot facing a direction where there's ROAD (not just any buildable direction)
    local depot_tile = GSMap.GetTileIndex(depot_spot.x, depot_spot.y);
    local depot_ok = false;
    local offsets = [
      { dx = -1, dy = 0 },  // dir 0: NE
      { dx = 0, dy = -1 },  // dir 1: SE
      { dx = 1, dy = 0 },   // dir 2: SW
      { dx = 0, dy = 1 }    // dir 3: NW
    ];
    // First pass: try directions where front tile has road
    for (local dir = 0; dir <= 3 && !depot_ok; dir++) {
      local front = GSMap.GetTileIndex(depot_spot.x + offsets[dir].dx, depot_spot.y + offsets[dir].dy);
      if (GSMap.IsValidTile(front) && GSRoad.IsRoadTile(front)) {
        depot_ok = GSRoad.BuildRoadDepot(depot_tile, front);
      }
    }
    // Second pass: try any direction, then connect
    if (!depot_ok) {
      for (local dir = 0; dir <= 3 && !depot_ok; dir++) {
        local front = GSMap.GetTileIndex(depot_spot.x + offsets[dir].dx, depot_spot.y + offsets[dir].dy);
        depot_ok = GSRoad.BuildRoadDepot(depot_tile, front);
        if (depot_ok) {
          // Build road from depot front to nearest road
          GSRoad.BuildRoad(front, GSMap.GetTileIndex(src_spot.x, src_spot.y));
        }
      }
    }
    this.Sleep(1);

    // Phase 5: Get station IDs
    local src_stn = GSStation.GetStationID(GSMap.GetTileIndex(src_stop_tile.x, src_stop_tile.y));
    local dst_stn = GSStation.GetStationID(GSMap.GetTileIndex(dst_stop_tile.x, dst_stop_tile.y));

    result.source_station <- src_stn;
    result.dest_station <- dst_stn;
    result.depot <- { x = depot_spot.x, y = depot_spot.y };

    // Phase 6: Buy trucks and set orders
    if (cargo_engine_id < 0) {
      // No engine specified — caller needs to buy manually
      result.trucks_bought <- 0;
      result.note <- "No engine_id specified. Buy trucks manually at the depot.";
    } else {
      local trucks = [];
      for (local t = 0; t < truck_count; t++) {
        local veh = GSVehicle.BuildVehicle(depot_tile, cargo_engine_id);
        if (GSVehicle.IsValidVehicle(veh)) {
          GSOrder.AppendOrder(veh, GSStation.GetLocation(src_stn), GSOrder.OF_FULL_LOAD_ANY);
          GSOrder.AppendOrder(veh, GSStation.GetLocation(dst_stn), GSOrder.OF_UNLOAD);
          GSVehicle.StartStopVehicle(veh);
          trucks.append(veh);
        }
        this.Sleep(1);
      }
      result.trucks_bought <- trucks.len();
      // Cap truck_ids to 10
      if (trucks.len() > 10) {
        local capped = [];
        for (local i = 0; i < 10; i++) capped.append(trucks[i]);
        result.truck_ids <- capped;
      } else {
        result.truck_ids <- trucks;
      }
    }

    return { success = true, result = result };
  }

  /**
   * Connect two towns with a complete bus route.
   * Finds drive-through bus stop locations, builds connecting road,
   * depot, buys buses, sets orders, and starts them.
   */
  function CmdConnectTownsBus(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local town_a = p.town_a_id;
    local town_b = p.town_b_id;
    local bus_count = ("bus_count" in p) ? p.bus_count : 2;
    local road_type = ("road_type" in p) ? p.road_type : 0;
    local engine_id = ("engine_id" in p) ? p.engine_id : -1;

    if (!GSTown.IsValidTown(town_a)) return { success = false, error = "Invalid town_a_id" };
    if (!GSTown.IsValidTown(town_b)) return { success = false, error = "Invalid town_b_id" };

    local result = {};
    GSRoad.SetCurrentRoadType(road_type);

    result.town_a_name <- GSTown.GetName(town_a);
    result.town_b_name <- GSTown.GetName(town_b);

    // Phase 1: Get town locations
    local loc_a = GSTown.GetLocation(town_a);
    local loc_b = GSTown.GetLocation(town_b);
    local ax = GSMap.GetTileX(loc_a);
    local ay = GSMap.GetTileY(loc_a);
    local bx = GSMap.GetTileX(loc_b);
    local by = GSMap.GetTileY(loc_b);
    this.Sleep(1);

    // Phase 2: Find road tiles near town centers for drive-through stops
    local stop_a_tile = this.FindRoadTileNear(ax, ay, 5);
    local stop_b_tile = this.FindRoadTileNear(bx, by, 5);

    if (stop_a_tile == null) return { success = false, error = "No road tile found near town A" };
    if (stop_b_tile == null) return { success = false, error = "No road tile found near town B" };
    this.Sleep(1);

    // Phase 3: Build connecting road using A* pathfinding (handles water, buildings, terrain)
    local route_result = this.CmdBuildRoadRoute({
      company_id = p.company_id,
      from_x = stop_a_tile.x, from_y = stop_a_tile.y,
      to_x = stop_b_tile.x, to_y = stop_b_tile.y,
      road_type = road_type,
      max_iterations = 10000
    });

    if (!route_result.success) {
      return { success = false, error = "Road pathfinding failed: " + (("error" in route_result) ? route_result.error : "unknown") + ". Towns may be separated by water or impassable terrain." };
    }

    result.road_built <- ("result" in route_result && "built" in route_result.result) ? route_result.result.built : 0;

    // Phase 4: Build drive-through bus stops
    // API: BuildDriveThroughRoadStation(tile, front, road_veh_type, station_id)
    // front must be != tile, on the same axis — determines orientation
    local tile_a = GSMap.GetTileIndex(stop_a_tile.x, stop_a_tile.y);
    local stop_a_ok = false;
    local fronts_a = [
      GSMap.GetTileIndex(stop_a_tile.x + 1, stop_a_tile.y),
      GSMap.GetTileIndex(stop_a_tile.x, stop_a_tile.y + 1)
    ];
    for (local dir = 0; dir < fronts_a.len() && !stop_a_ok; dir++) {
      stop_a_ok = GSRoad.BuildDriveThroughRoadStation(
        tile_a, fronts_a[dir], GSRoad.ROADVEHTYPE_BUS, GSStation.STATION_NEW
      );
    }
    if (!stop_a_ok) return { success = false, error = "Failed to build bus stop in town A: " + GSError.GetLastErrorString() };
    this.Sleep(1);

    local tile_b = GSMap.GetTileIndex(stop_b_tile.x, stop_b_tile.y);
    local stop_b_ok = false;
    local fronts_b = [
      GSMap.GetTileIndex(stop_b_tile.x + 1, stop_b_tile.y),
      GSMap.GetTileIndex(stop_b_tile.x, stop_b_tile.y + 1)
    ];
    for (local dir = 0; dir < fronts_b.len() && !stop_b_ok; dir++) {
      stop_b_ok = GSRoad.BuildDriveThroughRoadStation(
        tile_b, fronts_b[dir], GSRoad.ROADVEHTYPE_BUS, GSStation.STATION_NEW
      );
    }
    if (!stop_b_ok) return { success = false, error = "Failed to build bus stop in town B: " + GSError.GetLastErrorString() };
    this.Sleep(1);

    // Phase 5: Build depot near town A
    local depot_spot = this.FindBuildableNear(stop_a_tile.x, stop_a_tile.y, 5);
    if (depot_spot == null) return { success = false, error = "No depot spot near town A" };

    local depot_tile = GSMap.GetTileIndex(depot_spot.x, depot_spot.y);
    local depot_ok = false;
    local d_offsets = [
      { dx = -1, dy = 0 }, { dx = 0, dy = -1 },
      { dx = 1, dy = 0 }, { dx = 0, dy = 1 }
    ];
    // First: try directions where front has road
    for (local dir = 0; dir <= 3 && !depot_ok; dir++) {
      local front = GSMap.GetTileIndex(depot_spot.x + d_offsets[dir].dx, depot_spot.y + d_offsets[dir].dy);
      if (GSMap.IsValidTile(front) && GSRoad.IsRoadTile(front)) {
        depot_ok = GSRoad.BuildRoadDepot(depot_tile, front);
      }
    }
    // Fallback: any direction, then connect
    if (!depot_ok) {
      for (local dir = 0; dir <= 3 && !depot_ok; dir++) {
        local front = GSMap.GetTileIndex(depot_spot.x + d_offsets[dir].dx, depot_spot.y + d_offsets[dir].dy);
        depot_ok = GSRoad.BuildRoadDepot(depot_tile, front);
        if (depot_ok) {
          GSRoad.BuildRoad(front, GSMap.GetTileIndex(stop_a_tile.x, stop_a_tile.y));
        }
      }
    }
    this.Sleep(1);

    // Phase 6: Get station IDs
    local stn_a = GSStation.GetStationID(GSMap.GetTileIndex(stop_a_tile.x, stop_a_tile.y));
    local stn_b = GSStation.GetStationID(GSMap.GetTileIndex(stop_b_tile.x, stop_b_tile.y));

    result.station_a <- stn_a;
    result.station_b <- stn_b;
    result.depot <- { x = depot_spot.x, y = depot_spot.y };
    this.Sleep(1);

    // Phase 7: Auto-find bus engine if not specified
    if (engine_id < 0) {
      local eng_list = GSEngineList(GSVehicle.VT_ROAD);
      local engs = [];
      foreach (eng, _ in eng_list) engs.append(eng);
      this.Sleep(1);
      local search_ops = 0;
      for (local i = 0; i < engs.len(); i++) {
        local eng = engs[i];
        if (GSEngine.IsBuildable(eng) && GSEngine.GetCargoType(eng) == 0) {
          engine_id = eng;
          break;
        }
        if (++search_ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    if (engine_id < 0) {
      result.buses_bought <- 0;
      result.note <- "No bus engine found. Buy buses manually at the depot.";
      return { success = true, result = result };
    }

    // Phase 8: Buy buses and set orders
    local buses = [];
    for (local t = 0; t < bus_count; t++) {
      local veh = GSVehicle.BuildVehicle(depot_tile, engine_id);
      if (GSVehicle.IsValidVehicle(veh)) {
        GSOrder.AppendOrder(veh, GSStation.GetLocation(stn_a), 0);  // 0 = normal
        GSOrder.AppendOrder(veh, GSStation.GetLocation(stn_b), 0);
        GSVehicle.StartStopVehicle(veh);
        buses.append(veh);
      }
      this.Sleep(1);
    }

    result.engine_id <- engine_id;
    result.buses_bought <- buses.len();
    if (buses.len() > 10) {
      local capped = [];
      for (local i = 0; i < 10; i++) capped.append(buses[i]);
      result.bus_ids <- capped;
    } else {
      result.bus_ids <- buses;
    }

    return { success = true, result = result };
  }

  /**
   * Find and replace aging vehicles (>80% max age).
   * Vehicles in depot are sold and replaced with same engine type, orders restored.
   * Vehicles still running are sent to depot - run again later to complete.
   */
  function CmdReplaceOldVehicles(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local veh_list = GSVehicleList();
    local ids = [];
    foreach (vid, _ in veh_list) ids.append(vid);

    local replaced = 0;
    local sent_to_depot = 0;
    local ops = 0;

    for (local i = 0; i < ids.len(); i++) {
      local vid = ids[i];
      local age = GSVehicle.GetAge(vid);
      local max_age = GSVehicle.GetMaxAge(vid);

      if (age > max_age * 80 / 100) {
        if (GSVehicle.IsStoppedInDepot(vid)) {
          // Already in depot - sell and rebuy
          local engine = GSVehicle.GetEngineType(vid);
          local depot_tile = GSVehicle.GetLocation(vid);

          // Copy orders before selling
          local order_count = GSOrder.GetOrderCount(vid);
          local orders = [];
          for (local o = 0; o < order_count; o++) {
            orders.append({
              dest = GSOrder.GetOrderDestination(vid, o),
              flags = GSOrder.GetOrderFlags(vid, o)
            });
          }

          GSVehicle.SellVehicle(vid);

          // Buy replacement
          local new_vid = GSVehicle.BuildVehicle(depot_tile, engine);
          if (GSVehicle.IsValidVehicle(new_vid)) {
            // Restore orders
            for (local o = 0; o < orders.len(); o++) {
              GSOrder.AppendOrder(new_vid, orders[o].dest, orders[o].flags);
            }
            GSVehicle.StartStopVehicle(new_vid);
            replaced++;
          }
        } else {
          // Send to depot first
          GSVehicle.SendVehicleToDepot(vid);
          sent_to_depot++;
        }
      }

      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = {
      replaced = replaced,
      sent_to_depot = sent_to_depot,
      total_checked = ids.len()
    }};
  }

  // Helper: find a flat buildable tile near given coordinates
  function FindBuildableNear(cx, cy, radius) {
    local ops = 0;
    for (local r = 1; r <= radius; r++) {
      for (local dy = -r; dy <= r; dy++) {
        for (local dx = -r; dx <= r; dx++) {
          if (abs(dx) != r && abs(dy) != r) continue; // only check perimeter
          local tile = GSMap.GetTileIndex(cx + dx, cy + dy);
          if (GSMap.IsValidTile(tile) && GSTile.IsBuildable(tile) && GSTile.GetSlope(tile) == 0) {
            return { x = cx + dx, y = cy + dy };
          }
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        }
      }
    }
    return null;
  }

  // Helper: find a road tile near given coordinates
  // Find a STRAIGHT road tile (not a junction) suitable for drive-through stops
  function FindRoadTileNear(cx, cy, radius) {
    local ops = 0;
    for (local r = 0; r <= radius; r++) {
      for (local dy = -r; dy <= r; dy++) {
        for (local dx = -r; dx <= r; dx++) {
          if (r > 0 && abs(dx) != r && abs(dy) != r) continue;
          local x = cx + dx;
          local y = cy + dy;
          local tile = GSMap.GetTileIndex(x, y);
          if (!GSMap.IsValidTile(tile) || !GSRoad.IsRoadTile(tile)) {
            if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
            continue;
          }
          // Skip junctions — check that road doesn't exist on ALL 4 sides
          local t_n = GSMap.GetTileIndex(x, y-1);
          local t_s = GSMap.GetTileIndex(x, y+1);
          local t_w = GSMap.GetTileIndex(x-1, y);
          local t_e = GSMap.GetTileIndex(x+1, y);
          local has_ns = GSMap.IsValidTile(t_n) && GSRoad.IsRoadTile(t_n) &&
                         GSMap.IsValidTile(t_s) && GSRoad.IsRoadTile(t_s);
          local has_ew = GSMap.IsValidTile(t_w) && GSRoad.IsRoadTile(t_w) &&
                         GSMap.IsValidTile(t_e) && GSRoad.IsRoadTile(t_e);
          if (has_ns && has_ew) {
            // Junction — skip, can't place drive-through here
            if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
            continue;
          }
          return { x = x, y = y };
        }
      }
    }
    return null;
  }

  function Log(level, msg) {
    if (level <= this.log_level) {
      GSLog.Info("[ClaudeMCP] " + msg);
    }
  }

  // Atomic demolish + build road in same tick (prevents town rebuilding)
  function CmdDemolishAndBuildRoad(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local tiles = ("tiles" in p) ? p.tiles : [];
    local road_type = ("road_type" in p) ? p.road_type : 0;
    GSRoad.SetCurrentRoadType(road_type);

    local built = 0;
    local failed = [];
    local ops = 0;

    for (local i = 0; i < tiles.len() && i < 50; i++) {
      local x = tiles[i].x;
      local y = tiles[i].y;
      local tile = GSMap.GetTileIndex(x, y);

      // Demolish and immediately build road in same tick
      GSTile.DemolishTile(tile);

      if (i + 1 < tiles.len()) {
        local nx = tiles[i + 1].x;
        local ny = tiles[i + 1].y;
        local next_tile = GSMap.GetTileIndex(nx, ny);
        if (GSRoad.BuildRoad(tile, next_tile)) {
          built++;
        } else {
          failed.append({ x = x, y = y, error = GSError.GetLastErrorString() });
        }
      }

      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    if (failed.len() > 20) failed = failed.slice(0, 20);
    return { success = true, result = { built = built, failed = failed } };
  }

  // Check if a tile is within an industry's station catchment area
  function CmdCheckIndustryCatchment(p) {
    local industry_id = p.industry_id;
    local x = p.x;
    local y = p.y;

    if (!GSIndustry.IsValidIndustry(industry_id)) {
      return { success = false, error = "Invalid industry ID" };
    }

    local tile = GSMap.GetTileIndex(x, y);
    local ind_loc = GSIndustry.GetLocation(industry_id);
    local ind_x = GSMap.GetTileX(ind_loc);
    local ind_y = GSMap.GetTileY(ind_loc);
    local dist = GSIndustry.GetDistanceManhattanToTile(industry_id, tile);

    // Road station catchment is typically 3 tiles
    local in_catchment = (dist <= 4);

    // Also find the closest buildable+flat tile that IS in catchment
    local best_spot = null;
    local best_dist = 999;
    local ops = 0;

    for (local dy = -5; dy <= 5; dy++) {
      for (local dx = -5; dx <= 5; dx++) {
        local cx = ind_x + dx;
        local cy = ind_y + dy;
        local ct = GSMap.GetTileIndex(cx, cy);
        if (!GSMap.IsValidTile(ct)) continue;

        local cd = GSIndustry.GetDistanceManhattanToTile(industry_id, ct);
        if (cd > 4) continue;

        if (GSRoad.IsRoadTile(ct) && cd < best_dist) {
          best_dist = cd;
          best_spot = { x = cx, y = cy, distance = cd, is_road = true };
        } else if (GSTile.IsBuildable(ct) && GSTile.GetSlope(ct) == 0 && cd < best_dist) {
          best_dist = cd;
          best_spot = { x = cx, y = cy, distance = cd, is_road = false };
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    return { success = true, result = {
      industry_id = industry_id,
      industry_name = GSIndustry.GetName(industry_id),
      check_x = x, check_y = y,
      distance = dist,
      in_catchment = in_catchment,
      best_spot = best_spot
    }};
  }

  // =====================================================================
  // TOWN RATING & TREES
  // =====================================================================

  function CmdGetTownRating(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local town_id = p.town_id;
    if (!GSTown.IsValidTown(town_id)) return { success = false, error = "Invalid town ID" };

    local rating = GSTown.GetRating(town_id, GSCompany.ResolveCompanyID(GSCompany.COMPANY_SELF));
    return { success = true, result = {
      town_id = town_id,
      town_name = GSTown.GetName(town_id),
      rating = rating,
      rating_label = this.RatingLabel(rating)
    }};
  }

  function RatingLabel(r) {
    if (r >= 800) return "outstanding";
    if (r >= 600) return "good";
    if (r >= 400) return "mediocre";
    if (r >= 200) return "poor";
    if (r >= 0) return "appalling";
    return "hostile";
  }

  function CmdPlantTrees(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local cx = p.x;
    local cy = p.y;
    local radius = ("radius" in p) ? p.radius : 3;
    if (radius > 20) radius = 20;
    local planted = 0;
    local ops = 0;

    for (local dy = -radius; dy <= radius; dy++) {
      for (local dx = -radius; dx <= radius; dx++) {
        local tile = GSMap.GetTileIndex(cx + dx, cy + dy);
        if (GSMap.IsValidTile(tile) && GSTile.IsBuildable(tile) && !GSTile.HasTreeOnTile(tile)) {
          if (GSTile.PlantTree(tile)) planted++;
        }
        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    return { success = true, result = { planted = planted } };
  }

  // =====================================================================
  // STATION CARGO WAITING
  // =====================================================================

  function CmdGetStationCargo(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local station_id = p.station_id;

    if (!GSBaseStation.IsValidBaseStation(station_id)) {
      return { success = false, error = "Invalid station ID" };
    }

    local waiting = [];
    local cargo_list = GSCargoList();
    local cargo_ids = [];
    foreach (cid, _ in cargo_list) cargo_ids.append(cid);

    for (local i = 0; i < cargo_ids.len(); i++) {
      local cid = cargo_ids[i];
      local amount = GSStation.GetCargoWaiting(station_id, cid);
      if (amount > 0) {
        waiting.append({
          cargo_id = cid,
          cargo_name = GSCargo.GetName(cid),
          amount = amount,
          rating = GSStation.GetCargoRating(station_id, cid)
        });
      }
    }

    return { success = true, result = {
      station_id = station_id,
      station_name = GSBaseStation.GetName(station_id),
      cargo_waiting = waiting
    }};
  }

  // =====================================================================
  // LOAN MANAGEMENT
  // =====================================================================

  function CmdSetLoan(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local action = ("action" in p) ? p.action : "info";

    local current = GSCompany.GetLoanAmount();
    local max_loan = GSCompany.GetMaxLoanAmount();
    local interval = GSCompany.GetLoanInterval();

    if (action == "info") {
      return { success = true, result = {
        current_loan = current,
        max_loan = max_loan,
        loan_interval = interval
      }};
    }

    if (action == "repay") {
      local amount = ("amount" in p) ? p.amount : interval;
      local new_loan = current - amount;
      if (new_loan < 0) new_loan = 0;
      // Round to loan interval
      new_loan = (new_loan / interval) * interval;
      if (GSCompany.SetLoanAmount(new_loan)) {
        return { success = true, result = { new_loan = new_loan, repaid = current - new_loan } };
      }
      return { success = false, error = "Cannot repay - insufficient funds?" };
    }

    if (action == "borrow") {
      local amount = ("amount" in p) ? p.amount : interval;
      local new_loan = current + amount;
      if (new_loan > max_loan) new_loan = max_loan;
      new_loan = (new_loan / interval) * interval;
      if (GSCompany.SetLoanAmount(new_loan)) {
        return { success = true, result = { new_loan = new_loan, borrowed = new_loan - current } };
      }
      return { success = false, error = "Cannot borrow more" };
    }

    if (action == "repay_all") {
      if (GSCompany.SetLoanAmount(0)) {
        return { success = true, result = { new_loan = 0, repaid = current } };
      }
      return { success = false, error = "Cannot repay all - insufficient funds" };
    }

    return { success = false, error = "Unknown action. Use: info, repay, borrow, repay_all" };
  }

  function CmdGetDate() {
    local date = GSDate.GetCurrentDate();
    local year = GSDate.GetYear(date);
    local month = GSDate.GetMonth(date);
    local day = GSDate.GetDayOfMonth(date);
    return { success = true, result = {
      year = year,
      month = month,
      day = day,
      date_string = year + "-" +
        (month < 10 ? "0" : "") + month + "-" +
        (day < 10 ? "0" : "") + day
    }};
  }

  // =====================================================================
  // TERRAFORM
  // =====================================================================

  function CmdTerraform(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local x = p.x;
    local y = p.y;
    local action = ("action" in p) ? p.action : "level";
    local radius = ("radius" in p) ? p.radius : 0;
    if (radius > 20) radius = 20;
    local tile = GSMap.GetTileIndex(x, y);

    if (!GSMap.IsValidTile(tile)) return { success = false, error = "Invalid tile" };

    local modified = 0;
    local ops = 0;

    if (action == "raise") {
      for (local dy = -radius; dy <= radius; dy++) {
        for (local dx = -radius; dx <= radius; dx++) {
          local t = GSMap.GetTileIndex(x + dx, y + dy);
          if (GSMap.IsValidTile(t)) {
            if (GSTile.RaiseTile(t, GSTile.GetSlope(t))) modified++;
          }
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        }
      }
    } else if (action == "lower") {
      for (local dy = -radius; dy <= radius; dy++) {
        for (local dx = -radius; dx <= radius; dx++) {
          local t = GSMap.GetTileIndex(x + dx, y + dy);
          if (GSMap.IsValidTile(t)) {
            if (GSTile.LowerTile(t, GSTile.GetSlope(t))) modified++;
          }
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        }
      }
    } else if (action == "level") {
      local target_h = GSTile.GetMaxHeight(tile);
      for (local dy = -radius; dy <= radius; dy++) {
        for (local dx = -radius; dx <= radius; dx++) {
          local t = GSMap.GetTileIndex(x + dx, y + dy);
          if (!GSMap.IsValidTile(t)) continue;
          local h = GSTile.GetMaxHeight(t);
          local attempts = 0;
          while (h < target_h && attempts < 10) {
            if (!GSTile.RaiseTile(t, GSTile.GetSlope(t))) break;
            local new_h = GSTile.GetMaxHeight(t);
            if (new_h == h) break; // Height didn't change — stop
            h = new_h;
            modified++;
            attempts++;
          }
          attempts = 0;
          while (h > target_h && attempts < 10) {
            if (!GSTile.LowerTile(t, GSTile.GetSlope(t))) break;
            local new_h = GSTile.GetMaxHeight(t);
            if (new_h == h) break; // Height didn't change — stop
            h = new_h;
            modified++;
            attempts++;
          }
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        }
      }
    } else {
      return { success = false, error = "Unknown action. Use: raise, lower, level" };
    }

    return { success = true, result = { action = action, tiles_modified = modified } };
  }

  // =====================================================================
  // ROUTE PROFITABILITY ESTIMATOR
  // =====================================================================

  function CmdEstimateRouteProfit(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local from_x = p.from_x;
    local from_y = p.from_y;
    local to_x = p.to_x;
    local to_y = p.to_y;
    local cargo_id = ("cargo_id" in p) ? p.cargo_id : 1;
    local engine_id = ("engine_id" in p) ? p.engine_id : -1;

    local distance = abs(to_x - from_x) + abs(to_y - from_y);

    // Vehicle stats
    local capacity = 20;
    local speed = 48; // km/h default
    local running_cost = 421;
    local purchase_price = 4500;

    if (engine_id >= 0 && GSEngine.IsValidEngine(engine_id)) {
      capacity = GSEngine.GetCapacity(engine_id);
      speed = GSEngine.GetMaxSpeed(engine_id);
      running_cost = GSEngine.GetRunningCost(engine_id);
      purchase_price = GSEngine.GetPrice(engine_id);
    }

    // Estimate transit time
    // In OpenTTD, road vehicles at 48 km/h cover ~1 tile per 0.7 game days
    // Formula: days_per_tile ≈ 35 / speed (calibrated from gameplay)
    if (speed <= 0) speed = 1;
    local days_per_tile = 35.0 / speed;
    local days_transit = (distance * days_per_tile).tointeger();
    if (days_transit < 1) days_transit = 1;
    if (days_transit > 200) days_transit = 200;

    // Revenue per trip
    // GSCargo.GetCargoIncome returns income per 1 unit of cargo
    local income_per_unit = GSCargo.GetCargoIncome(cargo_id, distance, days_transit);
    local revenue_per_trip = income_per_unit * capacity;

    // Trips per year (365 days / round_trip_days)
    local round_trip_days = days_transit * 2 + 10; // +10 for loading time
    local trips_per_year = (365.0 / round_trip_days).tointeger();
    if (trips_per_year < 1) trips_per_year = 1;

    // Annual revenue and costs
    local annual_revenue = revenue_per_trip * trips_per_year;
    local annual_costs = running_cost; // running cost is per year
    local annual_profit = annual_revenue - annual_costs;

    return { success = true, result = {
      cargo = GSCargo.GetName(cargo_id),
      distance = distance,
      days_transit = days_transit,
      capacity = capacity,
      speed = speed,
      revenue_per_trip = revenue_per_trip,
      trips_per_year = trips_per_year,
      annual_revenue = annual_revenue,
      annual_running_cost = annual_costs,
      annual_profit = annual_profit,
      purchase_price = purchase_price,
      payback_months = annual_profit > 0 ? ((purchase_price * 12.0 / annual_profit).tointeger()) : -1,
      profitable = annual_profit > 0
    }};
  }

  // =====================================================================
  // COMPANY INFO
  // =====================================================================

  function CmdGetCompanyInfo(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local cid = GSCompany.ResolveCompanyID(GSCompany.COMPANY_SELF);

    return { success = true, result = {
      company_id = cid,
      name = GSCompany.GetName(cid),
      money = GSCompany.GetBankBalance(cid),
      loan = GSCompany.GetLoanAmount(),
      max_loan = GSCompany.GetMaxLoanAmount(),
      quarterly_income = GSCompany.GetQuarterlyIncome(cid, GSCompany.CURRENT_QUARTER),
      quarterly_expenses = GSCompany.GetQuarterlyExpenses(cid, GSCompany.CURRENT_QUARTER),
      company_value = GSCompany.GetQuarterlyCompanyValue(cid, GSCompany.CURRENT_QUARTER)
    }};
  }

  // =====================================================================
  // SUBSIDIES
  // =====================================================================

  function CmdGetSubsidies(p) {
    local subsidies = [];
    local sub_list = GSSubsidyList();
    local ids = [];
    foreach (sid, _ in sub_list) ids.append(sid);
    local ops = 0;

    for (local i = 0; i < ids.len(); i++) {
      local sid = ids[i];
      local is_awarded = GSSubsidy.IsAwarded(sid);
      local entry = {
        id = sid,
        is_awarded = is_awarded
      };

      if (is_awarded) {
        entry.rawset("awarded_to", GSSubsidy.GetAwardedTo(sid));
      }

      // Source and destination
      local src_type = GSSubsidy.GetSourceType(sid);
      local dst_type = GSSubsidy.GetDestinationType(sid);
      local src_id = GSSubsidy.GetSourceIndex(sid);
      local dst_id = GSSubsidy.GetDestinationIndex(sid);

      entry.rawset("cargo", GSCargo.GetName(GSSubsidy.GetCargoType(sid)));
      entry.rawset("cargo_id", GSSubsidy.GetCargoType(sid));

      // Source info
      if (src_type == GSSubsidy.SPT_INDUSTRY) {
        entry.rawset("source_type", "industry");
        entry.rawset("source_name", GSIndustry.GetName(src_id));
        entry.rawset("source_id", src_id);
      } else {
        entry.rawset("source_type", "town");
        entry.rawset("source_name", GSTown.GetName(src_id));
        entry.rawset("source_id", src_id);
      }

      // Destination info
      if (dst_type == GSSubsidy.SPT_INDUSTRY) {
        entry.rawset("dest_type", "industry");
        entry.rawset("dest_name", GSIndustry.GetName(dst_id));
        entry.rawset("dest_id", dst_id);
      } else {
        entry.rawset("dest_type", "town");
        entry.rawset("dest_name", GSTown.GetName(dst_id));
        entry.rawset("dest_id", dst_id);
      }

      subsidies.append(entry);
      if (subsidies.len() >= 5) break;
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = subsidies };
  }

  // =====================================================================
  // MAP OVERVIEW
  // =====================================================================

  function CmdGetMapOverview(p) {
    local company_id = ("company_id" in p) ? p.company_id : -1;

    // Date
    local date = GSDate.GetCurrentDate();
    local year = GSDate.GetYear(date);
    local month = GSDate.GetMonth(date);
    local day = GSDate.GetDayOfMonth(date);

    // Map size
    local map_x = GSMap.GetMapSizeX();
    local map_y = GSMap.GetMapSizeY();

    // Count towns and total population
    local town_list = GSTownList();
    local town_ids = [];
    foreach (tid, _ in town_list) town_ids.append(tid);
    local total_pop = 0;
    local ops = 0;
    for (local i = 0; i < town_ids.len(); i++) {
      total_pop += GSTown.GetPopulation(town_ids[i]);
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    // Count industries by type
    local ind_list = GSIndustryList();
    local ind_ids = [];
    foreach (iid, _ in ind_list) ind_ids.append(iid);
    local ind_types = {};
    for (local i = 0; i < ind_ids.len(); i++) {
      local type_name = GSIndustryType.GetName(GSIndustry.GetIndustryType(ind_ids[i]));
      if (type_name in ind_types) {
        ind_types[type_name]++;
      } else {
        ind_types[type_name] <- 1;
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    // Industry type counts as array (capped)
    local ind_summary = [];
    foreach (name, count in ind_types) {
      ind_summary.append({ type = name, count = count });
      if (ind_summary.len() >= 15) break;
    }

    // Subsidy count
    local sub_list = GSSubsidyList();
    local sub_count = 0;
    foreach (sid, _ in sub_list) sub_count++;

    // Company info (if specified)
    local company_info = null;
    if (company_id >= 0) {
      local cm = GSCompanyMode(company_id);
      local veh_list = GSVehicleList();
      local veh_count = 0;
      foreach (v, _ in veh_list) veh_count++;
      local stn_list = GSStationList(GSStation.STATION_ANY);
      local stn_count = 0;
      foreach (s, _ in stn_list) stn_count++;

      company_info = {
        money = GSCompany.GetBankBalance(GSCompany.COMPANY_SELF),
        loan = GSCompany.GetLoanAmount(),
        vehicles = veh_count,
        stations = stn_count
      };
    }

    local result = {
      date = year + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day,
      map_size = map_x + "x" + map_y,
      towns = town_ids.len(),
      total_population = total_pop,
      industries = ind_ids.len(),
      industry_types = ind_summary,
      subsidies = sub_count
    };

    if (company_info != null) {
      result.rawset("company", company_info);
    }

    return { success = true, result = result };
  }

  // =====================================================================
  // CARGO PAYMENT RATES
  // =====================================================================

  function CmdGetCargoPaymentRates(p) {
    local distance = ("distance" in p) ? p.distance : 50;
    local days_transit = ("days_transit" in p) ? p.days_transit : 30;

    local cargo_list = GSCargoList();
    local cargo_ids = [];
    foreach (cid, _ in cargo_list) cargo_ids.append(cid);

    local rates = [];
    local ops = 0;
    for (local i = 0; i < cargo_ids.len(); i++) {
      local cid = cargo_ids[i];
      local income = GSCargo.GetCargoIncome(cid, distance, days_transit);
      rates.append({
        cargo_id = cid,
        name = GSCargo.GetName(cid),
        income_per_unit = income,
        distance = distance,
        days_transit = days_transit
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    // Sort by income (simple bubble sort, small list)
    for (local i = 0; i < rates.len() - 1; i++) {
      for (local j = i + 1; j < rates.len(); j++) {
        if (rates[j].income_per_unit > rates[i].income_per_unit) {
          local tmp = rates[i]; rates[i] = rates[j]; rates[j] = tmp;
        }
      }
    }

    return { success = true, result = rates };
  }

  // =====================================================================
  // DIAGNOSTICS & FLEET MANAGEMENT
  // =====================================================================

  function CmdDiagnoseVehicles(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local veh_list = GSVehicleList();
    local ids = [];
    foreach (vid, _ in veh_list) ids.append(vid);

    local problems = [];
    local summary = { total = ids.len(), running = 0, loading = 0, stopped = 0, lost = 0, old = 0, unprofitable = 0, broken = 0 };
    local ops = 0;

    for (local i = 0; i < ids.len(); i++) {
      local vid = ids[i];
      local state = GSVehicle.GetState(vid);
      local speed = GSVehicle.GetCurrentSpeed(vid);
      local age = GSVehicle.GetAge(vid);
      local max_age = GSVehicle.GetMaxAge(vid);
      local profit_ly = GSVehicle.GetProfitLastYear(vid);
      local orders = GSOrder.GetOrderCount(vid);

      // Count states
      if (state == 0) summary.running++;
      else if (state == 3) summary.loading++;
      else if (state == 1 || state == 2) summary.stopped++;
      else if (state == 4) summary.broken++;

      // Detect problems
      local issue = null;

      if (state == 5) {
        issue = "CRASHED";
      } else if (state == 0 && speed == 0) {
        issue = "STUCK/LOST - cannot pathfind to destination";
        summary.lost++;
      } else if (orders < 2) {
        issue = "TOO_FEW_ORDERS - needs at least 2 orders for a route";
      } else if (age > max_age * 80 / 100) {
        issue = "AGING - past 80% lifespan, breakdowns increase";
        summary.old++;
      } else if (profit_ly < -500) {
        issue = "UNPROFITABLE - lost " + (-profit_ly) + " last year";
        summary.unprofitable++;
      } else if (state == 4) {
        issue = "BROKEN_DOWN - will auto-recover";
      }

      if (issue != null && problems.len() < 8) {
        local loc = GSVehicle.GetLocation(vid);
        problems.append({
          vehicle_id = vid,
          name = GSVehicle.GetName(vid),
          issue = issue,
          x = GSMap.GetTileX(loc),
          y = GSMap.GetTileY(loc)
        });
      }

      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = { summary = summary, problems = problems } };
  }

  function CmdFindRouteOpportunities(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local max_results = ("max_results" in p) ? p.max_results : 5;

    // Find industries not served by any station
    local ind_list = GSIndustryList();
    local ind_ids = [];
    foreach (iid, _ in ind_list) ind_ids.append(iid);

    local opportunities = [];
    local ops = 0;

    // Industry pair matching (source -> consumer)
    // Types: Coal Mine(0)->Power Plant(1), Farm(9)->Factory(6), Forest(3)->Sawmill(2),
    //        Iron Ore Mine(18)->Steel Mill(8), Oil Wells(11)->Oil Refinery(4)
    local pairs = [
      { src_type = 0, dst_type = 1, cargo = "Coal" },
      { src_type = 9, dst_type = 6, cargo = "Farm goods" },
      { src_type = 3, dst_type = 2, cargo = "Wood" },
      { src_type = 18, dst_type = 8, cargo = "Iron Ore" },
      { src_type = 11, dst_type = 4, cargo = "Oil" }
    ];

    for (local p_idx = 0; p_idx < pairs.len(); p_idx++) {
      local pair = pairs[p_idx];
      local sources = [];
      local dests = [];

      for (local i = 0; i < ind_ids.len(); i++) {
        local itype = GSIndustry.GetIndustryType(ind_ids[i]);
        if (itype == pair.src_type) sources.append(ind_ids[i]);
        else if (itype == pair.dst_type) dests.append(ind_ids[i]);
      }

      // Find closest unserved pairs
      for (local s = 0; s < sources.len() && opportunities.len() < max_results; s++) {
        local src = sources[s];
        local src_loc = GSIndustry.GetLocation(src);
        local src_x = GSMap.GetTileX(src_loc);
        local src_y = GSMap.GetTileY(src_loc);

        local best_dst = -1;
        local best_dist = 999999;

        for (local d = 0; d < dests.len(); d++) {
          local dst = dests[d];
          local dst_loc = GSIndustry.GetLocation(dst);
          local dist = abs(src_x - GSMap.GetTileX(dst_loc)) + abs(src_y - GSMap.GetTileY(dst_loc));
          if (dist < best_dist && dist > 20) { // min 20 tiles for profit
            best_dist = dist;
            best_dst = dst;
          }
          if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
        }

        if (best_dst >= 0 && best_dist < 150) {
          local dst_loc = GSIndustry.GetLocation(best_dst);
          opportunities.append({
            cargo = pair.cargo,
            source_id = src,
            source_name = GSIndustry.GetName(src),
            source_x = src_x,
            source_y = src_y,
            dest_id = best_dst,
            dest_name = GSIndustry.GetName(best_dst),
            dest_x = GSMap.GetTileX(dst_loc),
            dest_y = GSMap.GetTileY(dst_loc),
            distance = best_dist
          });
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    // Also find top unserved town pairs for bus routes
    local town_list = GSTownList();
    local town_ids = [];
    foreach (tid, _ in town_list) town_ids.append(tid);

    // Sort towns by population (simple selection of top 5)
    local big_towns = [];
    for (local i = 0; i < town_ids.len() && big_towns.len() < 10; i++) {
      local pop = GSTown.GetPopulation(town_ids[i]);
      if (pop >= 500) big_towns.append({ id = town_ids[i], pop = pop });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    // Find closest big town pairs
    for (local i = 0; i < big_towns.len() && opportunities.len() < max_results + 3; i++) {
      for (local j = i + 1; j < big_towns.len(); j++) {
        local a_loc = GSTown.GetLocation(big_towns[i].id);
        local b_loc = GSTown.GetLocation(big_towns[j].id);
        local dist = abs(GSMap.GetTileX(a_loc) - GSMap.GetTileX(b_loc)) + abs(GSMap.GetTileY(a_loc) - GSMap.GetTileY(b_loc));
        if (dist > 15 && dist < 80) {
          opportunities.append({
            cargo = "Passengers",
            source_id = big_towns[i].id,
            source_name = GSTown.GetName(big_towns[i].id),
            source_x = GSMap.GetTileX(a_loc),
            source_y = GSMap.GetTileY(a_loc),
            dest_id = big_towns[j].id,
            dest_name = GSTown.GetName(big_towns[j].id),
            dest_x = GSMap.GetTileX(b_loc),
            dest_y = GSMap.GetTileY(b_loc),
            distance = dist
          });
        }
      }
    }

    // Cap response
    if (opportunities.len() > 5) opportunities = opportunities.slice(0, 5);

    return { success = true, result = opportunities };
  }

  function CmdGetWaitingCargo(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local stn_list = GSStationList(GSStation.STATION_ANY);
    local stn_ids = [];
    foreach (sid, _ in stn_list) stn_ids.append(sid);

    local stations_with_cargo = [];
    local ops = 0;

    local cargo_list = GSCargoList();
    local cargo_ids = [];
    foreach (cid, _ in cargo_list) cargo_ids.append(cid);

    for (local i = 0; i < stn_ids.len(); i++) {
      local sid = stn_ids[i];
      local total_waiting = 0;
      local cargo_detail = [];

      for (local c = 0; c < cargo_ids.len(); c++) {
        local amount = GSStation.GetCargoWaiting(sid, cargo_ids[c]);
        if (amount > 0) {
          total_waiting += amount;
          if (cargo_detail.len() < 5) {
            cargo_detail.append({
              cargo = GSCargo.GetName(cargo_ids[c]),
              amount = amount
            });
          }
        }
      }

      if (total_waiting > 0 && stations_with_cargo.len() < 5) {
        stations_with_cargo.append({
          station_id = sid,
          station_name = GSBaseStation.GetName(sid),
          total_waiting = total_waiting,
          cargo = cargo_detail
        });
      }

      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    return { success = true, result = stations_with_cargo };
  }

  // =====================================================================
  // Auto-scaling: find stations with waiting cargo and vehicles serving them
  // =====================================================================
  function CmdAutoAddVehicles(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local max_add = ("max_add" in p) ? p.max_add : 3;

    // Find stations with significant waiting cargo
    local stn_list = GSStationList(GSStation.STATION_ANY);
    local stn_ids = [];
    foreach (sid, _ in stn_list) stn_ids.append(sid);

    local cargo_list = GSCargoList();
    local cargo_ids = [];
    foreach (cid, _ in cargo_list) cargo_ids.append(cid);

    local busy_stations = [];
    local ops = 0;

    for (local i = 0; i < stn_ids.len(); i++) {
      local sid = stn_ids[i];
      local total = 0;
      for (local c = 0; c < cargo_ids.len(); c++) {
        total += GSStation.GetCargoWaiting(sid, cargo_ids[c]);
      }
      if (total > 50) {
        busy_stations.append({ station_id = sid, waiting = total });
      }
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    // Find vehicles serving those stations and clone them
    local veh_list = GSVehicleList();
    local veh_ids = [];
    foreach (vid, _ in veh_list) veh_ids.append(vid);

    local added = 0;

    for (local s = 0; s < busy_stations.len() && added < max_add; s++) {
      local target_stn = busy_stations[s].station_id;

      // Find a vehicle that visits this station
      for (local v = 0; v < veh_ids.len() && added < max_add; v++) {
        local vid = veh_ids[v];
        local order_count = GSOrder.GetOrderCount(vid);
        local serves_station = false;

        for (local o = 0; o < order_count; o++) {
          local dest = GSOrder.GetOrderDestination(vid, o);
          if (GSStation.GetStationID(dest) == target_stn) {
            serves_station = true;
            break;
          }
        }

        if (serves_station && !GSVehicle.IsStoppedInDepot(vid)) {
          local engine = GSVehicle.GetEngineType(vid);
          busy_stations[s].rawset("vehicle_serving", vid);
          busy_stations[s].rawset("engine_id", engine);
          busy_stations[s].rawset("station_name", GSBaseStation.GetName(target_stn));
          break;
        }

        if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
      }
    }

    // Cap response
    if (busy_stations.len() > 10) busy_stations = busy_stations.slice(0, 10);

    return { success = true, result = {
      busy_stations = busy_stations,
      recommendation = "Buy more vehicles at the depot serving these stations"
    }};
  }

  // =====================================================================
  // Vehicle profit ranking
  // =====================================================================
  function CmdRankVehicles(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local veh_list = GSVehicleList();
    local ids = [];
    foreach (vid, _ in veh_list) ids.append(vid);

    local vehicles = [];
    local ops = 0;

    for (local i = 0; i < ids.len(); i++) {
      local vid = ids[i];
      vehicles.append({
        id = vid,
        name = GSVehicle.GetName(vid),
        profit_ly = GSVehicle.GetProfitLastYear(vid),
        profit_ty = GSVehicle.GetProfitThisYear(vid),
        age = GSVehicle.GetAge(vid)
      });
      if (++ops % this.YIELD_INTERVAL == 0) this.Sleep(1);
    }

    // Sort by last year profit descending (bubble sort, capped)
    for (local i = 0; i < vehicles.len() - 1 && i < 30; i++) {
      for (local j = i + 1; j < vehicles.len(); j++) {
        if (vehicles[j].profit_ly > vehicles[i].profit_ly) {
          local tmp = vehicles[i]; vehicles[i] = vehicles[j]; vehicles[j] = tmp;
        }
      }
    }

    // Cap to top 15
    if (vehicles.len() > 15) vehicles = vehicles.slice(0, 15);

    return { success = true, result = vehicles };
  }

  // =====================================================================
  // Remove station by demolishing its tile
  // =====================================================================
  function CmdRemoveStation(p) {
    if (!("company_id" in p)) return { success = false, error = "Missing required parameter: company_id" };
    local company_mode = GSCompanyMode(p.company_id);
    local x = p.x;
    local y = p.y;
    local tile = GSMap.GetTileIndex(x, y);

    if (GSTile.DemolishTile(tile)) {
      return { success = true, result = { x = x, y = y, removed = true } };
    }
    return { success = false, error = "Failed to remove: " + GSError.GetLastErrorString() };
  }

  function Save() { return {}; }
  function Load(version, data) {}
}

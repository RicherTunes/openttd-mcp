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

  function Start() {
    this.log_level = this.GetSetting("log_level");
    this.Log(1, "ClaudeMCP GameScript v3 started");

    // Main loop - process admin port events
    while (true) {
      this.HandleEvents();
      this.Sleep(1);
    }
  }

  function HandleEvents() {
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

      local result = this.DispatchCommand(data);
      this.SendResponse(data.id, result);
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

    try {
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

        // === Queries ===
        case "get_towns":           return this.CmdGetTowns();
        case "get_town_info":       return this.CmdGetTownInfo(params);
        case "get_industries":      return this.CmdGetIndustries();
        case "get_industry_info":   return this.CmdGetIndustryInfo(params);
        case "get_map_size":        return this.CmdGetMapSize();
        case "get_tile_info":       return this.CmdGetTileInfo(params);
        case "get_vehicles":        return this.CmdGetVehicles(params);
        case "get_stations":        return this.CmdGetStations(params);
        case "get_engines":         return this.CmdGetEngines(params);
        case "get_cargo_types":     return this.CmdGetCargoTypes();
        case "get_rail_types":      return this.CmdGetRailTypes();
        case "get_road_types":      return this.CmdGetRoadTypes();

        // === Smart Queries ===
        case "scan_town_area":      return this.CmdScanTownArea(params);
        case "find_bus_stop_spots": return this.CmdFindBusStopSpots(params);
        case "find_depot_spots":    return this.CmdFindDepotSpots(params);

        // === Rail Tools ===
        case "find_rail_station_spot": return this.CmdFindRailStationSpot(params);
        case "survey_line":            return this.CmdSurveyLine(params);
        case "survey_area":            return this.CmdSurveyArea(params);
        case "build_rail_line":        return this.CmdBuildRailLine(params);
        case "attach_wagon":           return this.CmdAttachWagon(params);

        // === Advanced Rail (A* Pathfinding) ===
        case "build_rail_route":        return this.CmdBuildRailRoute(params);
        case "build_signals_on_route":  return this.CmdBuildSignalsOnRoute(params);
        case "connect_towns_rail":      return this.CmdConnectTownsRail(params);

        default:
          return { success = false, error = "Unknown action: " + action };
      }
    } catch (e) {
      this.Log(1, "Error dispatching " + action + ": " + e);
      return { success = false, error = "Error: " + e };
    }
  }

  // =====================================================================
  // BUILDING COMMANDS
  // =====================================================================

  // BuildRail with 3-tile support: (prev, curr, next) or legacy (from, to)
  // 3-tile mode: prev_x/prev_y, x/y, next_x/next_y - builds rail AT (x,y)
  // Legacy mode: from_x/from_y, to_x/to_y - builds rail on BOTH tiles
  function CmdBuildRail(p) {
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
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    local direction = this.MapRailTrack(("direction" in p) ? p.direction : 0);
    local platforms = ("num_platforms" in p) ? p.num_platforms : 2;
    local length = ("platform_length" in p) ? p.platform_length : 5;

    GSRail.SetCurrentRailType(rail_type);

    if (GSRail.BuildRailStation(tile, direction, platforms, length, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y], platforms = platforms, length = length } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildRailDepot(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local rail_type = ("rail_type" in p) ? p.rail_type : 0;
    local front_dir = ("direction" in p) ? p.direction : 0;

    GSRail.SetCurrentRailType(rail_type);

    local front_tile = this.GetAdjacentTile(tile, front_dir);
    if (GSRail.BuildRailDepot(tile, front_tile)) {
      return { success = true, result = { tile = [p.x, p.y] } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildRailSignal(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local signal_type = ("signal_type" in p) ? p.signal_type : 0;

    if (GSRail.BuildSignal(tile, tile, signal_type)) {
      return { success = true, result = { tile = [p.x, p.y], signal_type = signal_type } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildRoad(p) {
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
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildRoadLine(p) {
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
        if (x + step == x2) break;
      }
    }

    // Auto-connect both endpoints to adjacent infrastructure
    local start_tile = GSMap.GetTileIndex(x1, y1);
    local end_tile = GSMap.GetTileIndex(x2, y2);
    local start_connected = this.AutoConnectRoad(start_tile);
    local end_connected = this.AutoConnectRoad(end_tile);

    return { success = true, result = {
      built = built, failed = failed, total = built + failed.len(),
      start_connected = start_connected, end_connected = end_connected
    }};
  }

  function CmdBuildRoadDepot(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local road_type = ("road_type" in p) ? p.road_type : 0;
    local front_dir = ("direction" in p) ? p.direction : 0;

    GSRoad.SetCurrentRoadType(road_type);

    local front_tile = this.GetAdjacentTile(tile, front_dir);
    if (GSRoad.BuildRoadDepot(tile, front_tile)) {
      local connected = this.AutoConnectRoad(tile);
      return { success = true, result = { tile = [p.x, p.y], connected_to = connected } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildRoadStop(p) {
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
      ok = GSRoad.BuildDriveThroughRoadStation(tile, front_tile, road_stop_type, GSStation.STATION_NEW);
    } else {
      ok = GSRoad.BuildRoadStation(tile, front_tile, road_stop_type, GSStation.STATION_NEW);
    }

    if (ok) {
      local connected = this.AutoConnectRoad(tile);
      return { success = true, result = { tile = [p.x, p.y], type = is_truck ? "truck" : "bus", connected_to = connected } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildAirport(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);
    local airport_type = ("airport_type" in p) ? p.airport_type : 0;

    if (GSAirport.BuildAirport(tile, airport_type, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y], type = airport_type } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildDock(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local tile = GSMap.GetTileIndex(p.x, p.y);

    if (GSMarine.BuildDock(tile, GSStation.STATION_NEW)) {
      return { success = true, result = { tile = [p.x, p.y] } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildBridge(p) {
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
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdBuildTunnel(p) {
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
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdDemolishTile(p) {
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
    local company_mode = GSCompanyMode(p.company_id);
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
    local company_mode = GSCompanyMode(p.company_id);
    if (GSVehicle.SellVehicle(p.vehicle_id)) {
      return { success = true, result = {} };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdStartVehicle(p) {
    local company_mode = GSCompanyMode(p.company_id);
    if (GSVehicle.StartStopVehicle(p.vehicle_id)) {
      return { success = true, result = { running = !GSVehicle.IsStoppedInDepot(p.vehicle_id) } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdStopVehicle(p) {
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
    local company_mode = GSCompanyMode(p.company_id);
    if (GSVehicle.SendVehicleToDepot(p.vehicle_id)) {
      return { success = true, result = {} };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdCloneVehicle(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local depot_tile = GSVehicle.GetLocation(p.vehicle_id);
    local share = ("share_orders" in p) ? p.share_orders : true;

    local clone_id = GSVehicle.CloneVehicle(depot_tile, p.vehicle_id, share);
    if (GSVehicle.IsValidVehicle(clone_id)) {
      return { success = true, result = { vehicle_id = clone_id, name = GSVehicle.GetName(clone_id) } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdRefitVehicle(p) {
    local company_mode = GSCompanyMode(p.company_id);
    if (GSVehicle.RefitVehicle(p.vehicle_id, p.cargo_id)) {
      return { success = true, result = {} };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  // =====================================================================
  // ORDER COMMANDS
  // =====================================================================

  function CmdAddOrder(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local flags = ("order_flags" in p) ? p.order_flags : 0;

    // GSOrder.AppendOrder expects a tile index, not a station ID
    // Convert station_id to tile location
    local dest = GSStation.GetLocation(p.station_id);
    if (!GSMap.IsValidTile(dest)) {
      return { success = false, error = "Invalid station_id " + p.station_id };
    }

    if (GSOrder.AppendOrder(p.vehicle_id, dest, flags)) {
      return { success = true, result = { order_count = GSOrder.GetOrderCount(p.vehicle_id) } };
    }
    return { success = false, error = GSError.GetLastErrorString() };
  }

  function CmdGetOrders(p) {
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

    return { success = true, result = { vehicle_id = vehicle_id, order_count = count, orders = orders } };
  }

  // =====================================================================
  // QUERY COMMANDS
  // =====================================================================

  function CmdGetTowns() {
    local towns = [];
    local town_list = GSTownList();

    foreach (town_id, _ in town_list) {
      local loc = GSTown.GetLocation(town_id);
      towns.append({
        id = town_id,
        name = GSTown.GetName(town_id),
        population = GSTown.GetPopulation(town_id),
        x = GSMap.GetTileX(loc),
        y = GSMap.GetTileY(loc)
      });
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

    foreach (ind_id, _ in ind_list) {
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
    foreach (cargo_id, _ in cargo_list) {
      local last_month = GSIndustry.GetLastMonthProduction(ind_id, cargo_id);
      if (last_month > 0) {
        produced.append({
          cargo_id = cargo_id,
          cargo_name = GSCargo.GetCargoLabel(cargo_id),
          last_month = last_month,
          transported = GSIndustry.GetLastMonthTransported(ind_id, cargo_id)
        });
      }
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
      owner = GSTile.GetOwner(tile)
    }};
  }

  function CmdGetVehicles(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local vehicles = [];
    local veh_list = GSVehicleList();

    foreach (veh_id, _ in veh_list) {
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
      vehicles.append({
        id = veh_id,
        name = GSVehicle.GetName(veh_id),
        type = GSVehicle.GetVehicleType(veh_id),
        x = GSMap.GetTileX(loc),
        y = GSMap.GetTileY(loc),
        engine_id = GSVehicle.GetEngineType(veh_id),
        age = GSVehicle.GetAge(veh_id),
        profit_this_year = GSVehicle.GetProfitThisYear(veh_id),
        profit_last_year = GSVehicle.GetProfitLastYear(veh_id),
        state = GSVehicle.GetState(veh_id),
        in_depot = GSVehicle.IsStoppedInDepot(veh_id),
        order_count = GSOrder.GetOrderCount(veh_id)
      });
    }

    return { success = true, result = vehicles };
  }

  function CmdGetStations(p) {
    local company_mode = GSCompanyMode(p.company_id);
    local stations = [];
    local stn_list = GSStationList(GSStation.STATION_ANY);

    foreach (stn_id, _ in stn_list) {
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
    foreach (eng_id, _ in eng_list) {
      if (!GSEngine.IsBuildable(eng_id)) continue;

      engines.append({
        id = eng_id,
        name = GSEngine.GetName(eng_id),
        cargo_type = GSEngine.GetCargoType(eng_id),
        capacity = GSEngine.GetCapacity(eng_id),
        max_speed = GSEngine.GetMaxSpeed(eng_id),
        price = GSEngine.GetPrice(eng_id),
        running_cost = GSEngine.GetRunningCost(eng_id),
        power = GSEngine.GetPower(eng_id),
        weight = GSEngine.GetWeight(eng_id),
        reliability = GSEngine.GetReliability(eng_id),
        is_wagon = GSEngine.IsWagon(eng_id)
      });
    }

    return { success = true, result = engines };
  }

  function CmdGetCargoTypes() {
    local cargos = [];
    local cargo_list = GSCargoList();

    foreach (cargo_id, _ in cargo_list) {
      cargos.append({
        id = cargo_id,
        label = GSCargo.GetCargoLabel(cargo_id),
        name = GSCargo.GetName(cargo_id),
        is_freight = GSCargo.IsFreight(cargo_id)
      });
    }

    return { success = true, result = cargos };
  }

  function CmdGetRailTypes() {
    local types = [];
    local rail_list = GSRailTypeList();

    foreach (rail_type, _ in rail_list) {
      types.append({
        id = rail_type,
        name = GSRail.GetName(rail_type)
      });
    }

    return { success = true, result = types };
  }

  function CmdGetRoadTypes() {
    local types = [];
    local road_list = GSRoadTypeList(GSRoad.ROADTRAMTYPES_ROAD);

    foreach (road_type, _ in road_list) {
      types.append({
        id = road_type,
        name = GSRoad.GetName(road_type),
        is_road = true
      });
    }

    local tram_list = GSRoadTypeList(GSRoad.ROADTRAMTYPES_TRAM);
    foreach (tram_type, _ in tram_list) {
      types.append({
        id = tram_type,
        name = GSRoad.GetName(tram_type),
        is_road = false
      });
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
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local buildable = [];
    local roads = [];
    local buildings = [];
    local water = [];

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
          // Not water, not road, not buildable = building/structure
          buildings.append({ x = x, y = y });
        }
      }
    }

    return { success = true, result = {
      town_name = GSTown.GetName(town_id),
      center_x = cx, center_y = cy,
      radius = radius,
      buildable = buildable,
      roads = roads,
      buildings = buildings,
      water = water,
      counts = {
        buildable = buildable.len(),
        roads = roads.len(),
        buildings = buildings.len(),
        water = water.len()
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
    local max_results = ("max_results" in p) ? p.max_results : 10;
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local spots = [];

    for (local dy = -radius; dy <= radius; dy++) {
      for (local dx = -radius; dx <= radius; dx++) {
        local x = cx + dx;
        local y = cy + dy;
        local tile = GSMap.GetTileIndex(x, y);
        if (!GSMap.IsValidTile(tile)) continue;
        if (!GSTile.IsBuildable(tile)) continue;

        local adj = this.GetAdjacentRoads(x, y);
        if (adj.len() == 0) continue;

        local dist = abs(dx) + abs(dy);  // Manhattan distance
        spots.append({
          x = x, y = y,
          distance = dist,
          adjacent_road_x = adj[0].nx,
          adjacent_road_y = adj[0].ny,
          adjacent_road_count = adj.len()
        });
      }
    }

    // Sort by distance (insertion sort - Squirrel has no built-in sort)
    for (local i = 1; i < spots.len(); i++) {
      local key = spots[i];
      local j = i - 1;
      while (j >= 0 && spots[j].distance > key.distance) {
        spots[j + 1] = spots[j];
        j--;
      }
      spots[j + 1] = key;
    }

    // Trim to max_results
    if (spots.len() > max_results) {
      spots = spots.slice(0, max_results);
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
    local max_results = ("max_results" in p) ? p.max_results : 5;
    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local spots = [];

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
        spots.append({
          x = x, y = y,
          distance = dist,
          adjacent_road_x = adj[0].nx,
          adjacent_road_y = adj[0].ny,
          depot_direction = adj[0].dir
        });
      }
    }

    // Sort by distance
    for (local i = 1; i < spots.len(); i++) {
      local key = spots[i];
      local j = i - 1;
      while (j >= 0 && spots[j].distance > key.distance) {
        spots[j + 1] = spots[j];
        j--;
      }
      spots[j + 1] = key;
    }

    if (spots.len() > max_results) {
      spots = spots.slice(0, max_results);
    }

    return { success = true, result = spots };
  }

  // =====================================================================
  // WAGON MANAGEMENT
  // =====================================================================

  function CmdAttachWagon(p) {
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
    local max_results = ("max_results" in p) ? p.max_results : 5;

    local loc = GSTown.GetLocation(town_id);
    local cx = GSMap.GetTileX(loc);
    local cy = GSMap.GetTileY(loc);

    local candidates = [];

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
            }
          }

          if (ok) {
            local dist = abs(dx + w / 2) + abs(dy + h / 2);
            candidates.append({
              x = sx, y = sy,
              direction = dir,
              distance = dist,
              elevation = base_h
            });
          }
        }
      }
    }

    // Sort by distance
    for (local i = 1; i < candidates.len(); i++) {
      local key = candidates[i];
      local j = i - 1;
      while (j >= 0 && candidates[j].distance > key.distance) {
        candidates[j + 1] = candidates[j];
        j--;
      }
      candidates[j + 1] = key;
    }

    if (candidates.len() > max_results) {
      candidates = candidates.slice(0, max_results);
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
    if (w > 50 || h > 50) {
      return { success = false, error = "Max 50x50 area" };
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
    foreach (tid, _ in town_list) {
      local loc = GSTown.GetLocation(tid);
      local tx = GSMap.GetTileX(loc);
      local ty = GSMap.GetTileY(loc);
      if (tx >= x1 && tx <= x2 && ty >= y1 && ty <= y2) {
        town_tiles[tx + "_" + ty] <- tid;
      }
    }

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
   * build_rail_line: Build rail track along a straight line.
   * Returns count of built segments and list of failures.
   */
  function CmdBuildRailLine(p) {
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

        if (x == x2) break;
      }
    }

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

    // Reconstruct path
    local path = [];
    local key = found_key;
    while (key != -1) {
      path.insert(0, state_info[key]);
      key = came_from[key];
    }

    // Build rail along path
    local built = 0;
    local failures = [];

    for (local i = 0; i < path.len(); i++) {
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
    local company_mode = GSCompanyMode(p.company_id);
    local path = p.path;
    local signal_type = ("signal_type" in p) ? p.signal_type : 5;  // one-way path signal
    local interval = ("interval" in p) ? p.interval : 5;

    local placed = 0;
    local failures = [];

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
    }

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

    for (local dy = -max_dist; dy <= max_dist; dy++) {
      for (local dx = -max_dist; dx <= max_dist; dx++) {
        local bx = cx + dx;
        local by = cy + dy;

        // Try both directions
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

    // Step 2: Build stations (convert MCP dir 0/1 to GS RailTrack enum)
    local sta_tile = GSMap.GetTileIndex(spot_a.x, spot_a.y);
    if (!GSRail.BuildRailStation(sta_tile, this.MapRailTrack(spot_a.dir), num_plat, plat_len, GSStation.STATION_NEW)) {
      return { success = false, error = "Station A failed: " + GSError.GetLastErrorString() };
    }

    local stb_tile = GSMap.GetTileIndex(spot_b.x, spot_b.y);
    if (!GSRail.BuildRailStation(stb_tile, this.MapRailTrack(spot_b.dir), num_plat, plat_len, GSStation.STATION_NEW)) {
      return { success = false, error = "Station B failed: " + GSError.GetLastErrorString() };
    }

    // Step 3: Calculate connection points (station edges facing each other)
    local town_b_loc = GSTown.GetLocation(town_b);
    local conn_a = this.GetStationConnectionPoint(spot_a, plat_len, num_plat,
      GSMap.GetTileX(town_b_loc), GSMap.GetTileY(town_b_loc));

    local town_a_loc = GSTown.GetLocation(town_a);
    local conn_b = this.GetStationConnectionPoint(spot_b, plat_len, num_plat,
      GSMap.GetTileX(town_a_loc), GSMap.GetTileY(town_a_loc));

    result.connection_a <- conn_a;
    result.connection_b <- conn_b;

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
                GSVehicle.BuildVehicle(depot_tile, p.wagon_id);
                wagons_built++;
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

  function Log(level, msg) {
    if (level <= this.log_level) {
      GSLog.Info("[ClaudeMCP] " + msg);
    }
  }

  function Save() { return {}; }
  function Load(version, data) {}
}

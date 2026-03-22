# Monitor Game — Continuous Status Loop

Poll the game state periodically and report issues. Use the `/loop` skill to run this on an interval.

## What to Check

1. **Vehicle Diagnostics** (primary check): `diagnose_vehicles(company_id=0)` — automatically detects all vehicle problems:
   - STUCK/LOST vehicles (speed=0, state=0)
   - Crashed vehicles
   - Broken down vehicles
   - Aging vehicles needing replacement
   - Unprofitable vehicles
   - Vehicles with too few orders
   This replaces manual `get_vehicles` analysis.
2. **Cargo Bottlenecks**: `get_waiting_cargo(company_id=0)` — find stations where cargo is piling up. If waiting cargo > 100, that route needs more vehicles.
3. **Financial Health**: `get_company_info(company_id=0)` — comprehensive financial overview including money, loan, income, and company stats.
4. **Game Alerts**: `get_alerts()` — check for game-generated warnings, notifications, and important events.
5. **Cargo delivery**: If `deliveredCargo` stays at 0 for multiple checks, something is wrong
6. **Date**: `get_game_date` to track time progression
7. **Game status**: Use `get_game_status` to get an overview of game state including paused status
8. **Area inspection**: Use `get_tile_range` to inspect a range of tiles when investigating stuck vehicles or infrastructure issues

## Vehicle States Reference
| State | Meaning |
|-------|---------|
| 0 | Running (moving or pathfinding) |
| 1 | Stopped manually |
| 2 | In depot |
| 3 | At station (loading/unloading) |
| 4 | Broken down |
| 5 | Crashed |

## How to Detect "Lost" Vehicles

The OpenTTD API does NOT expose a "lost" flag. To detect lost vehicles:
- Track vehicle positions across polls
- If a vehicle with state=0 (running) hasn't changed position significantly over 2+ checks, it's likely stuck or lost
- A vehicle bouncing between two nearby positions might be circling without reaching its destination
- **speed=0 + state=0 means STUCK/LOST**: The vehicle cannot pathfind to its next order
- **cargo_loaded > 0 but never delivering**: The destination stop is inaccessible (rebuild as drive-through)

## Quick Check Command

Run these MCP tools in sequence (NOT in parallel — they go through the GameScript queue):
1. `diagnose_vehicles(company_id=0)` — primary vehicle health check
2. `get_waiting_cargo(company_id=0)` — cargo bottleneck detection
3. `get_company_info(company_id=0)` — financial health
4. `get_alerts()` — game notifications
5. Report: vehicle problems, cargo bottlenecks, financial status, any alerts

## Recommended Interval

Use `/loop 2m /monitor` to check every 2 minutes.

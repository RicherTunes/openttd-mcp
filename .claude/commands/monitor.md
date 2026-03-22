# Monitor Game — Continuous Status Loop

Poll the game state periodically and report issues. Use the `/loop` skill to run this on an interval.

## What to Check

1. **Finances**: `get_company_economy` — alert if money < 10,000 or income trending negative
2. **Vehicles**: `get_vehicles` — check each vehicle:
   - state=5 (crashed) -> alert immediately
   - state=4 (broken) -> note, will self-recover
   - speed=0 + state=0 -> STUCK/LOST — vehicle is "running" but can't move. Likely a bay stop issue or road disconnection. Rebuild stop as drive-through.
   - cargo_loaded > 0 but never delivering -> destination stop inaccessible
   - profit_this_year strongly negative -> route may be unprofitable
   - Same position as last check -> vehicle might be stuck/lost
3. **Cargo delivery**: If `deliveredCargo` stays at 0 for multiple checks, something is wrong
4. **Date**: `get_game_date` to track time progression
5. **Alerts**: Use `get_alerts` to check for any game-generated warnings or notifications
6. **Game status**: Use `get_game_status` to get an overview of game state including paused status
7. **Area inspection**: Use `get_tile_range` to inspect a range of tiles when investigating stuck vehicles or infrastructure issues

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
1. `get_company_economy(company_id=0)`
2. `get_vehicles(company_id=0)`
3. Report: money, income trend, vehicle states, any issues

## Recommended Interval

Use `/loop 2m /monitor` to check every 2 minutes.

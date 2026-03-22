# Monitor Game — Continuous Status Loop

Poll the game state periodically and report issues. Use the `/loop` skill to run this on an interval.

## What to Check

1. **Finances**: `get_company_economy` — alert if money < 10,000 or income trending negative
2. **Vehicles**: `get_vehicles` — check each vehicle:
   - state=5 (crashed) → alert immediately
   - state=4 (broken) → note, will self-recover
   - profit_this_year strongly negative → route may be unprofitable
   - Same position as last check → vehicle might be stuck/lost
3. **Cargo delivery**: If `deliveredCargo` stays at 0 for multiple checks, something is wrong
4. **Date**: `get_game_date` to track time progression

## How to Detect "Lost" Vehicles

The OpenTTD API does NOT expose a "lost" flag. To detect lost vehicles:
- Track vehicle positions across polls
- If a vehicle with state=0 (running) hasn't changed position significantly over 2+ checks, it's likely stuck or lost
- A vehicle bouncing between two nearby positions might be circling without reaching its destination

## Quick Check Command

Run these MCP tools in sequence (NOT in parallel — they go through the GameScript queue):
1. `get_company_economy(company_id=0)`
2. `get_vehicles(company_id=0)`
3. Report: money, income trend, vehicle states, any issues

## Recommended Interval

Use `/loop 2m /monitor` to check every 2 minutes.

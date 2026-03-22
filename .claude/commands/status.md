# OpenTTD Game Status

Check the current state of the game and provide a strategic overview.

## Steps

1. **Connection check**: Use `get_connection_status` to verify we're connected.
2. **Map Overview** (primary status tool): Use `get_map_overview(company_id=0)` to get an instant snapshot — date, money, towns, industries, fleet size, and overall game state in one call.
3. **Vehicle Health**: Use `diagnose_vehicles(company_id=0)` to check for stuck, lost, aging, or unprofitable vehicles. This replaces manual `get_vehicles` analysis.
4. **Finances**: Use `get_company_info(company_id=0)` for detailed financial health — money, loan, income, and company stats.
5. **Stations**: Use `get_stations` to see all our infrastructure.
6. **Analysis**: Provide a summary with:
   - Current year and cash position
   - Profitable vs unprofitable routes
   - Vehicle problems diagnosed (stuck, lost, aging, unprofitable)
   - Recommendations for next moves (new routes, more vehicles on profitable routes, etc.)

## Vehicle States Reference
| State | Meaning |
|-------|---------|
| 0 | Running (moving or pathfinding) |
| 1 | Stopped manually |
| 2 | In depot |
| 3 | At station (loading/unloading) |
| 4 | Broken down |
| 5 | Crashed |

## Diagnosing Vehicle Problems

Use `diagnose_vehicles(company_id=0)` as the primary diagnostic tool. It automatically detects:
- **STUCK/LOST**: speed=0 + state=0. Fix: rebuild stop as drive-through on a straight road segment.
- **TOO_FEW_ORDERS**: Vehicle doesn't have enough orders to run a route.
- **AGING**: Vehicle is old and losing reliability. Use `replace_old_vehicles` to swap them out.
- **UNPROFITABLE**: Route may be too short or vehicle is circling. Route optimization needed.
- **CRASHED**: Immediate attention required.

Manual fallback checks:
- **cargo_loaded > 0 but never delivering = stop inaccessible**: The vehicle loaded cargo but can't reach the destination stop. Check that the destination is a drive-through stop on a connected road.
- If `deliveredCargo` is 0 across quarters, no routes are completing successfully.

## Strategy Tips

- Towns with population > 1000 are best for passenger routes
- Coal mine -> Power plant and Farm -> Factory are the most reliable early-game cargo routes
- Distance matters: 30-80 tiles is ideal for road vehicles (too short = low payment, too long = slow)
- ALWAYS use drive-through stops (`is_drive_through=true`) — regular bay stops are unreliable

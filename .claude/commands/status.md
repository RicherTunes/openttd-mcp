# OpenTTD Game Status

Check the current state of the game and provide a strategic overview.

## Steps

1. **Connection check**: Use `get_connection_status` to verify we're connected.
2. **Date and finances**: Use `get_game_date` and `get_company_economy` to check the current year and financial health.
3. **Vehicle fleet**: Use `get_vehicles` to list all vehicles with their profit/loss and state.
4. **Stations**: Use `get_stations` to see all our infrastructure.
5. **Analysis**: Provide a summary with:
   - Current year and cash position
   - Profitable vs unprofitable routes
   - Lost or broken vehicles that need attention
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

- **speed=0 + state=0 means STUCK/LOST**: The vehicle is "running" but not moving. It cannot find a path to its destination. Common cause: bay stop with wrong direction, or road disconnection. Fix: rebuild stop as drive-through on a straight road segment.
- **cargo_loaded > 0 but never delivering = stop inaccessible**: The vehicle loaded cargo but can't reach the destination stop. Check that the destination is a drive-through stop on a connected road.
- Vehicles with negative profit need route optimization.
- If `deliveredCargo` is 0 across quarters, no routes are completing successfully.

## Strategy Tips

- Towns with population > 1000 are best for passenger routes
- Coal mine -> Power plant and Farm -> Factory are the most reliable early-game cargo routes
- Distance matters: 30-80 tiles is ideal for road vehicles (too short = low payment, too long = slow)
- ALWAYS use drive-through stops (`is_drive_through=true`) — regular bay stops are unreliable

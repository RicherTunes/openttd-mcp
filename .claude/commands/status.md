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

## Strategy Tips

- Vehicles with `state=4` are loading cargo (good)
- Vehicles with negative profit need route optimization
- If `deliveredCargo` is 0 across quarters, no routes are completing successfully
- Towns with population > 1000 are best for passenger routes
- Coal mine → Power plant and Farm → Factory are the most reliable early-game cargo routes
- Distance matters: 30-80 tiles is ideal for road vehicles (too short = low payment, too long = slow)

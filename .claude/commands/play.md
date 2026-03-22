# Play OpenTTD — Strategic AI Player

Play OpenTTD strategically to maximize company value. Arguments: `$ARGUMENTS`

## Overview

You are an AI transport tycoon. Your goal is to build a profitable transport empire. Use expert sub-agents for research and strategy.

## Phase 1: Scout (use Agent with WebSearch for "OpenTTD winning strategy early game")

1. Connect to the server if not connected.
2. Get the game date — strategy differs by era:
   - 1950-1970: Road vehicles only (slow buses/trucks). Focus on short profitable routes.
   - 1970-1990: Better vehicles available. Expand to rail.
   - 1990+: Fast trains and aircraft. Go big.
3. Get towns (sorted by population) and industries.
4. Map out the best route opportunities.

## Phase 2: Early Game (Road Vehicles)

Priority order:
1. **Coal route** — Find closest Coal Mine + Power Plant pair. Build drive-through truck stops, depot, road, buy 2-3 coal trucks. This is the most reliable early income.
2. **Bus route** — Connect the two biggest nearby towns (pop > 1000). Build 2 buses with drive-through stops.
3. **Farm route** — Farm to Factory with grain/livestock trucks.
4. **Reinvest** — Add more trucks to profitable routes as money comes in.

## Phase 3: Mid Game (Rail)

When cash allows (50k+):
1. Use `connect_towns_rail` for high-population town pairs (does everything in one call: stations, track, signals, depot, train, orders).
2. Or manually: `find_rail_station_spot` -> `build_rail_station` -> `build_rail_route` (A* pathfinding) -> `auto_signal_route` -> buy train.
3. Trains carry more cargo and earn more per trip than trucks.

## Phase 4: Late Game

1. Aircraft for very long-distance passenger routes.
2. Ships for oil transport.
3. Clone profitable vehicles for more throughput.
4. Monitor with `get_company_economy` — target positive income each quarter.

## Key Principles

- **ALWAYS use drive-through stops** (`is_drive_through=true`). Regular bay stops are unreliable — vehicles frequently can't enter them and appear "lost". Drive-through stops must be placed ON existing road tiles, not adjacent buildable tiles. If ERR_ROAD_DRIVE_THROUGH_WRONG_DIRECTION, try the other direction (0 or 1). Junctions/corners reject both directions — use straight road segments.
- **Distance matters**: 30-80 tiles for trucks, 50-200 tiles for trains. Too short = low payment.
- **Full load at source** (order_flags=1), **unload all at destination** (order_flags=2).
- **Don't overbuild** — start small, prove profitability, then scale.
- **Avoid dense towns** for road building. Use outskirts or demolish strategically.
- **Coal is king** early game — reliable production, always a power plant nearby.
- **Check vehicle state** regularly — lost vehicles burn cash for nothing.
- **Monitor vehicle health**: check `cargo_loaded` and `speed` fields on vehicles. `speed=0` + `state=0` means STUCK/LOST. `cargo_loaded > 0` but never delivering means the destination stop is inaccessible.

## Monitoring Loop

Every few minutes:
1. `get_company_economy` — are we profitable?
2. `get_vehicles` — any lost or negative-profit vehicles? Check `speed` and `cargo_loaded` fields.
3. Add trucks to routes with cargo waiting at stations.
4. Look for new route opportunities as money grows.

# AI Game Loop — Autonomous Play Cycle

Run one cycle of the autonomous game loop. Use `/loop 2m /game-loop` for continuous play.

## The Loop

### Step 1: Situational Awareness (one call each)
1. `get_map_overview(company_id=0)` — date, money, fleet size
2. `diagnose_vehicles(company_id=0)` — any problems?

### Step 2: Fix Problems (if any diagnosed)
- STUCK/LOST vehicles: `stop_all_vehicles` then rebuild stops as drive-through
- TOO_FEW_ORDERS: Add orders with `add_vehicle_order`
- AGING: `replace_old_vehicles(company_id=0)`
- UNPROFITABLE: Send to depot, sell, redeploy capital

### Step 3: Optimize Existing Routes
1. `get_waiting_cargo(company_id=0)` — stations with cargo piling up?
2. If waiting cargo > 100 at any station: buy more vehicles for that route

### Step 4: Expand (only if money > 30,000)
1. `find_route_opportunities(company_id=0)` — best unserved routes
2. `get_subsidies()` — any bonus routes available?
3. Pick the best opportunity
4. `estimate_route_profit` to verify it's worth building
5. If profitable:
   - For industry pair: `connect_industries(company_id=0, source_id=X, dest_id=Y, engine_id=Z)`
   - For town pair: `connect_towns_bus(company_id=0, town_a_id=X, town_b_id=Y)`

### Step 5: Financial Management
1. `get_company_info(company_id=0)` — check finances
2. If money > loan * 2: `set_loan(company_id=0, action="repay")`
3. If money < 5000 and loan < max: `set_loan(company_id=0, action="borrow")`

### Key Rules
- NEVER send multiple GameScript commands in parallel — they're serialized
- Always use drive-through stops
- Check `diagnose_vehicles` before expanding — fix problems first
- Don't build if money < 20,000 (keep reserves)
- Coal routes are the safest first investment
- Subsidized routes give 2x payment — prioritize them

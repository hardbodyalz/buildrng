--[[
	FlowField
	Deterministic enemy routing. A Dijkstra pass from the Core outward gives
	every cell its cheapest cost-to-Core. Walking into a cell costs 1, plus
	(structure HP * costPerHp * costMult) if a blocking structure stands there.

	This is what lets players *design* a route: walls don't make the path
	impossible (everything can be smashed), they make detours cheaper than
	smashing, so enemies walk the maze you built. Enemies that are
	`PathCostMult < 1` (brutes, enraged bosses) value smashing more.

	Shared so the client can draw the predicted route in Build Mode.
]]

local Grid = require(script.Parent.Grid)
local BinaryHeap = require(script.Parent.BinaryHeap)

export type Field = {
	Region: Grid.Region,
	Dist: { [number]: number },
	Cost: { [number]: number },
}

local FlowField = {}

-- Neighbour order doubles as the deterministic tie-break (toward the Core first).
local DIRS = { { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }

-- blockers: cellKey -> current HP of the blocking structure on that cell
function FlowField.Compute(region: Grid.Region, blockers: { [number]: number }, costPerHp: number, costMult: number?): Field
	local mult = costMult or 1
	local dist: { [number]: number } = {}
	local cost: { [number]: number } = {}

	for x = region.MinX, region.MaxX do
		for z = region.MinZ, region.MaxZ do
			local key = Grid.Key(x, z)
			local hp = blockers[key]
			cost[key] = if hp then 1 + hp * costPerHp * mult else 1
		end
	end

	local heap = BinaryHeap.new()
	for _, c in Grid.CoreCells() do
		local key = Grid.Key(c[1], c[2])
		dist[key] = 0
		heap:Push(key, 0)
	end

	while not heap:IsEmpty() do
		local key, d = heap:Pop()
		if d <= (dist[key] or math.huge) then
			local x, z = Grid.FromKey(key)
			local step = cost[key]
			for _, dir in DIRS do
				local nx, nz = x + dir[1], z + dir[2]
				if Grid.InRegion(region, nx, nz) then
					local nkey = Grid.Key(nx, nz)
					local nd = d + step
					if nd < (dist[nkey] or math.huge) then
						dist[nkey] = nd
						heap:Push(nkey, nd)
					end
				end
			end
		end
	end

	return { Region = region, Dist = dist, Cost = cost }
end

-- Best next cell from (x, z). dirX/dirZ = current heading, preferred on ties so
-- enemies walk straight lines instead of zig-zagging.
function FlowField.NextCell(field: Field, x: number, z: number, dirX: number?, dirZ: number?): (number?, number?)
	local best, bestX, bestZ = math.huge, nil, nil
	local region = field.Region
	for _, dir in DIRS do
		local nx, nz = x + dir[1], z + dir[2]
		if Grid.InRegion(region, nx, nz) then
			local nkey = Grid.Key(nx, nz)
			local d = field.Dist[nkey]
			if d then
				local score = d + field.Cost[nkey]
				if dir[1] == dirX and dir[2] == dirZ then
					score -= 1e-6
				end
				if score < best then
					best, bestX, bestZ = score, nx, nz
				end
			end
		end
	end
	return bestX, bestZ
end

-- Full predicted route from (sx, sz) to the Core. Returns ordered cells and a key set.
function FlowField.Path(field: Field, sx: number, sz: number): ({ { number } }, { [number]: boolean })
	local cells = { { sx, sz } }
	local set = { [Grid.Key(sx, sz)] = true }
	local x, z = sx, sz
	local dx, dz = 0, 1
	for _ = 1, 2000 do
		if Grid.IsCore(x, z) then
			break
		end
		local nx, nz = FlowField.NextCell(field, x, z, dx, dz)
		if not nx or not nz then
			break
		end
		dx, dz = nx - x, nz - z
		x, z = nx, nz
		table.insert(cells, { x, z })
		set[Grid.Key(x, z)] = true
	end
	return cells, set
end

return FlowField

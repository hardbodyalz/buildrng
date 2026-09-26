local Items = require(Shared.Config.Items)
local Grid = require(Shared.Util.Grid)
local FlowField = require(Shared.Util.FlowField)

local region = Grid.Region(1)

test("region 1 is centred and ends at the core", function()
	checkEq(region.MaxZ, Grid.MaxLength - 1)
	checkEq(region.MaxX - region.MinX + 1, 7)
	checkEq(region.MaxZ - region.MinZ + 1, 11)
	check(Grid.IsCore(Grid.CenterX, Grid.MaxLength - 1))
end)

test("footprint rotation swaps dims", function()
	local wall = Items.Get("stone_wall")
	local w, d = Grid.Footprint(wall, 0)
	checkEq(w, 3); checkEq(d, 1)
	w, d = Grid.Footprint(wall, 1)
	checkEq(w, 1); checkEq(d, 3)
end)

test("placement validation", function()
	local turret = Items.Get("scrap_turret")
	local q = { Region = region, Occupancy = {}, Def = turret, X = region.MinX, Z = region.MinZ + 2, Rot = 0, PlacedCount = 0, Capacity = 10 }
	checkEq(Grid.CheckPlacement(q), "Valid")
	q.X = region.MinX - 1
	checkEq(Grid.CheckPlacement(q), "Invalid")
	q.X, q.Z = Grid.CenterX, region.MinZ
	checkEq(Grid.CheckPlacement(q), "Invalid", "entrance")
	q.X, q.Z = Grid.CenterX, Grid.CoreMinZ
	checkEq(Grid.CheckPlacement(q), "Invalid", "core")
	q.X, q.Z = region.MinX, region.MinZ + 2
	q.Occupancy = { [Grid.Key(q.X, q.Z)] = "s1" }
	checkEq(Grid.CheckPlacement(q), "Invalid", "overlap")
	q.Occupancy = {}
	q.PlacedCount = 10
	checkEq(Grid.CheckPlacement(q), "Invalid", "capacity")
	q.IsMove = true
	checkEq(Grid.CheckPlacement(q), "Valid", "moves ignore capacity")
end)

test("trap off the path warns", function()
	local trap = Items.Get("spike_trap")
	local field = FlowField.Compute(region, {}, 1 / 25)
	local sx, sz = Grid.Entrance(region)
	local _, set = FlowField.Path(field, sx, sz)
	local q = { Region = region, Occupancy = {}, Def = trap, X = region.MinX, Z = region.MinZ + 3, Rot = 0, PlacedCount = 0, Capacity = 10, PathCells = set }
	checkEq(Grid.CheckPlacement(q), "Warning")
	q.X = Grid.CenterX
	checkEq(Grid.CheckPlacement(q), "Valid")
end)

test("empty field path goes straight to core", function()
	local field = FlowField.Compute(region, {}, 1 / 25)
	local sx, sz = Grid.Entrance(region)
	local cells = FlowField.Path(field, sx, sz)
	local last = cells[#cells]
	check(Grid.IsCore(last[1], last[2]))
	checkEq(#cells, Grid.CoreMinZ - region.MinZ + 1)
	for _, c in cells do checkEq(c[1], Grid.CenterX) end
end)

test("cheap walls cause a detour, strong walls get smashed through less often", function()
	-- full-width line of walls with one gap at the far left
	local blockers = {}
	local z = region.MinZ + 4
	for x = region.MinX + 1, region.MaxX do
		blockers[Grid.Key(x, z)] = 700
	end
	local field = FlowField.Compute(region, blockers, 1 / 25)
	local sx, sz = Grid.Entrance(region)
	local cells = FlowField.Path(field, sx, sz)
	local passedGap = false
	for _, c in cells do
		if c[2] == z then
			checkEq(c[1], region.MinX, "should use the gap")
			passedGap = true
		end
	end
	check(passedGap)
	-- with a brute-like cost multiplier the wall becomes the shortcut
	local brute = FlowField.Compute(region, blockers, 1 / 25, 0.01)
	local bcells = FlowField.Path(brute, sx, sz)
	for _, c in bcells do
		if c[2] == z then check(c[1] ~= region.MinX, "wallbreaker should smash") end
	end
end)

summary()

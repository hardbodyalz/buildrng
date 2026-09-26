--[[
	Grid
	Pure plot-grid maths shared by server (authoritative validation) and client
	(placement preview). No Roblox instances here.

	Cells are integer (x, z). Cell centres are at integer coordinates in "cell
	space"; Grid.CellToLocal converts to studs relative to the plot origin.
	Rotation is 0..3 quarter turns (odd rotations swap footprint width/depth).
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local Progression = require(Config.Progression)

local G = GameConfig.Grid

export type Region = {
	Tier: number,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	Width: number,
	Length: number,
}

local Grid = {}

Grid.CellSize = G.CellSize
Grid.MaxWidth = G.MaxWidth
Grid.MaxLength = G.MaxLength
Grid.CenterX = (G.MaxWidth - 1) / 2
Grid.CenterZ = (G.MaxLength - 1) / 2
Grid.CoreMinX = Grid.CenterX - (G.CoreSize - 1) / 2
Grid.CoreMaxX = Grid.CenterX + (G.CoreSize - 1) / 2
Grid.CoreMinZ = G.MaxLength - G.CoreSize
Grid.CoreMaxZ = G.MaxLength - 1

Grid.Status = {
	Valid = "Valid",
	Warning = "Warning", -- legal but probably a mistake (shown yellow)
	Invalid = "Invalid",
}

function Grid.Key(x: number, z: number): number
	return z * 64 + x
end

function Grid.FromKey(key: number): (number, number)
	return key % 64, key // 64
end

function Grid.Region(tier: number): Region
	local count = #Progression.Expansions
	tier = math.clamp(math.floor(tier), 1, count)
	local e = Progression.Expansions[tier]
	local halfW = (e.Width - 1) / 2
	return {
		Tier = tier,
		MinX = Grid.CenterX - halfW,
		MaxX = Grid.CenterX + halfW,
		MinZ = G.MaxLength - e.Length,
		MaxZ = G.MaxLength - 1,
		Width = e.Width,
		Length = e.Length,
	}
end

function Grid.Entrance(region: Region): (number, number)
	return Grid.CenterX, region.MinZ
end

function Grid.InRegion(region: Region, x: number, z: number): boolean
	return x >= region.MinX and x <= region.MaxX and z >= region.MinZ and z <= region.MaxZ
end

function Grid.IsCore(x: number, z: number): boolean
	return x >= Grid.CoreMinX and x <= Grid.CoreMaxX and z >= Grid.CoreMinZ and z <= Grid.CoreMaxZ
end

function Grid.IsEntranceZone(region: Region, x: number, z: number): boolean
	return z == region.MinZ and math.abs(x - Grid.CenterX) <= (G.EntranceWidth - 1) / 2
end

function Grid.CoreCells(): { { number } }
	local out = {}
	for x = Grid.CoreMinX, Grid.CoreMaxX do
		for z = Grid.CoreMinZ, Grid.CoreMaxZ do
			table.insert(out, { x, z })
		end
	end
	return out
end

function Grid.Footprint(def: any, rot: number): (number, number)
	local w, d = def.Footprint[1], def.Footprint[2]
	if rot % 2 == 1 then
		return d, w
	end
	return w, d
end

function Grid.FootprintCells(def: any, x: number, z: number, rot: number): { { number } }
	local w, d = Grid.Footprint(def, rot)
	local out = {}
	for dx = 0, w - 1 do
		for dz = 0, d - 1 do
			table.insert(out, { x + dx, z + dz })
		end
	end
	return out
end

-- Centre of a footprint in cell space (anchor = min corner cell).
function Grid.FootprintCenter(def: any, x: number, z: number, rot: number): (number, number)
	local w, d = Grid.Footprint(def, rot)
	return x + (w - 1) / 2, z + (d - 1) / 2
end

-- Cell space -> studs relative to the plot origin (plot origin = grid centre).
function Grid.CellToLocal(cx: number, cz: number): (number, number)
	return (cx - Grid.CenterX) * G.CellSize, (cz - Grid.CenterZ) * G.CellSize
end

function Grid.LocalToCellFloat(lx: number, lz: number): (number, number)
	return lx / G.CellSize + Grid.CenterX, lz / G.CellSize + Grid.CenterZ
end

-- Anchor cell for a footprint whose centre should be nearest (fx, fz) in cell space.
function Grid.AnchorFromPoint(def: any, rot: number, fx: number, fz: number): (number, number)
	local w, d = Grid.Footprint(def, rot)
	return math.floor(fx - (w - 1) / 2 + 0.5), math.floor(fz - (d - 1) / 2 + 0.5)
end

-- structures: { [uid] = { Id, X, Z, R, ... } } ; returns cellKey -> uid
function Grid.BuildOccupancy(structures: { [string]: any }, items: { [string]: any }, ignoreUid: string?): { [number]: string }
	local occ = {}
	for uid, s in structures do
		if uid ~= ignoreUid then
			local def = items[s.Id]
			if def then
				for _, c in Grid.FootprintCells(def, s.X, s.Z, s.R or 0) do
					occ[Grid.Key(c[1], c[2])] = uid
				end
			end
		end
	end
	return occ
end

export type PlacementQuery = {
	Region: Region,
	Occupancy: { [number]: string },
	Def: any,
	X: number,
	Z: number,
	Rot: number,
	PlacedCount: number,
	Capacity: number,
	IsMove: boolean?,
	PathCells: { [number]: boolean }?, -- optional: cells on the current enemy route (for warnings)
}

-- Returns status, reason. The server treats Warning as legal.
function Grid.CheckPlacement(q: PlacementQuery): (string, string?)
	if q.Rot ~= 0 and q.Rot ~= 1 and q.Rot ~= 2 and q.Rot ~= 3 then
		return Grid.Status.Invalid, "Bad rotation"
	end
	if not q.IsMove and q.PlacedCount >= q.Capacity then
		return Grid.Status.Invalid, "Build limit reached - expand your base"
	end
	local touchesPath = false
	for _, c in Grid.FootprintCells(q.Def, q.X, q.Z, q.Rot) do
		local x, z = c[1], c[2]
		if not Grid.InRegion(q.Region, x, z) then
			return Grid.Status.Invalid, "Outside your base"
		end
		if Grid.IsCore(x, z) then
			return Grid.Status.Invalid, "Can't build on the Core"
		end
		if Grid.IsEntranceZone(q.Region, x, z) then
			return Grid.Status.Invalid, "Keep the entrance clear"
		end
		local key = Grid.Key(x, z)
		if q.Occupancy[key] then
			return Grid.Status.Invalid, "Space occupied"
		end
		if q.PathCells and q.PathCells[key] then
			touchesPath = true
		end
	end
	if q.PathCells and not q.Def.Blocks and not touchesPath then
		return Grid.Status.Warning, "Enemies don't currently walk here"
	end
	return Grid.Status.Valid, nil
end

return Grid

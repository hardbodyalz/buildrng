--[[
	EnemyRenderer
	Enemies exist only as data on the server (no physics, no server parts).
	The server sends compact 10 Hz snapshots per plot; this renders them with
	pooled, non-colliding models, smooth interpolation, walk bobbing, attack
	lunges and health bars. Moves are batched with Workspace:BulkMoveTo.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enemies = require(Shared.Config.Enemies)
local Waves = require(Shared.Config.Waves)
local Grid = require(Shared.Util.Grid)
local ModelBuilder = require(Shared.Util.ModelBuilder)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Net = require(script.Parent.Parent.Net)

local EnemyRenderer = {}

local FLAG_ATTACKING = 128
local HIDDEN = CFrame.new(0, -500, 0)

local MOD_TINT = {
	[1] = Color3.fromRGB(255, 200, 40), -- Elite
	[2] = Color3.fromRGB(255, 255, 120), -- Swift
	[4] = Color3.fromRGB(80, 255, 120), -- Regenerating
	[8] = Color3.fromRGB(160, 170, 190), -- Armored
	[16] = Color3.fromRGB(255, 50, 50), -- Enraged
}

type Visual = {
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	Key: string,
	Pos: Vector3,
	Target: Vector3,
	Facing: Vector3,
	Attacking: boolean,
	Seed: number,
	Scale: number,
	Bar: BillboardGui,
	Fill: Frame,
	IsBoss: boolean,
}

local folder: Folder
local pools: { [string]: { Visual } } = {}
local visuals: { [number]: { [number]: Visual } } = {} -- plotId -> enemyId -> visual

local function plotCFrame(plotId: number): CFrame?
	local plots = Workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. plotId) :: Model?
	return if plot and plot.PrimaryPart then plot.PrimaryPart.CFrame else nil
end

local function build(typeIndex: number, mods: number): Visual
	local def = Enemies.List[typeIndex]
	local scale, tint = 1, nil
	for bit, color in MOD_TINT do
		if bit32.band(mods, bit) ~= 0 then
			tint = color
		end
	end
	for _, m in Waves.Modifiers do
		if bit32.band(mods, m.Bit) ~= 0 and m.Scale then
			scale *= m.Scale
		end
	end
	local model = ModelBuilder.BuildEnemy(def, scale, tint)
	local root = model.PrimaryPart :: BasePart
	local parts, offsets = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(offsets, root.CFrame:ToObjectSpace(d.CFrame))
		end
	end
	local _, size = model:GetBoundingBox()
	local height = size.Y
	local bar = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(if def.IsBoss then 120 else 46, if def.IsBoss then 12 else 7),
		StudsOffsetWorldSpace = Vector3.new(0, height + 0.8, 0),
		MaxDistance = if def.IsBoss then 400 else 140,
		Enabled = false,
		Adornee = root,
		Parent = root,
	})
	local back = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 0, 0), BorderSizePixel = 0, Parent = bar })
	local fill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = if def.IsBoss then Theme.Bad else Theme.Good, BorderSizePixel = 0, Parent = back })
	model.Parent = folder
	return {
		Model = model,
		Parts = parts,
		Offsets = offsets,
		Key = typeIndex .. ":" .. mods,
		Pos = Vector3.zero,
		Target = Vector3.zero,
		Facing = Vector3.new(0, 0, -1),
		Attacking = false,
		Seed = 0,
		Scale = def.Scale * scale,
		Bar = bar,
		Fill = fill,
		IsBoss = def.IsBoss,
	}
end

local function acquire(typeIndex: number, mods: number): Visual
	local key = typeIndex .. ":" .. mods
	local pool = pools[key]
	if pool and #pool > 0 then
		return table.remove(pool) :: Visual
	end
	return build(typeIndex, mods)
end

local function release(v: Visual)
	v.Bar.Enabled = false
	for i, p in v.Parts do
		p.CFrame = HIDDEN * v.Offsets[i]
	end
	pools[v.Key] = pools[v.Key] or {}
	table.insert(pools[v.Key], v)
end

-- Deterministic per-enemy offset so a crowd doesn't stack on one line.
local function jitter(id: number): (number, number)
	local a = ((id * 9301 + 49297) % 233280) / 233280 - 0.5
	local b = ((id * 4096 + 150889) % 714025) / 714025 - 0.5
	return a * 0.55, b * 0.55
end

local function onSnapshot(payload)
	if type(payload) ~= "table" or type(payload.Data) ~= "table" then
		return
	end
	local plotId = payload.PlotId
	local cf = plotCFrame(plotId)
	if not cf then
		return
	end
	local data = payload.Data
	local stride = payload.Stride or 6
	local current = visuals[plotId] or {}
	visuals[plotId] = current
	local seen = {}
	for i = 1, #data - stride + 1, stride do
		local id, typeIndex, x, z, hp, flags = data[i], data[i + 1], data[i + 2], data[i + 3], data[i + 4], data[i + 5]
		if Enemies.List[typeIndex] then
			seen[id] = true
			local mods = bit32.band(flags, FLAG_ATTACKING - 1)
			local v = current[id]
			local isNew = false
			if not v then
				v = acquire(typeIndex, mods)
				v.Seed = id
				current[id] = v
				isNew = true
			end
			local jx, jz = 0, 0
			if not v.IsBoss then
				jx, jz = jitter(id)
			end
			local lx, lz = Grid.CellToLocal(x / 100 + jx, z / 100 + jz)
			local target = (cf * CFrame.new(lx, 0, lz)).Position
			if isNew then
				v.Pos = target
				v.Facing = cf.LookVector * -1
			end
			v.Target = target
			v.Attacking = bit32.band(flags, FLAG_ATTACKING) ~= 0
			local showBar = hp < 100 or v.IsBoss
			v.Bar.Enabled = showBar
			if showBar then
				v.Fill.Size = UDim2.fromScale(hp / 100, 1)
			end
		end
	end
	for id, v in current do
		if not seen[id] then
			current[id] = nil
			release(v)
		end
	end
end

local parts: { BasePart } = {}
local cframes: { CFrame } = {}

local function render(dt: number)
	table.clear(parts)
	table.clear(cframes)
	local t = os.clock()
	local alpha = 1 - math.exp(-dt * 10)
	for _, plotVisuals in visuals do
		for _, v in plotVisuals do
			local delta = v.Target - v.Pos
			v.Pos += delta * alpha
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude > 0.05 then
				v.Facing = v.Facing:Lerp(flat.Unit, math.min(1, dt * 10))
			end
			local moving = flat.Magnitude > 0.1
			local bob = if moving then math.abs(math.sin(t * 9 + v.Seed)) * 0.25 * v.Scale else 0
			local lunge = if v.Attacking then (math.sin(t * 10 + v.Seed) * 0.5 + 0.5) * 0.6 else 0
			local facing = if v.Facing.Magnitude > 0.01 then v.Facing.Unit else Vector3.new(0, 0, -1)
			local pos = v.Pos + Vector3.new(0, bob, 0) + facing * lunge
			local rootCF = CFrame.lookAt(pos, pos + facing)
			for i, p in v.Parts do
				table.insert(parts, p)
				table.insert(cframes, rootCF * v.Offsets[i])
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnemyRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientEnemies"
	folder.Parent = Workspace
	Net.On("EnemySnapshot", onSnapshot)
	RunService.RenderStepped:Connect(render)
end

return EnemyRenderer

--[[
	PlotService
	Owns the physical world: the hub, the six plots, per-plot terrain (which
	changes look with each expansion tier), the Core, and the placed structure
	models. Gameplay state lives in data + DefenseSim; this service only
	mirrors it into Instances.

	Plot model attributes (read by clients):
	  PlotId, OwnerUserId, OwnerName, Tier, CoreHp, CoreMax, Wave, DefenseState
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Config.Progression)
local Items = require(Shared.Config.Items)
local Grid = require(Shared.Util.Grid)
local ModelBuilder = require(Shared.Util.ModelBuilder)
local Registry = require(script.Parent.Parent.Registry)

local CS = GameConfig.Grid.CellSize
local PCFG = GameConfig.Plots
local rgb = ModelBuilder.RGB

local PlotService = {}

type Plot = {
	Id: number,
	CFrame: CFrame,
	Model: Model,
	Ground: Folder,
	Structures: Folder,
	Owner: Player?,
}

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function material(name: string): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

-- World ----------------------------------------------------------------------

local function buildHub(root: Folder)
	part({
		Name = "Ground",
		Size = Vector3.new(900, 2, 900),
		CFrame = CFrame.new(0, -1.6, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(78, 120, 64),
		Locked = true,
		Parent = root,
	})
	part({
		Name = "Plaza",
		Size = Vector3.new(PCFG.ColumnSpacing * 3 + 40, 1, (PCFG.RowDistance - GameConfig.Grid.MaxLength * CS / 2) * 2 - 4),
		CFrame = CFrame.new(0, -0.9, 0),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(170, 168, 160),
		Locked = true,
		Parent = root,
	})
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, -0.3, 0)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Transparency = 0.4
	spawn.Duration = 0
	spawn.CanTouch = true
	spawn.Parent = root
end

local function plotCFrame(i: number): CFrame
	local row = if i <= math.ceil(PCFG.Count / 2) then 1 else -1
	local perRow = math.ceil(PCFG.Count / 2)
	local col = ((i - 1) % perRow) - (perRow - 1) / 2
	local x = col * PCFG.ColumnSpacing
	local z = row * PCFG.RowDistance
	-- Local +Z (entrance -> Core) must point at the hub (world origin).
	local yaw = if row == 1 then math.pi else 0
	return CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
end

function PlotService:CellCFrame(plot: Plot, cx: number, cz: number, y: number?): CFrame
	local lx, lz = Grid.CellToLocal(cx, cz)
	return plot.CFrame * CFrame.new(lx, y or 0, lz)
end

-- Terrain for the current tier: slab, buildable floor, perimeter walls, entrance gate, Core.
local function buildTerrain(plot: Plot, tier: number, ownerName: string?)
	plot.Ground:ClearAllChildren()
	local region = Grid.Region(tier)
	local style = Progression.Expansions[region.Tier].Style
	local cf = plot.CFrame

	local maxW, maxL = GameConfig.Grid.MaxWidth * CS, GameConfig.Grid.MaxLength * CS
	part({
		Name = "Slab",
		Size = Vector3.new(maxW + 12, 1, maxL + 12),
		CFrame = cf * CFrame.new(0, -0.7, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(62, 96, 54),
		Parent = plot.Ground,
	})

	local midX = (region.MinX + region.MaxX) / 2
	local midZ = (region.MinZ + region.MaxZ) / 2
	local lx, lz = Grid.CellToLocal(midX, midZ)
	local w, l = region.Width * CS, region.Length * CS
	part({
		Name = "Floor",
		Size = Vector3.new(w, 0.4, l),
		CFrame = cf * CFrame.new(lx, -0.2, lz),
		Material = material(style.Floor),
		Color = rgb(style.FloorColor),
		Parent = plot.Ground,
	})

	-- Perimeter (gap at the entrance).
	local h = style.WallHeight
	local thick = 1
	local wallMat, wallColor = material(style.Wall), rgb(style.WallColor)
	local left = lx - w / 2 - thick / 2
	local right = lx + w / 2 + thick / 2
	local front = lz - l / 2 - thick / 2
	local back = lz + l / 2 + thick / 2
	local function wall(name, sx, sz, px, pz)
		part({
			Name = name,
			Size = Vector3.new(sx, h, sz),
			CFrame = cf * CFrame.new(px, h / 2, pz),
			Material = wallMat,
			Color = wallColor,
			Parent = plot.Ground,
		})
		part({
			Name = name .. "Trim",
			Size = Vector3.new(sx + 0.2, 0.4, sz + 0.2),
			CFrame = cf * CFrame.new(px, h + 0.2, pz),
			Material = Enum.Material.SmoothPlastic,
			Color = rgb(style.Trim),
			Parent = plot.Ground,
		})
	end
	wall("WallLeft", thick, l + thick * 2, left, lz)
	wall("WallRight", thick, l + thick * 2, right, lz)
	wall("WallBack", w, thick, lx, back)
	local gap = GameConfig.Grid.EntranceWidth * CS
	local seg = (w - gap) / 2
	if seg > 0 then
		wall("WallFrontL", seg, thick, lx - gap / 2 - seg / 2, front)
		wall("WallFrontR", seg, thick, lx + gap / 2 + seg / 2, front)
	end

	-- Enemy gate.
	local gateH = h + 4
	for _, side in { -1, 1 } do
		part({
			Name = "GatePillar",
			Size = Vector3.new(1.6, gateH, 1.6),
			CFrame = cf * CFrame.new(lx + side * (gap / 2 + 0.8), gateH / 2, front),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(50, 44, 48),
			Parent = plot.Ground,
		})
	end
	part({
		Name = "GateBeam",
		Size = Vector3.new(gap + 3.2, 0.8, 1.2),
		CFrame = cf * CFrame.new(lx, gateH, front),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 60, 50),
		Parent = plot.Ground,
	})
	part({
		Name = "Portal",
		Size = Vector3.new(gap, gateH - 0.4, 0.2),
		CFrame = cf * CFrame.new(lx, (gateH - 0.4) / 2, front - 1.2),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 40, 60),
		Transparency = 0.2,
		CanCollide = false,
		CanQuery = false,
		Parent = plot.Ground,
	})

	-- Core (fixed position at the +Z end).
	local core = Instance.new("Model")
	core.Name = "Core"
	local ccx = (Grid.CoreMinX + Grid.CoreMaxX) / 2
	local ccz = (Grid.CoreMinZ + Grid.CoreMaxZ) / 2
	local coreCF = PlotService:CellCFrame(plot, ccx, ccz)
	local size = GameConfig.Grid.CoreSize * CS
	local base = part({
		Name = "CoreBase",
		Size = Vector3.new(size - 0.4, 1.2, size - 0.4),
		CFrame = coreCF * CFrame.new(0, 0.6, 0),
		Material = Enum.Material.DiamondPlate,
		Color = Color3.fromRGB(70, 76, 90),
		Parent = core,
	})
	part({
		Name = "CoreRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, size - 3, size - 3),
		CFrame = coreCF * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Neon,
		Color = rgb(style.Trim),
		Parent = core,
	})
	local crystal = part({
		Name = "Crystal",
		Size = Vector3.new(3, 5, 3),
		CFrame = coreCF * CFrame.new(0, 5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(90, 220, 255),
		CanCollide = false,
		Parent = core,
	})
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 16
	light.Brightness = 2
	light.Parent = crystal
	core.PrimaryPart = base

	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromOffset(260, 50)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	sign.MaxDistance = 250
	sign.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = if ownerName then string.format("%s's %s", ownerName, Progression.Expansions[region.Tier].Name) else "Empty Plot"
	label.Parent = sign
	sign.Parent = base
	core.Parent = plot.Ground

	plot.Model:SetAttribute("Tier", region.Tier)
end

local function newPlot(i: number, root: Folder): Plot
	local model = Instance.new("Model")
	model.Name = "Plot" .. i
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = model
	local structures = Instance.new("Folder")
	structures.Name = "Structures"
	structures.Parent = model
	local cf = plotCFrame(i)
	local anchor = part({
		Name = "Anchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = cf,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	model.PrimaryPart = anchor
	model:SetAttribute("PlotId", i)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("CoreHp", GameConfig.Defense.BaseCoreHealth)
	model:SetAttribute("CoreMax", GameConfig.Defense.BaseCoreHealth)
	model:SetAttribute("Wave", 0)
	model:SetAttribute("DefenseState", "Idle")
	model.Parent = root
	local plot: Plot = { Id = i, CFrame = cf, Model = model, Ground = ground, Structures = structures, Owner = nil }
	buildTerrain(plot, 1, nil)
	return plot
end

-- Structures -------------------------------------------------------------------

local function signature(s): string
	return string.format("%s|%s|%d|%d|%d", s.Id, s.Mut or "Normal", s.X, s.Z, s.R or 0)
end

function PlotService:StructureCFrame(plot: Plot, def: any, s: any): CFrame
	local cx, cz = Grid.FootprintCenter(def, s.X, s.Z, s.R or 0)
	return self:CellCFrame(plot, cx, cz) * CFrame.Angles(0, -(s.R or 0) * math.pi / 2, 0)
end

-- Diff Base.Structures against existing models; rebuild only what changed.
function PlotService:SyncStructures(player: Player)
	local plot = plotByPlayer[player]
	local d = Registry.DataService:Get(player)
	if not plot or not d then
		return
	end
	local existing = {}
	for _, m in plot.Structures:GetChildren() do
		existing[m.Name] = m
	end
	for uid, s in d.Base.Structures do
		local def = Items.Get(s.Id)
		if def then
			local model = existing[uid]
			existing[uid] = nil
			if model and model:GetAttribute("Sig") ~= signature(s) then
				model:Destroy()
				model = nil
			end
			if not model then
				local built = ModelBuilder.BuildItem(def, s.Mut)
				built.Name = uid
				built:SetAttribute("Uid", uid)
				built:SetAttribute("ItemId", s.Id)
				built:SetAttribute("Mutation", s.Mut or "Normal")
				built:SetAttribute("OwnerUserId", player.UserId)
				built:SetAttribute("Sig", signature(s))
				built:PivotTo(self:StructureCFrame(plot, def, s))
				built.Parent = plot.Structures
				model = built
			end
			(model :: Model):SetAttribute("Level", s.Lvl or 1)
		end
	end
	for _, leftover in existing do
		leftover:Destroy()
	end
end

-- Destroyed structures turn into faint "rubble" until the wave ends.
function PlotService:SetStructureDestroyed(player: Player, uid: string, destroyed: boolean)
	local plot = plotByPlayer[player]
	local model = plot and plot.Structures:FindFirstChild(uid)
	if not model then
		return
	end
	model:SetAttribute("Destroyed", destroyed)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" and p.Name ~= "HeadPivot" then
			if destroyed then
				if p:GetAttribute("T0") == nil then
					p:SetAttribute("T0", p.Transparency)
				end
				p.Transparency = 0.85
				p.CanCollide = false
			else
				local t0 = p:GetAttribute("T0")
				if t0 ~= nil then
					p.Transparency = t0
				end
				p.CanCollide = true
			end
		elseif p:IsA("ParticleEmitter") or p:IsA("PointLight") then
			p.Enabled = not destroyed
		end
	end
end

function PlotService:RestoreAll(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	for _, m in plot.Structures:GetChildren() do
		if m:GetAttribute("Destroyed") then
			self:SetStructureDestroyed(player, m.Name, false)
		end
	end
end

-- Queries ----------------------------------------------------------------------

function PlotService:GetPlot(player: Player): Plot?
	return plotByPlayer[player]
end

function PlotService:RebuildTerrain(player: Player)
	local plot = plotByPlayer[player]
	local d = Registry.DataService:Get(player)
	if plot and d then
		buildTerrain(plot, d.Base.Tier, player.DisplayName)
	end
end

-- Players who should receive this plot's combat replication (owner + anyone nearby).
function PlotService:GetViewers(plot: Plot): { Player }
	local out = {}
	local range = GameConfig.Defense.SnapshotRange
	local center = plot.CFrame.Position
	for _, p in Players:GetPlayers() do
		if p == plot.Owner then
			table.insert(out, p)
		else
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - center).Magnitude <= range then
				table.insert(out, p)
			end
		end
	end
	return out
end

function PlotService:TeleportHome(player: Player)
	local plot = plotByPlayer[player]
	local char = player.Character
	if not plot or not char then
		return
	end
	-- Stand just behind the Core, looking down the field toward the entrance.
	local behind = (GameConfig.Grid.MaxLength / 2) * CS + 6
	local cf = plot.CFrame * CFrame.new(0, 4, behind) * CFrame.Angles(0, 0, 0)
	char:PivotTo(CFrame.lookAt(cf.Position, (plot.CFrame * CFrame.new(0, 4, 0)).Position))
end

local function assign(player: Player)
	for _, plot in plots do
		if not plot.Owner then
			plot.Owner = player
			plotByPlayer[player] = plot
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			plot.Model:SetAttribute("OwnerName", player.DisplayName)
			player:SetAttribute("PlotId", plot.Id)
			return plot
		end
	end
	return nil
end

local function release(player: Player)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	plotByPlayer[player] = nil
	plot.Owner = nil
	plot.Structures:ClearAllChildren()
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	plot.Model:SetAttribute("DefenseState", "Idle")
	plot.Model:SetAttribute("Wave", 0)
	buildTerrain(plot, 1, nil)
end

function PlotService:Init()
	local root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = Workspace
	buildHub(root)
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = Workspace
	for i = 1, PCFG.Count do
		table.insert(plots, newPlot(i, plotsFolder))
	end
end

function PlotService:Start()
	Registry.DataService.ProfileLoaded:Connect(function(player, d)
		local plot = assign(player)
		if not plot then
			player:Kick("This server is full of bases. Please join another server!")
			return
		end
		buildTerrain(plot, d.Base.Tier, player.DisplayName)
		self:SyncStructures(player)
		Registry.DefenseService:SetupPlayer(player)
		Registry.ProgressionService:Refresh(player)
		if player.Character then
			self:TeleportHome(player)
		end
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.1)
			self:TeleportHome(player)
		end)
	end)
	Registry.DataService.ProfileReleasing:Connect(function(player)
		Registry.DefenseService:TeardownPlayer(player)
		release(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- Covers players who left before their profile loaded.
		if plotByPlayer[player] and not Registry.DataService:IsLoaded(player) then
			release(player)
		end
	end)
end

return PlotService

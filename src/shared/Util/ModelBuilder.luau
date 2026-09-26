--[[
	ModelBuilder
	Builds Roblox models from the part descriptors in Items / Enemies config, so
	no hand-made assets are required and every new item is just data. The same
	builder produces the server's placed structures, the client's placement
	ghost and the client's pooled enemy visuals.

	Item model layout:
	  Model (PrimaryPart = Root, invisible, at footprint centre on the floor)
	    Root
	    <static parts>
	    Head (Model, PrimaryPart = HeadPivot)  -- parts flagged Head; client yaws it at targets
]]

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local GameConfig = require(Config.GameConfig)

local CS = GameConfig.Grid.CellSize

local ModelBuilder = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function material(name: string?): Enum.Material?
	if not name then
		return nil
	end
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok then m else nil
end

ModelBuilder.ParticlePresets = {
	Sparkle = { Color = { 255, 220, 90 }, Rate = 5, Life = 1.2, Size = 0.35, Speed = 1.5, Light = 1 },
	Shine = { Color = { 210, 250, 255 }, Rate = 7, Life = 1, Size = 0.3, Speed = 2, Light = 1 },
	Corrupt = { Color = { 255, 40, 90 }, Rate = 10, Life = 1.4, Size = 0.4, Speed = 2.5, Light = 0.6 },
	Stars = { Color = { 170, 140, 255 }, Rate = 12, Life = 2, Size = 0.25, Speed = 0.8, Light = 1 },
	Glitch = { Color = { 0, 255, 160 }, Rate = 16, Life = 0.4, Size = 0.5, Speed = 4, Light = 1 },
	Void = { Color = { 90, 0, 160 }, Rate = 14, Life = 2.5, Size = 0.6, Speed = 0.5, Light = 0 },
}

local function addParticles(parent: BasePart, presetName: string)
	local p = ModelBuilder.ParticlePresets[presetName]
	if not p then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(rgb(p.Color))
	e.Rate = p.Rate
	e.Lifetime = NumberRange.new(p.Life * 0.7, p.Life)
	e.Speed = NumberRange.new(p.Speed * 0.5, p.Speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, p.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = p.Light
	e.Parent = parent
end

-- Create one part from a descriptor. `scale` converts descriptor units to studs.
local function makePart(desc: any, scale: number, color: Color3, mat: Enum.Material?): BasePart
	local part: BasePart
	local size = Vector3.new(desc.Size[1], desc.Size[2], desc.Size[3]) * scale
	if desc.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if desc.Shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif desc.Shape == "Ball" then
			-- Ball parts are forced uniform; use a sphere mesh so ellipsoids work.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		part = p
	end
	part.Size = size
	part.Color = color
	part.Material = mat or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if desc.Transparency then
		part.Transparency = desc.Transparency
	end
	local rot = desc.Rot
	local cf = CFrame.new(desc.Pos[1] * scale, desc.Pos[2] * scale, desc.Pos[3] * scale)
	if rot then
		cf *= CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	end
	part.CFrame = cf
	return part
end

export type ItemBuildOptions = {
	Ghost: boolean?,
}

-- Builds an item model at the origin (caller PivotTo()s it into place).
function ModelBuilder.BuildItem(def: any, mutationId: string?, opts: ItemBuildOptions?): Model
	local ghost = opts ~= nil and opts.Ghost == true
	local mut = Mutations.Get(mutationId)
	local rarity = Rarities.Get(def.Rarity)
	local palette = {
		Primary = if mut.Color then rgb(mut.Color) else rgb(def.Colors.Primary),
		Accent = if mut.Accent then rgb(mut.Accent) else rgb(def.Colors.Accent),
		Dark = rgb(def.Colors.Dark),
		Rarity = rgb(rarity.Color),
	}

	local model = Instance.new("Model")
	model.Name = def.Id

	local w, d = def.Footprint[1], def.Footprint[2]
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(w * CS * 0.98, 0.2, d * CS * 0.98)
	root.CFrame = CFrame.new(0, 0.1, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root

	local head: Model? = nil
	local firstAccent: BasePart? = nil

	for _, desc in def.Model do
		local colorKey = desc.Color
		local color = if type(colorKey) == "table" then rgb(colorKey) else (palette[colorKey] or palette.Primary)
		local mat = material(desc.Material)
		if colorKey == "Primary" and mut.Material and desc.Material ~= "Neon" then
			mat = material(mut.Material)
		end
		local part = makePart(desc, CS, color, mat)
		if ghost then
			part.Transparency = math.max(part.Transparency, 0.45)
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
		end
		if colorKey == "Accent" and not firstAccent then
			firstAccent = part
		end
		if desc.Head then
			if not head then
				local h = Instance.new("Model")
				h.Name = "Head"
				local pivot = Instance.new("Part")
				pivot.Name = "HeadPivot"
				pivot.Size = Vector3.new(0.2, 0.2, 0.2)
				pivot.CFrame = CFrame.new(0, def.FxHeight * CS, 0)
				pivot.Transparency = 1
				pivot.Anchored = true
				pivot.CanCollide = false
				pivot.CanQuery = false
				pivot.CanTouch = false
				pivot.Parent = h
				h.PrimaryPart = pivot
				h.Parent = model
				head = h
			end
			part.Parent = head
		else
			part.Parent = model
		end
	end

	if not ghost then
		local glowColor = mut.Glow or (if rarity.RevealTier >= 4 then rarity.Color else nil)
		if glowColor then
			local light = Instance.new("PointLight")
			light.Color = rgb(glowColor)
			light.Range = 6 + rarity.RevealTier
			light.Brightness = 1
			light.Parent = firstAccent or root
		end
		if mut.Particles then
			addParticles(root, mut.Particles)
		end
	end

	return model
end

-- Enemy visuals (client-side only; never collide or get raycast).
function ModelBuilder.BuildEnemy(def: any, extraScale: number?, tint: Color3?): Model
	local scale = def.Scale * (extraScale or 1)
	local palette = {
		Primary = rgb(def.Colors.Primary),
		Accent = rgb(def.Colors.Accent),
		Dark = rgb(def.Colors.Dark),
		Eye = rgb(def.Colors.Eye),
	}
	if tint then
		palette.Primary = palette.Primary:Lerp(tint, 0.55)
	end
	local model = Instance.new("Model")
	model.Name = def.Id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	for _, desc in def.Model do
		local colorKey = desc.Color
		local color = if type(colorKey) == "table" then rgb(colorKey) else (palette[colorKey] or palette.Primary)
		local part = makePart(desc, scale, color, material(desc.Material))
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = model
	end
	return model
end

function ModelBuilder.RarityColor(rarityId: string): Color3
	return rgb(Rarities.Get(rarityId).Color)
end

ModelBuilder.RGB = rgb

return ModelBuilder

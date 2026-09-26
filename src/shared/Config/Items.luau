--[[
	Items
	Every rollable / placeable object, fully data-driven. Systems never special-
	case an item id: behaviour comes from `Behavior` + `Stats`, visuals from
	`Model`. Adding an item = adding an entry here.

	Fields
	  Id, DisplayName, Rarity, Category, Role, Description, Tip
	  World        which world's roll pool this item belongs to
	  Rollable     false = craft/boss/event only (default true)
	  RollWeight   relative weight inside its rarity pool (default 1)
	  Hidden       Index shows "???" until discovered
	  Footprint    { width(X), depth(Z) } in cells, before rotation
	  Blocks       does the structure occupy the enemy path (default true).
	               Blocking structures can be attacked and are expensive to path
	               through; non-blocking ones (traps) are walked over.
	  Behavior     Wall | SingleTarget | Splash | Pierce | Chain | Aura | Trap | Support | Generator
	  Targeting    First | Strongest | Closest (attacking behaviours)
	  Stats        level-1 stats (see ItemStats for level/mutation scaling)
	  FxHeight     muzzle height in cells (projectile origin)
	  Colors       { Primary, Accent, Dark } RGB palettes for the model
	  Model        list of parts (units = cells; origin = footprint centre on the floor)
	               { Shape, Size, Pos, Rot?, Color = "Primary"|"Accent"|"Dark"|"Rarity"|{r,g,b},
	                 Material?, Head? (rotates toward targets), Neon? }
]]

export type ModelPart = {
	Shape: string,
	Size: { number },
	Pos: { number },
	Rot: { number }?,
	Color: any,
	Material: string?,
	Head: boolean?,
	Transparency: number?,
}

export type ItemDef = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Category: string,
	Role: string,
	Description: string,
	Tip: string,
	World: string,
	Rollable: boolean,
	RollWeight: number,
	Hidden: boolean,
	Footprint: { number },
	Blocks: boolean,
	Behavior: string,
	Targeting: string,
	Stats: { [string]: number },
	FxHeight: number,
	Colors: { [string]: { number } },
	Model: { ModelPart },
	Order: number,
}

-- Model helpers ------------------------------------------------------------

local function block(size, pos, color, material, extra)
	local p = { Shape = "Block", Size = size, Pos = pos, Color = color, Material = material }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate 90 on Z).
local function vcyl(diameter, height, pos, color, material, extra)
	local p = { Shape = "Cylinder", Size = { height, diameter, diameter }, Pos = pos, Rot = { 0, 0, 90 }, Color = color, Material = material }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

-- Cylinder pointing along -Z (the "forward" of a turret head).
local function barrel(length, diameter, pos, color, material, extra)
	local p = { Shape = "Cylinder", Size = { length, diameter, diameter }, Pos = pos, Rot = { 0, 90, 0 }, Color = color, Material = material }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function ball(d, pos, color, material, extra)
	local p = { Shape = "Ball", Size = { d, d, d }, Pos = pos, Color = color, Material = material }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local HEAD = { Head = true }

local function spikeField()
	local parts = { block({ 0.92, 0.06, 0.92 }, { 0, 0.03, 0 }, "Dark", "DiamondPlate") }
	for ix = -1, 1 do
		for iz = -1, 1 do
			table.insert(parts, vcyl(0.09, 0.24, { ix * 0.27, 0.15, iz * 0.27 }, "Primary", "Metal"))
		end
	end
	return parts
end

local function sandbagRing(half, height, thickness)
	local len = half * 2
	return {
		block({ len, height, thickness }, { 0, height / 2, -half + thickness / 2 }, "Accent", "Fabric"),
		block({ len, height, thickness }, { 0, height / 2, half - thickness / 2 }, "Accent", "Fabric"),
		block({ thickness, height, len - thickness * 2 }, { -half + thickness / 2, height / 2, 0 }, "Accent", "Fabric"),
		block({ thickness, height, len - thickness * 2 }, { half - thickness / 2, height / 2, 0 }, "Accent", "Fabric"),
	}
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

-- Content ------------------------------------------------------------------

local list: { any } = {
	{
		Id = "wooden_barricade",
		DisplayName = "Wooden Barricade",
		Rarity = "Common",
		Category = "Defense",
		Role = "Wall",
		Description = "Cheap planks nailed together. Enemies must smash it or walk around.",
		Tip = "Use barricades to lengthen the enemy path past your turrets.",
		Behavior = "Wall",
		Stats = { Health = 150 },
		FxHeight = 0.5,
		Colors = { Primary = { 156, 104, 58 }, Accent = { 112, 74, 42 }, Dark = { 74, 56, 40 } },
		Model = {
			block({ 0.92, 0.1, 0.5 }, { 0, 0.05, 0 }, "Dark", "Wood"),
			vcyl(0.16, 0.85, { -0.37, 0.43, 0 }, "Accent", "Wood"),
			vcyl(0.16, 0.85, { 0.37, 0.43, 0 }, "Accent", "Wood"),
			block({ 0.96, 0.2, 0.14 }, { 0, 0.28, 0 }, "Primary", "WoodPlanks"),
			block({ 0.96, 0.2, 0.14 }, { 0, 0.52, 0 }, "Primary", "WoodPlanks", { Rot = { 0, 0, 6 } }),
			block({ 0.96, 0.2, 0.14 }, { 0, 0.76, 0 }, "Primary", "WoodPlanks", { Rot = { 0, 0, -4 } }),
		},
	},
	{
		Id = "scrap_turret",
		DisplayName = "Scrap Turret",
		Rarity = "Common",
		Category = "Defense",
		Role = "Turret",
		Description = "Reliable single-target gun bolted together from junk.",
		Tip = "Steady damage. Place near corners so enemies stay in range longer.",
		Behavior = "SingleTarget",
		Targeting = "First",
		Stats = { Health = 90, Damage = 10, Rate = 1.2, Range = 3.5 },
		FxHeight = 0.72,
		Colors = { Primary = { 124, 128, 134 }, Accent = { 232, 142, 40 }, Dark = { 58, 60, 66 } },
		Model = {
			vcyl(0.82, 0.24, { 0, 0.12, 0 }, "Dark", "DiamondPlate"),
			vcyl(0.38, 0.32, { 0, 0.4, 0 }, "Primary", "Metal"),
			block({ 0.46, 0.3, 0.5 }, { 0, 0.72, 0 }, "Primary", "Metal", HEAD),
			barrel(0.5, 0.13, { 0, 0.74, -0.42 }, "Accent", "Metal", HEAD),
		},
	},
	{
		Id = "spike_trap",
		DisplayName = "Spike Trap",
		Rarity = "Common",
		Category = "Defense",
		Role = "Trap",
		Description = "Spikes that stab everything standing on them. Enemies walk right over it.",
		Tip = "Traps hit every enemy on the tile - devastating against swarms. Put them where the path is.",
		Blocks = false,
		Behavior = "Trap",
		Stats = { Health = 1, Damage = 7, Rate = 2 },
		FxHeight = 0.1,
		Colors = { Primary = { 200, 205, 212 }, Accent = { 140, 40, 40 }, Dark = { 60, 58, 56 } },
		Model = spikeField(),
	},
	{
		Id = "coin_press",
		DisplayName = "Coin Press",
		Rarity = "Uncommon",
		Category = "Economy",
		Role = "Generator",
		Description = "Stamps out coins every wave your base survives.",
		Tip = "Earns coins per cleared wave but takes up space a turret could use.",
		Behavior = "Generator",
		Stats = { Health = 80, CoinsPerWave = 12 },
		FxHeight = 1,
		Colors = { Primary = { 244, 194, 62 }, Accent = { 84, 86, 96 }, Dark = { 50, 50, 56 } },
		Model = {
			block({ 0.86, 0.3, 0.86 }, { 0, 0.15, 0 }, "Accent", "DiamondPlate"),
			block({ 0.16, 0.8, 0.16 }, { -0.3, 0.7, 0 }, "Dark", "Metal"),
			block({ 0.16, 0.8, 0.16 }, { 0.3, 0.7, 0 }, "Dark", "Metal"),
			block({ 0.8, 0.16, 0.36 }, { 0, 1.08, 0 }, "Dark", "Metal"),
			vcyl(0.36, 0.2, { 0, 0.4, 0 }, "Primary", "Metal"),
			vcyl(0.3, 0.06, { 0, 0.54, 0 }, "Primary", "Neon"),
		},
	},
	{
		Id = "machine_gun_nest",
		DisplayName = "Machine Gun Nest",
		Rarity = "Uncommon",
		Category = "Offense",
		Role = "Machine Gun",
		Description = "Sprays a torrent of weak bullets.",
		Tip = "Shreds swarms and runners, but armoured enemies shrug off each tiny bullet.",
		Behavior = "SingleTarget",
		Targeting = "Closest",
		Stats = { Health = 120, Damage = 3.5, Rate = 7, Range = 3 },
		FxHeight = 0.52,
		Colors = { Primary = { 64, 70, 60 }, Accent = { 176, 156, 112 }, Dark = { 40, 42, 40 } },
		Model = concat(sandbagRing(0.46, 0.34, 0.2), {
			block({ 0.52, 0.06, 0.52 }, { 0, 0.03, 0 }, "Dark", "Concrete"),
			vcyl(0.14, 0.3, { 0, 0.3, 0 }, "Dark", "Metal"),
			block({ 0.26, 0.2, 0.42 }, { 0, 0.52, 0 }, "Primary", "Metal", HEAD),
			barrel(0.5, 0.07, { -0.06, 0.54, -0.42 }, "Dark", "Metal", HEAD),
			barrel(0.5, 0.07, { 0.06, 0.54, -0.42 }, "Dark", "Metal", HEAD),
		}),
	},
	{
		Id = "frost_beacon",
		DisplayName = "Frost Beacon",
		Rarity = "Uncommon",
		Category = "Support",
		Role = "Slow Field",
		Description = "Radiates bitter cold, slowing every enemy nearby.",
		Tip = "Barely hurts, but slowed enemies spend longer in front of your guns.",
		Behavior = "Aura",
		Stats = { Health = 100, Damage = 2, Rate = 1, Range = 2.5, Slow = 0.35 },
		FxHeight = 1.2,
		Colors = { Primary = { 140, 222, 255 }, Accent = { 226, 246, 255 }, Dark = { 70, 90, 112 } },
		Model = {
			vcyl(0.72, 0.2, { 0, 0.1, 0 }, "Dark", "Slate"),
			vcyl(0.26, 0.8, { 0, 0.6, 0 }, "Accent", "Ice"),
			block({ 0.36, 0.36, 0.36 }, { 0, 1.2, 0 }, "Primary", "Neon", { Rot = { 45, 45, 0 } }),
		},
	},
	{
		Id = "stone_wall",
		DisplayName = "Stone Wall",
		Rarity = "Rare",
		Category = "Defense",
		Role = "Wall",
		Description = "A thick three-tile rampart.",
		Tip = "Very high HP. Enemies will usually walk a long way around instead of breaking through.",
		Footprint = { 3, 1 },
		Behavior = "Wall",
		Stats = { Health = 700 },
		FxHeight = 1,
		Colors = { Primary = { 150, 152, 160 }, Accent = { 112, 114, 124 }, Dark = { 80, 80, 88 } },
		Model = {
			block({ 2.96, 0.9, 0.72 }, { 0, 0.45, 0 }, "Primary", "Cobblestone"),
			block({ 0.5, 0.26, 0.78 }, { -1.2, 1.03, 0 }, "Accent", "Cobblestone"),
			block({ 0.5, 0.26, 0.78 }, { -0.4, 1.03, 0 }, "Accent", "Cobblestone"),
			block({ 0.5, 0.26, 0.78 }, { 0.4, 1.03, 0 }, "Accent", "Cobblestone"),
			block({ 0.5, 0.26, 0.78 }, { 1.2, 1.03, 0 }, "Accent", "Cobblestone"),
		},
	},
	{
		Id = "cannon",
		DisplayName = "Cannon",
		Rarity = "Rare",
		Category = "Defense",
		Role = "Cannon",
		Description = "Slow, heavy shots that punch through armour and splash nearby enemies.",
		Tip = "The answer to armoured enemies and bosses. Pair with a Frost Beacon.",
		Behavior = "Splash",
		Targeting = "Strongest",
		Stats = { Health = 160, Damage = 40, Rate = 0.5, Range = 4, SplashRadius = 0.9 },
		FxHeight = 0.56,
		Colors = { Primary = { 52, 52, 58 }, Accent = { 138, 92, 52 }, Dark = { 90, 70, 50 } },
		Model = {
			vcyl(0.9, 0.12, { 0, 0.06, 0 }, "Dark", "WoodPlanks"),
			block({ 0.5, 0.24, 0.6 }, { 0, 0.26, 0.05 }, "Accent", "Wood", HEAD),
			{ Shape = "Cylinder", Size = { 0.1, 0.46, 0.46 }, Pos = { -0.32, 0.25, 0.1 }, Color = "Accent", Material = "Wood", Head = true },
			{ Shape = "Cylinder", Size = { 0.1, 0.46, 0.46 }, Pos = { 0.32, 0.25, 0.1 }, Color = "Accent", Material = "Wood", Head = true },
			barrel(0.8, 0.3, { 0, 0.54, -0.15 }, "Primary", "Metal", HEAD),
			barrel(0.1, 0.38, { 0, 0.54, -0.54 }, "Primary", "Metal", HEAD),
		},
	},
	{
		Id = "war_drum",
		DisplayName = "War Drum",
		Rarity = "Epic",
		Category = "Support",
		Role = "Buff Tower",
		Description = "Its rhythm drives nearby defenders into a frenzy.",
		Tip = "Boosts damage and fire rate of everything in range. Surround it with your best guns.",
		Behavior = "Support",
		Stats = { Health = 150, Range = 2.5, BuffDamage = 0.3, BuffRate = 0.15 },
		FxHeight = 0.7,
		Colors = { Primary = { 200, 48, 48 }, Accent = { 232, 206, 156 }, Dark = { 66, 44, 36 } },
		Model = {
			vcyl(0.86, 0.12, { 0, 0.06, 0 }, "Dark", "Wood"),
			vcyl(0.62, 0.5, { 0, 0.37, 0 }, "Primary", "Wood"),
			vcyl(0.64, 0.05, { 0, 0.645, 0 }, "Accent", "Fabric"),
			vcyl(0.06, 1.25, { 0.36, 0.7, 0.36 }, "Dark", "Wood"),
			block({ 0.03, 0.32, 0.42 }, { 0.36, 1.15, 0.15 }, "Primary", "Fabric"),
		},
	},
	{
		Id = "mortar",
		DisplayName = "Mortar",
		Rarity = "Epic",
		Category = "Offense",
		Role = "Mortar",
		Description = "Lobs explosive shells across the whole field. Can't hit anything too close.",
		Tip = "Huge range and splash. Keep it deep in your base and let walls hold enemies in clumps.",
		Footprint = { 2, 2 },
		Behavior = "Splash",
		Targeting = "First",
		Stats = { Health = 250, Damage = 70, Rate = 0.3, Range = 8, MinRange = 2, SplashRadius = 1.5 },
		FxHeight = 1.3,
		Colors = { Primary = { 82, 98, 70 }, Accent = { 170, 150, 110 }, Dark = { 70, 70, 74 } },
		Model = concat(sandbagRing(0.95, 0.36, 0.28), {
			block({ 1.9, 0.12, 1.9 }, { 0, 0.06, 0 }, "Dark", "Concrete"),
			vcyl(0.9, 0.16, { 0, 0.2, 0 }, "Dark", "Metal", HEAD),
			vcyl(0.5, 1.1, { 0, 0.75, -0.12 }, "Primary", "Metal", { Head = true, Rot = { -20, 0, 90 } }),
			vcyl(0.58, 0.12, { 0, 1.28, -0.3 }, "Dark", "Metal", { Head = true, Rot = { -20, 0, 90 } }),
		}),
	},
	{
		Id = "prism_laser",
		DisplayName = "Prism Laser",
		Rarity = "Legendary",
		Category = "Offense",
		Role = "Laser",
		Description = "Focuses light into a beam that pierces every enemy in a line.",
		Tip = "Aim down long straight corridors - one beam can hit a whole column of enemies.",
		Behavior = "Pierce",
		Targeting = "First",
		Stats = { Health = 220, Damage = 28, Rate = 1, Range = 6, PierceWidth = 0.45 },
		FxHeight = 1.05,
		Colors = { Primary = { 236, 238, 250 }, Accent = { 255, 198, 42 }, Dark = { 90, 80, 60 } },
		Model = {
			vcyl(0.86, 0.2, { 0, 0.1, 0 }, "Accent", "Metal"),
			vcyl(0.3, 0.7, { 0, 0.55, 0 }, "Primary", "Marble"),
			block({ 0.36, 0.36, 0.36 }, { 0, 1.05, 0 }, "Rarity", "Neon", { Head = true, Rot = { 45, 0, 45 } }),
			barrel(0.4, 0.1, { 0, 1.05, -0.3 }, "Accent", "Metal", HEAD),
		},
	},
	{
		Id = "tesla_coil",
		DisplayName = "Tesla Coil",
		Rarity = "Mythic",
		Category = "Offense",
		Role = "Chain Lightning",
		Description = "Arcs lightning from enemy to enemy.",
		Tip = "Each bolt jumps between up to five enemies. Best where enemies bunch up.",
		Behavior = "Chain",
		Targeting = "First",
		Stats = { Health = 260, Damage = 55, Rate = 0.8, Range = 4, Chains = 5, ChainRange = 2.5, ChainFalloff = 0.85 },
		FxHeight = 1.5,
		Colors = { Primary = { 62, 70, 92 }, Accent = { 120, 222, 255 }, Dark = { 36, 38, 48 } },
		Model = {
			block({ 0.82, 0.2, 0.82 }, { 0, 0.1, 0 }, "Dark", "DiamondPlate"),
			vcyl(0.3, 1.2, { 0, 0.8, 0 }, "Primary", "Metal"),
			vcyl(0.56, 0.06, { 0, 0.6, 0 }, "Accent", "Neon"),
			vcyl(0.5, 0.06, { 0, 0.9, 0 }, "Accent", "Neon"),
			vcyl(0.44, 0.06, { 0, 1.2, 0 }, "Accent", "Neon"),
			ball(0.5, { 0, 1.52, 0 }, "Accent", "Neon"),
		},
	},
	{
		Id = "the_anomaly",
		DisplayName = "The Anomaly",
		Rarity = "Secret",
		Category = "Special",
		Role = "???",
		Description = "Nobody knows what it is. Reality bends around it.",
		Tip = "Slows and erodes everything nearby. You probably shouldn't have this.",
		Hidden = true,
		Behavior = "Aura",
		Stats = { Health = 999, Damage = 45, Rate = 2, Range = 4, Slow = 0.5 },
		FxHeight = 1,
		Colors = { Primary = { 12, 10, 16 }, Accent = { 255, 0, 220 }, Dark = { 30, 0, 40 } },
		Model = {
			vcyl(0.9, 0.05, { 0, 0.03, 0 }, "Accent", "Neon"),
			ball(0.7, { 0, 1, 0 }, "Accent", "ForceField"),
			block({ 0.42, 0.42, 0.42 }, { 0, 1, 0 }, "Primary", "Neon", { Rot = { 45, 45, 45 } }),
		},
	},
}

local Items = {
	List = {} :: { ItemDef },
	ById = {} :: { [string]: ItemDef },
	Categories = { "Defense", "Offense", "Support", "Economy", "Special" },
}

for order, raw in list do
	local def: ItemDef = {
		Id = raw.Id,
		DisplayName = raw.DisplayName,
		Rarity = raw.Rarity,
		Category = raw.Category,
		Role = raw.Role,
		Description = raw.Description,
		Tip = raw.Tip or "",
		World = raw.World or "Greenland",
		Rollable = raw.Rollable ~= false,
		RollWeight = raw.RollWeight or 1,
		Hidden = raw.Hidden == true,
		Footprint = raw.Footprint or { 1, 1 },
		Blocks = raw.Blocks ~= false,
		Behavior = raw.Behavior,
		Targeting = raw.Targeting or "First",
		Stats = raw.Stats,
		FxHeight = raw.FxHeight or 0.6,
		Colors = raw.Colors,
		Model = raw.Model,
		Order = order,
	}
	assert(not Items.ById[def.Id], "Duplicate item id " .. def.Id)
	table.insert(Items.List, def)
	Items.ById[def.Id] = def
end

function Items.Get(id: string): ItemDef?
	return Items.ById[id]
end

function Items.IsValid(id: any): boolean
	return type(id) == "string" and Items.ById[id] ~= nil
end

return Items

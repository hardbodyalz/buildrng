--[[
	Enemies
	Data-driven enemy + boss definitions. The DefenseSim reads stats and
	phases; the client EnemyRenderer builds visuals from `Model`.

	Stats
	  Health, Speed (cells/s), Armor (flat reduction per hit), CoreDamage,
	  StructureDps (damage/s while smashing a structure), Reward (coins),
	  Xp, Threat (budget cost for procedural waves), MinWave (first procedural
	  wave it may appear in), GroupSize (spawns in clumps), SlowResist (0..1),
	  Regen (fraction of max HP per second), PathCostMult (<1 = prefers to smash
	  through walls rather than walk around), Scale (visual).

	Bosses additionally have `Phases`, evaluated by remaining HP fraction:
	  { HpBelow, Name, SpeedMult?, StructureDamageMult?, PathCostMult?,
	    Summon = { Enemy, Count, Interval }?, Announce? }

	Model parts are in studs, origin = feet. Colors: Primary | Accent | Dark | Eye | {r,g,b}
]]

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	Index: number,
	Health: number,
	Speed: number,
	Armor: number,
	CoreDamage: number,
	StructureDps: number,
	Reward: number,
	Xp: number,
	Threat: number,
	MinWave: number,
	GroupSize: number,
	SlowResist: number,
	Regen: number,
	PathCostMult: number,
	Scale: number,
	IsBoss: boolean,
	DiceReward: number,
	Phases: { any }?,
	MusicId: string?,
	Colors: { [string]: { number } },
	Model: { any },
}

local function part(shape, size, pos, color, material, rot)
	return { Shape = shape, Size = size, Pos = pos, Color = color, Material = material, Rot = rot }
end

local function humanoid(opts)
	-- Blocky humanoid silhouette; opts tweak proportions.
	local lean = opts.Lean or 0
	local parts = {
		part("Block", { 0.55, 1.3, 0.55 }, { -0.35, 0.65, 0 }, "Dark", "SmoothPlastic"),
		part("Block", { 0.55, 1.3, 0.55 }, { 0.35, 0.65, 0 }, "Dark", "SmoothPlastic"),
		part("Block", { 1.4, 1.5, 0.8 }, { 0, 2.05, -lean * 0.3 }, "Primary", "SmoothPlastic", { lean * 20, 0, 0 }),
		part("Block", { 1, 1, 1 }, { 0, 3.3, -lean * 0.6 }, "Accent", "SmoothPlastic"),
		part("Block", { 0.22, 0.18, 0.05 }, { -0.22, 3.4, -0.5 - lean * 0.6 }, "Eye", "Neon"),
		part("Block", { 0.22, 0.18, 0.05 }, { 0.22, 3.4, -0.5 - lean * 0.6 }, "Eye", "Neon"),
	}
	if opts.ZombieArms then
		table.insert(parts, part("Block", { 0.4, 0.4, 1.3 }, { -0.9, 2.5, -0.55 }, "Accent", "SmoothPlastic"))
		table.insert(parts, part("Block", { 0.4, 0.4, 1.3 }, { 0.9, 2.5, -0.55 }, "Accent", "SmoothPlastic"))
	else
		table.insert(parts, part("Block", { 0.4, 1.3, 0.4 }, { -0.9, 2.0, 0 }, "Accent", "SmoothPlastic"))
		table.insert(parts, part("Block", { 0.4, 1.3, 0.4 }, { 0.9, 2.0, 0 }, "Accent", "SmoothPlastic"))
	end
	if opts.Extra then
		for _, p in opts.Extra do
			table.insert(parts, p)
		end
	end
	return parts
end

local list: { any } = {
	{
		Id = "walker",
		DisplayName = "Walker",
		Description = "Shambling undead. Slow, steady, endless.",
		Health = 30, Speed = 1.0, Armor = 0, CoreDamage = 5, StructureDps = 10,
		Reward = 3, Xp = 1, Threat = 1, MinWave = 1,
		Colors = { Primary = { 70, 110, 80 }, Accent = { 128, 170, 110 }, Dark = { 50, 60, 70 }, Eye = { 255, 60, 40 } },
		Model = humanoid({ ZombieArms = true }),
	},
	{
		Id = "runner",
		DisplayName = "Runner",
		Description = "Fast and fragile. Sprints straight for your Core.",
		Health = 20, Speed = 2.1, Armor = 0, CoreDamage = 4, StructureDps = 5,
		Reward = 3, Xp = 1, Threat = 1.2, MinWave = 2, Scale = 0.9,
		Colors = { Primary = { 170, 60, 50 }, Accent = { 150, 170, 120 }, Dark = { 60, 40, 40 }, Eye = { 255, 220, 60 } },
		Model = humanoid({ Lean = 1 }),
	},
	{
		Id = "swarmling",
		DisplayName = "Swarmling",
		Description = "Tiny crawlers that arrive in packs.",
		Health = 9, Speed = 1.5, Armor = 0, CoreDamage = 2, StructureDps = 3,
		Reward = 1, Xp = 0.4, Threat = 0.35, MinWave = 3, GroupSize = 5, Scale = 0.8,
		Colors = { Primary = { 110, 60, 140 }, Accent = { 70, 30, 90 }, Dark = { 40, 20, 50 }, Eye = { 120, 255, 80 } },
		Model = {
			part("Ball", { 1.6, 1.2, 1.9 }, { 0, 0.75, 0 }, "Primary", "SmoothPlastic"),
			part("Ball", { 1, 0.9, 1 }, { 0, 0.8, -0.9 }, "Accent", "SmoothPlastic"),
			part("Block", { 0.2, 0.2, 0.05 }, { -0.2, 0.95, -1.4 }, "Eye", "Neon"),
			part("Block", { 0.2, 0.2, 0.05 }, { 0.2, 0.95, -1.4 }, "Eye", "Neon"),
			part("Block", { 2.2, 0.15, 0.15 }, { 0, 0.3, -0.3 }, "Dark", "SmoothPlastic"),
			part("Block", { 2.2, 0.15, 0.15 }, { 0, 0.3, 0.4 }, "Dark", "SmoothPlastic"),
		},
	},
	{
		Id = "brute",
		DisplayName = "Brute",
		Description = "A walking tank. Smashes walls and shrugs off slows.",
		Health = 180, Speed = 0.6, Armor = 3, CoreDamage = 20, StructureDps = 30,
		Reward = 14, Xp = 5, Threat = 6, MinWave = 4, SlowResist = 0.3, Scale = 1.5, PathCostMult = 0.6,
		Colors = { Primary = { 96, 100, 90 }, Accent = { 150, 160, 130 }, Dark = { 60, 58, 56 }, Eye = { 255, 120, 0 } },
		Model = humanoid({
			Extra = {
				part("Block", { 1.7, 0.5, 1 }, { 0, 2.8, 0 }, "Dark", "Metal"),
				part("Block", { 0.6, 0.6, 0.6 }, { -1.1, 1.3, 0 }, "Dark", "Metal"),
				part("Block", { 0.6, 0.6, 0.6 }, { 1.1, 1.3, 0 }, "Dark", "Metal"),
			},
		}),
	},
	{
		Id = "shieldbearer",
		DisplayName = "Shieldbearer",
		Description = "Carries a heavy shield. Small bullets barely scratch it.",
		Health = 80, Speed = 0.85, Armor = 7, CoreDamage = 8, StructureDps = 12,
		Reward = 9, Xp = 3, Threat = 3.5, MinWave = 6,
		Colors = { Primary = { 60, 80, 130 }, Accent = { 140, 160, 130 }, Dark = { 40, 44, 60 }, Eye = { 120, 200, 255 } },
		Model = humanoid({
			Extra = {
				part("Block", { 2.1, 2.6, 0.3 }, { 0, 1.9, -0.8 }, { 170, 176, 190 }, "DiamondPlate"),
				part("Block", { 0.6, 0.6, 0.1 }, { 0, 2.1, -0.98 }, { 230, 190, 60 }, "Metal"),
			},
		}),
	},
	{
		Id = "colossus",
		DisplayName = "The Colossus",
		Description = "An ancient stone giant. It gets angrier the more you hurt it.",
		IsBoss = true,
		Health = 1500, Speed = 0.45, Armor = 4, CoreDamage = 60, StructureDps = 50,
		Reward = 400, Xp = 150, DiceReward = 3, Threat = 0, MinWave = 10,
		SlowResist = 0.6, Scale = 2.6,
		MusicId = "",
		Phases = {
			{ HpBelow = 1.0, Name = "Awakened" },
			{
				HpBelow = 0.75,
				Name = "Call of the Horde",
				Summon = { Enemy = "walker", Count = 4, Interval = 7 },
				Announce = "The Colossus calls the horde!",
			},
			{
				HpBelow = 0.5,
				Name = "Wallbreaker",
				SpeedMult = 1.2,
				StructureDamageMult = 4,
				PathCostMult = 0.15,
				Announce = "The Colossus starts smashing through walls!",
			},
			{
				HpBelow = 0.25,
				Name = "RAGE",
				SpeedMult = 1.9,
				StructureDamageMult = 4,
				PathCostMult = 0.15,
				Summon = { Enemy = "runner", Count = 3, Interval = 5 },
				Announce = "The Colossus enters a RAGE!",
			},
		},
		Colors = { Primary = { 110, 104, 96 }, Accent = { 140, 132, 120 }, Dark = { 70, 66, 62 }, Eye = { 255, 110, 20 } },
		Model = {
			part("Block", { 0.9, 1.4, 0.9 }, { -0.55, 0.7, 0 }, "Dark", "Slate"),
			part("Block", { 0.9, 1.4, 0.9 }, { 0.55, 0.7, 0 }, "Dark", "Slate"),
			part("Block", { 2.4, 1.9, 1.5 }, { 0, 2.3, 0 }, "Primary", "Slate"),
			part("Block", { 1.2, 1, 1.1 }, { 0, 3.7, -0.2 }, "Accent", "Slate"),
			part("Block", { 0.9, 0.18, 0.05 }, { 0, 3.8, -0.78 }, "Eye", "Neon"),
			part("Block", { 0.8, 2.2, 0.8 }, { -1.65, 2, -0.2 }, "Accent", "Slate"),
			part("Block", { 0.8, 2.2, 0.8 }, { 1.65, 2, -0.2 }, "Accent", "Slate"),
			part("Block", { 1.1, 0.9, 1.1 }, { -1.65, 0.8, -0.3 }, "Dark", "Slate"),
			part("Block", { 1.1, 0.9, 1.1 }, { 1.65, 0.8, -0.3 }, "Dark", "Slate"),
			part("Block", { 1.6, 0.5, 0.2 }, { 0, 2.6, -0.8 }, "Eye", "Neon"),
		},
	},
}

local Enemies = {
	List = {} :: { EnemyDef },
	ById = {} :: { [string]: EnemyDef },
}

for index, raw in list do
	local def: EnemyDef = {
		Id = raw.Id,
		DisplayName = raw.DisplayName,
		Description = raw.Description or "",
		Index = index,
		Health = raw.Health,
		Speed = raw.Speed,
		Armor = raw.Armor or 0,
		CoreDamage = raw.CoreDamage,
		StructureDps = raw.StructureDps,
		Reward = raw.Reward,
		Xp = raw.Xp or 1,
		Threat = raw.Threat or 1,
		MinWave = raw.MinWave or 1,
		GroupSize = raw.GroupSize or 1,
		SlowResist = raw.SlowResist or 0,
		Regen = raw.Regen or 0,
		PathCostMult = raw.PathCostMult or 1,
		Scale = raw.Scale or 1,
		IsBoss = raw.IsBoss == true,
		DiceReward = raw.DiceReward or 0,
		Phases = raw.Phases,
		MusicId = raw.MusicId,
		Colors = raw.Colors,
		Model = raw.Model,
	}
	assert(not Enemies.ById[def.Id], "Duplicate enemy id " .. def.Id)
	table.insert(Enemies.List, def)
	Enemies.ById[def.Id] = def
end

function Enemies.Get(id: string): EnemyDef
	local def = Enemies.ById[id]
	assert(def, "Unknown enemy " .. tostring(id))
	return def
end

return Enemies

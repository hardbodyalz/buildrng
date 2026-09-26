--[[
	Progression
	Levels, base expansions, permanent upgrades, feature unlocks, collection
	rewards, pity and starter content.
]]

local Progression = {}

-- XP needed to go from level L to L+1.
function Progression.XpForLevel(level: number): number
	return math.floor(40 * level ^ 1.55)
end

-- Base expansion tiers. Width/Length are odd so the entrance and Core stay centred.
-- Capacity = max placed structures. Style fields drive how the plot looks, so a
-- base visibly grows from a sandbag bunker into a gleaming citadel.
Progression.Expansions = {
	{ Name = "Bunker", Width = 7, Length = 11, Capacity = 10, Level = 1, Cost = 0,
		Style = { Floor = "Ground", FloorColor = { 128, 112, 84 }, Wall = "Fabric", WallColor = { 176, 156, 112 }, WallHeight = 2.5, Trim = { 90, 80, 60 } } },
	{ Name = "Outpost", Width = 9, Length = 13, Capacity = 14, Level = 3, Cost = 1200,
		Style = { Floor = "Pebble", FloorColor = { 120, 118, 104 }, Wall = "WoodPlanks", WallColor = { 140, 100, 62 }, WallHeight = 3.5, Trim = { 90, 64, 40 } } },
	{ Name = "Compound", Width = 11, Length = 15, Capacity = 19, Level = 6, Cost = 5000,
		Style = { Floor = "Concrete", FloorColor = { 132, 134, 138 }, Wall = "Concrete", WallColor = { 150, 152, 156 }, WallHeight = 4, Trim = { 220, 180, 40 } } },
	{ Name = "Stronghold", Width = 13, Length = 17, Capacity = 25, Level = 10, Cost = 18000,
		Style = { Floor = "Slate", FloorColor = { 104, 108, 116 }, Wall = "Cobblestone", WallColor = { 128, 130, 138 }, WallHeight = 5, Trim = { 70, 70, 80 } } },
	{ Name = "Fortress", Width = 15, Length = 19, Capacity = 32, Level = 15, Cost = 55000,
		Style = { Floor = "Slate", FloorColor = { 84, 88, 100 }, Wall = "Brick", WallColor = { 110, 70, 60 }, WallHeight = 6, Trim = { 200, 60, 50 } } },
	{ Name = "Military Complex", Width = 17, Length = 21, Capacity = 40, Level = 22, Cost = 160000,
		Style = { Floor = "DiamondPlate", FloorColor = { 90, 96, 104 }, Wall = "Metal", WallColor = { 70, 78, 88 }, WallHeight = 7, Trim = { 60, 200, 255 } } },
	{ Name = "Citadel", Width = 21, Length = 25, Capacity = 52, Level = 30, Cost = 450000,
		Style = { Floor = "Marble", FloorColor = { 228, 226, 218 }, Wall = "Marble", WallColor = { 240, 238, 230 }, WallHeight = 9, Trim = { 255, 196, 40 } } },
}

-- Permanent coin upgrades. Values[i] is the value at upgrade level i-1 (level 0 = base).
-- Costs[i] is the price to go from level i-1 to level i.
Progression.Upgrades = {
	{
		Id = "Luck",
		Name = "Luck",
		Description = "Shifts roll odds toward higher rarities.",
		Format = "x%.2f",
		Values = { 1, 1.25, 1.5, 2, 3, 3.4, 3.8, 4.2, 4.6, 5 },
		Costs = { 250, 900, 2800, 9000, 22000, 45000, 80000, 130000, 200000 },
	},
	{
		Id = "RollSpeed",
		Name = "Roll Speed",
		Description = "Seconds between rolls.",
		Format = "%.2fs",
		Values = { 1.6, 1.45, 1.3, 1.15, 1.0, 0.9, 0.8, 0.7 },
		Costs = { 150, 500, 1500, 4500, 11000, 24000, 50000 },
	},
	{
		Id = "CoreHealth",
		Name = "Core Plating",
		Description = "Maximum Core HP.",
		Format = "%d HP",
		Values = { 100, 130, 170, 220, 290, 380, 500, 650 },
		Costs = { 300, 1000, 3000, 8000, 20000, 48000, 110000 },
	},
}

-- Feature unlock requirements (all listed conditions must be met).
-- Keeps the first hour understandable: roll/build/defend first, the rest later.
Progression.Unlocks = {
	Index = { TutorialDone = true },
	Upgrades = { HighestWave = 3 },
	Expansion = { HighestWave = 5 },
	Mutations = { HighestWave = 6 },
	LuckyRoll = { BossesDefeated = 1 },
	MassSell = { TotalRolls = 25 },
}

-- Rolls-without-X protection. Soft pity boosts the tracked rarity (and above)
-- after SoftStart rolls; at Guarantee the roll is forced to at least that rarity.
Progression.Pity = {
	{ Id = "Epic", Rarity = "Epic", SoftStart = 80, SoftBoostPerRoll = 0.03, Guarantee = 200 },
	{ Id = "Legendary", Rarity = "Legendary", SoftStart = 500, SoftBoostPerRoll = 0.006, Guarantee = 1500 },
	{ Id = "Mythic", Rarity = "Mythic", SoftStart = 1000, SoftBoostPerRoll = 0.003, Guarantee = 2500 },
}

-- Completing every rollable item of a rarity in the Index grants permanent luck.
-- (Secret/hidden items don't count toward completion.)
Progression.CollectionRewards = {
	{ Id = "AllCommon", Rarity = "Common", LuckBonus = 0.05, Title = "Scavenger" },
	{ Id = "AllUncommon", Rarity = "Uncommon", LuckBonus = 0.08, Title = "Collector" },
	{ Id = "AllRare", Rarity = "Rare", LuckBonus = 0.1, Title = "Curator" },
	{ Id = "AllEpic", Rarity = "Epic", LuckBonus = 0.15, Title = "Archivist" },
	{ Id = "AllLegendary", Rarity = "Legendary", LuckBonus = 0.2, Title = "Legend Keeper" },
	{ Id = "AllMythic", Rarity = "Mythic", LuckBonus = 0.3, Title = "Mythkeeper" },
}

Progression.StarterInventory = {}

return Progression

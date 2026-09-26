--[[
	GameConfig
	Global tunables. Anything a designer might want to tweak without touching
	systems code lives here (content lives in the sibling Config modules).
]]

local GameConfig = {}

GameConfig.Version = "0.1.0-slice"

-- Plot grid. Coordinates are integer cells in [0, MaxWidth-1] x [0, MaxLength-1].
-- +Z points from the entrance toward the Core. The Core always sits at the
-- far (+Z) end of the grid; base expansions grow the active area outward
-- (wider, and longer toward the entrance) so placed structures never move.
GameConfig.Grid = {
	CellSize = 4, -- studs
	MaxWidth = 21,
	MaxLength = 25,
	CoreSize = 3, -- Core is CoreSize x CoreSize cells, centred on the X axis
	EntranceWidth = 3, -- restricted spawn gate width at the entrance row
}

GameConfig.Plots = {
	Count = 6, -- one per player, server max ~6
	ColumnSpacing = 120, -- studs between plot centres along X
	RowDistance = 80, -- studs from world origin to each row's plot centre
}

GameConfig.Roll = {
	-- Seconds between rolls before upgrades (see Progression.Upgrades.RollSpeed).
	CooldownTolerance = 0.12, -- latency grace for the server-side cooldown check
	DiceCostLuckyRoll = 1,
	LuckyRollMultiplier = 2, -- luck multiplier applied to a Dice-powered roll
	-- Scripted early rolls so the tutorial always has something to place.
	ScriptedRolls = { "scrap_turret", "wooden_barricade" },
	AutoRollStopOrder = 4, -- auto-roll pauses on anything at/above this rarity order (Epic)
}

GameConfig.Luck = {
	-- Raw luck above SoftCap is compressed: SoftCap * (raw / SoftCap) ^ Exponent.
	SoftCap = 5,
	SoftCapExponent = 0.55,
	HardCap = 250,
	-- Mutation chance scales with luck ^ MutationExponent (gentler than rarity luck).
	MutationExponent = 0.5,
}

GameConfig.Defense = {
	TickRate = 10, -- simulation steps per second (server)
	StartCountdown = 3,
	Intermission = 4, -- seconds between waves
	BaseCoreHealth = 100,
	CoreRegenPerWave = 0.1, -- fraction of max HP restored after each cleared wave
	-- Path cost of walking through a blocking structure: 1 + HP * PathCostPerHp.
	-- Enemies pick detours instead of smashing a wall when the detour is shorter.
	PathCostPerHp = 1 / 25,
	MaxAliveEnemies = 140,
	CheckpointInterval = 10, -- player may restart from wave 1, 11, 21, ...
	SnapshotRange = 400, -- studs; clients farther than this from a plot don't get its snapshots
	ArmorMinDamageFraction = 0.2, -- armor can never reduce a hit below this fraction
}

GameConfig.Economy = {
	StartingCoins = 150,
	StartingDice = 0,
	StoreRefundFraction = 1, -- fraction of upgrade coins refunded when a structure is stored
}

GameConfig.Offline = {
	MinSeconds = 120, -- below this we don't bother showing a report
	MaxSeconds = 8 * 3600,
	Efficiency = 0.5, -- offline earns this fraction of the simulated online rate
	FailedEfficiency = 0.2, -- if the base can't even clear wave 1
	MinCoinsPerHour = 120, -- floor so time away is never worth literally nothing
	SimDt = 0.25, -- coarse step for the headless offline run
	MaxSimWaves = 60, -- cap on waves the offline run will simulate before extrapolating
	MaxSimSteps = 40000,
	YieldEverySteps = 400,
}

GameConfig.Data = {
	StoreName = "BuildDefendRNG_Players_v1",
	KeyPrefix = "p_",
	AutosaveInterval = 60,
	SessionLockTimeout = 300, -- a lock older than this is considered abandoned (crashed server)
	LoadRetries = 6,
	LoadRetryDelay = 4,
	SaveRetries = 4,
}

-- Token buckets per remote: Rate tokens/sec, Burst max tokens.
GameConfig.RateLimits = {
	Default = { Rate = 5, Burst = 10 },
	Roll = { Rate = 4, Burst = 4 },
	Place = { Rate = 10, Burst = 20 },
	Sell = { Rate = 6, Burst = 12 },
	Defense = { Rate = 1, Burst = 3 },
	Purchase = { Rate = 4, Burst = 8 },
}

return GameConfig

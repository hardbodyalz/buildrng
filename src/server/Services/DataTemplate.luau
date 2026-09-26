--[[
	DataTemplate
	Shape of a player's saved data. New fields added here are automatically
	back-filled into old saves by DataService.Reconcile; structural changes
	go through DataTemplate.Migrations (keyed by the version they upgrade FROM).

	DataStore-safe: only string-keyed dictionaries or pure arrays, no mixing.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local DataTemplate = {}

DataTemplate.Version = 1

function DataTemplate.New()
	return {
		Version = DataTemplate.Version,
		Coins = GameConfig.Economy.StartingCoins,
		Dice = GameConfig.Economy.StartingDice,
		Xp = 0,
		Level = 1,
		Stats = {
			TotalRolls = 0,
			EnemiesDefeated = 0,
			HighestWave = 0,
			BossesDefeated = 0,
			WavesCleared = 0,
			DefensesRun = 0,
			CoinsEarned = 0,
			BestRarityOrder = 0,
			Mutations = 0,
		},
		Pity = {}, -- pityId -> rolls since that tier
		Inventory = {}, -- "itemId|Mutation" -> { Count, Locked, Favorite }
		Index = {}, -- itemId -> { First = unix, Count, Muts = { [mutationId] = true } }
		Collections = {}, -- collectionRewardId -> true
		Unlocked = {}, -- feature -> true (so unlock toasts show once)
		Base = {
			Tier = 1,
			NextUid = 1,
			Structures = {}, -- "s<uid>" -> { Id, Mut, Lvl, X, Z, R, Spent }
		},
		Upgrades = {
			Luck = 0,
			RollSpeed = 0,
			CoreHealth = 0,
		},
		Tutorial = { Step = 1, Done = false },
		LastOnline = 0,
		Settings = {},
	}
end

-- [fromVersion] = function(data) ... end  (must set data.Version = fromVersion + 1)
DataTemplate.Migrations = {}

return DataTemplate

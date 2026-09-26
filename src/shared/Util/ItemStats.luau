--[[
	ItemStats
	Turns an item definition + level + mutation into concrete numbers. The only
	place that knows how levels and mutations scale stats, so the sim, offline
	estimator, sell prices and UI can never disagree.
]]

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)

local ItemStats = {}

-- Per-level additive growth (level 1 = base).
ItemStats.LevelGrowth = {
	Damage = 0.18,
	Health = 0.12,
	CoinsPerWave = 0.15,
}

-- Stats that the mutation multiplier applies to.
local MUTATION_SCALED = {
	Damage = true,
	Health = true,
	CoinsPerWave = true,
}

ItemStats.UpgradeCostGrowth = 1.55

function ItemStats.MaxLevel(def: any): number
	return Rarities.Get(def.Rarity).MaxLevel
end

function ItemStats.Compute(def: any, level: number?, mutationId: string?): { [string]: number }
	local lvl = math.max(1, level or 1)
	local mult = Mutations.Get(mutationId).StatMultiplier
	local out = {}
	for key, base in def.Stats do
		local value = base
		local growth = ItemStats.LevelGrowth[key]
		if growth then
			value *= 1 + growth * (lvl - 1)
		end
		if MUTATION_SCALED[key] then
			value *= mult
		end
		out[key] = value
	end
	return out
end

-- Coins to go from `level` to `level + 1`.
function ItemStats.UpgradeCost(def: any, level: number): number
	local base = Rarities.Get(def.Rarity).UpgradeBaseCost
	return math.floor(base * ItemStats.UpgradeCostGrowth ^ (level - 1))
end

function ItemStats.SellValue(def: any, mutationId: string?): number
	local r = Rarities.Get(def.Rarity)
	return math.floor(r.SellValue * Mutations.Get(mutationId).ValueMultiplier)
end

-- Rough sustained damage per second for UI and power estimates.
function ItemStats.Dps(def: any, stats: { [string]: number }): number
	local dmg = stats.Damage or 0
	local rate = stats.Rate or 0
	local b = def.Behavior
	if b == "Chain" then
		local total, f = 0, 1
		for _ = 1, (stats.Chains or 1) do
			total += f
			f *= stats.ChainFalloff or 1
		end
		return dmg * rate * total
	end
	return dmg * rate
end

-- Human-readable stat lines for the UI: { { Label, Value } }
function ItemStats.Describe(def: any, stats: { [string]: number }): { { string } }
	local lines = {}
	local function add(label, value)
		table.insert(lines, { label, value })
	end
	if stats.Damage then
		add("Damage", string.format("%.1f", stats.Damage))
	end
	if stats.Rate then
		add("Attack speed", string.format("%.2f/s", stats.Rate))
	end
	if stats.Damage and stats.Rate then
		add("DPS", string.format("%.1f", ItemStats.Dps(def, stats)))
	end
	if stats.Range then
		add("Range", string.format("%.1f tiles", stats.Range))
	end
	if stats.MinRange then
		add("Min range", string.format("%.1f tiles", stats.MinRange))
	end
	if stats.SplashRadius then
		add("Splash", string.format("%.1f tiles", stats.SplashRadius))
	end
	if stats.Chains then
		add("Chains", string.format("%d", stats.Chains))
	end
	if stats.Slow then
		add("Slow", string.format("%d%%", math.floor(stats.Slow * 100 + 0.5)))
	end
	if stats.BuffDamage then
		add("Damage buff", string.format("+%d%%", math.floor(stats.BuffDamage * 100 + 0.5)))
	end
	if stats.BuffRate then
		add("Speed buff", string.format("+%d%%", math.floor(stats.BuffRate * 100 + 0.5)))
	end
	if stats.CoinsPerWave then
		add("Coins / wave", string.format("%d", math.floor(stats.CoinsPerWave)))
	end
	if stats.Health and def.Blocks then
		add("Health", string.format("%d", math.floor(stats.Health)))
	end
	return lines
end

return ItemStats

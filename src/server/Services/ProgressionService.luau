--[[
	ProgressionService
	Derived player state (luck, roll speed, core HP, build capacity, odds,
	pity progress, feature unlocks) plus permanent upgrades, base expansions,
	collection rewards and tutorial progress.

	"Derived" values are computed only here and replicated to the client as a
	read-only section so UI and server can never disagree.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Config.Progression)
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Luck = require(Shared.Util.Luck)
local RollMath = require(Shared.Util.RollMath)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)

local ProgressionService = {}

local TUTORIAL_STEPS = 8
local TUTORIAL_REWARD = 150

local upgradeById = {}
for _, u in Progression.Upgrades do
	upgradeById[u.Id] = u
end

local FEATURE_NAMES = {
	Index = "Index",
	Upgrades = "Upgrades shop",
	Expansion = "Base expansion",
	Mutations = "Mutations",
	LuckyRoll = "Lucky Rolls",
	MassSell = "Mass sell",
}

local function data(player)
	return Registry.DataService:Get(player)
end

function ProgressionService:UpgradeValue(d, id: string): number
	local u = upgradeById[id]
	local level = math.clamp(d.Upgrades[id] or 0, 0, #u.Values - 1)
	return u.Values[level + 1]
end

function ProgressionService:CollectionLuckBonus(d): number
	local bonus = 0
	for _, c in Progression.CollectionRewards do
		if d.Collections[c.Id] then
			bonus += c.LuckBonus
		end
	end
	return bonus
end

-- Effective luck (after diminishing returns). extraMult = e.g. Lucky Roll.
function ProgressionService:GetLuck(player: Player, extraMult: number?): number
	local d = data(player)
	if not d then
		return 1
	end
	return Luck.Compute({
		Base = self:UpgradeValue(d, "Luck"),
		Additive = { self:CollectionLuckBonus(d) },
		Multipliers = { extraMult or 1 },
	})
end

function ProgressionService:GetRollCooldown(player: Player): number
	local d = data(player)
	return if d then self:UpgradeValue(d, "RollSpeed") else 2
end

function ProgressionService:GetCoreMaxHealth(player: Player): number
	local d = data(player)
	return if d then self:UpgradeValue(d, "CoreHealth") else GameConfig.Defense.BaseCoreHealth
end

function ProgressionService:GetCapacity(player: Player): number
	local d = data(player)
	if not d then
		return 0
	end
	local e = Progression.Expansions[math.clamp(d.Base.Tier, 1, #Progression.Expansions)]
	return e.Capacity
end

function ProgressionService:IsUnlocked(player: Player, feature: string): boolean
	local d = data(player)
	if not d then
		return false
	end
	local req = Progression.Unlocks[feature]
	if not req then
		return true
	end
	if req.TutorialDone and not d.Tutorial.Done then
		return false
	end
	if req.HighestWave and d.Stats.HighestWave < req.HighestWave then
		return false
	end
	if req.BossesDefeated and d.Stats.BossesDefeated < req.BossesDefeated then
		return false
	end
	if req.TotalRolls and d.Stats.TotalRolls < req.TotalRolls then
		return false
	end
	if req.Level and d.Level < req.Level then
		return false
	end
	return true
end

function ProgressionService:DescribeRequirement(feature: string): string
	local req = Progression.Unlocks[feature]
	if not req then
		return ""
	end
	if req.TutorialDone then
		return "Finish the tutorial"
	elseif req.HighestWave then
		return "Reach wave " .. req.HighestWave
	elseif req.BossesDefeated then
		return "Defeat a boss"
	elseif req.TotalRolls then
		return "Roll " .. req.TotalRolls .. " times"
	elseif req.Level then
		return "Reach level " .. req.Level
	end
	return ""
end

local rollPool = RollMath.BuildPool(Items.List)

function ProgressionService:GetDerived(player: Player)
	local d = data(player)
	if not d then
		return nil
	end
	local luck = self:GetLuck(player)
	local odds = {}
	for _, o in RollMath.Odds(rollPool, luck, Progression.Pity, d.Pity) do
		-- Hidden rarities only show once discovered.
		if not o.Rarity.Hidden or (d.Stats.BestRarityOrder >= o.Rarity.Order) then
			table.insert(odds, { Rarity = o.Rarity.Id, Chance = o.Chance })
		end
	end
	local pity = {}
	for _, p in Progression.Pity do
		table.insert(pity, { Id = p.Id, Rarity = p.Rarity, Count = d.Pity[p.Id] or 0, Guarantee = p.Guarantee })
	end
	local unlocks, requirements = {}, {}
	for feature in Progression.Unlocks do
		unlocks[feature] = self:IsUnlocked(player, feature)
		requirements[feature] = self:DescribeRequirement(feature)
	end
	local tier = math.clamp(d.Base.Tier, 1, #Progression.Expansions)
	local nextExp = Progression.Expansions[tier + 1]
	local upgrades = {}
	for _, u in Progression.Upgrades do
		local level = d.Upgrades[u.Id] or 0
		table.insert(upgrades, {
			Id = u.Id,
			Level = level,
			Value = u.Values[level + 1],
			Next = u.Values[level + 2],
			Cost = u.Costs[level + 1],
		})
	end
	return {
		Luck = luck,
		LuckyRollLuck = self:GetLuck(player, GameConfig.Roll.LuckyRollMultiplier),
		CollectionLuck = self:CollectionLuckBonus(d),
		RollCooldown = self:GetRollCooldown(player),
		CoreMaxHealth = self:GetCoreMaxHealth(player),
		Capacity = self:GetCapacity(player),
		Tier = tier,
		TierName = Progression.Expansions[tier].Name,
		NextExpansion = if nextExp
			then { Name = nextExp.Name, Level = nextExp.Level, Cost = nextExp.Cost, Capacity = nextExp.Capacity, Width = nextExp.Width, Length = nextExp.Length }
			else nil,
		Odds = odds,
		Pity = pity,
		Unlocks = unlocks,
		UnlockRequirements = requirements,
		Upgrades = upgrades,
		XpToNext = Progression.XpForLevel(d.Level),
		PlotId = player:GetAttribute("PlotId"),
	}
end

-- Recompute derived state, announce newly unlocked features.
function ProgressionService:Refresh(player: Player)
	local d = data(player)
	if not d then
		return
	end
	for feature in Progression.Unlocks do
		if self:IsUnlocked(player, feature) and not d.Unlocked[feature] then
			d.Unlocked[feature] = true
			Net.Notify(player, "Unlocked: " .. (FEATURE_NAMES[feature] or feature) .. "!", "Unlock")
		end
	end
	Registry.DataService:Replicate(player, "Derived", "Unlocked")
end

-- Called after the Index changes.
function ProgressionService:CheckCollections(player: Player)
	local d = data(player)
	if not d then
		return
	end
	local changed = false
	for _, c in Progression.CollectionRewards do
		if not d.Collections[c.Id] then
			local total, found = 0, 0
			for _, def in Items.List do
				if def.Rarity == c.Rarity and def.Rollable and not def.Hidden then
					total += 1
					if d.Index[def.Id] then
						found += 1
					end
				end
			end
			if total > 0 and found == total then
				d.Collections[c.Id] = true
				changed = true
				Net.Notify(
					player,
					string.format("Collection complete: every %s item! +%d%% Luck", Rarities.Get(c.Rarity).Name, math.floor(c.LuckBonus * 100 + 0.5)),
					"Collection"
				)
			end
		end
	end
	if changed then
		Registry.DataService:Replicate(player, "Collections")
		self:Refresh(player)
	end
end

function ProgressionService:Init()
	Net.Handle("BuyUpgrade", function(player, upgradeId)
		if type(upgradeId) ~= "string" or not upgradeById[upgradeId] then
			return false, "Unknown upgrade"
		end
		if not self:IsUnlocked(player, "Upgrades") then
			return false, "Upgrades are locked"
		end
		local d = data(player)
		local u = upgradeById[upgradeId]
		local level = d.Upgrades[upgradeId] or 0
		local cost = u.Costs[level + 1]
		if not cost then
			return false, "Already maxed"
		end
		if not Registry.EconomyService:SpendCoins(player, cost) then
			return false, "Not enough coins"
		end
		d.Upgrades[upgradeId] = level + 1
		Registry.DataService:Replicate(player, "Upgrades")
		self:Refresh(player)
		if upgradeId == "CoreHealth" then
			Registry.DefenseService:OnStatsChanged(player)
		end
		return true, d.Upgrades[upgradeId]
	end)

	Net.Handle("BuyExpansion", function(player)
		if not self:IsUnlocked(player, "Expansion") then
			return false, "Expansion is locked"
		end
		local d = data(player)
		local nextTier = d.Base.Tier + 1
		local e = Progression.Expansions[nextTier]
		if not e then
			return false, "Your base is already a Citadel!"
		end
		if d.Level < e.Level then
			return false, "Requires level " .. e.Level
		end
		if Registry.DefenseService:IsActive(player) then
			return false, "Finish your defence first"
		end
		if not Registry.EconomyService:SpendCoins(player, e.Cost) then
			return false, "Not enough coins"
		end
		d.Base.Tier = nextTier
		Registry.DataService:Replicate(player, "Base")
		Registry.PlotService:RebuildTerrain(player)
		Registry.DefenseService:OnLayoutChanged(player)
		self:Refresh(player)
		Net.Notify(player, "Your base is now a " .. e.Name .. "!", "Unlock")
		return true, nextTier
	end)

	Net.Handle("TutorialAdvance", function(player, step)
		if not Validate.Int(step, 1, TUTORIAL_STEPS + 1) then
			return false, "Bad step"
		end
		local d = data(player)
		if d.Tutorial.Done then
			return true, d.Tutorial
		end
		-- Monotonic; the tutorial is guidance only, so the client drives it.
		d.Tutorial.Step = math.max(d.Tutorial.Step, step)
		if step > TUTORIAL_STEPS then
			d.Tutorial.Done = true
			Registry.EconomyService:AddCoins(player, TUTORIAL_REWARD)
			Net.Notify(player, "Tutorial complete! +" .. TUTORIAL_REWARD .. " coins", "Reward")
			self:Refresh(player)
		end
		Registry.DataService:Replicate(player, "Tutorial")
		return true, d.Tutorial
	end)
end

function ProgressionService:Start()
	Registry.DataService.ProfileLoaded:Connect(function(player, d)
		-- Silently mark already-met unlocks so returning players don't get toasts.
		for feature in Progression.Unlocks do
			if self:IsUnlocked(player, feature) then
				d.Unlocked[feature] = true
			end
		end
	end)
end

return ProgressionService

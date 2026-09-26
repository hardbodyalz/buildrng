--[[
	RollService
	Server-authoritative rolling. The client only asks; the server:
	  1. validates the request (loaded, rate limit, cooldown, dice for lucky rolls)
	  2. computes luck (+ diminishing returns) and pity
	  3. picks rarity -> item -> mutation with a server Random
	  4. updates pity, stats, inventory and index
	  5. returns the result (the client animates it) and announces rare pulls
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Config.Progression)
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local RollMath = require(Shared.Util.RollMath)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)

local RollService = {}

local rng = Random.new()
local lastRoll: { [Player]: number } = {}

-- One pool per world; the slice has one world. New worlds = new filter.
local pools = {
	Greenland = RollMath.BuildPool(Items.List, function(def)
		return def.World == "Greenland"
	end),
}

local function random01(): number
	return rng:NextNumber()
end

function RollService:Roll(player: Player, lucky: boolean)
	local d = Registry.DataService:Get(player)
	local Progress = Registry.ProgressionService

	local now = os.clock()
	local cooldown = Progress:GetRollCooldown(player)
	if lastRoll[player] and now - lastRoll[player] < cooldown - GameConfig.Roll.CooldownTolerance then
		return false, "Rolling too fast"
	end

	if lucky then
		if not Progress:IsUnlocked(player, "LuckyRoll") then
			return false, "Lucky Rolls are locked"
		end
		if not Registry.EconomyService:SpendDice(player, GameConfig.Roll.DiceCostLuckyRoll) then
			return false, "Not enough Dice"
		end
	end
	lastRoll[player] = now

	local luck = Progress:GetLuck(player, if lucky then GameConfig.Roll.LuckyRollMultiplier else 1)
	local pool = pools.Greenland
	local rollIndex = d.Stats.TotalRolls + 1

	local def, rarity
	local scripted = GameConfig.Roll.ScriptedRolls[rollIndex]
	if scripted and Items.Get(scripted) then
		def = Items.Get(scripted)
		rarity = Rarities.Get(def.Rarity)
	else
		rarity = RollMath.PickRarity(pool, luck, Progression.Pity, d.Pity, random01)
		def = RollMath.PickItem(pool, rarity.Id, random01)
	end

	local mutation = Mutations.NormalId
	if Progress:IsUnlocked(player, "Mutations") then
		mutation = RollMath.PickMutation(luck, GameConfig.Luck.MutationExponent, random01)
	end

	RollMath.UpdatePity(Progression.Pity, d.Pity, rarity.Order)
	d.Stats.TotalRolls = rollIndex

	local isNew, isNewMutation = Registry.InventoryService:AddItem(player, def.Id, mutation, 1)
	Registry.DataService:Replicate(player, "Pity", "Stats")
	Progress:Refresh(player) -- odds/pity/unlocks changed

	if rarity.AnnounceGlobally or Mutations.Get(mutation).Order >= 4 then
		local label = if mutation ~= Mutations.NormalId then mutation .. " " .. def.DisplayName else def.DisplayName
		Net.FireAll("Announce", {
			Player = player.DisplayName,
			Item = label,
			Rarity = rarity.Id,
			Mutation = mutation,
		})
	end

	return true, {
		ItemId = def.Id,
		Rarity = rarity.Id,
		Mutation = mutation,
		IsNew = isNew,
		IsNewMutation = isNewMutation,
		Lucky = lucky,
		RollNumber = rollIndex,
	}
end

function RollService:Init()
	Net.Handle("Roll", function(player, lucky)
		return RollService:Roll(player, lucky == true)
	end)
end

function RollService:Start()
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
	end)
end

return RollService

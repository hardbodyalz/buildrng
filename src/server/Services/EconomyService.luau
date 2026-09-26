--[[
	EconomyService
	The only code that changes Coins, Dice and XP. Keeps leaderstats and the
	client mirror in sync.

	Currencies (deliberately few):
	  Coins  primary: upgrades, structure levels, expansions
	  Dice   secondary: boss drops, spent on Lucky Rolls (x2 luck)
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Progression = require(Shared.Config.Progression)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)

local EconomyService = {}

local function data(player: Player)
	return Registry.DataService:Get(player)
end

local function updateLeaderstats(player: Player, d)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local coins = ls:FindFirstChild("Coins") :: IntValue?
	local wave = ls:FindFirstChild("Best Wave") :: IntValue?
	if coins then
		coins.Value = math.min(d.Coins, 2 ^ 53)
	end
	if wave then
		wave.Value = d.Stats.HighestWave
	end
end

function EconomyService:RefreshLeaderstats(player: Player)
	local d = data(player)
	if d then
		updateLeaderstats(player, d)
	end
end

function EconomyService:GetCoins(player: Player): number
	local d = data(player)
	return if d then d.Coins else 0
end

function EconomyService:AddCoins(player: Player, amount: number)
	local d = data(player)
	if not d or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	d.Coins += amount
	d.Stats.CoinsEarned += amount
	updateLeaderstats(player, d)
	Registry.DataService:Replicate(player, "Coins", "Stats")
end

function EconomyService:CanAfford(player: Player, amount: number): boolean
	local d = data(player)
	return d ~= nil and d.Coins >= amount
end

function EconomyService:SpendCoins(player: Player, amount: number): boolean
	local d = data(player)
	amount = math.floor(amount)
	if not d or amount < 0 or d.Coins < amount then
		return false
	end
	d.Coins -= amount
	updateLeaderstats(player, d)
	Registry.DataService:Replicate(player, "Coins")
	return true
end

function EconomyService:AddDice(player: Player, amount: number)
	local d = data(player)
	if not d or amount <= 0 then
		return
	end
	d.Dice += math.floor(amount)
	Registry.DataService:Replicate(player, "Dice")
end

function EconomyService:SpendDice(player: Player, amount: number): boolean
	local d = data(player)
	if not d or d.Dice < amount then
		return false
	end
	d.Dice -= amount
	Registry.DataService:Replicate(player, "Dice")
	return true
end

function EconomyService:AddXp(player: Player, amount: number)
	local d = data(player)
	if not d or amount <= 0 then
		return
	end
	d.Xp += amount
	local leveled = false
	while d.Xp >= Progression.XpForLevel(d.Level) do
		d.Xp -= Progression.XpForLevel(d.Level)
		d.Level += 1
		leveled = true
	end
	Registry.DataService:Replicate(player, "Xp", "Level")
	if leveled then
		Net.Notify(player, "Level up! You are now level " .. d.Level, "Level")
		Registry.ProgressionService:Refresh(player)
	end
end

function EconomyService:Init() end

function EconomyService:Start()
	Registry.DataService.ProfileLoaded:Connect(function(player, d)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = ls
		local wave = Instance.new("IntValue")
		wave.Name = "Best Wave"
		wave.Parent = ls
		ls.Parent = player
		updateLeaderstats(player, d)
	end)
	-- Players already loaded before Start (unlikely) are handled by the signal ordering in ServerMain.
	for _, player in Players:GetPlayers() do
		if data(player) and not player:FindFirstChild("leaderstats") then
			self:RefreshLeaderstats(player)
		end
	end
end

return EconomyService

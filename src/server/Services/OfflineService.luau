--[[
	OfflineService
	When a returning player loads, estimate what their base did while they
	were away (see Sim/OfflineSim), grant it, and show the return screen.

	Exploit safety: LastOnline is moved to "now" in the same in-memory profile
	that receives the rewards, so both persist together in one save - a crash
	can lose a report but can never grant it twice.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)
local OfflineSim = require(script.Parent.Parent.Sim.OfflineSim)

local OCFG = GameConfig.Offline

local OfflineService = {}

local pending: { [Player]: any } = {}

local function deliver(player: Player)
	local report = pending[player]
	if report and Registry.DataService:IsClientReady(player) then
		pending[player] = nil
		Net.Fire("OfflineReport", player, report)
	end
end

local function process(player: Player, d)
	local last = d.LastOnline or 0
	local now = os.time()
	if last <= 0 then
		return -- brand new player
	end
	local elapsed = now - last
	if elapsed < OCFG.MinSeconds then
		return
	end
	d.LastOnline = now

	local report = OfflineSim.Estimate({
		Tier = d.Base.Tier,
		Structures = d.Base.Structures,
		CoreMaxHealth = Registry.ProgressionService:GetCoreMaxHealth(player),
		ElapsedSeconds = elapsed,
	}, function()
		task.wait()
	end)

	if not Registry.DataService:IsLoaded(player) then
		return
	end
	local economy = Registry.EconomyService
	economy:AddCoins(player, report.Coins)
	economy:AddXp(player, report.Xp)
	economy:AddDice(player, report.Dice)
	d.Stats.EnemiesDefeated += report.EnemiesDefeated
	d.Stats.WavesCleared += report.WavesDefeated
	d.Stats.BossesDefeated += report.BossesDefeated
	Registry.DataService:Replicate(player, "Stats")
	if report.BossesDefeated > 0 then
		Registry.ProgressionService:Refresh(player)
	end

	pending[player] = report
	deliver(player)
end

function OfflineService:Init() end

function OfflineService:Start()
	Registry.DataService.ProfileLoaded:Connect(function(player, d)
		local ok, err = pcall(process, player, d)
		if not ok then
			warn("[OfflineService] failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
	Registry.DataService.ClientReady:Connect(deliver)
	Registry.DataService.ProfileReleasing:Connect(function(player)
		pending[player] = nil
	end)
end

return OfflineService

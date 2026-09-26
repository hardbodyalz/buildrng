--[[
	DefenseService
	Runs live defences. Each player has one DefenseSim (pure simulation) that
	is stepped at a fixed tick rate; this service turns sim events into
	rewards, stats, world visuals and client replication.

	Run lifecycle:  Idle -> Countdown -> Wave <-> Intermission -> ... -> Idle
	A run ends when the Core falls or the player retreats. Rewards are granted
	per kill / per wave as they happen, so the player always keeps what they
	earned; the base and Core are fully restored afterwards.

	Replication (to the owner + nearby viewers):
	  EnemySnapshot  { plotId, stride, data }   every tick while enemies exist
	  DefenseEvents  { plotId, events }         fx / kills / boss phases per tick
	  DefenseState   owner-only HUD state, on change + twice a second
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Enemies = require(Shared.Config.Enemies)
local WaveGen = require(Shared.Util.WaveGen)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)
local DefenseSim = require(script.Parent.Parent.Sim.DefenseSim)

local DCFG = GameConfig.Defense
local TICK = 1 / DCFG.TickRate

local DefenseService = {}

type Session = {
	Player: Player,
	Sim: any,
	State: string,
	Timer: number,
	Wave: number,
	StartWave: number,
	Earned: { Coins: number, Xp: number, Dice: number, Kills: number, Waves: number, Bosses: number },
	Destroyed: { [string]: boolean },
	HadEnemies: boolean,
	StateClock: number,
}

local sessions: { [Player]: Session } = {}

local function newEarned()
	return { Coins = 0, Xp = 0, Dice = 0, Kills = 0, Waves = 0, Bosses = 0 }
end

local function checkpointFor(highest: number): number
	return (highest // DCFG.CheckpointInterval) * DCFG.CheckpointInterval + 1
end

local function buildSim(player: Player)
	local d = Registry.DataService:Get(player)
	return DefenseSim.new({
		Tier = d.Base.Tier,
		Structures = d.Base.Structures,
		CoreMaxHealth = Registry.ProgressionService:GetCoreMaxHealth(player),
	})
end

local function sendState(session: Session, summary: any?)
	local player = session.Player
	local d = Registry.DataService:Get(player)
	if not d then
		return
	end
	local sim = session.Sim
	local plot = Registry.PlotService:GetPlot(player)
	if plot then
		plot.Model:SetAttribute("CoreHp", math.ceil(sim.CoreHp))
		plot.Model:SetAttribute("CoreMax", sim.CoreMax)
		plot.Model:SetAttribute("Wave", if session.State == "Idle" then 0 else session.Wave)
		plot.Model:SetAttribute("DefenseState", session.State)
	end
	local nextWave = if session.State == "Idle" then 1 else session.Wave + (if session.State == "Wave" then 1 else 0)
	Net.Fire("DefenseState", player, {
		State = session.State,
		Wave = session.Wave,
		Timer = session.Timer,
		CoreHp = sim.CoreHp,
		CoreMax = sim.CoreMax,
		Boss = sim:BossInfo(),
		Enemies = #sim.Enemies,
		Remaining = if sim.Wave then (#sim.Wave.Spawns - sim.SpawnIndex + 1) else 0,
		Earned = session.Earned,
		Checkpoint = checkpointFor(d.Stats.HighestWave),
		HighestWave = d.Stats.HighestWave,
		NextPreview = WaveGen.Preview(math.max(1, nextWave)),
		Summary = summary,
	})
end

local function endRun(session: Session, reason: string)
	if session.State == "Idle" then
		return
	end
	local player = session.Player
	local summary = {
		Reason = reason,
		StartWave = session.StartWave,
		LastWave = session.Wave,
		WavesCleared = session.Earned.Waves,
		Coins = session.Earned.Coins,
		Kills = session.Earned.Kills,
		Dice = session.Earned.Dice,
		Bosses = session.Earned.Bosses,
	}
	session.State = "Idle"
	session.Sim:Reset()
	session.Sim:DrainEvents()
	session.Destroyed = {}
	Registry.PlotService:RestoreAll(player)
	local plot = Registry.PlotService:GetPlot(player)
	if plot then
		Net.FireList("EnemySnapshot", Registry.PlotService:GetViewers(plot), { PlotId = plot.Id, Stride = DefenseSim.SnapshotStride, Data = {} })
	end
	sendState(session, summary)
end

local function handleEvents(session: Session, events: { any })
	local player = session.Player
	local d = Registry.DataService:Get(player)
	local economy = Registry.EconomyService
	local outgoing = {}
	local coins, xp, dice, kills = 0, 0, 0, 0
	local progressionDirty = false

	for _, ev in events do
		local k = ev.k
		if k == "fx" then
			table.insert(outgoing, ev)
		elseif k == "kill" then
			coins += ev.coins
			xp += ev.xp
			kills += 1
			if ev.boss then
				dice += ev.dice
				d.Stats.BossesDefeated += 1
				session.Earned.Bosses += 1
				progressionDirty = true
				Net.Notify(player, "Boss defeated! +" .. ev.dice .. " Dice", "Reward")
			end
			table.insert(outgoing, { k = "kill", x = ev.x, z = ev.z, coins = math.floor(ev.coins), boss = ev.boss })
		elseif k == "waveCleared" then
			coins += ev.bonus
			session.Earned.Waves += 1
			d.Stats.WavesCleared += 1
			if ev.wave > d.Stats.HighestWave then
				d.Stats.HighestWave = ev.wave
				progressionDirty = true
			end
			table.insert(outgoing, { k = "waveCleared", wave = ev.wave, bonus = ev.bonus })
		elseif k == "destroyed" then
			session.Destroyed[ev.uid] = true
			Registry.PlotService:SetStructureDestroyed(player, ev.uid, true)
			table.insert(outgoing, ev)
		elseif k == "restored" then
			session.Destroyed = {}
			Registry.PlotService:RestoreAll(player)
		elseif k == "coreHit" then
			table.insert(outgoing, ev)
		elseif k == "bossPhase" then
			table.insert(outgoing, ev)
		elseif k == "coreDestroyed" then
			table.insert(outgoing, ev)
		end
	end

	if coins > 0 then
		economy:AddCoins(player, coins)
		session.Earned.Coins += coins
	end
	if dice > 0 then
		economy:AddDice(player, dice)
		session.Earned.Dice += dice
	end
	if xp > 0 then
		economy:AddXp(player, xp)
		session.Earned.Xp += xp
	end
	if kills > 0 then
		d.Stats.EnemiesDefeated += kills
		session.Earned.Kills += kills
		Registry.DataService:Replicate(player, "Stats")
	end
	if progressionDirty then
		Registry.DataService:Replicate(player, "Stats")
		Registry.EconomyService:RefreshLeaderstats(player)
		Registry.ProgressionService:Refresh(player)
	end
	return outgoing
end

-- Start a wave and tell viewers (boss waves get a dramatic intro client-side).
local function startWave(session: Session, n: number)
	session.Sim:StartWave(n)
	local wave = session.Sim.Wave
	local plot = Registry.PlotService:GetPlot(session.Player)
	if plot then
		local ev = { k = "waveStart", wave = n, boss = wave.BossId }
		if wave.BossId then
			local def = Enemies.Get(wave.BossId)
			ev.bossName = def.DisplayName
			ev.music = def.MusicId
		end
		Net.FireList("DefenseEvents", Registry.PlotService:GetViewers(plot), { PlotId = plot.Id, Events = { ev } })
	end
end

local function tickSession(session: Session, dt: number)
	local sim = session.Sim
	local prevState = session.State

	if session.State == "Countdown" then
		session.Timer -= dt
		if session.Timer <= 0 then
			session.State = "Wave"
			startWave(session, session.Wave)
		end
	elseif session.State == "Intermission" then
		session.Timer -= dt
		sim:Step(dt)
		if session.Timer <= 0 then
			session.Wave += 1
			session.State = "Wave"
			startWave(session, session.Wave)
		end
	elseif session.State == "Wave" then
		sim:Step(dt)
	end

	local events = sim:DrainEvents()
	local plot = Registry.PlotService:GetPlot(session.Player)
	if #events > 0 then
		local outgoing = handleEvents(session, events)
		if plot and #outgoing > 0 then
			Net.FireList("DefenseEvents", Registry.PlotService:GetViewers(plot), { PlotId = plot.Id, Events = outgoing })
		end
	end

	if session.State == "Wave" then
		if sim.Failed then
			endRun(session, "CoreDestroyed")
			return
		elseif not sim.WaveActive then
			session.State = "Intermission"
			session.Timer = DCFG.Intermission
		end
	end

	-- Enemy snapshots (send one empty snapshot after the last enemy dies to clear visuals).
	local hasEnemies = #sim.Enemies > 0
	if plot and (hasEnemies or session.HadEnemies) then
		Net.FireList("EnemySnapshot", Registry.PlotService:GetViewers(plot), {
			PlotId = plot.Id,
			Stride = DefenseSim.SnapshotStride,
			Data = sim:Snapshot(),
		})
	end
	session.HadEnemies = hasEnemies

	session.StateClock += dt
	if session.State ~= prevState or session.StateClock >= 0.5 then
		session.StateClock = 0
		sendState(session)
	end
end

-- Public API ---------------------------------------------------------------------

function DefenseService:SetupPlayer(player: Player)
	sessions[player] = {
		Player = player,
		Sim = buildSim(player),
		State = "Idle",
		Timer = 0,
		Wave = 0,
		StartWave = 1,
		Earned = newEarned(),
		Destroyed = {},
		HadEnemies = false,
		StateClock = 0,
	}
	sendState(sessions[player])
end

function DefenseService:TeardownPlayer(player: Player)
	sessions[player] = nil
end

function DefenseService:IsActive(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and s.State ~= "Idle"
end

function DefenseService:IsStructureDestroyed(player: Player, uid: string): boolean
	local s = sessions[player]
	return s ~= nil and s.Destroyed[uid] == true
end

function DefenseService:OnLayoutChanged(player: Player)
	local s = sessions[player]
	local d = Registry.DataService:Get(player)
	if not s or not d then
		return
	end
	if s.Sim.Region.Tier ~= d.Base.Tier then
		s.Sim = buildSim(player) -- expansion only happens while idle
	else
		s.Sim:SetStructures(d.Base.Structures)
	end
end

function DefenseService:OnStatsChanged(player: Player)
	local s = sessions[player]
	if s then
		s.Sim:SetCoreMax(Registry.ProgressionService:GetCoreMaxHealth(player))
		sendState(s)
	end
end

function DefenseService:Init()
	Net.Handle("StartDefense", function(player, fromCheckpoint)
		local s = sessions[player]
		if not s then
			return false, "Your base isn't ready yet"
		end
		if s.State ~= "Idle" then
			return false, "A defence is already running"
		end
		local d = Registry.DataService:Get(player)
		local start = if fromCheckpoint == true then checkpointFor(d.Stats.HighestWave) else 1
		s.Sim:Reset()
		s.Sim:DrainEvents()
		s.Destroyed = {}
		s.Earned = newEarned()
		s.Wave = start
		s.StartWave = start
		s.State = "Countdown"
		s.Timer = DCFG.StartCountdown
		d.Stats.DefensesRun += 1
		sendState(s)
		return true, start
	end)

	Net.Handle("StopDefense", function(player)
		local s = sessions[player]
		if not s or s.State == "Idle" then
			return false, "No defence running"
		end
		endRun(s, "Retreat")
		return true, nil
	end)
end

function DefenseService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += math.min(dt, 0.25)
		while acc >= TICK do
			acc -= TICK
			for player, session in sessions do
				if session.State ~= "Idle" or session.HadEnemies then
					local ok, err = pcall(tickSession, session, TICK)
					if not ok then
						warn("[DefenseService] tick error for " .. player.Name .. ": " .. tostring(err))
						endRun(session, "Error")
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return DefenseService

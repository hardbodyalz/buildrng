--[[
	OfflineSim
	Estimates what a base achieves while the player is away WITHOUT simulating
	hours of enemies. It runs the real DefenseSim once, headless, with a coarse
	timestep: waves 1..N until the Core falls (or a cap is hit). That single
	"run" gives a real reward rate and a real duration; the offline period is
	then treated as repeated runs, scaled by an efficiency factor.

	So a better *layout* directly gives better offline results - offline is a
	measurement of the player's base, not a flat timer.

	`yield` (optional) is called every N steps so the server can spread the
	work over frames.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local DefenseSim = require(script.Parent.DefenseSim)

local OCFG = GameConfig.Offline
local DCFG = GameConfig.Defense

local OfflineSim = {}

export type Params = {
	Tier: number,
	Structures: { [string]: any },
	CoreMaxHealth: number,
	ElapsedSeconds: number,
	StartWave: number?,
}

export type Report = {
	ElapsedSeconds: number,
	CountedSeconds: number,
	WavesDefeated: number,
	EnemiesDefeated: number,
	Coins: number,
	Xp: number,
	Dice: number,
	BossesDefeated: number,
	BestWave: number,
	CoreHealthPct: number,
	BaseFell: boolean,
	RunWaves: number,
	RunSeconds: number,
	FailedAtWave: number?,
}

-- Simulate one run from StartWave until the Core falls (or a cap is hit).
-- Returns:
--   cleared  totals over fully CLEARED waves only (what the base can reliably hold)
--   partial  totals including the failed wave (consolation when nothing was cleared)
--   clearedSeconds, coreFracAtLastClear, failed, lastWave
function OfflineSim.SimulateRun(params: Params, yield: (() -> ())?)
	local sim = DefenseSim.new({
		Tier = params.Tier,
		Structures = params.Structures,
		CoreMaxHealth = params.CoreMaxHealth,
		NoFx = true,
	})
	local dt = OCFG.SimDt
	local function newTotals()
		return { Coins = 0, Xp = 0, Dice = 0, Kills = 0, Waves = 0, Bosses = 0 }
	end
	local cleared = newTotals()
	local waveTotals = newTotals()
	local wave = params.StartWave or 1
	local steps = 0
	local clearedSeconds = DCFG.StartCountdown
	local waveSeconds = 0
	local coreFrac = 1
	local lastWave = wave

	while cleared.Waves < OCFG.MaxSimWaves and steps < OCFG.MaxSimSteps do
		sim:StartWave(wave)
		lastWave = wave
		waveTotals = newTotals()
		waveSeconds = 0
		while sim.WaveActive and not sim.Failed and steps < OCFG.MaxSimSteps do
			sim:Step(dt)
			steps += 1
			waveSeconds += dt
			for _, ev in sim:DrainEvents() do
				if ev.k == "kill" then
					waveTotals.Coins += ev.coins
					waveTotals.Xp += ev.xp
					waveTotals.Kills += 1
					if ev.boss then
						waveTotals.Bosses += 1
						waveTotals.Dice += ev.dice
					end
				elseif ev.k == "waveCleared" then
					waveTotals.Coins += ev.bonus
					waveTotals.Waves += 1
				end
			end
			if yield and steps % OCFG.YieldEverySteps == 0 then
				yield()
			end
		end
		if sim.Failed or sim.WaveActive then
			break
		end
		for k, v in waveTotals do
			cleared[k] += v
		end
		clearedSeconds += waveSeconds + DCFG.Intermission
		coreFrac = sim.CoreHp / sim.CoreMax
		wave += 1
	end

	return cleared, waveTotals, clearedSeconds, waveSeconds, coreFrac, sim.Failed, lastWave
end

-- Offline model: the base repeatedly defends the waves it can actually hold
-- (1..last cleared), so the player is never punished with losses - a weak
-- base simply earns less. A base that can't clear wave 1 still earns a
-- consolation share of what it killed.
function OfflineSim.Estimate(params: Params, yield: (() -> ())?): Report
	local elapsed = math.max(0, params.ElapsedSeconds)
	local counted = math.min(elapsed, OCFG.MaxSeconds)
	local cleared, partial, clearedSeconds, partialSeconds, coreFrac, failed, lastWave =
		OfflineSim.SimulateRun(params, yield)

	local totals, runSeconds, efficiency
	if cleared.Waves > 0 then
		totals, runSeconds, efficiency = cleared, clearedSeconds, OCFG.Efficiency
	else
		totals, runSeconds, efficiency = partial, DCFG.StartCountdown + partialSeconds, OCFG.FailedEfficiency
	end
	local runs = if runSeconds > 0 then counted / runSeconds else 0

	local function scaled(v: number): number
		return math.floor(v * runs * efficiency)
	end

	local bestWave = (params.StartWave or 1) + cleared.Waves - 1
	return {
		ElapsedSeconds = elapsed,
		CountedSeconds = counted,
		WavesDefeated = math.floor(totals.Waves * runs),
		EnemiesDefeated = math.floor(totals.Kills * runs),
		Coins = math.max(scaled(totals.Coins), math.floor(counted / 3600 * OCFG.MinCoinsPerHour)),
		Xp = scaled(totals.Xp),
		Dice = scaled(totals.Dice),
		BossesDefeated = math.floor(totals.Bosses * runs),
		BestWave = math.max(bestWave, 0),
		CoreHealthPct = if cleared.Waves > 0 then math.floor(coreFrac * 100 + 0.5) else 0,
		BaseFell = cleared.Waves == 0,
		RunWaves = cleared.Waves,
		RunSeconds = runSeconds,
		FailedAtWave = if failed then lastWave else nil,
	}
end

return OfflineSim

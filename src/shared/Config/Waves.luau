--[[
	Waves
	Hand-authored waves for the first stretch (the tutorial-to-first-boss
	curve), then an infinite procedural generator (see Util/WaveGen).

	Explicit wave groups: { Enemy, Count, Interval (s between spawns), Delay (s from wave start) }

	Scaling is deliberately NOT just "multiply HP forever": later waves add
	modifiers (elite, swift, armoured, regenerating, enraged), more enemy
	variety and larger budgets, while HP scaling itself is polynomial.
]]

local Waves = {}

Waves.Explicit = {
	[1] = { { Enemy = "walker", Count = 6, Interval = 2.2 } },
	[2] = { { Enemy = "walker", Count = 10, Interval = 1.6 } },
	[3] = {
		{ Enemy = "walker", Count = 8, Interval = 1.5 },
		{ Enemy = "swarmling", Count = 10, Interval = 0.35, Delay = 6 },
	},
	[4] = {
		{ Enemy = "walker", Count = 10, Interval = 1.3 },
		{ Enemy = "runner", Count = 6, Interval = 1.2, Delay = 5 },
	},
	[5] = {
		{ Enemy = "walker", Count = 12, Interval = 1.1 },
		{ Enemy = "brute", Count = 1, Interval = 1, Delay = 8 },
		{ Enemy = "runner", Count = 6, Interval = 1, Delay = 12 },
	},
	[6] = {
		{ Enemy = "shieldbearer", Count = 3, Interval = 3 },
		{ Enemy = "walker", Count = 10, Interval = 1, Delay = 2 },
		{ Enemy = "swarmling", Count = 10, Interval = 0.3, Delay = 12 },
	},
	[7] = {
		{ Enemy = "runner", Count = 10, Interval = 0.8 },
		{ Enemy = "brute", Count = 2, Interval = 5, Delay = 4 },
		{ Enemy = "walker", Count = 8, Interval = 1, Delay = 8 },
	},
	[8] = {
		{ Enemy = "swarmling", Count = 20, Interval = 0.3 },
		{ Enemy = "shieldbearer", Count = 4, Interval = 2.5, Delay = 5 },
	},
	[9] = {
		{ Enemy = "brute", Count = 3, Interval = 4 },
		{ Enemy = "shieldbearer", Count = 6, Interval = 2, Delay = 3 },
		{ Enemy = "runner", Count = 10, Interval = 0.7, Delay = 10 },
	},
	[10] = {
		{ Enemy = "colossus", Count = 1, Interval = 1 },
		{ Enemy = "walker", Count = 10, Interval = 1.5, Delay = 3 },
	},
}

-- Procedural generator settings (waves beyond the explicit list).
Waves.Procedural = {
	-- Threat budget: Base + Linear*w + Power coefficient * w^Exponent
	BudgetBase = 8,
	BudgetLinear = 1.6,
	BudgetPowerCoef = 0.18,
	BudgetExponent = 1.45,
	SpawnWindow = 22, -- seconds over which the wave's budget is spawned (shrinks slightly with wave)
	MinSpawnWindow = 12,
	MaxGroupsPerWave = 5,
}

-- HP multiplier applied to every enemy in wave w (explicit waves included).
function Waves.HealthScale(w: number): number
	local n = w - 1
	return 1 + 0.07 * n + 0.0022 * n * n
end

-- Coin reward multiplier per wave.
function Waves.RewardScale(w: number): number
	return 1 + 0.06 * (w - 1)
end

-- Flat coins for clearing wave w.
function Waves.ClearBonus(w: number): number
	return math.floor(10 + 4 * w + 0.05 * w * w)
end

-- Boss waves: every BossInterval waves. MajorEvery multiplies boss HP.
Waves.Bosses = {
	Interval = 10,
	Rotation = { "colossus" }, -- add new boss ids here; they cycle
	MajorEvery = 50,
	MajorHealthMult = 2.5,
	-- After the first cycle, bosses get this extra HP per boss number.
	ExtraHealthPerCycle = 0.35,
	Escort = { Enemy = "walker", Count = 10, Interval = 1.5, Delay = 3 },
}

-- Modifiers roll per spawned enemy (bosses excluded) once their FromWave is reached.
-- Chance ramps from BaseChance by ChancePerWave up to MaxChance.
Waves.Modifiers = {
	{ Id = "Elite", Bit = 1, FromWave = 11, BaseChance = 0.05, ChancePerWave = 0.004, MaxChance = 0.3, HealthMult = 2.5, RewardMult = 3, Scale = 1.25 },
	{ Id = "Swift", Bit = 2, FromWave = 16, BaseChance = 0.05, ChancePerWave = 0.003, MaxChance = 0.25, SpeedMult = 1.35 },
	{ Id = "Regenerating", Bit = 4, FromWave = 22, BaseChance = 0.05, ChancePerWave = 0.003, MaxChance = 0.25, Regen = 0.04 },
	{ Id = "Armored", Bit = 8, FromWave = 28, BaseChance = 0.05, ChancePerWave = 0.004, MaxChance = 0.3, ArmorAdd = 6 },
	{ Id = "Enraged", Bit = 16, FromWave = 35, BaseChance = 0.04, ChancePerWave = 0.003, MaxChance = 0.25, StructureDamageMult = 2.5 },
}

return Waves

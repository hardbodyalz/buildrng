--[[
	WaveGen
	Builds the spawn schedule for any wave number. Explicit waves come from
	Config/Waves; everything else is procedurally generated from a threat
	budget with a seeded RNG, so wave N is always the same wave (fair to
	compare on leaderboards, and the offline estimator sees what online would).

	Output:
	{
		Wave = n,
		IsBoss = bool,
		BossId = string?,
		HealthScale = number,
		RewardScale = number,
		Spawns = { { T = seconds, Enemy = id, Mods = bitmask, HealthMult = number } } -- sorted by T
	}
]]

local Config = script.Parent.Parent.Config
local Waves = require(Config.Waves)
local Enemies = require(Config.Enemies)
local SeededRandom = require(script.Parent.SeededRandom)

local WaveGen = {}

local function modifierChance(mod, w)
	if w < mod.FromWave then
		return 0
	end
	return math.min(mod.BaseChance + (w - mod.FromWave) * mod.ChancePerWave, mod.MaxChance)
end

local function addGroup(spawns, enemyId, count, interval, delay)
	for i = 0, count - 1 do
		table.insert(spawns, { T = delay + i * interval, Enemy = enemyId, Mods = 0, HealthMult = 1 })
	end
end

local function proceduralGroups(spawns, w, budget, rng, startDelay)
	local p = Waves.Procedural
	local eligible = {}
	for _, def in Enemies.List do
		if not def.IsBoss and def.MinWave <= w and def.Threat > 0 then
			table.insert(eligible, def)
		end
	end
	if #eligible == 0 then
		return
	end
	local groupCount = math.clamp(2 + w // 15, 2, p.MaxGroupsPerWave)
	local window = math.max(p.MinSpawnWindow, p.SpawnWindow - w * 0.05)
	for g = 1, groupCount do
		local def = eligible[math.floor(rng() * #eligible) + 1]
		local share = budget / groupCount
		local count = math.max(1, math.floor(share / def.Threat + 0.5))
		local delay = startDelay + (g - 1) * (window / groupCount) * 0.6
		local span = window * 0.7
		local interval = if def.GroupSize > 1 then 0.3 else math.max(0.25, span / count)
		addGroup(spawns, def.Id, count, interval, delay)
	end
end

function WaveGen.Budget(w: number): number
	local p = Waves.Procedural
	return p.BudgetBase + p.BudgetLinear * w + p.BudgetPowerCoef * w ^ p.BudgetExponent
end

function WaveGen.BossFor(w: number): string?
	local b = Waves.Bosses
	if w % b.Interval ~= 0 then
		return nil
	end
	local n = w // b.Interval
	return b.Rotation[((n - 1) % #b.Rotation) + 1]
end

function WaveGen.Build(w: number)
	w = math.max(1, math.floor(w))
	local rng = SeededRandom.new(w * 7919 + 17)
	local spawns = {}
	local bossId = WaveGen.BossFor(w)
	local explicit = Waves.Explicit[w]

	if explicit then
		for _, g in explicit do
			addGroup(spawns, g.Enemy, g.Count, g.Interval or 1, g.Delay or 0)
		end
		-- Explicit waves may already contain the boss.
		if bossId then
			local found = false
			for _, s in spawns do
				if s.Enemy == bossId then
					found = true
				end
			end
			if not found then
				addGroup(spawns, bossId, 1, 1, 0)
			end
		end
	elseif bossId then
		addGroup(spawns, bossId, 1, 1, 0)
		local e = Waves.Bosses.Escort
		addGroup(spawns, e.Enemy, e.Count, e.Interval, e.Delay)
		proceduralGroups(spawns, w, WaveGen.Budget(w) * 0.4, rng, 8)
	else
		proceduralGroups(spawns, w, WaveGen.Budget(w), rng, 0)
	end

	-- Boss HP scaling beyond the first appearance.
	if bossId then
		local b = Waves.Bosses
		local cycle = w // b.Interval - 1
		local mult = 1 + cycle * b.ExtraHealthPerCycle
		if w % b.MajorEvery == 0 then
			mult *= b.MajorHealthMult
		end
		for _, s in spawns do
			if s.Enemy == bossId then
				s.HealthMult = mult
			end
		end
	end

	-- Modifiers (never on bosses).
	for _, s in spawns do
		if s.Enemy ~= bossId then
			for _, mod in Waves.Modifiers do
				local chance = modifierChance(mod, w)
				if chance > 0 and rng() < chance then
					s.Mods = bit32.bor(s.Mods, mod.Bit)
				end
			end
		end
	end

	table.sort(spawns, function(a, b)
		return a.T < b.T
	end)

	return {
		Wave = w,
		IsBoss = bossId ~= nil,
		BossId = bossId,
		HealthScale = Waves.HealthScale(w),
		RewardScale = Waves.RewardScale(w),
		Spawns = spawns,
	}
end

-- Short description for UI ("Boss: The Colossus", "24 enemies").
function WaveGen.Preview(w: number): string
	local wave = WaveGen.Build(w)
	if wave.BossId then
		return "BOSS: " .. Enemies.Get(wave.BossId).DisplayName
	end
	return string.format("%d enemies", #wave.Spawns)
end

return WaveGen

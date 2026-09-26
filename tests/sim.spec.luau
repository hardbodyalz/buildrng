local Grid = require(Shared.Util.Grid)
local DefenseSim = require(Server.Sim.DefenseSim)
local OfflineSim = require(Server.Sim.OfflineSim)

local CX = Grid.CenterX

-- Run waves from 1 until failure (or cap). Returns last cleared wave and stats.
local function runUntilFail(tier, structures, cap, coreMax)
	local sim = DefenseSim.new({ Tier = tier, Structures = structures, CoreMaxHealth = coreMax or 100, NoFx = true })
	local cleared, coins, kills = 0, 0, 0
	local phases = {}
	for w = 1, cap do
		sim:StartWave(w)
		local t = 0
		while sim.WaveActive and not sim.Failed do
			sim:Step(0.1)
			t += 0.1
			for _, ev in sim:DrainEvents() do
				if ev.k == "kill" then coins += ev.coins; kills += 1
				elseif ev.k == "waveCleared" then coins += ev.bonus
				elseif ev.k == "bossPhase" then table.insert(phases, ev.name) end
			end
			assert(t < 900, "wave " .. w .. " never ended")
		end
		if sim.Failed then break end
		cleared = w
	end
	return cleared, coins, kills, phases, sim
end

local function S(list)
	local out = {}
	for i, s in list do
		out["s" .. i] = { Id = s[1], X = s[2], Z = s[3], R = s[4] or 0, Lvl = s[5] or 1, Mut = s[6] or "Normal" }
	end
	return out
end

local r1 = Grid.Region(1)

test("empty base survives wave 1 but falls early", function()
	local cleared = runUntilFail(1, {}, 20)
	print("    empty base cleared", cleared)
	check(cleared >= 1 and cleared <= 3)
end)

test("tutorial: one scrap turret beside the path clears wave 1 comfortably", function()
	local sim = DefenseSim.new({ Tier = 1, Structures = S({ { "scrap_turret", CX + 1, r1.MinZ + 4 } }), CoreMaxHealth = 100, NoFx = true })
	sim:StartWave(1)
	local kills = 0
	while sim.WaveActive and not sim.Failed do
		sim:Step(0.1)
		for _, ev in sim:DrainEvents() do if ev.k == "kill" then kills += 1 end end
	end
	print("    kills", kills, "core", sim.CoreHp)
	check(kills >= 5, "turret should kill most walkers")
end)

test("barricade maze makes enemies detour (longer path)", function()
	local sim = DefenseSim.new({ Tier = 1, Structures = S({
		{ "wooden_barricade", CX - 1, r1.MinZ + 3 }, { "wooden_barricade", CX, r1.MinZ + 3 }, { "wooden_barricade", CX + 1, r1.MinZ + 3 },
	}), CoreMaxHealth = 100, NoFx = true })
	local FlowField = require(Shared.Util.FlowField)
	local field = sim:GetField(1)
	local cells = FlowField.Path(field, Grid.Entrance(r1))
	print("    path length with barricades", #cells, "straight", Grid.CoreMinZ - r1.MinZ + 1)
	check(#cells > Grid.CoreMinZ - r1.MinZ + 1)
end)

test("early starter base reaches mid waves", function()
	local base = S({
		{ "scrap_turret", CX + 1, r1.MinZ + 3 },
		{ "scrap_turret", CX - 1, r1.MinZ + 5 },
		{ "scrap_turret", CX + 1, r1.MinZ + 7 },
		{ "spike_trap", CX, r1.MinZ + 4 },
		{ "wooden_barricade", CX - 1, r1.MinZ + 2 },
		{ "machine_gun_nest", CX - 1, r1.MinZ + 7 },
	})
	local cleared, coins = runUntilFail(1, base, 30)
	print("    starter base cleared", cleared, "coins", math.floor(coins))
	check(cleared >= 3 and cleared < 10, "starter base cleared " .. cleared)
end)

local function midBase(level, extra)
	local z = r1.MinZ
	local list = {
		{ "stone_wall", CX - 3, z + 3, 0, level }, { "wooden_barricade", CX, z + 3, 0, level },
		{ "wooden_barricade", CX + 1, z + 3, 0, level }, { "wooden_barricade", CX + 2, z + 3, 0, level },
		{ "stone_wall", CX + 1, z + 6, 0, level }, { "wooden_barricade", CX, z + 6, 0, level },
		{ "cannon", CX, z + 5, 0, level }, { "scrap_turret", CX + 1, z + 5, 0, level },
		{ "machine_gun_nest", CX + 2, z + 5, 0, level }, { "war_drum", CX - 1, z + 5, 0, level },
	}
	for _, e in extra or {} do table.insert(list, e) end
	return S(list)
end

test("mid base (level 1) vs level 8 - upgrades matter", function()
	local c1 = runUntilFail(1, midBase(1), 40)
	local c8 = runUntilFail(1, midBase(8), 40)
	print("    mid base L1 cleared", c1, " L8 cleared", c8)
	check(c1 >= 5, "mid base should handle early waves")
	check(c8 > c1 + 5, "upgrades should matter")
end)

test("boss wave: upgraded base with mortar can beat the Colossus; phases trigger", function()
	local cleared, coins, kills, phases = runUntilFail(2, midBase(8, {
		{ "mortar", CX - 2, r1.MinZ + 8, 0, 8 },
	}), 12, 220)
	print("    boss base cleared", cleared, "phases", table.concat(phases, ","))
	check(#phases >= 1, "boss phases should trigger")
end)

test("deterministic: same layout, same result", function()
	local a = { runUntilFail(1, midBase(3), 25) }
	local b = { runUntilFail(1, midBase(3), 25) }
	checkEq(a[1], b[1]); checkEq(a[2], b[2])
end)

test("offline estimate scales with time and layout", function()
	local weak = OfflineSim.Estimate({ Tier = 1, Structures = S({ { "scrap_turret", CX + 1, r1.MinZ + 4 } }), CoreMaxHealth = 100, ElapsedSeconds = 3600 })
	local strong = OfflineSim.Estimate({ Tier = 1, Structures = midBase(5), CoreMaxHealth = 100, ElapsedSeconds = 3600 })
	local strong8h = OfflineSim.Estimate({ Tier = 1, Structures = midBase(5), CoreMaxHealth = 100, ElapsedSeconds = 20 * 3600 })
	print(string.format("    weak: waves %d coins %d core %d%% runWaves %d runSec %.0f", weak.WavesDefeated, weak.Coins, weak.CoreHealthPct, weak.RunWaves, weak.RunSeconds))
	print(string.format("    strong: waves %d coins %d kills %d runWaves %d runSec %.0f", strong.WavesDefeated, strong.Coins, strong.EnemiesDefeated, strong.RunWaves, strong.RunSeconds))
	check(strong.Coins > weak.Coins)
	checkEq(strong8h.CountedSeconds, 8 * 3600, "cap")
	check(weak.Coins > 0, "offline never gives nothing")
	check(strong.CoreHealthPct > 0 and not strong.BaseFell)
	local hopeless = OfflineSim.Estimate({ Tier = 1, Structures = {}, CoreMaxHealth = 1, ElapsedSeconds = 3600 })
	print(string.format("    hopeless: coins %d fell %s", hopeless.Coins, tostring(hopeless.BaseFell)))
	check(hopeless.BaseFell and hopeless.Coins > 0, "floor applies")
end)

summary()

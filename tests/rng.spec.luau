local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Progression = require(Shared.Config.Progression)
local RollMath = require(Shared.Util.RollMath)
local Luck = require(Shared.Util.Luck)
local SeededRandom = require(Shared.Util.SeededRandom)

local pool = RollMath.BuildPool(Items.List)

test("pool only contains rarities that have items", function()
	for _, r in pool.Rarities do
		check(pool.Items[r.Id] and #pool.Items[r.Id] > 0, r.Id)
	end
	check(pool.Rarities[1].Id == "Common")
end)

test("odds sum to 1 and luck shifts mass upward", function()
	local o1 = RollMath.Odds(pool, 1)
	local o5 = RollMath.Odds(pool, 5)
	local s = 0
	for _, e in o1 do s += e.Chance end
	check(math.abs(s - 1) < 1e-9, "sum " .. s)
	check(o5[1].Chance < o1[1].Chance, "common should drop with luck")
	check(o5[#o5].Chance > o1[#o1].Chance, "top tier should rise with luck")
	for _, e in o1 do
		print(string.format("    luck1 %-10s 1 in %.1f", e.Rarity.Id, 1 / e.Chance))
	end
end)

test("luck has diminishing returns past the soft cap", function()
	checkEq(Luck.Diminish(3), 3)
	local a, b = Luck.Diminish(10), Luck.Diminish(100)
	check(a < 10 and b < 100 and b > a, "diminish " .. a .. " " .. b)
	checkEq(Luck.Compute({ Base = 2, Additive = { 0.5 } }), 3)
end)

test("empirical distribution roughly matches odds", function()
	local rng = SeededRandom.new(42)
	local counts = {}
	local N = 200000
	for _ = 1, N do
		local r = RollMath.PickRarity(pool, 1, nil, nil, rng)
		counts[r.Id] = (counts[r.Id] or 0) + 1
	end
	for _, e in RollMath.Odds(pool, 1) do
		local observed = (counts[e.Rarity.Id] or 0) / N
		if e.Chance > 0.001 then
			check(math.abs(observed - e.Chance) / e.Chance < 0.05, e.Rarity.Id .. " observed " .. observed .. " expected " .. e.Chance)
		end
	end
end)

test("pity guarantees minimum rarity and resets", function()
	local state = { Epic = 199, Legendary = 10, Mythic = 10 }
	local rng = SeededRandom.new(7)
	for _ = 1, 50 do
		local r = RollMath.PickRarity(pool, 1, Progression.Pity, state, rng)
		check(r.Order >= Rarities.OrderOf("Epic"), "got " .. r.Id)
	end
	RollMath.UpdatePity(Progression.Pity, state, Rarities.OrderOf("Epic"))
	checkEq(state.Epic, 0)
	checkEq(state.Legendary, 11)
end)

test("pity never exceeds guarantee over a long session", function()
	local state = {}
	local rng = SeededRandom.new(99)
	local since = 0
	local worst = 0
	for _ = 1, 20000 do
		local r = RollMath.PickRarity(pool, 1, Progression.Pity, state, rng)
		RollMath.UpdatePity(Progression.Pity, state, r.Order)
		if r.Order >= Rarities.OrderOf("Epic") then
			since = 0
		else
			since += 1
			worst = math.max(worst, since)
		end
	end
	check(worst < 200, "epic drought " .. worst)
end)

test("mutations are rare and luck-sensitive", function()
	local rng = SeededRandom.new(5)
	local n1, n9 = 0, 0
	for _ = 1, 50000 do
		if RollMath.PickMutation(1, 0.5, rng) ~= "Normal" then n1 += 1 end
		if RollMath.PickMutation(9, 0.5, rng) ~= "Normal" then n9 += 1 end
	end
	check(n1 > 800 and n1 < 2000, "mutation rate luck1 " .. n1)
	check(n9 > n1 * 2, "luck should raise mutation rate")
end)

summary()

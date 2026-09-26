-- End-to-end server flow against the Roblox mock (tests/mock/Roblox.luau).
local Grid = require(Shared.Util.Grid)

require(game:GetService("ServerScriptService"):WaitForChild("Server"))
__flush()

local function noWarnings(label)
	if #__warnings > 0 then
		error(label .. " produced warnings:\n  " .. table.concat(__warnings, "\n  "))
	end
end

local Registry = require(Server.Registry)
local p = __newPlayer(101, "Tester")
__advance(1)

test("profile loads, plot assigned, leaderstats created", function()
	check(Registry.DataService:IsLoaded(p), "loaded")
	check(p:GetAttribute("PlotId") == 1, "plot id")
	check(p:FindFirstChild("leaderstats") ~= nil, "leaderstats")
	local res = __invoke("GetInitialState", p)
	check(res.ok, tostring(res.err))
	check(#__firedTo(p, "Sync") > 0, "sync fired")
	noWarnings("load")
end)

test("scripted first rolls, cooldown enforced, inventory + index updated", function()
	local r1 = __invoke("Roll", p, false)
	check(r1.ok, tostring(r1.err))
	checkEq(r1.data.ItemId, "scrap_turret")
	check(r1.data.IsNew)
	local fast = __invoke("Roll", p, false)
	check(not fast.ok, "cooldown should block")
	__advance(2)
	local r2 = __invoke("Roll", p, false)
	check(r2.ok, tostring(r2.err))
	checkEq(r2.data.ItemId, "wooden_barricade")
	local d = Registry.DataService:Get(p)
	checkEq(d.Inventory["scrap_turret|Normal"].Count, 1)
	checkEq(d.Stats.TotalRolls, 2)
	check(d.Index.scrap_turret.First > 0)
	local lucky = __invoke("Roll", p, true)
	check(not lucky.ok, "lucky roll locked")
end)

test("rate limiter trips on spam", function()
	local blocked = false
	for _ = 1, 20 do
		local r = __invoke("SetItemFlag", p, "scrap_turret|Normal", "Favorite", true)
		if not r.ok and r.err == "Slow down!" then
			blocked = true
		end
	end
	check(blocked)
	__advance(5)
end)

local region = Grid.Region(1)
local turretUid

test("placement validation + place + model built", function()
	local bad = __invoke("PlaceStructure", p, "scrap_turret|Normal", Grid.CenterX, region.MinZ, 0)
	check(not bad.ok, "entrance is restricted")
	local bogus = __invoke("PlaceStructure", p, "the_anomaly|Normal", Grid.CenterX + 1, region.MinZ + 3, 0)
	check(not bogus.ok, "can't place unowned item")
	local inject = __invoke("PlaceStructure", p, "scrap_turret|Normal", 1.5, "x", 9)
	check(not inject.ok, "bad args rejected")
	local ok = __invoke("PlaceStructure", p, "scrap_turret|Normal", Grid.CenterX + 1, region.MinZ + 4, 0)
	check(ok.ok, tostring(ok.err))
	turretUid = ok.data
	local d = Registry.DataService:Get(p)
	check(d.Base.Structures[turretUid] ~= nil)
	check((d.Inventory["scrap_turret|Normal"] or { Count = 0 }).Count == 0)
	local plot = Registry.PlotService:GetPlot(p)
	check(plot.Structures:FindFirstChild(turretUid) ~= nil, "model built")
	local overlap = __invoke("PlaceStructure", p, "wooden_barricade|Normal", Grid.CenterX + 1, region.MinZ + 4, 0)
	check(not overlap.ok, "overlap rejected")
	noWarnings("place")
end)

test("defence runs, waves clear, rewards granted live", function()
	local d = Registry.DataService:Get(p)
	local coins0 = d.Coins
	local r = __invoke("StartDefense", p, false)
	check(r.ok, tostring(r.err))
	__advance(60, 0.1)
	noWarnings("defence")
	check(d.Stats.HighestWave >= 1, "cleared wave 1, highest=" .. d.Stats.HighestWave)
	check(d.Coins > coins0, "coins earned")
	check(d.Stats.EnemiesDefeated > 0)
	check(#__firedTo(p, "EnemySnapshot") > 0, "snapshots")
	check(#__firedTo(p, "DefenseEvents") > 0, "events")
	local plot = Registry.PlotService:GetPlot(p)
	check(plot.Model:GetAttribute("DefenseState") ~= "Idle")
	local stop = __invoke("StopDefense", p)
	check(stop.ok)
	__advance(1)
	checkEq(plot.Model:GetAttribute("DefenseState"), "Idle")
	local states = __firedTo(p, "DefenseState")
	check(states[#states][1].Summary ~= nil, "summary sent")
end)

test("upgrade, move, store with refund", function()
	local d = Registry.DataService:Get(p)
	d.Coins += 1000
	local up = __invoke("UpgradeStructure", p, turretUid)
	check(up.ok, tostring(up.err))
	checkEq(d.Base.Structures[turretUid].Lvl, 2)
	local mv = __invoke("MoveStructure", p, turretUid, Grid.CenterX - 1, region.MinZ + 5, 1)
	check(mv.ok, tostring(mv.err))
	checkEq(d.Base.Structures[turretUid].X, Grid.CenterX - 1)
	local coins = d.Coins
	local st = __invoke("StoreStructure", p, turretUid)
	check(st.ok, tostring(st.err))
	check(d.Coins > coins, "refund")
	checkEq(d.Inventory["scrap_turret|Normal"].Count, 1)
	-- place it back for the offline test
	local again = __invoke("PlaceStructure", p, "scrap_turret|Normal", Grid.CenterX + 1, region.MinZ + 4, 0)
	check(again.ok, tostring(again.err))
	noWarnings("edit")
end)

test("selling: locked items protected, sell gives coins", function()
	local d = Registry.DataService:Get(p)
	__advance(3)
	local set = __invoke("SetItemFlag", p, "wooden_barricade|Normal", "Locked", true)
	check(set.ok, tostring(set.err))
	local sell = __invoke("SellItems", p, "wooden_barricade|Normal", 1)
	check(not sell.ok, "locked can't sell")
	__invoke("SetItemFlag", p, "wooden_barricade|Normal", "Locked", false)
	local coins = d.Coins
	local sell2 = __invoke("SellItems", p, "wooden_barricade|Normal", 1)
	check(sell2.ok, tostring(sell2.err))
	check(d.Coins > coins)
end)

test("upgrades gated by unlocks, then purchasable", function()
	local d = Registry.DataService:Get(p)
	local r = __invoke("BuyUpgrade", p, "Luck")
	if d.Stats.HighestWave < 3 then
		check(not r.ok, "locked early")
		d.Stats.HighestWave = 3
		Registry.ProgressionService:Refresh(p)
		__advance(0.5)
	end
	d.Coins += 10000
	local r2 = __invoke("BuyUpgrade", p, "Luck")
	check(r2.ok, tostring(r2.err))
	checkEq(d.Upgrades.Luck, 1)
	check(Registry.ProgressionService:GetLuck(p) > 1)
end)

test("leaving saves and releases the session lock", function()
	__removePlayer(p)
	__advance(2)
	local rec = __store["p_101"]
	check(rec ~= nil, "saved")
	check(rec.Lock == nil, "lock released")
	check(rec.Data.Stats.TotalRolls >= 2)
	check(rec.Data.LastOnline > 0)
	checkEq(Registry.PlotService:GetPlot(p), nil)
end)

test("rejoin after 2h: offline report granted once", function()
	__advance(7200, 60)
	local before = __store["p_101"].Data.Coins
	local p2 = __newPlayer(101, "Tester")
	__advance(2)
	__invoke("GetInitialState", p2)
	__advance(5)
	local reports = __firedTo(p2, "OfflineReport")
	checkEq(#reports, 1, "one report")
	local rep = reports[1][1]
	print(string.format("    offline: %s elapsed, waves %d, coins %d, core %d%%", tostring(rep.ElapsedSeconds), rep.WavesDefeated, rep.Coins, rep.CoreHealthPct))
	check(rep.Coins > 0)
	local d = Registry.DataService:Get(p2)
	check(d.Coins >= before + rep.Coins, "coins granted")
	noWarnings("offline")
	__removePlayer(p2)
	__advance(2)
end)

test("session lock: a live lock from another server blocks load, then kicks", function()
	__store["p_202"] = { Data = { Coins = 999 }, Lock = { JobId = "server-B", Time = os.time() } }
	local p3 = __newPlayer(202, "Locked")
	__advance(40, 1)
	check(p3.__kicked ~= nil, "kicked")
	checkEq(__store["p_202"].Lock.JobId, "server-B", "foreign lock untouched")
	checkEq(__store["p_202"].Data.Coins, 999, "data untouched")
	table.clear(__warnings)
end)

test("stale lock (crashed server) is taken over; datastore outage retries", function()
	__store["p_303"] = { Data = { Coins = 777 }, Lock = { JobId = "server-dead", Time = os.time() - 10000 } }
	__storeFailNext = 2
	local p4 = __newPlayer(303, "Stale")
	__advance(15, 1)
	check(Registry.DataService:IsLoaded(p4), "loaded after retries")
	checkEq(Registry.DataService:Get(p4).Coins, 777, "kept old data + reconciled")
	check(Registry.DataService:Get(p4).Base ~= nil, "template fields reconciled")
	table.clear(__warnings)
end)

test("load failure never produces a blank save", function()
	__storeFailNext = 100
	local p5 = __newPlayer(404, "Unlucky")
	__advance(60, 1)
	check(p5.__kicked ~= nil, "kicked instead of blank profile")
	checkEq(__store["p_404"], nil, "nothing written")
	__storeFailNext = 0
	table.clear(__warnings)
end)

summary()

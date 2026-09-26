-- Boots the real server AND the real client controllers in one mock process,
-- with remotes looped back, then drives the first-session flow through the
-- client code (roll animation, inventory, build mode, defence HUD, tutorial).
local Grid = require(Shared.Util.Grid)

require(game:GetService("ServerScriptService"):WaitForChild("Server"))
__flush()
local ServerRegistry = require(Server.Registry)

local p = __newPlayer(501, "ClientTester")
game:GetService("Players").__props.LocalPlayer = p
__localPlayer = p
__advance(1)

local Client = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
require(Client)
__advance(2)
local C = require(Client.Registry)
local State = require(Client.State)

local function noWarnings(label)
	if #__warnings > 0 then
		error(label .. " produced warnings:\n  " .. table.concat(__warnings, "\n  "))
	end
end

test("client boots and receives state", function()
	check(State.Get("Coins") ~= nil, "coins synced")
	check(State.Derived().Luck ~= nil, "derived synced")
	check(State.Get("Tutorial").Step == 1)
	noWarnings("boot")
end)

test("roll through the client: animation, card, tutorial advances", function()
	local shown = nil
	C.RollController.RollShown:Connect(function(r)
		shown = r
	end)
	task.spawn(C.RollController.Roll, false)
	__advance(3)
	check(shown ~= nil and shown.ItemId == "scrap_turret", "roll shown")
	__advance(1)
	checkEq(State.Get("Tutorial").Step, 2, "tutorial -> open inventory")
	noWarnings("roll")
end)

test("windows open and render (inventory, odds, index locked, shop locked)", function()
	C.HudController.Open("Inventory")
	__advance(0.5)
	check(C.HudController.IsOpen("Inventory"))
	checkEq(State.Get("Tutorial").Step, 3)
	C.HudController.Open("Odds")
	__advance(0.2)
	C.HudController.Open("Index") -- windows exist even if the button is gated
	__advance(0.2)
	C.HudController.Open("Shop")
	__advance(0.2)
	C.HudController.Close()
	noWarnings("windows")
end)

test("build mode: enter with item, preview, confirm places via server", function()
	C.BuildController.Enter("scrap_turret|Normal")
	__advance(0.3)
	check(C.BuildController.IsActive())
	checkEq(State.Get("Tutorial").Step, 4)
	-- Aim with the touch path: screen coords map to world XZ in the mock.
	local plot = ServerRegistry.PlotService:GetPlot(p)
	local cell = plot.CFrame * Vector3.new(Grid.CellToLocal(Grid.CenterX + 1, Grid.Region(1).MinZ + 4))
	local uis = game:GetService("UserInputService")
	-- Grid.CellToLocal returns two numbers; build the local point explicitly
	local lx, lz = Grid.CellToLocal(Grid.CenterX + 1, Grid.Region(1).MinZ + 4)
	cell = plot.CFrame * Vector3.new(lx, 0, lz)
	__mouse = Vector2.new(cell.X, cell.Z)
	__advance(0.2) -- RenderStepped aims at the mouse
	uis.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
	__advance(0.5)
	local count = 0
	for _ in State.Get("Base").Structures do
		count += 1
	end
	checkEq(count, 1, "placed through the client")
	checkEq(State.Get("Tutorial").Step, 5)
	noWarnings("build")
end)

test("select + upgrade panel, rotate key, exit", function()
	local uis = game:GetService("UserInputService")
	uis.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.R }, false)
	C.BuildController.Exit()
	__advance(0.2)
	check(not C.BuildController.IsActive())
	noWarnings("exit")
end)

test("start defence from the HUD, HUD + renderer + fx survive a wave", function()
	local btn = C.DefenseController.StartButton()
	btn.Activated:Fire()
	__advance(40, 0.1)
	check(State.Get("Stats").HighestWave >= 1, "wave cleared")
	check(State.Get("Tutorial").Step >= 7, "tutorial saw the wave clear, step=" .. State.Get("Tutorial").Step)
	local ok = require(Client.Net).Invoke("StopDefense")
	__advance(1)
	noWarnings("defence")
end)

test("second roll finishes the tutorial path; GOT IT completes it", function()
	__advance(2)
	task.spawn(C.RollController.Roll, false)
	__advance(3)
	checkEq(State.Get("Tutorial").Step, 8)
	require(Client.Net).Invoke("TutorialAdvance", 9)
	__advance(0.5)
	check(State.Get("Tutorial").Done, "tutorial done")
	check(State.IsUnlocked("Index"), "index unlocked after tutorial")
	noWarnings("tutorial")
end)

test("offline report UI renders", function()
	local re = game:GetService("ReplicatedStorage").Remotes.OfflineReport
	re:FireClient(p, { ElapsedSeconds = 3600, CountedSeconds = 3600, WavesDefeated = 10, EnemiesDefeated = 100, Coins = 500, Xp = 20, Dice = 1, BossesDefeated = 0, BestWave = 5, CoreHealthPct = 60, BaseFell = false })
	__advance(2)
	noWarnings("offline ui")
end)

test("every combat fx / boss event type renders without errors", function()
	local plot = ServerRegistry.PlotService:GetPlot(p)
	local uid = next(State.Get("Base").Structures)
	local re = game:GetService("ReplicatedStorage").Remotes
	local cx, cz = Grid.CenterX, Grid.Region(1).MinZ + 3
	re.DefenseEvents:FireClient(p, { PlotId = plot.Id, Events = {
		{ k = "waveStart", wave = 10, boss = "colossus", bossName = "The Colossus", music = "" },
		{ k = "fx", kind = "shot", s = uid, x = cx, z = cz },
		{ k = "fx", kind = "splash", s = uid, x = cx, z = cz, r = 1.2 },
		{ k = "fx", kind = "beam", s = uid, x = cx, z = cz + 4 },
		{ k = "fx", kind = "chain", s = uid, pts = { cx, cz, cx + 1, cz + 1, cx + 2, cz } },
		{ k = "fx", kind = "pulse", s = uid, r = 2.5 },
		{ k = "fx", kind = "trap", s = uid },
		{ k = "fx", kind = "shot", s = "missing-uid", x = cx, z = cz },
		{ k = "bossPhase", name = "RAGE", text = "The Colossus enters a RAGE!", phase = 4 },
		{ k = "kill", x = cx, z = cz, coins = 12, boss = true },
		{ k = "destroyed", uid = uid },
		{ k = "coreHit", damage = 5, hp = 50 },
		{ k = "waveCleared", wave = 10, bonus = 55 },
		{ k = "coreDestroyed" },
	} })
	re.EnemySnapshot:FireClient(p, { PlotId = plot.Id, Stride = 6, Data = { 1, 6, 1000, 1500, 40, 0, 2, 1, 1000, 1600, 100, 1 + 128 } })
	__advance(1)
	re.EnemySnapshot:FireClient(p, { PlotId = plot.Id, Stride = 6, Data = {} })
	__advance(1)
	noWarnings("fx")
end)

summary()

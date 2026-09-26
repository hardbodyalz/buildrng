--[[
	ClientMain
	Boots client controllers in dependency order, then requests the initial
	state from the server. The client only renders and asks; every decision
	(rolls, rewards, placement, combat) is made on the server.
]]

local Registry = require(script.Registry)
local State = require(script.State)
local Net = require(script.Net)

local Controllers = script.Controllers

local ORDER = {
	"SoundController",
	"HudController",
	"NotifyController",
	"FxController",
	"EnemyRenderer",
	"RollController",
	"InventoryController",
	"IndexController",
	"ShopController",
	"BuildController",
	"DefenseController",
	"OfflineController",
	"TutorialController",
}

for _, name in ORDER do
	Registry[name] = require(Controllers[name])
end

Net.On("Sync", function(payload)
	if type(payload) == "table" then
		State.Apply(payload)
	end
end)

for _, name in ORDER do
	local controller = Registry[name]
	if controller.Init then
		if name == "NotifyController" then
			controller.Init(Registry.HudController.Root())
		else
			controller.Init()
		end
	end
end

-- Ask for the full state (retry until the profile has loaded).
task.spawn(function()
	while true do
		local ok, res = Net.Invoke("GetInitialState")
		if ok then
			if res and res.Mock then
				Registry.NotifyController.Toast("Studio: DataStore unavailable - progress won't save", "Error")
			end
			break
		end
		task.wait(1)
	end
end)

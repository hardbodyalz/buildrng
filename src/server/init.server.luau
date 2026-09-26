--[[
	ServerMain
	Boots every service: Init() all (create remotes, register handlers), then
	Start() all (connect events, loops). DataService starts last so no player
	profile can load before every service is listening for ProfileLoaded.
]]

local Registry = require(script.Registry)
local Services = script.Services

local ORDER = {
	"DataService",
	"EconomyService",
	"ProgressionService",
	"InventoryService",
	"RollService",
	"PlotService",
	"BaseService",
	"DefenseService",
	"OfflineService",
}

for _, name in ORDER do
	Registry[name] = require(Services[name])
end

for _, name in ORDER do
	local service = Registry[name]
	if service.Init then
		service:Init()
	end
end

for _, name in ORDER do
	if name ~= "DataService" then
		local service = Registry[name]
		if service.Start then
			service:Start()
		end
	end
end
Registry.DataService:Start()

print("[Build & Defend RNG] server ready")

--[[
	State (client)
	Read-only mirror of the player's server data plus the server-computed
	"Derived" section. Controllers subscribe to keys they care about.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

local State = {
	Data = {} :: { [string]: any },
	Changed = Signal.new(), -- (key)
}

function State.Apply(payload: { [string]: any })
	for key, value in payload do
		State.Data[key] = value
	end
	for key in payload do
		State.Changed:Fire(key)
	end
end

function State.Get(key: string): any
	return State.Data[key]
end

-- Subscribe to one or more keys; `fn` also runs immediately if data exists.
function State.Watch(keys: { string }, fn: () -> ())
	local set = {}
	for _, k in keys do
		set[k] = true
	end
	-- Coalesce: several watched keys changing in one sync -> one call.
	local queued = false
	local conn = State.Changed:Connect(function(key)
		if set[key] and not queued then
			queued = true
			task.defer(function()
				queued = false
				fn()
			end)
		end
	end)
	for _, k in keys do
		if State.Data[k] ~= nil then
			task.spawn(fn)
			break
		end
	end
	return conn
end

function State.Derived(): any
	return State.Data.Derived or {}
end

function State.IsUnlocked(feature: string): boolean
	local d = State.Data.Derived
	return d ~= nil and d.Unlocks ~= nil and d.Unlocks[feature] == true
end

return State

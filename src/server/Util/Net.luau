--[[
	Net (server)
	Creates the remotes declared in Shared/Net/Remotes and wraps every
	client->server handler with: profile-loaded check, rate limiting, error
	isolation, and a uniform { ok, err } response shape.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)
local RateLimiter = require(script.Parent.RateLimiter)
local Registry = require(script.Parent.Parent.Registry)

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local functions: { [string]: RemoteFunction } = {}
local events: { [string]: RemoteEvent } = {}

for name in Remotes.Functions do
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = folder
	functions[name] = rf
	-- Default handler until a service registers one.
	rf.OnServerInvoke = function()
		return { ok = false, err = "Not ready" }
	end
end
for _, name in Remotes.Events do
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = folder
	events[name] = re
end
folder.Parent = ReplicatedStorage

-- handler(player, ...) -> (ok: boolean, errOrData: any)
function Net.Handle(name: string, handler: (Player, ...any) -> (boolean, any))
	local rf = functions[name]
	assert(rf, "Unknown remote function " .. name)
	local bucket = Remotes.Functions[name]
	rf.OnServerInvoke = function(player: Player, ...)
		if not Registry.DataService:IsLoaded(player) then
			return { ok = false, err = "Still loading..." }
		end
		if not RateLimiter.Allow(player, bucket) then
			return { ok = false, err = "Slow down!" }
		end
		local success, ok, data = pcall(handler, player, ...)
		if not success then
			warn(string.format("[Net] %s handler error for %s: %s", name, player.Name, tostring(ok)))
			return { ok = false, err = "Server error" }
		end
		if ok then
			return { ok = true, data = data }
		end
		return { ok = false, err = data }
	end
end

function Net.Fire(name: string, player: Player, ...)
	local re = events[name]
	if player.Parent then
		re:FireClient(player, ...)
	end
end

function Net.FireAll(name: string, ...)
	events[name]:FireAllClients(...)
end

function Net.FireList(name: string, players: { Player }, ...)
	local re = events[name]
	for _, p in players do
		if p.Parent then
			re:FireClient(p, ...)
		end
	end
end

function Net.Notify(player: Player, text: string, kind: string?)
	Net.Fire("Notify", player, { Text = text, Kind = kind or "Info" })
end

Players.PlayerRemoving:Connect(function(player)
	RateLimiter.Clear(player)
end)

return Net

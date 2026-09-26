--[[
	Net (client)
	Thin wrapper over the server's remotes. Invoke returns (ok, dataOrError).
	The client never decides outcomes - it only asks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local Net = {}

function Net.Invoke(name: string, ...): (boolean, any)
	local rf = folder:WaitForChild(name) :: RemoteFunction
	local ok, result = pcall(rf.InvokeServer, rf, ...)
	if not ok then
		return false, "Connection problem"
	end
	if type(result) ~= "table" then
		return false, "Bad response"
	end
	if result.ok then
		return true, result.data
	end
	return false, result.err or "Failed"
end

function Net.On(name: string, fn: (...any) -> ())
	local re = folder:WaitForChild(name) :: RemoteEvent
	return re.OnClientEvent:Connect(fn)
end

return Net

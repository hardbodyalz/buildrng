--[[
	Signal
	Lightweight script signal (no BindableEvent, so values aren't copied).
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	local conn
	conn = {
		Connected = true,
		Disconnect = function(c)
			c.Connected = false
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
	table.insert(handlers, fn)
	return conn
end

function Signal:Once(fn: (...any) -> ())
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	-- Copy so handlers can disconnect while firing.
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal

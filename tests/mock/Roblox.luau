--[[
	Minimal Roblox mock for headless server integration tests.
	Implements just enough of the engine API used by src/server: instances
	with parenting/attributes, signals, services, a virtual-clock task
	scheduler, CFrame/Vector3 maths and an in-memory DataStore.
	Loaded after the module bundle prelude (see tests/run.py).
]]

-- Virtual clock + scheduler ----------------------------------------------------------
local vclock = 1000
local realOs = os
os = setmetatable({
	clock = function()
		return vclock
	end,
	time = function()
		return math.floor(vclock)
	end,
}, { __index = realOs })

local queue = {} -- { at, thread, args }
local function schedule(at, thread, ...)
	table.insert(queue, { at = at, thread = thread, args = table.pack(...) })
end
local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		error(debug.traceback(thread, tostring(err)), 0)
	end
end

task = {}
function task.spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(vclock, thread, ...)
	return thread
end
function task.delay(t, fn, ...)
	local thread = coroutine.create(fn)
	schedule(vclock + (t or 0), thread, ...)
	return thread
end
function task.wait(t)
	local thread = coroutine.running()
	schedule(vclock + (t or 0.03), thread)
	coroutine.yield()
	return t or 0.03
end

-- Run everything due up to now (+ deferred chains).
function __flush()
	for _ = 1, 10000 do
		local best, bi = nil, nil
		for i, q in queue do
			if q.at <= vclock and (not best or q.at < best.at) then
				best, bi = q, i
			end
		end
		if not best then
			return
		end
		table.remove(queue, bi)
		resume(best.thread, table.unpack(best.args, 1, best.args.n))
	end
	error("scheduler runaway")
end

local heartbeat -- set below
-- Advance virtual time in steps, firing Heartbeat each step.
function __advance(seconds, step)
	step = step or 0.1
	local target = vclock + seconds
	while vclock < target - 1e-9 do
		local dt = math.min(step, target - vclock)
		vclock += dt
		__flush()
		heartbeat:Fire(dt)
		__flush()
		renderStepped:Fire(dt)
		__flush()
	end
end

function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	table.insert(__warnings, table.concat(parts, " "))
end
__warnings = {}

-- Signals -----------------------------------------------------------------------------
local Sig = {}
Sig.__index = Sig
local function newSignal()
	return setmetatable({ handlers = {} }, Sig)
end
function Sig:Connect(fn)
	table.insert(self.handlers, fn)
	local handlers = self.handlers
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end
function Sig:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end
function Sig:Fire(...)
	for _, fn in table.clone(self.handlers) do
		task.spawn(fn, ...)
	end
end

-- Datatypes ---------------------------------------------------------------------------
local V3 = {}
V3.__index = V3
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	return v3(a.X / b, a.Y / b, a.Z / b)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
	elseif k == "Unit" then
		local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return rawget(V3, k)
end
function V3:Lerp(o, t)
	return v3(self.X + (o.X - self.X) * t, self.Y + (o.Y - self.Y) * t, self.Z + (o.Z - self.Z) * t)
end
function V3:Dot(o)
	return self.X * o.X + self.Y * o.Y + self.Z * o.Z
end
function V3:Cross(o)
	return v3(self.Y * o.Z - self.Z * o.Y, self.Z * o.X - self.X * o.Z, self.X * o.Y - self.Y * o.X)
end
Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1) }

-- CFrame: position + 3x3 rotation (row-major r00..r22)
local CF = {}
local function cf(px, py, pz, r)
	local c = setmetatable({ p = v3(px, py, pz), r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CF)
	return c
end
local function mulR(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			o[i * 3 + j + 1] = s
		end
	end
	return o
end
local function rotV(r, v)
	return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r)
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		local p = a.p + rotV(a.r, b.p)
		return cf(p.X, p.Y, p.Z, mulR(a.r, b.r))
	end
	return a.p + rotV(a.r, b) -- CFrame * Vector3
end
CF.__index = function(self, k)
	if k == "Position" then
		return self.p
	elseif k == "LookVector" then
		return v3(-self.r[3], -self.r[6], -self.r[9])
	elseif k == "X" then
		return self.p.X
	elseif k == "Y" then
		return self.p.Y
	elseif k == "Z" then
		return self.p.Z
	end
	return rawget(CF, k)
end
function CF:PointToObjectSpace(v)
	return rotV(transpose(self.r), v - self.p)
end
function CF:VectorToObjectSpace(v)
	return rotV(transpose(self.r), v)
end
function CF:ToObjectSpace(o)
	local inv = transpose(self.r)
	local p = rotV(inv, o.p - self.p)
	return cf(p.X, p.Y, p.Z, mulR(inv, o.r))
end
function CF:Inverse()
	local inv = transpose(self.r)
	local p = rotV(inv, -self.p)
	return cf(p.X, p.Y, p.Z, inv)
end
local function angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(0, 0, 0, mulR(mulR(Rx, Ry), Rz))
end
CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then
			return cf(x.X, x.Y, x.Z)
		end
		return cf(x or 0, y or 0, z or 0)
	end,
	Angles = angles,
	fromEulerAnglesXYZ = angles,
	lookAt = function(at, target)
		local f = (target - at).Unit
		local right = f:Cross(v3(0, 1, 0))
		if right.Magnitude < 1e-6 then
			right = v3(1, 0, 0)
		end
		right = right.Unit
		local up = right:Cross(f)
		return cf(at.X, at.Y, at.Z, { right.X, up.X, -f.X, right.Y, up.Y, -f.Y, right.Z, up.Z, -f.Z })
	end,
}

Color3 = {
	new = function(r, g, b)
		return { R = r, G = g, B = b, Lerp = function(self, o, t)
			return Color3.new(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t)
		end }
	end,
}
Color3.fromRGB = function(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end

local function genericType()
	return setmetatable({}, {
		__index = function(_, k)
			return function(...)
				return { __ctor = k, ... }
			end
		end,
	})
end
UDim2 = genericType()
UDim = genericType()
local V2 = {}
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b)
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b) return v2(a.X / b, a.Y / b) end
V2.__index = function(self, k)
	if k == "Magnitude" then return math.sqrt(self.X ^ 2 + self.Y ^ 2) end
	return nil
end
Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }
NumberRange = genericType()
NumberSequence = genericType()
NumberSequenceKeypoint = genericType()
ColorSequence = genericType()
TweenInfo = genericType()

local enumCache = {}
RaycastParams = { new = function() return {} end }
local function enumProxy(path)
	if enumCache[path] then
		return enumCache[path]
	end
	local e = setmetatable({ __enum = path }, {
		__index = function(self, k)
			return enumProxy(path .. "." .. k)
		end,
		__tostring = function()
			return path
		end,
	})
	enumCache[path] = e
	return e
end
Enum = enumProxy("Enum")

Random = {
	new = function()
		return {
			NextNumber = function()
				return math.random()
			end,
			NextInteger = function(_, a, b)
				return math.random(a, b)
			end,
		}
	end,
}

-- Instances -----------------------------------------------------------------------------
local IS_A = {
	Part = { "BasePart", "PVInstance" },
	WedgePart = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	IntValue = { "ValueBase" },
}

local Inst = {}
local function newInstance(className)
	local self = {
		__class = className,
		__props = { Name = className },
		__children = {},
		__attrs = {},
		__attrSignals = {},
		__parent = nil,
	}
	return setmetatable(self, Inst)
end

local methods = {}
function methods:GetChildren()
	return table.clone(self.__children)
end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in i.__children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name)
	for _, c in self.__children do
		if c.Name == name then
			return c
		end
	end
	local mp = rawget(self, "__modulePath")
	if mp and __sources and (__sources[mp .. "/" .. name] or __hasPrefix(mp .. "/" .. name)) then
		return __proxy(mp .. "/" .. name)
	end
	return nil
end
function methods:WaitForChild(name)
	local c = self:FindFirstChild(name)
	assert(c, "WaitForChild would hang: " .. tostring(self.Name) .. "." .. name)
	return c
end
function methods:FindFirstChildOfClass(cls)
	for _, c in self.__children do
		if c.__class == cls then
			return c
		end
	end
	return nil
end
function methods:FindFirstAncestorOfClass(cls)
	local p = self.__parent
	while p do
		if p.__class == cls then
			return p
		end
		p = p.__parent
	end
	return nil
end
function methods:IsA(cls)
	if self.__class == cls or cls == "Instance" then
		return true
	end
	for _, b in IS_A[self.__class] or {} do
		if b == cls then
			return true
		end
	end
	return false
end
function methods:Destroy()
	self.Parent = nil
	for _, c in table.clone(self.__children) do
		c:Destroy()
	end
	self.__destroyed = true
end
function methods:ClearAllChildren()
	for _, c in table.clone(self.__children) do
		c:Destroy()
	end
end
function methods:SetAttribute(k, v)
	self.__attrs[k] = v
	local s = self.__attrSignals[k]
	if s then
		s:Fire()
	end
end
function methods:GetAttribute(k)
	return self.__attrs[k]
end
function methods:GetAttributeChangedSignal(k)
	self.__attrSignals[k] = self.__attrSignals[k] or newSignal()
	return self.__attrSignals[k]
end
function methods:GetPropertyChangedSignal()
	return newSignal()
end
function methods:GetPivot()
	if self.__class == "Model" then
		local pp = self.PrimaryPart
		return if pp then pp.CFrame else CFrame.new()
	end
	return self.CFrame
end
function methods:PivotTo(target)
	if self.__class == "Model" then
		local pivot = self:GetPivot()
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				local rel = pivot:ToObjectSpace(d.CFrame)
				d.CFrame = target * rel
			end
		end
	else
		self.CFrame = target
	end
end
function methods:GetBoundingBox()
	return CFrame.new(), v3(4, 4, 4)
end
function methods:Kick(msg)
	self.__kicked = msg or true
	self.Parent = nil
end
function methods:FireClient(player, ...)
	table.insert(__fired, { remote = self.Name, player = player, args = table.pack(...) })
	if __localPlayer and player == __localPlayer then
		self.OnClientEvent:Fire(__deepcopy(table.pack(...))[1], select(2, ...))
	end
end
function methods:FireAllClients(...)
	table.insert(__fired, { remote = self.Name, player = "*", args = table.pack(...) })
	if __localPlayer then
		self.OnClientEvent:Fire(__deepcopy(table.pack(...))[1], select(2, ...))
	end
end
function methods:InvokeServer(...)
	-- Loopback: deep-copy args/results like the network would.
	local res = self.OnServerInvoke(__localPlayer, table.unpack(__deepcopy(table.pack(...)), 1, select("#", ...)))
	return __deepcopy(res)
end
function methods:Play() end
function methods:Stop() end
function methods:Create(inst, _info, goal)
	return {
		Play = function()
			for k, v in goal do
				inst[k] = v
			end
		end,
	}
end
function methods:ViewportPointToRay(x, y)
	-- Test convention: screen (x, y) maps straight down onto world (x, z).
	return { Origin = Vector3.new(x, 200, y), Direction = Vector3.new(0, -1, 0) }
end
function methods:Raycast()
	return nil
end
function methods:BulkMoveTo(parts, cframes)
	for i, p in parts do
		p.CFrame = cframes[i]
	end
end
function methods:GetMouseLocation()
	return __mouse or Vector2.new(0, 0)
end
function methods:GetPropertyChangedSignal()
	return newSignal()
end

Inst.__index = function(self, k)
	if methods[k] then
		return methods[k]
	end
	if k == "Parent" then
		return self.__parent
	elseif k == "ClassName" then
		return self.__class
	end
	local v = self.__props[k]
	if v ~= nil then
		return v
	end
	if k == "CFrame" then
		return CFrame.new()
	elseif k == "Transparency" then
		return 0
	elseif k == "Position" then
		return (self.__props.CFrame or CFrame.new()).Position
	elseif k == "Character" or k == "PrimaryPart" then
		return nil
	elseif k == "AbsolutePosition" or k == "AbsoluteSize" then
		return Vector2.new(100, 100)
	elseif __EVENTS[k] then
		local sig = newSignal()
		self.__props[k] = sig
		return sig
	end
	-- Unknown: child lookup (like Roblox's dot-access for children).
	return methods.FindFirstChild(self, k)
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = self.__parent
		if old then
			local i = table.find(old.__children, self)
			if i then
				table.remove(old.__children, i)
			end
		end
		self.__parent = v
		if v then
			table.insert(v.__children, self)
		end
		return
	end
	if k == "Size" and self.__class ~= "BillboardGui" and type(v) ~= "table" then
		error("bad Size")
	end
	self.__props[k] = v
end

__fired = {}
__EVENTS = {
	Activated = true, MouseEnter = true, MouseLeave = true, MouseButton1Down = true, MouseButton1Up = true,
	Changed = true, OnClientEvent = true, OnServerEvent = true, Ended = true, CharacterAdded = true,
	FocusLost = true, ChildAdded = true, DescendantAdded = true, ChildRemoved = true,
}

local PLAIN_CLASSES = {}
Instance = {
	new = function(className, parent)
		local i = newInstance(className)
		if className == "RemoteEvent" then
			i.__props.OnServerEvent = newSignal()
		elseif className == "Player" then
			i.__props.CharacterAdded = newSignal()
		end
		if parent then
			i.Parent = parent
		end
		return i
	end,
}

-- Module-proxy fallback: service children that are Rojo-mounted folders.
function __hasPrefix(prefix)
	for k in __sources do
		if string.sub(k, 1, #prefix + 1) == prefix .. "/" then
			return true
		end
	end
	return false
end

-- Services ---------------------------------------------------------------------------------
local services = {}
local function service(name)
	local s = newInstance(name)
	s.__props.Name = name
	rawset(s, "__modulePath", name)
	services[name] = s
	return s
end

local Players = service("Players")
Players.__props.PlayerAdded = newSignal()
Players.__props.PlayerRemoving = newSignal()
function Players:GetPlayers()
	local out = {}
	for _, c in self.__children do
		if c.__class == "Player" then
			table.insert(out, c)
		end
	end
	return out
end
rawset(Players, "GetPlayers", Players.GetPlayers)

service("ReplicatedStorage")
service("ServerScriptService")
service("Workspace")
service("SoundService")
service("TweenService")
local RunService = service("RunService")
heartbeat = newSignal()
renderStepped = newSignal()
RunService.__props.Heartbeat = heartbeat
RunService.__props.RenderStepped = renderStepped
local UIS = service("UserInputService")
for _, ev in { "InputBegan", "InputEnded", "InputChanged", "TouchTapInWorld", "TouchPan", "TouchPinch", "LastInputTypeChanged" } do
	UIS.__props[ev] = newSignal()
end
UIS.__props.MouseEnabled = true
UIS.__props.TouchEnabled = false
local camera = newInstance("Camera")
camera.__props.ViewportSize = Vector2.new(1280, 720)
camera.__props.FieldOfView = 70
services.Workspace.__props.CurrentCamera = camera
rawset(RunService, "IsStudio", function()
	return false
end)

-- DataStore mock (shared across "servers": tests can inspect/modify)
__store = {}
__storeFailNext = 0
local DataStoreService = service("DataStoreService")
rawset(DataStoreService, "GetDataStore", function()
	return {
		UpdateAsync = function(_, key, fn)
			if __storeFailNext > 0 then
				__storeFailNext -= 1
				error("503: DataStore unavailable (mock)")
			end
			local old = __store[key]
			local copy = if old then __deepcopy(old) else nil
			local result = fn(copy)
			if result ~= nil then
				__store[key] = __deepcopy(result)
			end
			return result
		end,
		GetAsync = function(_, key)
			return __store[key]
		end,
	}
end)

function __deepcopy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in t do
		o[k] = __deepcopy(v)
	end
	return o
end

local closers = {}
game = newInstance("DataModel")
rawset(game, "__modulePath", "")
game.__props.JobId = "server-A"
rawset(game, "GetService", function(_, name)
	return services[name] or service(name)
end)
rawset(game, "BindToClose", function(_, fn)
	table.insert(closers, fn)
end)
function __close()
	for _, fn in closers do
		task.spawn(fn)
	end
	__advance(30, 0.5)
end
for name, s in services do
	s.Parent = game
end

function __newPlayer(userId, name)
	local p = Instance.new("Player")
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = p
	p.__props.UserId = userId
	p.__props.Name = name
	p.__props.DisplayName = name
	p.__props.Character = nil
	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	return p
end
function __removePlayer(p)
	Players.PlayerRemoving:Fire(p)
	p.Parent = nil
	__flush()
end
function __invoke(name, player, ...)
	local rf = services.ReplicatedStorage:FindFirstChild("Remotes"):FindFirstChild(name)
	assert(rf, "no remote " .. name)
	return rf.OnServerInvoke(player, ...)
end
function __firedTo(player, remote)
	local out = {}
	for _, f in __fired do
		if f.remote == remote and (f.player == player or f.player == "*") then
			table.insert(out, f.args)
		end
	end
	return out
end

--[[
	DataService
	Loads, session-locks, autosaves and releases player data.

	Safety rules:
	  * Every write uses UpdateAsync.
	  * A session lock ({ JobId, Time }) is written on load. Another server
	    holding a fresh lock blocks loading (we retry, then kick) so the same
	    profile can never be live in two servers (duplication protection).
	    Locks older than SessionLockTimeout are treated as abandoned (crash).
	  * A profile that failed to load is NEVER saved (so a DataStore outage
	    can't overwrite real data with a blank template). The player is
	    kicked with a friendly message instead of playing on blank data.
	  * If a save discovers our lock was taken over, we stop saving that
	    profile and kick the player.
	  * In Studio without API access, a non-persistent in-memory store is used.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)
local DataTemplate = require(script.Parent.DataTemplate)

local DCFG = GameConfig.Data

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- (player, data)
DataService.ProfileReleasing = Signal.new() -- (player, data) fired before the final save
DataService.ClientReady = Signal.new() -- (player) client UI is up and listening

type Profile = {
	Data: any,
	Key: string,
	Released: boolean,
	LockLost: boolean,
	Pending: { [string]: boolean },
	FlushQueued: boolean,
	ClientReady: boolean,
}

local profiles: { [Player]: Profile } = {}
local store: any = nil
local usingMock = false

-- In-memory stand-in with the same UpdateAsync contract (Studio without API access).
local MockStore = {}
MockStore.__index = MockStore
function MockStore.new()
	return setmetatable({ data = {} }, MockStore)
end
function MockStore:UpdateAsync(key, fn)
	local result = fn(self.data[key])
	if result ~= nil then
		self.data[key] = result
	end
	return result
end
function MockStore:GetAsync(key)
	return self.data[key]
end

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

-- Fill keys that exist in the template but not in data (recursively for dict sections).
function DataService.Reconcile(data, template)
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil then
			DataService.Reconcile(data[k], v)
		end
	end
end

local function migrate(data)
	local guard = 0
	while (data.Version or 1) < DataTemplate.Version and guard < 100 do
		local fn = DataTemplate.Migrations[data.Version or 1]
		if not fn then
			break
		end
		fn(data)
		guard += 1
	end
	data.Version = DataTemplate.Version
end

local function lockIsForeign(record): boolean
	local lock = record and record.Lock
	if not lock then
		return false
	end
	if lock.JobId == game.JobId then
		return false
	end
	return os.time() - (lock.Time or 0) < DCFG.SessionLockTimeout
end

local function loadProfile(player: Player)
	local key = DCFG.KeyPrefix .. player.UserId
	local loaded = nil

	for attempt = 1, DCFG.LoadRetries do
		local blocked = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				if lockIsForeign(old) then
					blocked = true
					return nil -- cancel the write, leave their lock alone
				end
				blocked = false
				local data = if old and old.Data then old.Data else DataTemplate.New()
				loaded = data
				return { Data = data, Lock = { JobId = game.JobId, Time = os.time() } }
			end)
		end)
		if ok and not blocked and loaded then
			break
		end
		if not player.Parent then
			return
		end
		loaded = nil
		if not ok then
			warn(string.format("[DataService] load attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
		else
			warn(string.format("[DataService] %s's data is locked by another server (attempt %d)", player.Name, attempt))
		end
		task.wait(DCFG.LoadRetryDelay)
	end

	if not player.Parent then
		-- Left while loading: hand the lock back so their next server isn't blocked.
		if loaded then
			pcall(function()
				store:UpdateAsync(key, function(old)
					if old and old.Lock and old.Lock.JobId == game.JobId then
						old.Lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end
	if not loaded then
		player:Kick("We couldn't load your save safely. Your data is untouched - please rejoin in a minute.")
		return
	end

	migrate(loaded)
	DataService.Reconcile(loaded, DataTemplate.New())

	profiles[player] = {
		Data = loaded,
		Key = key,
		Released = false,
		LockLost = false,
		Pending = {},
		FlushQueued = false,
		ClientReady = false,
	}
	DataService.ProfileLoaded:Fire(player, loaded)
end

-- Returns true if written. `release` clears the session lock.
local function saveProfile(player: Player, profile: Profile, release: boolean): boolean
	if profile.LockLost then
		return false
	end
	if not release then
		profile.Data.LastOnline = os.time()
	end
	for attempt = 1, DCFG.SaveRetries do
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(profile.Key, function(old)
				if old and old.Lock and old.Lock.JobId ~= game.JobId then
					lostLock = true
					return nil
				end
				return {
					Data = profile.Data,
					Lock = if release then nil else { JobId = game.JobId, Time = os.time() },
				}
			end)
		end)
		if ok then
			if lostLock then
				profile.LockLost = true
				warn(string.format("[DataService] %s's session was taken over by another server; not saving.", player.Name))
				if player.Parent then
					player:Kick("Your data was opened in another server.")
				end
				return false
			end
			return true
		end
		warn(string.format("[DataService] save attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
		task.wait(2 ^ attempt)
	end
	return false
end

local function releaseProfile(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	profile.Data.LastOnline = os.time()
	DataService.ProfileReleasing:Fire(player, profile.Data)
	saveProfile(player, profile, true)
	profiles[player] = nil
end

function DataService:Get(player: Player): any
	local p = profiles[player]
	return if p and not p.Released then p.Data else nil
end

function DataService:IsLoaded(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and not p.Released
end

function DataService:IsClientReady(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and p.ClientReady
end

function DataService:IsMock(): boolean
	return usingMock
end

-- Queue top-level data keys (or "Derived") for replication to the owner.
function DataService:Replicate(player: Player, ...: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, key in { ... } do
		profile.Pending[key] = true
	end
	if profile.FlushQueued then
		return
	end
	profile.FlushQueued = true
	task.defer(function()
		profile.FlushQueued = false
		if profile.Released or not player.Parent then
			return
		end
		local payload = {}
		for key in profile.Pending do
			if key == "Derived" then
				payload.Derived = Registry.ProgressionService:GetDerived(player)
			else
				payload[key] = profile.Data[key]
			end
		end
		profile.Pending = {}
		Net.Fire("Sync", player, payload)
	end)
end

function DataService:ReplicateAll(player: Player)
	local data = self:Get(player)
	if not data then
		return
	end
	local keys = { "Derived" }
	for k in data do
		table.insert(keys, k)
	end
	self:Replicate(player, table.unpack(keys))
end

function DataService:Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DCFG.StoreName)
	end)
	if ok then
		store = result
		-- Probe for API access (Studio without "Enable Studio Access to API Services").
		local probeOk, probeErr = pcall(function()
			return store:GetAsync("__probe")
		end)
		if not probeOk and RunService:IsStudio() then
			warn("[DataService] DataStore unavailable in Studio (" .. tostring(probeErr) .. "). Using a NON-PERSISTENT mock store.")
			store = MockStore.new()
			usingMock = true
		end
	elseif RunService:IsStudio() then
		warn("[DataService] DataStore unavailable in Studio. Using a NON-PERSISTENT mock store.")
		store = MockStore.new()
		usingMock = true
	else
		error("[DataService] DataStoreService unavailable: " .. tostring(result))
	end

	Net.Handle("GetInitialState", function(player)
		DataService:ReplicateAll(player)
		local profile = profiles[player]
		if profile and not profile.ClientReady then
			profile.ClientReady = true
			DataService.ClientReady:Fire(player)
		end
		return true, { Mock = usingMock }
	end)
end

function DataService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(releaseProfile)

	task.spawn(function()
		while true do
			task.wait(DCFG.AutosaveInterval)
			for player, profile in profiles do
				if not profile.Released then
					task.spawn(saveProfile, player, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		for player in profiles do
			task.spawn(releaseProfile, player)
		end
		-- Profiles are removed from the table only after their final save
		-- finishes (including releases already started by PlayerRemoving).
		local deadline = os.clock() + 25
		while next(profiles) ~= nil and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService

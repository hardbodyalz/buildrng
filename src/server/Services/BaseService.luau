--[[
	BaseService
	Authoritative building: place, move, store (pick up) and upgrade
	structures. Every request is re-validated with the same Grid rules the
	client preview uses; the client's preview is only a hint.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Grid = require(Shared.Util.Grid)
local ItemStats = require(Shared.Util.ItemStats)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)

local G = GameConfig.Grid

local BaseService = {}

local function countStructures(structures): number
	local n = 0
	for _ in structures do
		n += 1
	end
	return n
end

local function validCoords(x, z, rot): boolean
	return Validate.Int(x, 0, G.MaxWidth - 1) and Validate.Int(z, 0, G.MaxLength - 1) and Validate.Int(rot, 0, 3)
end

local function check(player: Player, def, x: number, z: number, rot: number, ignoreUid: string?)
	local d = Registry.DataService:Get(player)
	local structures = d.Base.Structures
	return Grid.CheckPlacement({
		Region = Grid.Region(d.Base.Tier),
		Occupancy = Grid.BuildOccupancy(structures, Items.ById, ignoreUid),
		Def = def,
		X = x,
		Z = z,
		Rot = rot,
		PlacedCount = countStructures(structures),
		Capacity = Registry.ProgressionService:GetCapacity(player),
		IsMove = ignoreUid ~= nil,
	})
end

local function changed(player: Player)
	Registry.DataService:Replicate(player, "Base")
	Registry.PlotService:SyncStructures(player)
	Registry.DefenseService:OnLayoutChanged(player)
end

local function getStructure(player: Player, uid: any)
	if not Validate.String(uid, 16) then
		return nil
	end
	local d = Registry.DataService:Get(player)
	return d.Base.Structures[uid]
end

function BaseService:Init()
	Net.Handle("PlaceStructure", function(player, key, x, z, rot)
		local def, mut = Registry.InventoryService.ParseKey(key)
		if not def or not validCoords(x, z, rot) then
			return false, "Invalid request"
		end
		if Registry.InventoryService:GetCount(player, key) < 1 then
			return false, "You don't have that item"
		end
		local status, reason = check(player, def, x, z, rot, nil)
		if status == Grid.Status.Invalid then
			return false, reason
		end
		if not Registry.InventoryService:RemoveItem(player, key, 1) then
			return false, "You don't have that item"
		end
		local d = Registry.DataService:Get(player)
		local uid = "s" .. d.Base.NextUid
		d.Base.NextUid += 1
		d.Base.Structures[uid] = { Id = def.Id, Mut = mut, Lvl = 1, X = x, Z = z, R = rot, Spent = 0 }
		changed(player)
		return true, uid
	end)

	Net.Handle("MoveStructure", function(player, uid, x, z, rot)
		local s = getStructure(player, uid)
		if not s or not validCoords(x, z, rot) then
			return false, "Invalid request"
		end
		if Registry.DefenseService:IsStructureDestroyed(player, uid) then
			return false, "It's rubble - it rebuilds after the wave"
		end
		local def = Items.Get(s.Id)
		local status, reason = check(player, def, x, z, rot, uid)
		if status == Grid.Status.Invalid then
			return false, reason
		end
		s.X, s.Z, s.R = x, z, rot
		changed(player)
		return true, uid
	end)

	Net.Handle("StoreStructure", function(player, uid)
		local s = getStructure(player, uid)
		if not s then
			return false, "Invalid request"
		end
		if Registry.DefenseService:IsStructureDestroyed(player, uid) then
			return false, "It's rubble - it rebuilds after the wave"
		end
		local d = Registry.DataService:Get(player)
		d.Base.Structures[uid] = nil
		Registry.InventoryService:ReturnItem(player, s.Id, s.Mut)
		local refund = math.floor((s.Spent or 0) * GameConfig.Economy.StoreRefundFraction)
		if refund > 0 then
			Registry.EconomyService:AddCoins(player, refund)
		end
		changed(player)
		return true, { Refund = refund }
	end)

	Net.Handle("UpgradeStructure", function(player, uid)
		local s = getStructure(player, uid)
		if not s then
			return false, "Invalid request"
		end
		local def = Items.Get(s.Id)
		local level = s.Lvl or 1
		if level >= ItemStats.MaxLevel(def) then
			return false, "Max level"
		end
		local cost = ItemStats.UpgradeCost(def, level)
		if not Registry.EconomyService:SpendCoins(player, cost) then
			return false, "Not enough coins"
		end
		s.Lvl = level + 1
		s.Spent = (s.Spent or 0) + cost
		changed(player)
		return true, s.Lvl
	end)
end

function BaseService:Start() end

return BaseService

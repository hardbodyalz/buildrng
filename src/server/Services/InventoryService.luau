--[[
	InventoryService
	Unplaced items are stored as stacks keyed "itemId|Mutation" -> { Count, Locked, Favorite }.
	(Placed structures live in Base.Structures with their own level.)
	Also owns the Index (discovery log) and selling.

	Locked stacks can never be sold. Favourite stacks are skipped by mass-sell.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local ItemStats = require(Shared.Util.ItemStats)
local Registry = require(script.Parent.Parent.Registry)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)

local InventoryService = {}

local function data(player)
	return Registry.DataService:Get(player)
end

function InventoryService.StackKey(itemId: string, mutationId: string?): string
	return itemId .. "|" .. (mutationId or Mutations.NormalId)
end

-- Returns itemDef, mutationId for a valid key, else nil.
function InventoryService.ParseKey(key: any): (any, string?)
	if not Validate.String(key, 80) then
		return nil, nil
	end
	local itemId, mutationId = string.match(key, "^([%w_]+)|(%w+)$")
	if not itemId or not Items.IsValid(itemId) or not Mutations.IsValid(mutationId) then
		return nil, nil
	end
	return Items.Get(itemId), mutationId
end

-- Adds items and records the discovery. Returns (firstEverOfItem, firstOfThisMutation).
function InventoryService:AddItem(player: Player, itemId: string, mutationId: string?, count: number?): (boolean, boolean)
	local d = data(player)
	local def = Items.Get(itemId)
	if not d or not def then
		return false, false
	end
	local n = count or 1
	local mut = mutationId or Mutations.NormalId
	local key = InventoryService.StackKey(itemId, mut)
	local stack = d.Inventory[key]
	if not stack then
		stack = { Count = 0, Locked = false, Favorite = false }
		d.Inventory[key] = stack
	end
	stack.Count += n

	local entry = d.Index[itemId]
	local isNew = false
	if not entry then
		entry = { First = os.time(), Count = 0, Muts = {} }
		d.Index[itemId] = entry
		isNew = true
	end
	entry.Count += n
	local newMut = false
	if mut ~= Mutations.NormalId then
		d.Stats.Mutations += n
		if not entry.Muts[mut] then
			entry.Muts[mut] = true
			newMut = true
		end
	end
	local order = Rarities.OrderOf(def.Rarity)
	if order > d.Stats.BestRarityOrder then
		d.Stats.BestRarityOrder = order
	end

	Registry.DataService:Replicate(player, "Inventory", "Index", "Stats")
	if isNew then
		Registry.ProgressionService:CheckCollections(player)
	end
	return isNew, newMut
end

-- Put a picked-up structure back in its stack (not a new discovery; Index untouched).
function InventoryService:ReturnItem(player: Player, itemId: string, mutationId: string?)
	local d = data(player)
	if not d or not Items.Get(itemId) then
		return
	end
	local key = InventoryService.StackKey(itemId, mutationId)
	local stack = d.Inventory[key]
	if not stack then
		stack = { Count = 0, Locked = false, Favorite = false }
		d.Inventory[key] = stack
	end
	stack.Count += 1
	Registry.DataService:Replicate(player, "Inventory")
end

function InventoryService:GetCount(player: Player, key: string): number
	local d = data(player)
	local stack = d and d.Inventory[key]
	return if stack then stack.Count else 0
end

function InventoryService:RemoveItem(player: Player, key: string, count: number): boolean
	local d = data(player)
	local stack = d and d.Inventory[key]
	if not stack or stack.Count < count or count <= 0 then
		return false
	end
	stack.Count -= count
	if stack.Count <= 0 and not stack.Locked and not stack.Favorite then
		d.Inventory[key] = nil
	end
	Registry.DataService:Replicate(player, "Inventory")
	return true
end

local function sellValue(def, mutationId)
	return ItemStats.SellValue(def, mutationId)
end

function InventoryService:Init()
	Net.Handle("SetItemFlag", function(player, key, flag, value)
		local def = InventoryService.ParseKey(key)
		if not def or (flag ~= "Locked" and flag ~= "Favorite") or not Validate.Bool(value) then
			return false, "Invalid request"
		end
		local d = data(player)
		local stack = d.Inventory[key]
		if not stack then
			return false, "You don't own that"
		end
		stack[flag] = value
		if stack.Count <= 0 and not stack.Locked and not stack.Favorite then
			d.Inventory[key] = nil
		end
		Registry.DataService:Replicate(player, "Inventory")
		return true, nil
	end)

	Net.Handle("SellItems", function(player, key, count)
		local def, mut = InventoryService.ParseKey(key)
		if not def or not Validate.Int(count, 1, 1e6) then
			return false, "Invalid request"
		end
		local d = data(player)
		local stack = d.Inventory[key]
		if not stack or stack.Count < count then
			return false, "You don't have that many"
		end
		if stack.Locked then
			return false, "That item is locked"
		end
		local coins = sellValue(def, mut) * count
		InventoryService:RemoveItem(player, key, count)
		Registry.EconomyService:AddCoins(player, coins)
		return true, { Coins = coins }
	end)

	-- Sell every unlocked, non-favourite stack at or below maxOrder rarity.
	-- Mutated stacks are only included when includeMutations is true.
	Net.Handle("MassSell", function(player, maxOrder, includeMutations)
		if not Registry.ProgressionService:IsUnlocked(player, "MassSell") then
			return false, "Mass sell is locked"
		end
		if not Validate.Int(maxOrder, 1, #Rarities.List) or not Validate.Bool(includeMutations) then
			return false, "Invalid request"
		end
		local d = data(player)
		local total, sold = 0, 0
		for key, stack in d.Inventory do
			local def, mut = InventoryService.ParseKey(key)
			if def and stack.Count > 0 and not stack.Locked and not stack.Favorite
				and Rarities.OrderOf(def.Rarity) <= maxOrder
				and (includeMutations or mut == Mutations.NormalId)
			then
				total += sellValue(def, mut) * stack.Count
				sold += stack.Count
				stack.Count = 0
				d.Inventory[key] = nil
			end
		end
		if sold == 0 then
			return false, "Nothing to sell"
		end
		Registry.DataService:Replicate(player, "Inventory")
		Registry.EconomyService:AddCoins(player, total)
		return true, { Sold = sold, Coins = total }
	end)
end

function InventoryService:Start() end

return InventoryService

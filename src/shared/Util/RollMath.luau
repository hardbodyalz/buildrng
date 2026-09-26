--[[
	RollMath
	Pure weighted-RNG maths. The server's RollService is the only caller that
	turns these into real rewards; the client only uses Odds() for display.

	Randomness is injected (`rng(): number` in [0, 1)) so the maths is testable
	and the server can use a Random object.
]]

local Config = script.Parent.Parent.Config
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)

local RollMath = {}

export type Pool = {
	Rarities: { any }, -- rarity defs that have at least one eligible item, ascending order
	Items: { [string]: { any } }, -- rarityId -> item defs
	ItemWeight: { [string]: number }, -- rarityId -> summed RollWeight
}

export type PityEntry = { Id: string, Rarity: string, SoftStart: number, SoftBoostPerRoll: number, Guarantee: number }

-- Build a roll pool from item defs. `filter(def) -> boolean` decides eligibility.
function RollMath.BuildPool(itemList: { any }, filter: ((any) -> boolean)?): Pool
	local items: { [string]: { any } } = {}
	local weights: { [string]: number } = {}
	for _, def in itemList do
		if def.Rollable and (filter == nil or filter(def)) then
			items[def.Rarity] = items[def.Rarity] or {}
			table.insert(items[def.Rarity], def)
			weights[def.Rarity] = (weights[def.Rarity] or 0) + def.RollWeight
		end
	end
	local rarities = {}
	for _, r in Rarities.List do
		if items[r.Id] then
			table.insert(rarities, r)
		end
	end
	return { Rarities = rarities, Items = items, ItemWeight = weights }
end

-- Pity modifiers from the current counters: boost[order] multipliers and a forced minimum order.
function RollMath.PityModifiers(pityConfig: { PityEntry }, pityState: { [string]: number }): ({ [number]: number }, number)
	local boostFromOrder: { [number]: number } = {}
	local minOrder = 0
	for _, entry in pityConfig do
		local count = pityState[entry.Id] or 0
		local order = Rarities.OrderOf(entry.Rarity)
		-- `count` is rolls already made without hitting the tier; this roll is count+1.
		if count + 1 >= entry.Guarantee then
			minOrder = math.max(minOrder, order)
		end
		if count > entry.SoftStart then
			local boost = 1 + (count - entry.SoftStart) * entry.SoftBoostPerRoll
			boostFromOrder[order] = (boostFromOrder[order] or 1) * boost
		end
	end
	return boostFromOrder, minOrder
end

-- Final weight per pool rarity (aligned with pool.Rarities).
function RollMath.Weights(pool: Pool, luck: number, pityConfig: { PityEntry }?, pityState: { [string]: number }?): { number }
	local boosts, minOrder = {}, 0
	if pityConfig and pityState then
		boosts, minOrder = RollMath.PityModifiers(pityConfig, pityState)
	end
	-- Only enforce a guarantee if something at/above it is actually rollable.
	local top = pool.Rarities[#pool.Rarities]
	if top and minOrder > top.Order then
		minOrder = top.Order
	end
	local weights = {}
	for i, r in pool.Rarities do
		local w = 0
		if r.Order >= minOrder then
			w = (1 / r.OneIn) * math.max(luck, 0.01) ^ r.LuckScaling
			for order, boost in boosts do
				if r.Order >= order then
					w *= boost
				end
			end
		end
		weights[i] = w
	end
	return weights
end

-- Display odds: { { Rarity = def, Chance = p } } in ascending rarity.
function RollMath.Odds(pool: Pool, luck: number, pityConfig: { PityEntry }?, pityState: { [string]: number }?): { any }
	local weights = RollMath.Weights(pool, luck, pityConfig, pityState)
	local total = 0
	for _, w in weights do
		total += w
	end
	local out = {}
	for i, r in pool.Rarities do
		table.insert(out, { Rarity = r, Chance = if total > 0 then weights[i] / total else 0 })
	end
	return out
end

local function pickWeighted(weights: { number }, rng: () -> number): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng() * total
	for i, w in weights do
		roll -= w
		if roll < 0 then
			return i
		end
	end
	-- Floating-point fallthrough: return the last non-zero weight.
	for i = #weights, 1, -1 do
		if weights[i] > 0 then
			return i
		end
	end
	return 1
end

function RollMath.PickRarity(pool: Pool, luck: number, pityConfig: { PityEntry }?, pityState: { [string]: number }?, rng: () -> number): any
	local weights = RollMath.Weights(pool, luck, pityConfig, pityState)
	return pool.Rarities[pickWeighted(weights, rng)]
end

function RollMath.PickItem(pool: Pool, rarityId: string, rng: () -> number): any
	local list = pool.Items[rarityId]
	local weights = {}
	for i, def in list do
		weights[i] = def.RollWeight
	end
	return list[pickWeighted(weights, rng)]
end

-- Rarest-first independent checks; first success wins. Returns mutation id.
function RollMath.PickMutation(luck: number, luckExponent: number, rng: () -> number, chanceMultiplier: number?): string
	local factor = math.max(luck, 1) ^ luckExponent * (chanceMultiplier or 1)
	for i = #Mutations.List, 1, -1 do
		local m = Mutations.List[i]
		if rng() < math.min(factor / m.OneIn, 1) then
			return m.Id
		end
	end
	return Mutations.NormalId
end

-- Advance pity counters after a roll of `resultOrder`. Counters for tiers the
-- result met or beat reset to 0; others increment.
function RollMath.UpdatePity(pityConfig: { PityEntry }, pityState: { [string]: number }, resultOrder: number)
	for _, entry in pityConfig do
		if resultOrder >= Rarities.OrderOf(entry.Rarity) then
			pityState[entry.Id] = 0
		else
			pityState[entry.Id] = (pityState[entry.Id] or 0) + 1
		end
	end
end

return RollMath

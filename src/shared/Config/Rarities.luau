--[[
	Rarities
	The rarity ladder. Order matters (index = Order). Everything that depends on
	rarity (odds, sell value, upgrade cost, reveal effects, announcements) reads
	from here.

	OneIn       conceptual base odds. Actual odds are the normalized weights of
	            every rarity that currently has rollable items (see RollMath).
	LuckScaling how strongly Luck affects this tier: weight * luck ^ LuckScaling.
	            0 = unaffected. Low tiers barely move, high tiers scale fully,
	            so luck shifts probability mass upward instead of multiplying
	            everything linearly.
	RevealTier  1..6, drives roll animation drama and sound escalation.
]]

export type Rarity = {
	Id: string,
	Name: string,
	Order: number,
	OneIn: number,
	Color: { number },
	LuckScaling: number,
	SellValue: number,
	UpgradeBaseCost: number,
	MaxLevel: number,
	RevealTier: number,
	AnnounceGlobally: boolean,
	Hidden: boolean,
}

local list: { any } = {
	{ Id = "Common", OneIn = 2, Color = { 196, 200, 206 }, LuckScaling = 0, SellValue = 4, UpgradeBaseCost = 35, MaxLevel = 10, RevealTier = 1 },
	{ Id = "Uncommon", OneIn = 5, Color = { 92, 214, 112 }, LuckScaling = 0.3, SellValue = 12, UpgradeBaseCost = 80, MaxLevel = 12, RevealTier = 1 },
	{ Id = "Rare", OneIn = 20, Color = { 64, 152, 255 }, LuckScaling = 0.6, SellValue = 45, UpgradeBaseCost = 180, MaxLevel = 15, RevealTier = 2 },
	{ Id = "Epic", OneIn = 100, Color = { 172, 92, 255 }, LuckScaling = 0.85, SellValue = 180, UpgradeBaseCost = 420, MaxLevel = 18, RevealTier = 3 },
	{ Id = "Legendary", OneIn = 500, Color = { 255, 186, 36 }, LuckScaling = 1, SellValue = 900, UpgradeBaseCost = 1000, MaxLevel = 20, RevealTier = 4 },
	{ Id = "Mythic", OneIn = 2500, Color = { 255, 64, 112 }, LuckScaling = 1, SellValue = 4500, UpgradeBaseCost = 2400, MaxLevel = 25, RevealTier = 5, AnnounceGlobally = true },
	{ Id = "Divine", OneIn = 10000, Color = { 255, 244, 160 }, LuckScaling = 1, SellValue = 20000, UpgradeBaseCost = 6000, MaxLevel = 30, RevealTier = 5, AnnounceGlobally = true },
	{ Id = "Celestial", OneIn = 50000, Color = { 110, 232, 255 }, LuckScaling = 1, SellValue = 90000, UpgradeBaseCost = 15000, MaxLevel = 35, RevealTier = 6, AnnounceGlobally = true },
	{ Id = "Eternal", OneIn = 200000, Color = { 64, 255, 196 }, LuckScaling = 0.95, SellValue = 400000, UpgradeBaseCost = 40000, MaxLevel = 40, RevealTier = 6, AnnounceGlobally = true },
	{ Id = "Transcendent", OneIn = 500000, Color = { 255, 120, 255 }, LuckScaling = 0.9, SellValue = 1500000, UpgradeBaseCost = 100000, MaxLevel = 45, RevealTier = 6, AnnounceGlobally = true },
	{ Id = "Secret", Name = "???", OneIn = 1000000, Color = { 24, 24, 28 }, LuckScaling = 0.5, SellValue = 5000000, UpgradeBaseCost = 250000, MaxLevel = 50, RevealTier = 6, AnnounceGlobally = true, Hidden = true },
}

local Rarities = {
	List = {} :: { Rarity },
	ById = {} :: { [string]: Rarity },
}

for order, raw in list do
	local r: Rarity = {
		Id = raw.Id,
		Name = raw.Name or raw.Id,
		Order = order,
		OneIn = raw.OneIn,
		Color = raw.Color,
		LuckScaling = raw.LuckScaling,
		SellValue = raw.SellValue,
		UpgradeBaseCost = raw.UpgradeBaseCost,
		MaxLevel = raw.MaxLevel,
		RevealTier = raw.RevealTier,
		AnnounceGlobally = raw.AnnounceGlobally == true,
		Hidden = raw.Hidden == true,
	}
	table.insert(Rarities.List, r)
	Rarities.ById[r.Id] = r
end

function Rarities.Get(id: string): Rarity
	local r = Rarities.ById[id]
	assert(r, "Unknown rarity " .. tostring(id))
	return r
end

function Rarities.OrderOf(id: string): number
	local r = Rarities.ById[id]
	return if r then r.Order else 0
end

return Rarities

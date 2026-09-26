--[[
	Luck
	Combines luck sources and applies diminishing returns.

	raw = Base (permanent upgrade track) * (1 + sum of additive bonuses) * temporary multipliers
	effective = raw                                   if raw <= SoftCap
	          = SoftCap * (raw / SoftCap) ^ Exponent  otherwise   (capped at HardCap)

	Effective luck then feeds RollMath, where each rarity only responds with
	luck ^ LuckScaling - a second layer that keeps luck from being a flat
	multiplier on everything.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Luck = {}

export type Sources = {
	Base: number,
	Additive: { number }?,
	Multipliers: { number }?,
}

function Luck.Diminish(raw: number): number
	local cfg = GameConfig.Luck
	if raw <= cfg.SoftCap then
		return math.max(raw, 0)
	end
	return math.min(cfg.SoftCap * (raw / cfg.SoftCap) ^ cfg.SoftCapExponent, cfg.HardCap)
end

function Luck.Raw(sources: Sources): number
	local add = 0
	local additive: { number } = sources.Additive or {}
	for _, v in additive do
		add += v
	end
	local mult = 1
	local multipliers: { number } = sources.Multipliers or {}
	for _, v in multipliers do
		mult *= v
	end
	return sources.Base * (1 + add) * mult
end

function Luck.Compute(sources: Sources): number
	return Luck.Diminish(Luck.Raw(sources))
end

return Luck

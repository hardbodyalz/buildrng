--[[
	Mutations
	A second, independent RNG layer rolled on top of every item roll. A mutation
	multiplies an item's combat stats / sell value and changes its look, so a
	Common Scrap Turret can still be a chase ("Galaxy Scrap Turret").

	"Normal" is implicit (Id = "Normal") and never stored in this list's rolls.
	Rolls check rarest-first; the first success wins.

	Visual keys (read by ModelBuilder):
	  Color     override for every "Primary" coloured part
	  Accent    override for "Accent" parts
	  Material  override material for Primary parts
	  Glow      adds a PointLight of this colour
	  Particles name of a particle preset (see ModelBuilder.ParticlePresets)
]]

export type Mutation = {
	Id: string,
	Name: string,
	Order: number,
	OneIn: number,
	StatMultiplier: number,
	ValueMultiplier: number,
	Color: { number }?,
	Accent: { number }?,
	Material: string?,
	Glow: { number }?,
	Particles: string?,
	Hidden: boolean,
}

local list: { any } = {
	{ Id = "Golden", OneIn = 40, StatMultiplier = 1.5, ValueMultiplier = 3, Color = { 255, 200, 50 }, Accent = { 255, 235, 140 }, Material = "Metal", Particles = "Sparkle" },
	{ Id = "Shiny", OneIn = 150, StatMultiplier = 2, ValueMultiplier = 6, Accent = { 200, 255, 255 }, Material = "Glass", Glow = { 180, 240, 255 }, Particles = "Shine" },
	{ Id = "Corrupted", OneIn = 600, StatMultiplier = 3, ValueMultiplier = 15, Color = { 70, 20, 60 }, Accent = { 255, 40, 80 }, Material = "Slate", Glow = { 255, 40, 80 }, Particles = "Corrupt" },
	{ Id = "Galaxy", OneIn = 2500, StatMultiplier = 5, ValueMultiplier = 50, Color = { 40, 30, 110 }, Accent = { 160, 120, 255 }, Material = "Neon", Glow = { 140, 100, 255 }, Particles = "Stars" },
	{ Id = "Glitched", OneIn = 10000, StatMultiplier = 8, ValueMultiplier = 200, Color = { 10, 255, 120 }, Accent = { 255, 0, 200 }, Material = "ForceField", Glow = { 0, 255, 150 }, Particles = "Glitch" },
	{ Id = "Void", OneIn = 50000, StatMultiplier = 15, ValueMultiplier = 1000, Color = { 5, 5, 10 }, Accent = { 90, 0, 160 }, Material = "Neon", Glow = { 90, 0, 160 }, Particles = "Void", Hidden = true },
}

local Mutations = {
	NormalId = "Normal",
	List = {} :: { Mutation }, -- common -> rare
	ById = {} :: { [string]: Mutation },
}

local normal: Mutation = {
	Id = "Normal",
	Name = "Normal",
	Order = 0,
	OneIn = 1,
	StatMultiplier = 1,
	ValueMultiplier = 1,
	Hidden = false,
}
Mutations.ById.Normal = normal

for order, raw in list do
	local m: Mutation = {
		Id = raw.Id,
		Name = raw.Name or raw.Id,
		Order = order,
		OneIn = raw.OneIn,
		StatMultiplier = raw.StatMultiplier,
		ValueMultiplier = raw.ValueMultiplier,
		Color = raw.Color,
		Accent = raw.Accent,
		Material = raw.Material,
		Glow = raw.Glow,
		Particles = raw.Particles,
		Hidden = raw.Hidden == true,
	}
	table.insert(Mutations.List, m)
	Mutations.ById[m.Id] = m
end

function Mutations.Get(id: string?): Mutation
	return Mutations.ById[id or "Normal"] or normal
end

function Mutations.IsValid(id: any): boolean
	return type(id) == "string" and Mutations.ById[id] ~= nil
end

return Mutations

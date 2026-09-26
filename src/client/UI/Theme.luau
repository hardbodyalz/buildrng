--[[
	Theme
	Colours and fonts for the whole UI.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)

local Theme = {
	Bg = Color3.fromRGB(16, 18, 26),
	Panel = Color3.fromRGB(26, 29, 40),
	PanelLight = Color3.fromRGB(40, 44, 60),
	PanelLighter = Color3.fromRGB(56, 61, 80),
	Stroke = Color3.fromRGB(70, 76, 100),
	Text = Color3.fromRGB(245, 246, 250),
	TextDim = Color3.fromRGB(165, 172, 190),
	Accent = Color3.fromRGB(255, 196, 40),
	Accent2 = Color3.fromRGB(80, 200, 255),
	Good = Color3.fromRGB(80, 214, 120),
	Bad = Color3.fromRGB(255, 84, 84),
	Warn = Color3.fromRGB(255, 200, 60),
	Coins = Color3.fromRGB(255, 208, 64),
	Dice = Color3.fromRGB(120, 220, 255),
	Xp = Color3.fromRGB(150, 110, 255),

	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontBlack = Enum.Font.GothamBlack,
}

function Theme.Rarity(id: string): Color3
	local r = Rarities.ById[id]
	if not r then
		return Theme.TextDim
	end
	return Color3.fromRGB(r.Color[1], r.Color[2], r.Color[3])
end

function Theme.Mutation(id: string?): Color3
	local m = Mutations.Get(id)
	local c = m.Accent or m.Color
	if not c then
		return Theme.Text
	end
	return Color3.fromRGB(c[1], c[2], c[3])
end

return Theme

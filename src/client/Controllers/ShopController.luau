--[[
	ShopController
	Permanent upgrades (Luck, Roll Speed, Core Plating) and base expansion.
	All numbers come from the server's Derived state.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Progression = require(Shared.Config.Progression)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local ShopController = {}

local list: ScrollingFrame

local upgradeDefs = {}
for _, u in Progression.Upgrades do
	upgradeDefs[u.Id] = u
end

local function fmt(u, v)
	if v == nil then
		return "MAX"
	end
	return string.format(u.Format, v)
end

local function row(order: number, title: string, desc: string, valueText: string, buttonText: string, affordable: boolean, enabled: boolean, onBuy: () -> ())
	local frame = UI.new("Frame", {
		Size = UDim2.new(1, -10, 0, 82),
		BackgroundColor3 = Theme.PanelLight,
		LayoutOrder = order,
		Parent = list,
	}, { UI.Corner(10), UI.Padding(10) })
	UI.Label({ Text = title, Size = UDim2.new(0.62, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.FontBlack, MaxTextSize = 20, Parent = frame })
	UI.Label({ Text = desc, Size = UDim2.new(0.62, 0, 0, 18), Position = UDim2.fromOffset(0, 26), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, TextColor3 = Theme.TextDim, MaxTextSize = 14, Parent = frame })
	UI.Label({ Text = valueText, Size = UDim2.new(0.62, 0, 0, 18), Position = UDim2.fromOffset(0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Accent, MaxTextSize = 16, Parent = frame })
	UI.Button({
		Text = buttonText,
		Size = UDim2.new(0.36, 0, 1, 0),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Color = if not enabled then Theme.PanelLighter elseif affordable then Theme.Good else Theme.Bad:Lerp(Theme.Panel, 0.4),
		MaxTextSize = 18,
		Parent = frame,
		OnClick = function()
			if enabled then
				onBuy()
			end
		end,
	})
end

local function refresh()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local d = State.Derived()
	local coins = State.Get("Coins") or 0
	for i, u in d.Upgrades or {} do
		local def = upgradeDefs[u.Id]
		local maxed = u.Cost == nil
		row(
			i,
			string.format("%s  (Lv %d)", def.Name, u.Level),
			def.Description,
			fmt(def, u.Value) .. (if maxed then "" else "  ->  " .. fmt(def, u.Next)),
			if maxed then "MAX" else Format.Abbrev(u.Cost),
			not maxed and coins >= u.Cost,
			not maxed,
			function()
				local ok, res = Net.Invoke("BuyUpgrade", u.Id)
				if ok then
					Registry.SoundController.Play("Upgrade")
					Registry.NotifyController.Toast(def.Name .. " upgraded!", "Reward")
				else
					Registry.NotifyController.Error(res)
				end
			end
		)
	end
	local nextExp = d.NextExpansion
	if nextExp then
		local unlocked = State.IsUnlocked("Expansion")
		local levelOk = (State.Get("Level") or 1) >= nextExp.Level
		local req = if not unlocked then (d.UnlockRequirements and d.UnlockRequirements.Expansion or "Locked")
			elseif not levelOk then "Requires level " .. nextExp.Level
			else string.format("%dx%d tiles, %d structures", nextExp.Width, nextExp.Length, nextExp.Capacity)
		row(
			50,
			"EXPAND: " .. string.upper(nextExp.Name),
			string.format("Current: %s (%d structures)", d.TierName or "", d.Capacity or 0),
			req,
			Format.Abbrev(nextExp.Cost),
			unlocked and levelOk and coins >= nextExp.Cost,
			unlocked and levelOk,
			function()
				local ok, res = Net.Invoke("BuyExpansion")
				if ok then
					Registry.SoundController.Play("Upgrade")
				else
					Registry.NotifyController.Error(res)
				end
			end
		)
	else
		row(50, "CITADEL", "Your base is fully expanded.", "", "MAX", false, false, function() end)
	end
end

function ShopController.Init()
	local frame, content = UI.Window({
		Name = "ShopWindow",
		Title = "SHOP - UPGRADES",
		Size = UDim2.fromScale(0.48, 0.66),
		MaxSize = Vector2.new(640, 560),
		Parent = Registry.HudController.Root(),
		OnClose = function()
			Registry.HudController.Close()
		end,
	})
	list = UI.Scroll({ Size = UDim2.fromScale(1, 1), Parent = content })
	UI.List(Enum.FillDirection.Vertical, 8).Parent = list
	Registry.HudController.RegisterWindow("Shop", frame, refresh)
	State.Watch({ "Derived", "Coins", "Level", "Upgrades", "Base" }, function()
		if Registry.HudController.IsOpen("Shop") then
			refresh()
		end
	end)
end

return ShopController

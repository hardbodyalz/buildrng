--[[
	NotifyController
	Toasts (small, stacking), banners (big centre text for waves / bosses /
	rare pulls) and server-wide announcements.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local NotifyController = {}

local toastHolder: Frame
local bannerHolder: Frame

local KIND_COLORS = {
	Info = Theme.PanelLight,
	Error = Color3.fromRGB(150, 40, 40),
	Reward = Color3.fromRGB(150, 110, 20),
	Level = Color3.fromRGB(90, 60, 170),
	Unlock = Color3.fromRGB(30, 120, 80),
	Collection = Color3.fromRGB(30, 100, 150),
}

function NotifyController.Toast(text: string, kind: string?)
	if not toastHolder then
		return
	end
	local toast = UI.Panel({
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = KIND_COLORS[kind or "Info"] or Theme.PanelLight,
		BackgroundTransparency = 0.05,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = toastHolder,
	})
	UI.Label({
		Text = text,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		MaxTextSize = 18,
		Parent = toast,
	})
	local scale = UI.new("UIScale", { Scale = 0.6, Parent = toast })
	UI.Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		UI.Tween(toast, 0.3, { BackgroundTransparency = 1 })
		for _, d in toast:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.Tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				UI.Tween(d, 0.3, { Transparency = 1 })
			end
		end
		task.wait(0.32)
		toast:Destroy()
	end)
	-- Cap stack size.
	local toasts = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	if #toasts > 5 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
end

function NotifyController.Error(text: string)
	NotifyController.Toast(text, "Error")
	Registry.SoundController.Play("Invalid")
end

-- Big centre banner. subtitle optional.
function NotifyController.Banner(title: string, color: Color3?, subtitle: string?, duration: number?)
	if not bannerHolder then
		return
	end
	bannerHolder:ClearAllChildren()
	local frame = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = bannerHolder,
	})
	local titleLabel = UI.Label({
		Text = title,
		Size = UDim2.fromScale(1, 0.62),
		Font = Theme.FontBlack,
		TextColor3 = color or Theme.Text,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		MaxTextSize = 64,
		Parent = frame,
	})
	if subtitle then
		UI.Label({
			Text = subtitle,
			Size = UDim2.fromScale(1, 0.34),
			Position = UDim2.fromScale(0, 0.64),
			TextColor3 = Theme.Text,
			TextStrokeTransparency = 0.2,
			MaxTextSize = 28,
			Parent = frame,
		})
	end
	local scale = UI.new("UIScale", { Scale = 1.6, Parent = frame })
	UI.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(duration or 2.2, function()
		if frame.Parent then
			for _, d in frame:GetDescendants() do
				if d:IsA("TextLabel") then
					UI.Tween(d, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
				end
			end
			task.wait(0.45)
			frame:Destroy()
		end
	end)
	return titleLabel
end

function NotifyController.Init(root: ScreenGui)
	toastHolder = UI.new("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0.34, 0, 0.3, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = root,
	}, { UI.List(Enum.FillDirection.Vertical, 6) })
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(460, 400), MinSize = Vector2.new(260, 0), Parent = toastHolder })

	bannerHolder = UI.new("Frame", {
		Name = "Banner",
		Size = UDim2.new(0.8, 0, 0, 120),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = root,
	})

	Net.On("Notify", function(payload)
		if type(payload) == "table" then
			NotifyController.Toast(tostring(payload.Text), payload.Kind)
			if payload.Kind == "Level" or payload.Kind == "Unlock" or payload.Kind == "Collection" then
				Registry.SoundController.Play("Upgrade")
			end
		end
	end)

	Net.On("Announce", function(payload)
		if type(payload) ~= "table" then
			return
		end
		local r = Rarities.ById[payload.Rarity]
		local rarityName = if r then r.Name else tostring(payload.Rarity)
		NotifyController.Banner(
			string.upper(rarityName) .. "!",
			Theme.Rarity(payload.Rarity),
			string.format("%s rolled %s", tostring(payload.Player), tostring(payload.Item)),
			3.5
		)
		Registry.SoundController.PlayReveal(r and r.RevealTier or 5)
	end)
end

return NotifyController

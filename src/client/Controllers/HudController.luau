--[[
	HudController
	Owns the root ScreenGui, responsive scaling, the always-on HUD (currencies,
	level, side buttons) and a simple window manager (one window at a time).

	Layout (spec §36):
	  TOP     Coins / Dice / Level
	  LEFT    Quests, Index, Inventory
	  RIGHT   Build (Base), World, Shop
	  BOTTOM  ROLL (RollController)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local player = Players.LocalPlayer

local HudController = {}
HudController.WindowOpened = Signal.new() -- (name)
HudController.WindowClosed = Signal.new() -- (name)
HudController.Buttons = {} :: { [string]: TextButton }

local root: ScreenGui
local hud: Frame
local windows: { [string]: { Frame: Frame, OnOpen: (() -> ())?, OnClose: (() -> ())? } } = {}
local openWindow: string? = nil

function HudController.Root(): ScreenGui
	return root
end

function HudController.Hud(): Frame
	return hud
end

-- Windows ------------------------------------------------------------------------

function HudController.RegisterWindow(name: string, frame: Frame, onOpen: (() -> ())?, onClose: (() -> ())?)
	windows[name] = { Frame = frame, OnOpen = onOpen, OnClose = onClose }
end

function HudController.IsOpen(name: string): boolean
	return openWindow == name
end

function HudController.Close()
	if not openWindow then
		return
	end
	local w = windows[openWindow]
	local name = openWindow
	openWindow = nil
	if w then
		w.Frame.Visible = false
		if w.OnClose then
			w.OnClose()
		end
	end
	HudController.WindowClosed:Fire(name)
end

function HudController.Open(name: string)
	if openWindow == name then
		return
	end
	HudController.Close()
	local w = windows[name]
	if not w then
		return
	end
	if Registry.BuildController and Registry.BuildController.IsActive() then
		Registry.BuildController.Exit()
	end
	openWindow = name
	if w.OnOpen then
		w.OnOpen()
	end
	w.Frame.Visible = true
	local scale = w.Frame:FindFirstChild("OpenScale") :: UIScale?
	if not scale then
		scale = UI.new("UIScale", { Name = "OpenScale", Parent = w.Frame })
	end
	(scale :: UIScale).Scale = 0.85
	UI.Tween(scale :: UIScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	HudController.WindowOpened:Fire(name)
end

function HudController.Toggle(name: string)
	if openWindow == name then
		HudController.Close()
	else
		HudController.Open(name)
	end
end

-- HUD visibility (build mode hides the roll area etc.)
function HudController.SetMode(mode: string)
	local rollArea = hud:FindFirstChild("RollArea")
	if rollArea then
		(rollArea :: Frame).Visible = mode ~= "Build"
	end
end

-- Construction -------------------------------------------------------------------

local function currencyPill(name: string, color: Color3, order: number): (Frame, TextLabel)
	local pill = UI.Panel({
		Name = name,
		Size = UDim2.fromOffset(150, 40),
		LayoutOrder = order,
		BackgroundColor3 = Theme.Panel,
	})
	UI.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(9, 8),
		BackgroundColor3 = color,
		Rotation = if name == "Dice" then 12 else 0,
		Parent = pill,
	}, { UI.Corner(if name == "Coins" then 12 else 5), UI.Stroke(color:Lerp(Color3.new(0, 0, 0), 0.4), 2) })
	local label = UI.Label({
		Name = "Value",
		Text = "0",
		Size = UDim2.new(1, -46, 1, -10),
		Position = UDim2.fromOffset(40, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.FontBlack,
		TextColor3 = color,
		MaxTextSize = 24,
		Parent = pill,
	})
	return pill, label
end

local function sideButton(parent: Frame, key: string, text: string, color: Color3, order: number, onClick: () -> ())
	local btn = UI.Button({
		Name = key,
		Text = text,
		Size = UDim2.fromOffset(112, 50),
		Color = color,
		LayoutOrder = order,
		Parent = parent,
		MaxTextSize = 20,
		OnClick = onClick,
	})
	local lock = UI.Label({
		Name = "Lock",
		Text = "LOCKED",
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -2),
		AnchorPoint = Vector2.new(0, 1),
		TextColor3 = Theme.Warn,
		Font = Theme.FontBlack,
		MaxTextSize = 11,
		Visible = false,
		ZIndex = 3,
		Parent = btn,
	})
	lock.TextStrokeTransparency = 0.2
	HudController.Buttons[key] = btn
	return btn
end

-- A feature button that shows its unlock requirement until available.
local function gated(feature: string?, fn: () -> ()): () -> ()
	return function()
		if feature and not State.IsUnlocked(feature) then
			local req = State.Derived().UnlockRequirements
			Registry.NotifyController.Error("Locked - " .. ((req and req[feature]) or "keep playing"))
			return
		end
		fn()
	end
end

local function refreshLocks()
	local map = { Index = "Index", Shop = "Upgrades" }
	for key, feature in map do
		local btn = HudController.Buttons[key]
		if btn then
			local locked = not State.IsUnlocked(feature)
			local lock = btn:FindFirstChild("Lock") :: TextLabel
			lock.Visible = locked
			btn.TextTransparency = if locked then 0.45 else 0
		end
	end
end

function HudController.Init()
	root = UI.new("ScreenGui", {
		Name = "BuildDefendRNG",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local uiScale = UI.new("UIScale", { Parent = root })
	local function rescale()
		local vp = Workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.55, 1.25)
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	hud = UI.new("Frame", {
		Name = "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- Top bar
	local top = UI.new("Frame", {
		Name = "TopBar",
		Size = UDim2.fromOffset(560, 44),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = hud,
	}, { UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	local coinsPill, coinsLabel = currencyPill("Coins", Theme.Coins, 1)
	local dicePill, diceLabel = currencyPill("Dice", Theme.Dice, 2)
	coinsPill.Parent = top
	dicePill.Parent = top
	local levelPill = UI.Panel({ Name = "Level", Size = UDim2.fromOffset(190, 40), LayoutOrder = 3, Parent = top })
	local levelText = UI.Label({
		Text = "Lv 1",
		Size = UDim2.new(0, 56, 1, -10),
		Position = UDim2.fromOffset(8, 5),
		TextColor3 = Theme.Xp,
		Font = Theme.FontBlack,
		MaxTextSize = 22,
		Parent = levelPill,
	})
	local _, xpFill, xpLabel = UI.Bar({
		Size = UDim2.new(1, -76, 0, 18),
		Position = UDim2.new(0, 68, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Theme.Xp,
		MaxTextSize = 12,
		Parent = levelPill,
	})

	local lastCoins = 0
	State.Watch({ "Coins", "Dice", "Xp", "Level", "Derived" }, function()
		local coins = State.Get("Coins") or 0
		coinsLabel.Text = Format.Abbrev(coins)
		if coins > lastCoins and lastCoins > 0 then
			local s = coinsPill:FindFirstChild("Pop") :: UIScale?
			if not s then
				s = UI.new("UIScale", { Name = "Pop", Parent = coinsPill })
			end
			(s :: UIScale).Scale = 1.08
			UI.Tween(s :: UIScale, 0.2, { Scale = 1 })
		end
		lastCoins = coins
		local dice = State.Get("Dice") or 0
		diceLabel.Text = Format.Abbrev(dice)
		dicePill.Visible = dice > 0 or State.IsUnlocked("LuckyRoll")
		levelText.Text = "Lv " .. tostring(State.Get("Level") or 1)
		local need = State.Derived().XpToNext or 1
		local xp = State.Get("Xp") or 0
		UI.SetBar(xpFill, xp / need, true)
		xpLabel.Text = string.format("%s / %s XP", Format.Abbrev(xp), Format.Abbrev(need))
	end)

	-- Left column: Quests / Index / Inventory
	local left = UI.new("Frame", {
		Name = "LeftColumn",
		Size = UDim2.fromOffset(112, 180),
		Position = UDim2.new(0, 12, 0.5, 20),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = hud,
	}, { UI.List(Enum.FillDirection.Vertical, 10) })
	sideButton(left, "Quests", "QUESTS", Color3.fromRGB(90, 90, 110), 1, function()
		Registry.NotifyController.Toast("Quests arrive in a future update!", "Info")
	end)
	sideButton(left, "Index", "INDEX", Color3.fromRGB(60, 130, 200), 2, gated("Index", function()
		HudController.Toggle("Index")
	end))
	sideButton(left, "Inventory", "INVENTORY", Color3.fromRGB(150, 90, 220), 3, function()
		HudController.Toggle("Inventory")
	end)

	-- Right column: Build / World / Shop
	local right = UI.new("Frame", {
		Name = "RightColumn",
		Size = UDim2.fromOffset(112, 180),
		Position = UDim2.new(1, -12, 0.5, 20),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = hud,
	}, { UI.List(Enum.FillDirection.Vertical, 10) })
	sideButton(right, "Build", "BUILD", Color3.fromRGB(60, 170, 90), 1, function()
		HudController.Close()
		Registry.BuildController.Toggle()
	end)
	sideButton(right, "World", "WORLD", Color3.fromRGB(90, 90, 110), 2, function()
		Registry.NotifyController.Toast("New worlds arrive in a future update!", "Info")
	end)
	sideButton(right, "Shop", "SHOP", Color3.fromRGB(210, 140, 30), 3, gated("Upgrades", function()
		HudController.Toggle("Shop")
	end))

	State.Watch({ "Derived" }, refreshLocks)
end

return HudController

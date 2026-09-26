--[[
	RollController
	The ROLL button, auto-roll, Lucky Rolls, the odds window and the reveal
	animation. The server decides the result; this only builds anticipation:
	cards cycle and slow down, tension builds for rare tiers, then the reveal
	escalates with rarity (colour -> sound layers -> flash -> shake -> banner).
	Commons stay quick and quiet so rolling never gets obnoxious.
]]

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local RollController = {}
RollController.RollShown = Signal.new() -- (result)

local rolling = false
local nextReady = 0
local auto = false
local cardHideToken = 0

local rollButton: TextButton
local cooldownShade: Frame
local autoButton: TextButton
local luckyButton: TextButton
local infoLabel: TextLabel
local card: Frame
local cardTitle: TextLabel
local cardRarity: TextLabel
local cardMutation: TextLabel
local cardNew: TextLabel
local cardViewportHolder: Frame
local cardPlace: TextButton
local cardStroke: UIStroke
local flash: Frame
local lastResult: any = nil

local itemsByRarity: { [string]: { any } } = {}
for _, def in Items.List do
	if def.Rollable and not def.Hidden then
		itemsByRarity[def.Rarity] = itemsByRarity[def.Rarity] or {}
		table.insert(itemsByRarity[def.Rarity], def)
	end
end

local function cooldown(): number
	return State.Derived().RollCooldown or 1.6
end

-- Random filler card for the spin, weighted by the player's current odds.
local function fillerItem(): any
	local odds = State.Derived().Odds or {}
	local roll = math.random()
	local chosen = "Common"
	for _, o in odds do
		roll -= o.Chance
		if roll <= 0 then
			chosen = o.Rarity
			break
		end
	end
	-- Spice: occasionally flash something rarer so the reel feels alive.
	if math.random() < 0.18 then
		local rare = { "Rare", "Epic", "Legendary", "Mythic" }
		chosen = rare[math.random(1, #rare)]
	end
	local list = itemsByRarity[chosen] or itemsByRarity.Common
	return list[math.random(1, #list)]
end

local function setCard(def: any, mutation: string?, final: boolean)
	local color = Theme.Rarity(def.Rarity)
	local rarity = Rarities.Get(def.Rarity)
	cardTitle.Text = if final or not def.Hidden then def.DisplayName else "???"
	cardRarity.Text = string.upper(rarity.Name)
	cardRarity.TextColor3 = color
	cardStroke.Color = color
	card.BackgroundColor3 = Theme.Panel:Lerp(color, 0.18)
	if final and mutation and mutation ~= Mutations.NormalId then
		cardMutation.Visible = true
		cardMutation.Text = string.upper(mutation)
		cardMutation.TextColor3 = Theme.Mutation(mutation)
	else
		cardMutation.Visible = false
	end
end

local function shake(intensity: number, duration: number)
	if Registry.FxController then
		Registry.FxController.Shake(intensity, duration)
	end
end

local function fovPunch(amount: number)
	local cam = Workspace.CurrentCamera
	local base = cam.FieldOfView
	UI.Tween(cam, 0.12, { FieldOfView = base - amount })
	task.delay(0.35, function()
		UI.Tween(cam, 0.4, { FieldOfView = base })
	end)
end

local function animate(result: any)
	local def = Items.Get(result.ItemId)
	if not def then
		return
	end
	local rarity = Rarities.Get(result.Rarity)
	local tier = rarity.RevealTier
	cardHideToken += 1
	card.Visible = true
	cardNew.Visible = false
	cardPlace.Visible = false
	cardViewportHolder:ClearAllChildren()

	-- Spin: fixed-ish length so duration doesn't leak the rarity.
	local spinTime = math.clamp(cooldown() * 0.55, 0.45, 0.9)
	local elapsed, step = 0, 0.035
	local pitch = 0.9
	while elapsed < spinTime do
		setCard(fillerItem(), nil, false)
		Registry.SoundController.Play("RollTick", { Pitch = pitch, Throttle = 0 })
		task.wait(step)
		elapsed += step
		step = math.min(step * 1.18, 0.14)
		pitch += 0.04
	end

	-- Tension for Epic+: hold on a dark card that pulses in the result colour.
	if tier >= 3 then
		cardTitle.Text = "..."
		cardRarity.Text = ""
		card.BackgroundColor3 = Theme.Bg
		local color = Theme.Rarity(result.Rarity)
		for i = 1, tier - 1 do
			cardStroke.Color = color
			UI.Tween(cardStroke, 0.12, { Thickness = 6 })
			Registry.SoundController.Play("RollTick", { Pitch = 0.6 + i * 0.1, Throttle = 0, Volume = 2 })
			task.wait(0.14)
			UI.Tween(cardStroke, 0.12, { Thickness = 3 })
			task.wait(0.06)
		end
	end

	-- Reveal
	setCard(def, result.Mutation, true)
	local vp = UI.ItemViewport(def, result.Mutation)
	vp.Parent = cardViewportHolder
	local scale = card:FindFirstChild("RevealScale") :: UIScale
	scale.Scale = 1.25
	UI.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Registry.SoundController.PlayReveal(tier)
	cardNew.Visible = result.IsNew or result.IsNewMutation
	cardNew.Text = if result.IsNew then "NEW!" else "NEW MUTATION!"
	cardPlace.Visible = true

	if tier >= 4 then
		flash.BackgroundColor3 = Theme.Rarity(result.Rarity)
		flash.BackgroundTransparency = 0.35
		UI.Tween(flash, 0.6, { BackgroundTransparency = 1 })
		fovPunch(6 + tier)
	end
	if tier >= 5 then
		shake(0.6 + (tier - 5) * 0.4, 0.6)
		Registry.NotifyController.Banner(string.upper(rarity.Name) .. "!", Theme.Rarity(result.Rarity), def.DisplayName, 2.5)
	end
	if result.Mutation ~= Mutations.NormalId then
		Registry.NotifyController.Toast(string.format("%s mutation! (%s stats)", result.Mutation, "x" .. Mutations.Get(result.Mutation).StatMultiplier), "Reward")
	end

	local token = cardHideToken
	task.delay(if tier >= 4 then 4 else 2.4, function()
		if token == cardHideToken and not rolling then
			card.Visible = false
		end
	end)
end

function RollController.Roll(lucky: boolean?)
	if rolling or os.clock() < nextReady then
		return false
	end
	rolling = true
	local requested = os.clock()
	local ok, result = Net.Invoke("Roll", lucky == true)
	if not ok then
		rolling = false
		Registry.NotifyController.Error(tostring(result))
		return false
	end
	nextReady = requested + cooldown()
	lastResult = result
	animate(result)
	rolling = false
	RollController.RollShown:Fire(result)
	if auto and Rarities.OrderOf(result.Rarity) >= GameConfig.Roll.AutoRollStopOrder then
		RollController.SetAuto(false)
		Registry.NotifyController.Toast("Auto-roll paused - you pulled something good!", "Reward")
	end
	return true
end

function RollController.SetAuto(on: boolean)
	auto = on
	autoButton.Text = if on then "AUTO: ON" else "AUTO: OFF"
	UI.SetButtonColor(autoButton, if on then Theme.Good else Theme.PanelLight)
end

function RollController.Button(): TextButton
	return rollButton
end

local function refreshInfo()
	local d = State.Derived()
	local luck = d.Luck or 1
	local text = string.format("Luck x%.2f", luck)
	if d.Pity then
		-- Show the pity counter that is closest to triggering (as a fraction).
		local best, bestFrac = nil, -1
		for _, p in d.Pity do
			local frac = p.Count / p.Guarantee
			if frac > bestFrac then
				best, bestFrac = p, frac
			end
		end
		if best then
			text ..= string.format("   |   %s pity %d/%d", Rarities.Get(best.Rarity).Name, best.Count, best.Guarantee)
		end
	end
	infoLabel.Text = text
	luckyButton.Visible = State.IsUnlocked("LuckyRoll")
	luckyButton.Text = string.format("LUCKY x%d\n%d Dice", GameConfig.Roll.LuckyRollMultiplier, GameConfig.Roll.DiceCostLuckyRoll)
end

-- Odds window -------------------------------------------------------------------

local function buildOddsWindow(root: ScreenGui)
	local frame, content = UI.Window({
		Name = "OddsWindow",
		Title = "ROLL ODDS",
		Size = UDim2.fromScale(0.36, 0.62),
		MaxSize = Vector2.new(460, 560),
		Parent = root,
		OnClose = function()
			Registry.HudController.Close()
		end,
	})
	local list = UI.Scroll({ Size = UDim2.fromScale(1, 1), Parent = content })
	UI.List(Enum.FillDirection.Vertical, 4).Parent = list
	local function refresh()
		for _, c in list:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local d = State.Derived()
		local header = UI.new("Frame", { Size = UDim2.new(1, -8, 0, 28), BackgroundTransparency = 1, LayoutOrder = 0, Parent = list })
		UI.Label({
			Text = string.format("Luck x%.2f (Lucky Roll x%.2f)", d.Luck or 1, d.LuckyRollLuck or 1),
			TextColor3 = Theme.Accent,
			MaxTextSize = 18,
			Parent = header,
		})
		for i, o in d.Odds or {} do
			local row = UI.new("Frame", {
				Size = UDim2.new(1, -8, 0, 30),
				BackgroundColor3 = Theme.PanelLight,
				LayoutOrder = i,
				Parent = list,
			}, { UI.Corner(6) })
			UI.Label({
				Text = Rarities.Get(o.Rarity).Name,
				Size = UDim2.new(0.5, -8, 1, -6),
				Position = UDim2.fromOffset(8, 3),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.Rarity(o.Rarity),
				MaxTextSize = 18,
				Parent = row,
			})
			UI.Label({
				Text = string.format("%s  (%.3f%%)", Format.OneIn(o.Chance), o.Chance * 100),
				Size = UDim2.new(0.5, -8, 1, -6),
				Position = UDim2.new(0.5, 0, 0, 3),
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Theme.Font,
				MaxTextSize = 16,
				Parent = row,
			})
		end
		local order = 100
		for _, p in d.Pity or {} do
			order += 1
			local row = UI.new("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundTransparency = 1, LayoutOrder = order, Parent = list })
			UI.Label({
				Text = string.format("Guaranteed %s+ in %d rolls", Rarities.Get(p.Rarity).Name, math.max(0, p.Guarantee - p.Count)),
				Size = UDim2.new(1, 0, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.Font,
				MaxTextSize = 15,
				Parent = row,
			})
			local _, fill = UI.Bar({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 24), Color = Theme.Rarity(p.Rarity), Parent = row })
			UI.SetBar(fill, p.Count / p.Guarantee)
		end
	end
	Registry.HudController.RegisterWindow("Odds", frame, refresh)
	State.Watch({ "Derived" }, function()
		if Registry.HudController.IsOpen("Odds") then
			refresh()
		end
	end)
end

-- Construction ----------------------------------------------------------------------

function RollController.Init()
	local hud = Registry.HudController.Hud()
	local root = Registry.HudController.Root()

	local area = UI.new("Frame", {
		Name = "RollArea",
		Size = UDim2.fromOffset(560, 150),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = hud,
	})

	infoLabel = UI.Label({
		Name = "Info",
		Size = UDim2.new(1, -60, 0, 24),
		Position = UDim2.fromOffset(0, 0),
		TextColor3 = Theme.Accent,
		TextStrokeTransparency = 0.3,
		MaxTextSize = 18,
		Parent = area,
	})
	UI.Button({
		Name = "OddsButton",
		Text = "ODDS",
		Size = UDim2.fromOffset(56, 26),
		Position = UDim2.new(1, 0, 0, -1),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.PanelLight,
		MaxTextSize = 14,
		Parent = area,
		OnClick = function()
			Registry.HudController.Toggle("Odds")
		end,
	})

	rollButton = UI.Button({
		Name = "RollButton",
		Text = "ROLL",
		Size = UDim2.fromOffset(250, 88),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = Theme.Accent,
		TextColor = Color3.fromRGB(60, 36, 0),
		MaxTextSize = 44,
		Radius = 16,
		StrokeThickness = 3,
		Parent = area,
		OnClick = function()
			task.spawn(RollController.Roll, false)
		end,
	})
	cooldownShade = UI.new("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = rollButton,
	}, { UI.Corner(16) })

	autoButton = UI.Button({
		Name = "Auto",
		Text = "AUTO: OFF",
		Size = UDim2.fromOffset(120, 52),
		Position = UDim2.new(0.5, -140, 1, -18),
		AnchorPoint = Vector2.new(1, 1),
		MaxTextSize = 18,
		Parent = area,
		OnClick = function()
			RollController.SetAuto(not auto)
		end,
	})
	luckyButton = UI.Button({
		Name = "Lucky",
		Text = "LUCKY",
		Size = UDim2.fromOffset(120, 52),
		Position = UDim2.new(0.5, 140, 1, -18),
		AnchorPoint = Vector2.new(0, 1),
		Color = Theme.Dice:Lerp(Color3.new(0, 0, 0), 0.25),
		MaxTextSize = 16,
		Visible = false,
		Parent = area,
		OnClick = function()
			task.spawn(RollController.Roll, true)
		end,
	})

	-- Reveal card
	card = UI.Panel({
		Name = "RollCard",
		Size = UDim2.fromOffset(300, 250),
		Position = UDim2.new(0.5, 0, 1, -180),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		ZIndex = 20,
		Parent = hud,
	})
	cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	cardStroke.Thickness = 3
	cardStroke.Transparency = 0
	UI.new("UIScale", { Name = "RevealScale", Parent = card })
	cardViewportHolder = UI.new("Frame", {
		Size = UDim2.new(1, -20, 0, 120),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Parent = card,
	})
	cardRarity = UI.Label({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 128), Font = Theme.FontBlack, MaxTextSize = 20, Parent = card })
	cardTitle = UI.Label({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 150), Font = Theme.FontBlack, MaxTextSize = 30, Parent = card })
	cardMutation = UI.Label({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 184), Font = Theme.FontBlack, MaxTextSize = 18, Visible = false, Parent = card })
	cardNew = UI.Label({
		Text = "NEW!",
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		TextColor3 = Theme.Good,
		Font = Theme.FontBlack,
		Rotation = 8,
		TextStrokeTransparency = 0,
		MaxTextSize = 22,
		Visible = false,
		Parent = card,
	})
	cardPlace = UI.Button({
		Name = "PlaceNow",
		Text = "PLACE",
		Size = UDim2.new(0.5, 0, 0, 34),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = Theme.Good,
		MaxTextSize = 18,
		Visible = false,
		Parent = card,
		OnClick = function()
			if lastResult then
				card.Visible = false
				Registry.BuildController.Enter(lastResult.ItemId .. "|" .. lastResult.Mutation)
			end
		end,
	})

	flash = UI.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 60,
		Active = false,
		Parent = root,
	})

	buildOddsWindow(root)
	State.Watch({ "Derived" }, refreshInfo)

	-- Cooldown shading + auto-roll loop.
	task.spawn(function()
		while true do
			local remaining = nextReady - os.clock()
			local frac = if remaining > 0 then remaining / cooldown() else 0
			cooldownShade.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
			if auto and not rolling and remaining <= 0 then
				task.spawn(RollController.Roll, false)
			end
			task.wait()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then -- (Space is jump)
			if not (Registry.BuildController and Registry.BuildController.IsActive()) then
				task.spawn(RollController.Roll, false)
			end
		end
	end)
end

return RollController

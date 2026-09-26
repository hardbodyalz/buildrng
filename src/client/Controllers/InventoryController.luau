--[[
	InventoryController
	Build-oriented inventory: category tabs, search, sort, a details pane
	with stats and the strategic tip, plus lock / favourite / sell / mass-sell.
	"PLACE" jumps straight into Build Mode with the selected stack.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local ItemStats = require(Shared.Util.ItemStats)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local InventoryController = {}

local TABS = { "All", "Defense", "Offense", "Support", "Economy", "Special" }
local SORTS = { "Rarity", "Name", "Count", "Type" }

local category = "All"
local sortIndex = 1
local search = ""
local selectedKey: string? = nil

local grid: ScrollingFrame
local details: Frame
local tabButtons: { [string]: TextButton } = {}
local sortButton: TextButton
local footerLabel: TextLabel
local massSellPopup: Frame

local function parseKey(key: string): (any, string)
	local itemId, mut = string.match(key, "^([%w_]+)|(%w+)$")
	return Items.Get(itemId or ""), mut or "Normal"
end

local function stacks(): { any }
	local out = {}
	for key, stack in State.Get("Inventory") or {} do
		local def, mut = parseKey(key)
		if def and stack.Count > 0 then
			local matchesCategory = category == "All" or def.Category == category
			local matchesSearch = search == "" or string.find(string.lower(def.DisplayName), string.lower(search), 1, true) ~= nil
			if matchesCategory and matchesSearch then
				table.insert(out, { Key = key, Def = def, Mut = mut, Stack = stack })
			end
		end
	end
	local mode = SORTS[sortIndex]
	table.sort(out, function(a, b)
		if a.Stack.Favorite ~= b.Stack.Favorite then
			return a.Stack.Favorite
		end
		local ra, rb = Rarities.OrderOf(a.Def.Rarity), Rarities.OrderOf(b.Def.Rarity)
		local ma, mb = Mutations.Get(a.Mut).Order, Mutations.Get(b.Mut).Order
		if mode == "Name" then
			if a.Def.DisplayName ~= b.Def.DisplayName then
				return a.Def.DisplayName < b.Def.DisplayName
			end
		elseif mode == "Count" then
			if a.Stack.Count ~= b.Stack.Count then
				return a.Stack.Count > b.Stack.Count
			end
		elseif mode == "Type" then
			if a.Def.Category ~= b.Def.Category then
				return a.Def.Category < b.Def.Category
			end
		end
		if ra ~= rb then
			return ra > rb
		end
		if ma ~= mb then
			return ma > mb
		end
		return a.Def.Order < b.Def.Order
	end)
	return out
end

local refresh: () -> ()

local function tag(parent: Instance, text: string, color: Color3, pos: UDim2, anchor: Vector2?)
	local t = UI.new("TextLabel", {
		Text = text,
		Size = UDim2.fromOffset(38, 16),
		Position = pos,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = color,
		TextColor3 = Color3.new(0, 0, 0),
		Font = Theme.FontBlack,
		TextScaled = true,
		ZIndex = 13,
		Parent = parent,
	}, { UI.Corner(4) })
	return t
end

local function renderDetails()
	UI.Clear(details)
	UI.List(Enum.FillDirection.Vertical, 6).Parent = details
	local stack = selectedKey and (State.Get("Inventory") or {})[selectedKey]
	if not selectedKey or not stack or stack.Count <= 0 then
		UI.Label({ Text = "Select an item", Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.TextDim, Parent = details })
		return
	end
	local key = selectedKey :: string
	local def, mut = parseKey(key)
	local color = Theme.Rarity(def.Rarity)
	local holder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 1, LayoutOrder = 1, Parent = details })
	UI.ItemViewport(def, mut).Parent = holder
	UI.Label({ Text = def.DisplayName, Size = UDim2.new(1, 0, 0, 28), Font = Theme.FontBlack, LayoutOrder = 2, Parent = details })
	local sub = Rarities.Get(def.Rarity).Name .. "  -  " .. def.Role
	if mut ~= Mutations.NormalId then
		sub = mut .. " " .. sub
	end
	UI.Label({ Text = sub, Size = UDim2.new(1, 0, 0, 20), TextColor3 = color, MaxTextSize = 18, LayoutOrder = 3, Parent = details })
	UI.Label({
		Text = def.Description,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.Font,
		TextWrapped = true,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 15,
		LayoutOrder = 4,
		Parent = details,
	})
	local stats = ItemStats.Compute(def, 1, mut)
	local statText = {}
	for _, line in ItemStats.Describe(def, stats) do
		table.insert(statText, line[1] .. ": " .. line[2])
	end
	UI.Label({
		Text = table.concat(statText, "   "),
		Size = UDim2.new(1, 0, 0, 44),
		Font = Theme.FontBold,
		TextWrapped = true,
		MaxTextSize = 14,
		LayoutOrder = 5,
		Parent = details,
	})
	UI.Label({
		Text = "TIP: " .. def.Tip,
		Size = UDim2.new(1, 0, 0, 38),
		Font = Theme.Font,
		TextWrapped = true,
		TextColor3 = Theme.Accent,
		MaxTextSize = 14,
		LayoutOrder = 6,
		Parent = details,
	})
	UI.Label({
		Text = string.format("Owned: %d   |   Sells for %s", stack.Count, Format.Abbrev(ItemStats.SellValue(def, mut))),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font,
		MaxTextSize = 14,
		LayoutOrder = 7,
		Parent = details,
	})

	local row1 = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 8, Parent = details }, {
		UI.List(Enum.FillDirection.Horizontal, 6),
	})
	UI.Button({
		Name = "Place",
		Text = "PLACE",
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = Theme.Good,
		Parent = row1,
		OnClick = function()
			Registry.HudController.Close()
			Registry.BuildController.Enter(key)
		end,
	})
	UI.Button({
		Text = if stack.Locked then "UNLOCK" else "LOCK",
		Size = UDim2.new(0.25, -3, 1, 0),
		Color = if stack.Locked then Theme.Warn else Theme.PanelLighter,
		MaxTextSize = 14,
		Parent = row1,
		OnClick = function()
			local ok, err = Net.Invoke("SetItemFlag", key, "Locked", not stack.Locked)
			if not ok then
				Registry.NotifyController.Error(err)
			end
		end,
	})
	UI.Button({
		Text = if stack.Favorite then "UNFAV" else "FAV",
		Size = UDim2.new(0.25, -3, 1, 0),
		Color = if stack.Favorite then Theme.Accent else Theme.PanelLighter,
		MaxTextSize = 14,
		Parent = row1,
		OnClick = function()
			local ok, err = Net.Invoke("SetItemFlag", key, "Favorite", not stack.Favorite)
			if not ok then
				Registry.NotifyController.Error(err)
			end
		end,
	})

	local row2 = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 9, Parent = details }, {
		UI.List(Enum.FillDirection.Horizontal, 6),
	})
	local function sell(count: number)
		local ok, res = Net.Invoke("SellItems", key, count)
		if ok then
			Registry.SoundController.Play("Sell")
			Registry.NotifyController.Toast("Sold for " .. Format.Abbrev(res.Coins) .. " coins", "Reward")
		else
			Registry.NotifyController.Error(res)
		end
	end
	UI.Button({
		Text = "SELL 1",
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = Theme.Bad:Lerp(Theme.Panel, 0.3),
		MaxTextSize = 15,
		Visible = not stack.Locked,
		Parent = row2,
		OnClick = function()
			sell(1)
		end,
	})
	UI.Button({
		Text = "SELL ALL (" .. stack.Count .. ")",
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = Theme.Bad:Lerp(Theme.Panel, 0.1),
		MaxTextSize = 15,
		Visible = not stack.Locked,
		Parent = row2,
		OnClick = function()
			sell(stack.Count)
		end,
	})
end

local function renderGrid()
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local list = stacks()
	for i, entry in list do
		local def, mut, stack = entry.Def, entry.Mut, entry.Stack
		local color = Theme.Rarity(def.Rarity)
		local cardBtn = UI.new("TextButton", {
			Name = entry.Key,
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = Theme.PanelLight:Lerp(color, 0.15),
			LayoutOrder = i,
			ZIndex = 11,
			Parent = grid,
		}, {
			UI.Corner(8),
			UI.Stroke(color, if entry.Key == selectedKey then 4 else 2),
		})
		UI.Label({
			Text = def.DisplayName,
			Size = UDim2.new(1, -8, 0, 32),
			Position = UDim2.new(0, 4, 1, -34),
			TextWrapped = true,
			MaxTextSize = 14,
			ZIndex = 12,
			Parent = cardBtn,
		})
		UI.Label({
			Text = Rarities.Get(def.Rarity).Name,
			Size = UDim2.new(1, -8, 0, 14),
			Position = UDim2.fromOffset(4, 4),
			TextColor3 = color,
			MaxTextSize = 12,
			ZIndex = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = cardBtn,
		})
		UI.Label({
			Text = "x" .. stack.Count,
			Size = UDim2.new(0.5, 0, 0, 22),
			Position = UDim2.new(1, -4, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Theme.FontBlack,
			MaxTextSize = 20,
			ZIndex = 12,
			Parent = cardBtn,
		})
		if mut ~= Mutations.NormalId then
			local t = tag(cardBtn, string.upper(mut), Theme.Mutation(mut), UDim2.fromOffset(4, 22))
			t.Size = UDim2.fromOffset(62, 16)
		end
		if stack.Locked then
			tag(cardBtn, "LOCK", Theme.Warn, UDim2.new(0, 4, 1, -52))
		end
		if stack.Favorite then
			tag(cardBtn, "FAV", Theme.Accent, UDim2.new(1, -4, 1, -52), Vector2.new(1, 0))
		end
		cardBtn.Activated:Connect(function()
			UI.ClickSound()
			selectedKey = entry.Key
			refresh()
		end)
	end
	if #list == 0 then
		UI.Label({
			Text = "Nothing here yet - roll for more!",
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Theme.TextDim,
			Parent = grid,
		})
	end
	-- Placed count footer
	local derived = State.Derived()
	local placed = 0
	local base = State.Get("Base")
	if base then
		for _ in base.Structures do
			placed += 1
		end
	end
	footerLabel.Text = string.format("Placed %d / %d", placed, derived.Capacity or 0)
end

refresh = function()
	for name, btn in tabButtons do
		UI.SetButtonColor(btn, if name == category then Theme.Accent2:Lerp(Theme.Panel, 0.3) else Theme.PanelLight)
	end
	sortButton.Text = "SORT: " .. string.upper(SORTS[sortIndex])
	renderGrid()
	renderDetails()
end

local function buildMassSell(parent: Frame)
	massSellPopup = UI.Panel({
		Name = "MassSell",
		Size = UDim2.fromOffset(360, 190),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		BackgroundColor3 = Theme.Bg,
		Parent = parent,
	})
	local maxOrder = 2
	local includeMut = false
	local content = UI.new("Frame", { Size = UDim2.new(1, -20, 1, -20), Position = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Parent = massSellPopup }, {
		UI.List(Enum.FillDirection.Vertical, 8),
	})
	UI.Label({
		Text = "Sell every unlocked, non-favourite item up to:",
		Size = UDim2.new(1, 0, 0, 36),
		TextWrapped = true,
		MaxTextSize = 16,
		ZIndex = 21,
		LayoutOrder = 1,
		Parent = content,
	})
	local rarityBtn, mutBtn
	local function update()
		local r = Rarities.List[maxOrder]
		rarityBtn.Text = string.upper(r.Name)
		UI.SetButtonColor(rarityBtn, Theme.Rarity(r.Id):Lerp(Theme.Panel, 0.3))
		mutBtn.Text = if includeMut then "INCLUDE MUTATIONS: YES" else "INCLUDE MUTATIONS: NO"
	end
	rarityBtn = UI.Button({
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 2,
		ZIndex = 21,
		Parent = content,
		OnClick = function()
			maxOrder = maxOrder % 4 + 1 -- Common..Epic; rarer items must be sold one stack at a time
			update()
		end,
	})
	mutBtn = UI.Button({
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 3,
		ZIndex = 21,
		MaxTextSize = 14,
		Parent = content,
		OnClick = function()
			includeMut = not includeMut
			update()
		end,
	})
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 4, Parent = content }, {
		UI.List(Enum.FillDirection.Horizontal, 8),
	})
	UI.Button({
		Text = "SELL",
		Size = UDim2.new(0.5, -4, 1, 0),
		Color = Theme.Bad,
		ZIndex = 21,
		Parent = row,
		OnClick = function()
			local ok, res = Net.Invoke("MassSell", maxOrder, includeMut)
			massSellPopup.Visible = false
			if ok then
				Registry.SoundController.Play("Sell")
				Registry.NotifyController.Toast(string.format("Sold %d items for %s coins", res.Sold, Format.Abbrev(res.Coins)), "Reward")
			else
				Registry.NotifyController.Error(res)
			end
		end,
	})
	UI.Button({
		Text = "CANCEL",
		Size = UDim2.new(0.5, -4, 1, 0),
		ZIndex = 21,
		Parent = row,
		OnClick = function()
			massSellPopup.Visible = false
		end,
	})
	update()
end

function InventoryController.Init()
	local root = Registry.HudController.Root()
	local frame, content = UI.Window({
		Name = "InventoryWindow",
		Title = "INVENTORY",
		Parent = root,
		OnClose = function()
			Registry.HudController.Close()
		end,
	})

	local top = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = content }, {
		UI.List(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left),
	})
	for i, name in TABS do
		tabButtons[name] = UI.Button({
			Text = string.upper(name),
			Size = UDim2.fromOffset(78, 34),
			LayoutOrder = i,
			MaxTextSize = 13,
			Parent = top,
			OnClick = function()
				category = name
				refresh()
			end,
		})
	end
	local searchBox = UI.new("TextBox", {
		Size = UDim2.fromOffset(120, 34),
		LayoutOrder = 20,
		BackgroundColor3 = Theme.Bg,
		PlaceholderText = "Search...",
		Text = "",
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.TextDim,
		Font = Theme.Font,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = top,
	}, { UI.Corner(8), UI.Padding(6), UI.new("UITextSizeConstraint", { MaxTextSize = 16 }) })
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		search = searchBox.Text
		renderGrid()
	end)
	sortButton = UI.Button({
		Text = "SORT",
		Size = UDim2.fromOffset(110, 34),
		LayoutOrder = 21,
		MaxTextSize = 13,
		Parent = top,
		OnClick = function()
			sortIndex = sortIndex % #SORTS + 1
			refresh()
		end,
	})

	grid = UI.Scroll({
		Size = UDim2.new(0.62, -6, 1, -86),
		Position = UDim2.fromOffset(0, 42),
		Parent = content,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(104, 112),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UI.Padding(4).Parent = grid

	details = UI.new("Frame", {
		Size = UDim2.new(0.38, -6, 1, -42),
		Position = UDim2.new(0.62, 6, 0, 42),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.3,
		Parent = content,
	})
	UI.Corner(10).Parent = details
	UI.Padding(8).Parent = details

	local footer = UI.new("Frame", {
		Size = UDim2.new(0.62, -6, 0, 38),
		Position = UDim2.new(0, 0, 1, -38),
		BackgroundTransparency = 1,
		Parent = content,
	})
	footerLabel = UI.Label({ Size = UDim2.new(0.5, 0, 1, -8), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 16, Parent = footer })
	local massBtn = UI.Button({
		Text = "MASS SELL",
		Size = UDim2.new(0.4, 0, 1, 0),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Bad:Lerp(Theme.Panel, 0.2),
		MaxTextSize = 16,
		Parent = footer,
		OnClick = function()
			if not State.IsUnlocked("MassSell") then
				local req = State.Derived().UnlockRequirements
				Registry.NotifyController.Error("Locked - " .. ((req and req.MassSell) or "keep rolling"))
				return
			end
			massSellPopup.Visible = true
		end,
	})
	buildMassSell(frame)

	Registry.HudController.RegisterWindow("Inventory", frame, refresh, function()
		massSellPopup.Visible = false
	end)
	State.Watch({ "Inventory", "Base", "Derived" }, function()
		massBtn.TextTransparency = if State.IsUnlocked("MassSell") then 0 else 0.5
		if Registry.HudController.IsOpen("Inventory") then
			refresh()
		end
	end)
end

return InventoryController

--[[
	IndexController
	The collection log. Every rollable item is listed by rarity; undiscovered
	ones show as "???" (secret items don't appear at all until found).
	Each rarity row shows completion and its permanent Luck reward.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Progression = require(Shared.Config.Progression)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local IndexController = {}

local list: ScrollingFrame
local details: Frame
local selected: string? = nil

local rewardByRarity = {}
for _, c in Progression.CollectionRewards do
	rewardByRarity[c.Rarity] = c
end

local refresh: () -> ()

local function renderDetails()
	UI.Clear(details)
	UI.List(Enum.FillDirection.Vertical, 6).Parent = details
	local def = selected and Items.Get(selected)
	local index = State.Get("Index") or {}
	local entry = def and index[def.Id]
	if not def then
		UI.Label({ Text = "Select an entry", Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.TextDim, Parent = details })
		return
	end
	local holder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 130), BackgroundTransparency = 1, LayoutOrder = 1, Parent = details })
	if entry then
		UI.ItemViewport(def, nil).Parent = holder
	else
		UI.Label({ Text = "?", TextColor3 = Theme.TextDim, Font = Theme.FontBlack, MaxTextSize = 80, Parent = holder })
	end
	UI.Label({ Text = if entry then def.DisplayName else "???", Size = UDim2.new(1, 0, 0, 28), Font = Theme.FontBlack, LayoutOrder = 2, Parent = details })
	UI.Label({
		Text = Rarities.Get(def.Rarity).Name .. (if entry then "  -  " .. def.Role else ""),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.Rarity(def.Rarity),
		MaxTextSize = 18,
		LayoutOrder = 3,
		Parent = details,
	})
	UI.Label({
		Text = if entry then def.Description else "Not discovered yet. Keep rolling!",
		Size = UDim2.new(1, 0, 0, 44),
		Font = Theme.Font,
		TextWrapped = true,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 15,
		LayoutOrder = 4,
		Parent = details,
	})
	if entry then
		UI.Label({
			Text = string.format("Obtained: %d\nFirst found: %s", entry.Count, Format.Date(entry.First)),
			Size = UDim2.new(1, 0, 0, 40),
			Font = Theme.Font,
			TextScaled = false,
			TextSize = 15,
			LayoutOrder = 5,
			Parent = details,
		})
		local muts = {}
		for _, m in Mutations.List do
			if entry.Muts and entry.Muts[m.Id] then
				table.insert(muts, m.Id)
			elseif not m.Hidden then
				table.insert(muts, "?")
			end
		end
		UI.Label({
			Text = "Mutations: " .. table.concat(muts, ", "),
			Size = UDim2.new(1, 0, 0, 36),
			Font = Theme.Font,
			TextWrapped = true,
			TextColor3 = Theme.Accent,
			MaxTextSize = 14,
			LayoutOrder = 6,
			Parent = details,
		})
	end
end

local function renderList()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local index = State.Get("Index") or {}
	local collections = State.Get("Collections") or {}
	local order = 0
	for _, rarity in Rarities.List do
		local defs = {}
		for _, def in Items.List do
			if def.Rarity == rarity.Id and (not def.Hidden or index[def.Id]) then
				table.insert(defs, def)
			end
		end
		if #defs > 0 then
			order += 1
			local found = 0
			for _, def in defs do
				if index[def.Id] then
					found += 1
				end
			end
			local reward = rewardByRarity[rarity.Id]
			local header = UI.new("Frame", { Size = UDim2.new(1, -10, 0, 28), BackgroundTransparency = 1, LayoutOrder = order, Parent = list })
			local rewardText = ""
			if reward then
				rewardText = string.format("   (+%d%% Luck%s)", math.floor(reward.LuckBonus * 100 + 0.5), if collections[reward.Id] then " - CLAIMED" else "")
			end
			UI.Label({
				Text = string.format("%s  %d/%d%s", string.upper(rarity.Name), found, #defs, rewardText),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.Rarity(rarity.Id),
				Font = Theme.FontBlack,
				MaxTextSize = 18,
				Parent = header,
			})
			order += 1
			local row = UI.new("Frame", {
				Size = UDim2.new(1, -10, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = order,
				Parent = list,
			})
			UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(92, 64), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
			for i, def in defs do
				local discovered = index[def.Id] ~= nil
				local color = Theme.Rarity(def.Rarity)
				local btn = UI.new("TextButton", {
					Text = "",
					LayoutOrder = i,
					BackgroundColor3 = if discovered then Theme.PanelLight:Lerp(color, 0.2) else Theme.Bg,
					Parent = row,
				}, { UI.Corner(8), UI.Stroke(color, if selected == def.Id then 4 else 2, if discovered then 0 else 0.5) })
				UI.Label({
					Text = if discovered then def.DisplayName else "???",
					Size = UDim2.new(1, -8, 1, -8),
					Position = UDim2.fromOffset(4, 4),
					TextWrapped = true,
					TextColor3 = if discovered then Theme.Text else Theme.TextDim,
					MaxTextSize = 14,
					Parent = btn,
				})
				btn.Activated:Connect(function()
					UI.ClickSound()
					selected = def.Id
					refresh()
				end)
			end
		end
	end
end

refresh = function()
	renderList()
	renderDetails()
end

function IndexController.Init()
	local frame, content = UI.Window({
		Name = "IndexWindow",
		Title = "INDEX",
		Parent = Registry.HudController.Root(),
		OnClose = function()
			Registry.HudController.Close()
		end,
	})
	list = UI.Scroll({ Size = UDim2.new(0.62, -6, 1, 0), Parent = content })
	UI.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left).Parent = list
	details = UI.new("Frame", {
		Size = UDim2.new(0.38, -6, 1, 0),
		Position = UDim2.new(0.62, 6, 0, 0),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.3,
		Parent = content,
	}, { UI.Corner(10), UI.Padding(8) })
	Registry.HudController.RegisterWindow("Index", frame, refresh)
	State.Watch({ "Index", "Collections" }, function()
		if Registry.HudController.IsOpen("Index") then
			refresh()
		end
	end)
end

return IndexController

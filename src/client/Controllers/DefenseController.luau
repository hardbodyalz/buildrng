--[[
	DefenseController
	Defence HUD: start / checkpoint / retreat, wave + Core HP, boss health bar,
	and the end-of-run summary. Also floats a status billboard over every
	plot's Core so players can watch each other's defences.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local DefenseController = {}
DefenseController.StateChanged = Signal.new() -- (state)
DefenseController.Current = nil :: any

local panel: Frame
local stateLabel: TextLabel
local waveLabel: TextLabel
local coreFill: Frame
local coreLabel: TextLabel
local startButton: TextButton
local checkpointButton: TextButton
local retreatButton: TextButton
local bossBar: Frame
local bossFill: Frame
local bossLabel: TextLabel
local bossPhase: TextLabel
local summary: Frame
local lastState = "Idle"

function DefenseController.StartButton(): TextButton
	return startButton
end

local function start(fromCheckpoint: boolean)
	local ok, res = Net.Invoke("StartDefense", fromCheckpoint)
	if not ok then
		Registry.NotifyController.Error(res)
		return
	end
	summary.Visible = false
	if Registry.BuildController.IsActive() then
		Registry.BuildController.Exit()
	end
end

local function showSummary(s: any)
	UI.Clear(summary)
	UI.List(Enum.FillDirection.Vertical, 8).Parent = summary
	local fell = s.Reason == "CoreDestroyed"
	UI.Label({
		Text = if fell then "YOUR CORE FELL" else "DEFENCE ENDED",
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.FontBlack,
		TextColor3 = if fell then Theme.Bad else Theme.Accent,
		LayoutOrder = 1,
		Parent = summary,
	})
	UI.Label({
		Text = string.format("Reached wave %d  (cleared %d)", s.LastWave or 0, s.WavesCleared or 0),
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 2,
		Parent = summary,
	})
	UI.Label({
		Text = string.format("+%s coins    %d enemies defeated%s", Format.Abbrev(s.Coins or 0), s.Kills or 0, if (s.Dice or 0) > 0 then "    +" .. s.Dice .. " Dice" else ""),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Theme.Coins,
		LayoutOrder = 3,
		Parent = summary,
	})
	UI.Label({
		Text = if fell then "You keep everything you earned. Find the weak spot, upgrade and try again!" else "Rewards are yours to keep.",
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.Font,
		TextWrapped = true,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 16,
		LayoutOrder = 4,
		Parent = summary,
	})
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = 5, Parent = summary }, {
		UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center),
	})
	UI.Button({ Text = "IMPROVE BASE", Size = UDim2.new(0.33, -6, 1, 0), Color = Theme.Accent2:Lerp(Theme.Panel, 0.2), MaxTextSize = 16, Parent = row, OnClick = function()
		summary.Visible = false
		Registry.BuildController.Enter(nil)
	end })
	UI.Button({ Text = "RETRY", Size = UDim2.new(0.33, -6, 1, 0), Color = Theme.Good, MaxTextSize = 16, Parent = row, OnClick = function()
		start(false)
	end })
	UI.Button({ Text = "CLOSE", Size = UDim2.new(0.33, -6, 1, 0), MaxTextSize = 16, Parent = row, OnClick = function()
		summary.Visible = false
	end })
	summary.Visible = true
	local scale = summary:FindFirstChild("Pop") :: UIScale
	scale.Scale = 0.8
	UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function onState(s: any)
	DefenseController.Current = s
	local idle = s.State == "Idle"
	startButton.Visible = idle
	checkpointButton.Visible = idle and (s.Checkpoint or 1) > 1
	checkpointButton.Text = "START AT WAVE " .. tostring(s.Checkpoint)
	retreatButton.Visible = not idle

	if idle then
		stateLabel.Text = if s.HighestWave and s.HighestWave > 0 then "Best wave: " .. s.HighestWave else "Ready to defend"
		waveLabel.Text = "Next: " .. tostring(s.NextPreview or "")
	elseif s.State == "Countdown" then
		stateLabel.Text = string.format("Wave %d starts in %d", s.Wave, math.ceil(s.Timer))
		waveLabel.Text = tostring(s.NextPreview or "")
	elseif s.State == "Intermission" then
		stateLabel.Text = string.format("Wave %d cleared!  Next in %d", s.Wave, math.ceil(s.Timer))
		waveLabel.Text = "Next: " .. tostring(s.NextPreview or "")
	else
		stateLabel.Text = "WAVE " .. tostring(s.Wave)
		waveLabel.Text = string.format("%d enemies left", (s.Enemies or 0) + (s.Remaining or 0))
	end
	local frac = if s.CoreMax and s.CoreMax > 0 then s.CoreHp / s.CoreMax else 1
	UI.SetBar(coreFill, frac, true)
	coreFill.BackgroundColor3 = if frac > 0.5 then Theme.Good elseif frac > 0.25 then Theme.Warn else Theme.Bad
	coreLabel.Text = string.format("CORE  %d / %d", math.ceil(s.CoreHp or 0), s.CoreMax or 0)

	if s.Boss then
		bossBar.Visible = true
		UI.SetBar(bossFill, s.Boss.Hp / s.Boss.MaxHp, true)
		bossLabel.Text = string.upper(s.Boss.Name)
		bossPhase.Text = "Phase " .. s.Boss.Phase .. ": " .. s.Boss.PhaseName
	else
		bossBar.Visible = false
	end

	if s.State ~= lastState then
		if s.State == "Idle" then
			Registry.SoundController.StopMusic()
		end
		lastState = s.State
		DefenseController.StateChanged:Fire(s.State)
	end
	if s.Summary then
		showSummary(s.Summary)
	end
end

-- Billboards over every Core (watch other players' defences).
local billboardUpdaters: { [Instance]: () -> () } = {}

local function attachCoreBillboard(plot: Model)
	if billboardUpdaters[plot] then
		billboardUpdaters[plot]()
		return
	end
	local function ensure()
		local ground = plot:FindFirstChild("Ground")
		local core = ground and ground:FindFirstChild("Core")
		local basePart = core and core:FindFirstChild("CoreBase") :: BasePart?
		if not basePart then
			return nil
		end
		local gui = basePart:FindFirstChild("DefenseStatus") :: BillboardGui?
		if not gui then
			gui = UI.new("BillboardGui", {
				Name = "DefenseStatus",
				Size = UDim2.fromOffset(200, 44),
				StudsOffsetWorldSpace = Vector3.new(0, 14, 0),
				MaxDistance = 300,
				Parent = basePart,
			})
			local _, fill, label = UI.Bar({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 22), Color = Theme.Good, Parent = gui })
			fill.Name = "CoreFill"
			label.Name = "CoreText"
			UI.Label({ Name = "WaveText", Size = UDim2.new(1, 0, 0, 20), TextStrokeTransparency = 0.3, MaxTextSize = 18, Parent = gui })
		end
		return gui
	end
	local function update()
		local gui = ensure()
		if not gui then
			return
		end
		local stateName = plot:GetAttribute("DefenseState")
		gui.Enabled = stateName ~= nil and stateName ~= "Idle"
		local hp, max = plot:GetAttribute("CoreHp") or 0, plot:GetAttribute("CoreMax") or 1
		local bar = gui:FindFirstChild("Bar") :: Frame
		if bar then
			local fill = bar:FindFirstChild("CoreFill") :: Frame
			UI.SetBar(fill, hp / math.max(max, 1))
			fill.BackgroundColor3 = if hp / max > 0.5 then Theme.Good elseif hp / max > 0.25 then Theme.Warn else Theme.Bad;
			(bar:FindFirstChild("CoreText") :: TextLabel).Text = string.format("%d / %d", hp, max)
		end
		(gui:FindFirstChild("WaveText") :: TextLabel).Text = "WAVE " .. tostring(plot:GetAttribute("Wave") or 0)
	end
	billboardUpdaters[plot] = update
	for _, attr in { "DefenseState", "CoreHp", "CoreMax", "Wave", "Tier" } do
		plot:GetAttributeChangedSignal(attr):Connect(update)
	end
	update()
end

function DefenseController.Init()
	local hud = Registry.HudController.Hud()

	panel = UI.Panel({
		Name = "DefensePanel",
		Size = UDim2.fromOffset(250, 150),
		Position = UDim2.fromOffset(12, 60),
		Parent = hud,
	})
	UI.Padding(10).Parent = panel
	UI.List(Enum.FillDirection.Vertical, 6).Parent = panel
	stateLabel = UI.Label({ Text = "Ready to defend", Size = UDim2.new(1, 0, 0, 22), Font = Theme.FontBlack, LayoutOrder = 1, MaxTextSize = 20, Parent = panel })
	waveLabel = UI.Label({ Text = "", Size = UDim2.new(1, 0, 0, 16), Font = Theme.Font, TextColor3 = Theme.TextDim, LayoutOrder = 2, MaxTextSize = 14, Parent = panel })
	local _, fill, label = UI.Bar({ Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3, Parent = panel })
	coreFill, coreLabel = fill, label
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 4, Parent = panel }, {
		UI.List(Enum.FillDirection.Horizontal, 6),
	})
	startButton = UI.Button({ Name = "Start", Text = "START DEFENCE", Size = UDim2.new(1, 0, 1, 0), Color = Theme.Bad, MaxTextSize = 18, Parent = row, OnClick = function()
		start(false)
	end })
	retreatButton = UI.Button({ Text = "RETREAT", Size = UDim2.new(1, 0, 1, 0), Visible = false, MaxTextSize = 18, Parent = row, OnClick = function()
		local ok, err = Net.Invoke("StopDefense")
		if not ok then
			Registry.NotifyController.Error(err)
		end
	end })
	checkpointButton = UI.Button({ Text = "START AT WAVE 11", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 5, Visible = false, Color = Theme.PanelLighter, MaxTextSize = 14, Parent = panel, OnClick = function()
		start(true)
	end })
	panel.AutomaticSize = Enum.AutomaticSize.Y

	bossBar = UI.Panel({
		Name = "BossBar",
		Size = UDim2.new(0.44, 0, 0, 62),
		Position = UDim2.new(0.5, 0, 0, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(40, 10, 14),
		Visible = false,
		Parent = hud,
	})
	bossLabel = UI.Label({ Size = UDim2.new(0.6, 0, 0, 24), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.FontBlack, TextColor3 = Theme.Bad, MaxTextSize = 22, Parent = bossBar })
	bossPhase = UI.Label({ Size = UDim2.new(0.4, -10, 0, 24), Position = UDim2.new(0.6, 0, 0, 4), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Warn, MaxTextSize = 16, Parent = bossBar })
	local _, bfill = UI.Bar({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 32), Color = Theme.Bad, Parent = bossBar })
	bossFill = bfill

	summary = UI.Panel({
		Name = "DefenseSummary",
		Size = UDim2.fromOffset(460, 250),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 30,
		Parent = Registry.HudController.Root(),
	})
	UI.Padding(14).Parent = summary
	UI.new("UIScale", { Name = "Pop", Parent = summary })

	Net.On("DefenseState", function(s)
		if type(s) == "table" then
			onState(s)
		end
	end)

	local plots = Workspace:WaitForChild("Plots")
	for _, plot in plots:GetChildren() do
		attachCoreBillboard(plot :: Model)
	end
	plots.ChildAdded:Connect(function(p)
		attachCoreBillboard(p :: Model)
	end)
	-- Re-attach after terrain rebuilds (expansions replace the Core).
	plots.DescendantAdded:Connect(function(d)
		if d.Name == "CoreBase" then
			task.defer(function()
				local plot = d:FindFirstAncestorOfClass("Model")
				while plot and plot.Parent ~= plots do
					plot = plot:FindFirstAncestorOfClass("Model")
				end
				if plot then
					attachCoreBillboard(plot)
				end
			end)
		end
	end)
end

return DefenseController

--[[
	OfflineController
	"Welcome back" screen: shows what the base did while the player was away,
	with numbers that count up for a satisfying return.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local OfflineController = {}

local function countUp(label: TextLabel, target: number, prefix: string, suffix: string, duration: number)
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local f = math.min((os.clock() - t0) / duration, 1)
			local eased = 1 - (1 - f) ^ 3
			label.Text = prefix .. Format.Commas(math.floor(target * eased)) .. suffix
			if f >= 1 then
				break
			end
			task.wait()
		end
	end)
end

local function show(report: any)
	local root = Registry.HudController.Root()
	local dim = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 70,
		Active = true,
		Parent = root,
	})
	local panel = UI.Panel({
		Size = UDim2.fromOffset(480, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 71,
		Parent = dim,
	})
	UI.List(Enum.FillDirection.Vertical, 6).Parent = panel
	UI.Padding(16).Parent = panel
	UI.Label({ Text = "WELCOME BACK!", Size = UDim2.new(1, 0, 0, 44), Font = Theme.FontBlack, TextColor3 = Theme.Accent, MaxTextSize = 40, LayoutOrder = 1, Parent = panel })
	UI.Label({
		Text = "You were gone for " .. Format.Duration(report.ElapsedSeconds),
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Font,
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = panel,
	})
	if report.CountedSeconds < report.ElapsedSeconds then
		UI.Label({
			Text = "(offline defence runs for up to " .. Format.Duration(report.CountedSeconds) .. ")",
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.Font,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 13,
			LayoutOrder = 3,
			Parent = panel,
		})
	end
	local rows = {
		{ "Waves defeated", report.WavesDefeated, Theme.Text },
		{ "Enemies defeated", report.EnemiesDefeated, Theme.Text },
		{ "Coins earned", report.Coins, Theme.Coins },
		{ "XP earned", report.Xp, Theme.Xp },
	}
	if report.Dice > 0 then
		table.insert(rows, { "Dice found", report.Dice, Theme.Dice })
	end
	if report.BossesDefeated > 0 then
		table.insert(rows, { "Bosses defeated", report.BossesDefeated, Theme.Bad })
	end
	for i, r in rows do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.PanelLight, LayoutOrder = 10 + i, Parent = panel }, { UI.Corner(6) })
		UI.Label({ Text = r[1], Size = UDim2.new(0.55, -10, 1, -6), Position = UDim2.fromOffset(10, 3), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, MaxTextSize = 17, Parent = row })
		local value = UI.Label({ Text = "0", Size = UDim2.new(0.45, -10, 1, -6), Position = UDim2.new(0.55, 0, 0, 3), TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.FontBlack, TextColor3 = r[3], MaxTextSize = 19, Parent = row })
		task.delay(0.15 * i, countUp, value, r[2], "", "", 1.1)
	end
	local verdict = if report.BaseFell
		then "Your base couldn't hold wave 1 - build more defences for better offline rewards!"
		else string.format("Your base held up to wave %d. The Core survived with %d%% HP.", report.BestWave, report.CoreHealthPct)
	UI.Label({
		Text = verdict,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.FontBold,
		TextWrapped = true,
		TextColor3 = if report.BaseFell then Theme.Warn else Theme.Good,
		MaxTextSize = 16,
		LayoutOrder = 30,
		Parent = panel,
	})
	UI.Button({
		Text = "COLLECT",
		Size = UDim2.new(0.6, 0, 0, 50),
		Color = Theme.Good,
		LayoutOrder = 31,
		MaxTextSize = 26,
		Parent = panel,
		OnClick = function()
			Registry.SoundController.PlayReveal(3)
			dim:Destroy()
		end,
	})
	local scale = UI.new("UIScale", { Scale = 0.7, Parent = panel })
	UI.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Registry.SoundController.PlayReveal(2)
end

function OfflineController.Init()
	Net.On("OfflineReport", function(report)
		if type(report) == "table" then
			show(report)
		end
	end)
end

return OfflineController

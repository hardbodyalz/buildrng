--[[
	TutorialController
	A < 3 minute guided first loop:  roll -> inventory -> place -> defend ->
	watch -> reward -> roll again. One short instruction at a time with a
	pointer at the relevant button; everything else unlocks later
	(Progression.Unlocks), so new players aren't buried in systems.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local player = Players.LocalPlayer

local TutorialController = {}

local FINAL_STEP = 8

local STEPS = {
	[1] = { Text = "Welcome, Commander! Press ROLL to get your first defence.", Target = function()
		return Registry.RollController.Button()
	end },
	[2] = { Text = "You got a Scrap Turret! Open your INVENTORY.", Target = function()
		return Registry.HudController.Buttons.Inventory
	end },
	[3] = { Text = "Select the Scrap Turret, then press PLACE.", Target = nil },
	[4] = { Text = "Tap a tile NEXT TO the red enemy path to build your turret.", Target = nil },
	[5] = { Text = "Exit Build mode and press START DEFENCE!", Target = function()
		return Registry.DefenseController.StartButton()
	end },
	[6] = { Text = "Your turret fires on its own. Protect the Core!", Target = nil },
	[7] = { Text = "Wave cleared - you earned coins! ROLL again for more defences.", Target = function()
		return Registry.RollController.Button()
	end },
	[8] = { Text = "Tip: in BUILD mode tap a structure to upgrade it, and use walls to force enemies past your guns. Good luck!", Target = nil, Ok = true },
}

local step = 0
local gui: ScreenGui
local box: Frame
local label: TextLabel
local okButton: TextButton
local pointer: Frame
local ring: Frame

local function current(): number
	local t = State.Get("Tutorial")
	if not t or t.Done then
		return FINAL_STEP + 1
	end
	return t.Step or 1
end

local function render()
	local def = STEPS[step]
	gui.Enabled = def ~= nil
	if not def then
		return
	end
	label.Text = def.Text
	okButton.Visible = def.Ok == true
end

local function advanceTo(n: number)
	if n <= step then
		return
	end
	step = n
	render()
	task.spawn(Net.Invoke, "TutorialAdvance", n)
end

local function placedCount(): number
	local base = State.Get("Base")
	local n = 0
	if base then
		for _ in base.Structures do
			n += 1
		end
	end
	return n
end

function TutorialController.Init()
	gui = UI.new("ScreenGui", {
		Name = "Tutorial",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	box = UI.Panel({
		Size = UDim2.new(0.5, 0, 0, 74),
		Position = UDim2.new(0.5, 0, 0.2, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(30, 34, 60),
		StrokeColor = Theme.Accent,
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(620, 120), MinSize = Vector2.new(300, 60), Parent = box })
	label = UI.Label({ Size = UDim2.new(1, -24, 1, -16), Position = UDim2.fromOffset(12, 8), TextWrapped = true, MaxTextSize = 22, Parent = box })
	okButton = UI.Button({
		Text = "GOT IT",
		Size = UDim2.fromOffset(110, 36),
		Position = UDim2.new(0.5, 0, 1, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Good,
		Visible = false,
		Parent = box,
		OnClick = function()
			advanceTo(FINAL_STEP + 1)
		end,
	})
	pointer = UI.new("Frame", {
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = Theme.Accent,
		Visible = false,
		Parent = gui,
	}, { UI.Stroke(Color3.new(0, 0, 0), 2) })
	ring = UI.new("Frame", {
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}, { UI.Corner(14), UI.Stroke(Theme.Accent, 4) })

	-- Follow the target element every frame (it may move / scale).
	RunService.RenderStepped:Connect(function()
		local def = STEPS[step]
		local target = def and def.Target and def.Target()
		if not gui.Enabled or not target or not target.Visible then
			pointer.Visible = false
			ring.Visible = false
			return
		end
		local pos, size = target.AbsolutePosition, target.AbsoluteSize
		local bounce = math.abs(math.sin(os.clock() * 4)) * 10
		pointer.Visible = true
		pointer.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y - 22 - bounce)
		ring.Visible = true
		ring.Position = UDim2.fromOffset(pos.X - 6, pos.Y - 6)
		ring.Size = UDim2.fromOffset(size.X + 12, size.Y + 12)
	end)

	-- Step triggers --------------------------------------------------------------
	Registry.RollController.RollShown:Connect(function()
		if step == 1 then
			advanceTo(2)
		elseif step == 7 then
			advanceTo(8)
		end
	end)
	Registry.HudController.WindowOpened:Connect(function(name)
		if step == 2 and name == "Inventory" then
			advanceTo(3)
		end
	end)
	Registry.BuildController.Entered:Connect(function(key)
		if (step == 2 or step == 3) and key then
			advanceTo(4)
		end
	end)
	Registry.BuildController.Placed:Connect(function()
		if step <= 4 and step >= 2 then
			advanceTo(5)
		end
	end)
	Registry.DefenseController.StateChanged:Connect(function(s: string)
		local running = s ~= "Idle"
		if step == 5 and running then
			advanceTo(6)
		elseif step == 6 and (s == "Intermission" or not running) then
			advanceTo(7)
		end
	end)

	State.Watch({ "Tutorial" }, function()
		if step == 0 then
			step = current()
			-- Resume sensibly if the player already did later actions.
			if step >= 2 and step <= 4 and placedCount() > 0 then
				advanceTo(5)
			end
			render()
		elseif current() > FINAL_STEP then
			step = FINAL_STEP + 1
			render()
		end
	end)
end

return TutorialController

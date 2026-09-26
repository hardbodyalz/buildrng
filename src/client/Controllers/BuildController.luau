--[[
	BuildController
	Build Mode: overhead camera, grid overlay, live predicted enemy route,
	placement ghost with GREEN (valid) / YELLOW (legal but questionable) /
	RED (invalid) feedback, rotate, move, store and upgrade.

	The preview runs the same Grid + FlowField code as the server, but the
	server re-validates everything - the client only asks.

	Controls
	  PC:     click to place / select, R rotate, Q cancel, B toggle build,
	          right-drag to pan, mouse wheel to zoom
	  Mobile: tap a tile to preview, PLACE HERE to confirm, drag to pan,
	          pinch to zoom; big buttons for rotate / cancel / exit
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Grid = require(Shared.Util.Grid)
local FlowField = require(Shared.Util.FlowField)
local ItemStats = require(Shared.Util.ItemStats)
local ModelBuilder = require(Shared.Util.ModelBuilder)
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local player = Players.LocalPlayer
local CS = GameConfig.Grid.CellSize

local BuildController = {}
BuildController.Entered = Signal.new() -- (stackKey?)
BuildController.Exited = Signal.new()
BuildController.Placed = Signal.new() -- (uid)

local STATUS_COLORS = {
	Valid = Color3.fromRGB(70, 230, 110),
	Warning = Color3.fromRGB(255, 210, 60),
	Invalid = Color3.fromRGB(255, 70, 70),
}

local active = false
local placingKey: string? = nil
local movingUid: string? = nil
local rot = 0
local anchorX, anchorZ = 0, 0
local status, statusReason = "Invalid", nil
local previewSet = false
local selectedUid: string? = nil
local busy = false

local overlay: Folder
local gridFolder: Folder
local pathFolder: Folder
local ghost: Model? = nil
local footprint: Part
local selectionBox: SelectionBox
local pathSet: { [number]: boolean } = {}

local ui: Frame
local banner: TextLabel
local reasonLabel: TextLabel
local hotbar: ScrollingFrame
local confirmButton: TextButton
local panel: Frame
local renderConn: RBXScriptConnection? = nil

-- Follow the cursor only while the player is actually using a mouse
-- (touch laptops switch back and forth).
local usingMouse = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
UserInputService.LastInputTypeChanged:Connect(function(t)
	if t == Enum.UserInputType.Touch then
		usingMouse = false
	elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseButton1 then
		usingMouse = true
	end
end)

-- Camera state (plot-local)
local camHeight = 70
local camPanX, camPanZ = 0, 0

local function plotModel(): Model?
	local id = player:GetAttribute("PlotId")
	local plots = Workspace:FindFirstChild("Plots")
	return if id and plots then plots:FindFirstChild("Plot" .. id) :: Model? else nil
end

local function plotCFrame(): CFrame?
	local m = plotModel()
	return if m and m.PrimaryPart then m.PrimaryPart.CFrame else nil
end

local function base(): any
	return State.Get("Base") or { Tier = 1, Structures = {} }
end

local function region()
	return Grid.Region(base().Tier)
end

local function placedCount(): number
	local n = 0
	for _ in base().Structures do
		n += 1
	end
	return n
end

local function currentDef(): (any, string?)
	if movingUid then
		local s = base().Structures[movingUid]
		if s then
			return Items.Get(s.Id), s.Mut
		end
		return nil, nil
	end
	if placingKey then
		local itemId, mut = string.match(placingKey, "^([%w_]+)|(%w+)$")
		return Items.Get(itemId or ""), mut
	end
	return nil, nil
end

-- Overlay: grid lines + predicted route -------------------------------------------

local function newPart(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function rebuildGrid()
	gridFolder:ClearAllChildren()
	local cf = plotCFrame()
	if not cf then
		return
	end
	local r = region()
	local x0, z0 = Grid.CellToLocal(r.MinX - 0.5, r.MinZ - 0.5)
	local x1, z1 = Grid.CellToLocal(r.MaxX + 0.5, r.MaxZ + 0.5)
	for x = r.MinX, r.MaxX + 1 do
		local lx = Grid.CellToLocal(x - 0.5, 0)
		newPart({
			Size = Vector3.new(0.12, 0.05, z1 - z0),
			CFrame = cf * CFrame.new(lx, 0.06, (z0 + z1) / 2),
			Color = Color3.new(1, 1, 1),
			Transparency = 0.75,
			Parent = gridFolder,
		})
	end
	for z = r.MinZ, r.MaxZ + 1 do
		local _, lz = Grid.CellToLocal(0, z - 0.5)
		newPart({
			Size = Vector3.new(x1 - x0, 0.05, 0.12),
			CFrame = cf * CFrame.new((x0 + x1) / 2, 0.06, lz),
			Color = Color3.new(1, 1, 1),
			Transparency = 0.75,
			Parent = gridFolder,
		})
	end
end

-- Route enemies would take right now (same maths as the server).
local function rebuildPath()
	pathFolder:ClearAllChildren()
	pathSet = {}
	local cf = plotCFrame()
	if not cf then
		return
	end
	local r = region()
	local blockers = {}
	for _, s in base().Structures do
		local def = Items.Get(s.Id)
		if def and def.Blocks then
			local hp = ItemStats.Compute(def, s.Lvl or 1, s.Mut).Health or 1
			for _, c in Grid.FootprintCells(def, s.X, s.Z, s.R or 0) do
				blockers[Grid.Key(c[1], c[2])] = hp
			end
		end
	end
	local field = FlowField.Compute(r, blockers, GameConfig.Defense.PathCostPerHp, 1)
	local sx, sz = Grid.Entrance(r)
	local cells, set = FlowField.Path(field, sx, sz)
	pathSet = set
	for i, c in cells do
		if not Grid.IsCore(c[1], c[2]) then
			local lx, lz = Grid.CellToLocal(c[1], c[2])
			local smash = blockers[Grid.Key(c[1], c[2])] ~= nil
			newPart({
				Size = Vector3.new(CS * 0.34, 0.08, CS * 0.34),
				CFrame = cf * CFrame.new(lx, 0.08, lz) * CFrame.Angles(0, math.rad(45), 0),
				Color = if smash then Color3.fromRGB(255, 140, 0) else Color3.fromRGB(255, 50, 50),
				Transparency = 0.25 + 0.35 * (i / #cells),
				Parent = pathFolder,
			})
		end
	end
end

-- Ghost / preview ---------------------------------------------------------------------

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	footprint.Transparency = 1
	confirmButton.Visible = false
	reasonLabel.Text = ""
	previewSet = false
end

local function updatePreview()
	local def, mut = currentDef()
	local cf = plotCFrame()
	if not def or not cf then
		clearGhost()
		return
	end
	if not ghost or ghost.Name ~= def.Id .. "|" .. tostring(mut) then
		if ghost then
			ghost:Destroy()
		end
		local g = ModelBuilder.BuildItem(def, mut, { Ghost = true })
		g.Name = def.Id .. "|" .. tostring(mut)
		g.Parent = overlay
		ghost = g
	end
	local s = { X = anchorX, Z = anchorZ, R = rot }
	local occ = Grid.BuildOccupancy(base().Structures, Items.ById, movingUid)
	status, statusReason = Grid.CheckPlacement({
		Region = region(),
		Occupancy = occ,
		Def = def,
		X = anchorX,
		Z = anchorZ,
		Rot = rot,
		PlacedCount = placedCount(),
		Capacity = State.Derived().Capacity or 0,
		IsMove = movingUid ~= nil,
		PathCells = pathSet,
	})
	local cx, cz = Grid.FootprintCenter(def, s.X, s.Z, s.R)
	local lx, lz = Grid.CellToLocal(cx, cz)
	local w, d = Grid.Footprint(def, rot);
	(ghost :: Model):PivotTo(cf * CFrame.new(lx, 0, lz) * CFrame.Angles(0, -rot * math.pi / 2, 0))
	footprint.Size = Vector3.new(w * CS - 0.2, 0.25, d * CS - 0.2)
	footprint.CFrame = cf * CFrame.new(lx, 0.14, lz)
	footprint.Color = STATUS_COLORS[status]
	footprint.Transparency = 0.45
	reasonLabel.Text = statusReason or ""
	reasonLabel.TextColor3 = STATUS_COLORS[status]
	previewSet = true
end

local function screenToCell(pos: Vector2): (number?, number?)
	local cf = plotCFrame()
	if not cf then
		return nil, nil
	end
	local ray = Workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
	local o = cf:PointToObjectSpace(ray.Origin)
	local d = cf:VectorToObjectSpace(ray.Direction)
	if math.abs(d.Y) < 1e-4 then
		return nil, nil
	end
	local t = -o.Y / d.Y
	if t <= 0 then
		return nil, nil
	end
	local hit = o + d * t
	return Grid.LocalToCellFloat(hit.X, hit.Z)
end

local function aimAt(pos: Vector2)
	local def = currentDef()
	if not def then
		return
	end
	local fx, fz = screenToCell(pos)
	if fx and fz then
		anchorX, anchorZ = Grid.AnchorFromPoint(def, rot, fx, fz)
		updatePreview()
	end
end

-- Actions -------------------------------------------------------------------------------

local renderHotbar: () -> ()
local renderPanel: () -> ()

function BuildController.CancelPlacement()
	placingKey = nil
	movingUid = nil
	clearGhost()
	renderHotbar()
end

local function confirm()
	if busy or not previewSet then
		return
	end
	if status == "Invalid" then
		Registry.NotifyController.Error(statusReason or "Can't place there")
		return
	end
	busy = true
	local ok, res
	if movingUid then
		ok, res = Net.Invoke("MoveStructure", movingUid, anchorX, anchorZ, rot)
	else
		ok, res = Net.Invoke("PlaceStructure", placingKey, anchorX, anchorZ, rot)
	end
	busy = false
	if not ok then
		Registry.NotifyController.Error(res)
		return
	end
	Registry.SoundController.Play("Place")
	if Registry.FxController then
		local cf = plotCFrame()
		local def = currentDef()
		if cf and def then
			local cx, cz = Grid.FootprintCenter(def, anchorX, anchorZ, rot)
			local lx, lz = Grid.CellToLocal(cx, cz)
			Registry.FxController.PlaceBurst((cf * CFrame.new(lx, 1, lz)).Position, Theme.Rarity(def.Rarity))
		end
	end
	if movingUid then
		movingUid = nil
		clearGhost()
	else
		BuildController.Placed:Fire(res)
		-- Keep placing the same stack while copies remain.
		local inv = State.Get("Inventory") or {}
		local stack = placingKey and inv[placingKey]
		if not stack or stack.Count <= 1 then
			placingKey = nil
			clearGhost()
		end
	end
	confirmButton.Visible = false
end

local function selectStructure(uid: string?)
	selectedUid = uid
	local m = plotModel()
	local structures = m and m:FindFirstChild("Structures")
	local model = if uid and structures then structures:FindFirstChild(uid) else nil
	selectionBox.Adornee = model :: any
	renderPanel()
end

local function trySelectAt(pos: Vector2)
	local m = plotModel()
	if not m then
		return
	end
	local ray = Workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { m:FindFirstChild("Structures") :: Instance }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then
		local inst: Instance? = hit.Instance
		while inst and inst.Parent ~= m:FindFirstChild("Structures") do
			inst = inst.Parent
		end
		if inst then
			selectStructure(inst.Name)
			return
		end
	end
	selectStructure(nil)
end

function BuildController.Rotate()
	rot = (rot + 1) % 4
	if previewSet then
		updatePreview()
	end
end

-- Camera ----------------------------------------------------------------------------

local function applyCamera()
	local cf = plotCFrame()
	if not cf then
		return
	end
	local r = region()
	local minX, minZ = Grid.CellToLocal(r.MinX, r.MinZ)
	local maxX, maxZ = Grid.CellToLocal(r.MaxX, r.MaxZ)
	camPanX = math.clamp(camPanX, minX, maxX)
	camPanZ = math.clamp(camPanZ, minZ, maxZ)
	camHeight = math.clamp(camHeight, 25, 150)
	local target = cf * Vector3.new(camPanX, 0, camPanZ)
	local eye = cf * Vector3.new(camPanX, camHeight, camPanZ + camHeight * 0.55)
	Workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, target)
end

local function resetCamera()
	local r = region()
	local _, midZ = Grid.CellToLocal(0, (r.MinZ + r.MaxZ) / 2)
	camPanX, camPanZ = 0, midZ + 6
	camHeight = math.max(r.Width, r.Length) * CS * 0.95
end

-- UI ----------------------------------------------------------------------------------

renderHotbar = function()
	for _, c in hotbar:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local entries = {}
	for key, stack in State.Get("Inventory") or {} do
		local itemId, mut = string.match(key, "^([%w_]+)|(%w+)$")
		local def = Items.Get(itemId or "")
		if def and stack.Count > 0 then
			table.insert(entries, { Key = key, Def = def, Mut = mut, Count = stack.Count })
		end
	end
	table.sort(entries, function(a, b)
		local ra, rb = Rarities.OrderOf(a.Def.Rarity), Rarities.OrderOf(b.Def.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		local ma, mb = Mutations.Get(a.Mut).Order, Mutations.Get(b.Mut).Order
		if ma ~= mb then
			return ma > mb
		end
		return a.Def.Order < b.Def.Order
	end)
	for i, e in entries do
		local color = Theme.Rarity(e.Def.Rarity)
		local selected = e.Key == placingKey
		local btn = UI.new("TextButton", {
			Name = e.Key,
			Text = "",
			Size = UDim2.fromOffset(96, 92),
			LayoutOrder = i,
			AutoButtonColor = true,
			BackgroundColor3 = if selected then color:Lerp(Theme.Panel, 0.4) else Theme.PanelLight,
			Parent = hotbar,
		}, { UI.Corner(8), UI.Stroke(color, if selected then 4 else 2) })
		UI.Label({ Text = e.Def.DisplayName, Size = UDim2.new(1, -8, 0, 30), Position = UDim2.new(0, 4, 1, -32), TextWrapped = true, MaxTextSize = 14, Parent = btn })
		UI.Label({ Text = "x" .. e.Count, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.FontBlack, MaxTextSize = 18, Parent = btn })
		UI.Label({ Text = Rarities.Get(e.Def.Rarity).Name, Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 26), TextColor3 = color, MaxTextSize = 12, Parent = btn })
		if e.Mut ~= Mutations.NormalId then
			UI.Label({ Text = string.upper(e.Mut), Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 40), TextColor3 = Theme.Mutation(e.Mut), MaxTextSize = 12, Parent = btn })
		end
		btn.Activated:Connect(function()
			UI.ClickSound()
			if placingKey == e.Key then
				BuildController.CancelPlacement()
				return
			end
			movingUid = nil
			placingKey = e.Key
			selectStructure(nil)
			clearGhost()
			renderHotbar()
			if not usingMouse then
				-- Touch: preview in the middle of the screen until the player taps a tile.
				aimAt(Workspace.CurrentCamera.ViewportSize / 2)
				confirmButton.Visible = true
			end
		end)
	end
	if #entries == 0 then
		UI.Label({ Text = "No items - go ROLL!", Size = UDim2.fromOffset(240, 90), TextColor3 = Theme.TextDim, Parent = hotbar })
	end
	local d = State.Derived()
	banner.Text = string.format("BUILD MODE   %d / %d placed   (%s)", placedCount(), d.Capacity or 0, d.TierName or "")
end

renderPanel = function()
	UI.Clear(panel)
	local s = selectedUid and base().Structures[selectedUid]
	if not s then
		panel.Visible = false
		selectionBox.Adornee = nil
		return
	end
	local uid = selectedUid :: string
	local def = Items.Get(s.Id)
	if not def then
		panel.Visible = false
		return
	end
	panel.Visible = true
	UI.List(Enum.FillDirection.Vertical, 6).Parent = panel
	local color = Theme.Rarity(def.Rarity)
	local level = s.Lvl or 1
	local maxLevel = ItemStats.MaxLevel(def)
	UI.Label({ Text = def.DisplayName, Size = UDim2.new(1, 0, 0, 26), Font = Theme.FontBlack, LayoutOrder = 1, Parent = panel })
	local sub = string.format("%s%s  -  Lv %d/%d", if s.Mut and s.Mut ~= "Normal" then s.Mut .. " " else "", Rarities.Get(def.Rarity).Name, level, maxLevel)
	UI.Label({ Text = sub, Size = UDim2.new(1, 0, 0, 18), TextColor3 = color, MaxTextSize = 16, LayoutOrder = 2, Parent = panel })
	local stats = ItemStats.Compute(def, level, s.Mut)
	local nextStats = if level < maxLevel then ItemStats.Compute(def, level + 1, s.Mut) else nil
	local lines = {}
	for _, line in ItemStats.Describe(def, stats) do
		local text = line[1] .. ": " .. line[2]
		if nextStats then
			for _, nl in ItemStats.Describe(def, nextStats) do
				if nl[1] == line[1] and nl[2] ~= line[2] then
					text ..= "  ->  " .. nl[2]
				end
			end
		end
		table.insert(lines, text)
	end
	UI.Label({
		Text = table.concat(lines, "\n"),
		Size = UDim2.new(1, 0, 0, 18 * #lines),
		Font = Theme.Font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextScaled = false,
		TextSize = 15,
		LayoutOrder = 3,
		Parent = panel,
	})
	UI.Label({ Text = def.Tip, Size = UDim2.new(1, 0, 0, 36), Font = Theme.Font, TextWrapped = true, TextColor3 = Theme.Accent, MaxTextSize = 13, LayoutOrder = 4, Parent = panel })
	if level < maxLevel then
		local cost = ItemStats.UpgradeCost(def, level)
		local affordable = (State.Get("Coins") or 0) >= cost
		UI.Button({
			Text = "UPGRADE  " .. Format.Abbrev(cost),
			Size = UDim2.new(1, 0, 0, 40),
			Color = if affordable then Theme.Good else Theme.PanelLighter,
			LayoutOrder = 5,
			Parent = panel,
			OnClick = function()
				local ok, res = Net.Invoke("UpgradeStructure", uid)
				if ok then
					Registry.SoundController.Play("Upgrade")
				else
					Registry.NotifyController.Error(res)
				end
			end,
		})
	else
		UI.Label({ Text = "MAX LEVEL", Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Accent, LayoutOrder = 5, Parent = panel })
	end
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = 6, Parent = panel }, {
		UI.List(Enum.FillDirection.Horizontal, 6),
	})
	UI.Button({
		Text = "MOVE",
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = Theme.Accent2:Lerp(Theme.Panel, 0.3),
		Parent = row,
		OnClick = function()
			placingKey = nil
			movingUid = uid
			rot = s.R or 0
			anchorX, anchorZ = s.X, s.Z
			selectStructure(nil)
			updatePreview()
			if not usingMouse then
				confirmButton.Visible = true
			end
		end,
	})
	UI.Button({
		Text = "STORE",
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = Theme.Bad:Lerp(Theme.Panel, 0.3),
		Parent = row,
		OnClick = function()
			local ok, res = Net.Invoke("StoreStructure", uid)
			if ok then
				selectStructure(nil)
				if res.Refund and res.Refund > 0 then
					Registry.NotifyController.Toast("Stored. Refunded " .. Format.Abbrev(res.Refund) .. " upgrade coins", "Reward")
				end
			else
				Registry.NotifyController.Error(res)
			end
		end,
	})
end

local function buildUI(root: ScreenGui)
	ui = UI.new("Frame", {
		Name = "BuildHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local top = UI.Panel({
		Size = UDim2.fromOffset(560, 60),
		Position = UDim2.new(0.5, 0, 0, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = ui,
	})
	banner = UI.Label({ Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 4), Font = Theme.FontBlack, MaxTextSize = 22, Parent = top })
	reasonLabel = UI.Label({ Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 34), MaxTextSize = 16, Parent = top })

	local bottom = UI.Panel({
		Size = UDim2.new(0.7, 0, 0, 112),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = ui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(820, 112), Parent = bottom })
	hotbar = UI.Scroll({
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 5,
		Parent = bottom,
	})
	UI.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = hotbar

	local buttons = UI.new("Frame", {
		Size = UDim2.fromOffset(120, 190),
		Position = UDim2.new(1, -12, 1, -130),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = ui,
	}, { UI.List(Enum.FillDirection.Vertical, 8) })
	UI.Button({ Text = "ROTATE [R]", Size = UDim2.fromOffset(120, 54), Color = Theme.Accent2:Lerp(Theme.Panel, 0.2), MaxTextSize = 18, LayoutOrder = 1, Parent = buttons, OnClick = BuildController.Rotate })
	UI.Button({ Text = "CANCEL [Q]", Size = UDim2.fromOffset(120, 54), LayoutOrder = 2, MaxTextSize = 18, Parent = buttons, OnClick = function()
		BuildController.CancelPlacement()
		selectStructure(nil)
	end })
	UI.Button({ Text = "EXIT [B]", Size = UDim2.fromOffset(120, 54), Color = Theme.Bad, LayoutOrder = 3, MaxTextSize = 18, Parent = buttons, OnClick = function()
		BuildController.Exit()
	end })

	confirmButton = UI.Button({
		Name = "Confirm",
		Text = "PLACE HERE",
		Size = UDim2.fromOffset(220, 60),
		Position = UDim2.new(0.5, 0, 1, -134),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = Theme.Good,
		MaxTextSize = 26,
		Visible = false,
		Parent = ui,
		OnClick = confirm,
	})

	panel = UI.Panel({
		Name = "Selection",
		Size = UDim2.fromOffset(260, 330),
		Position = UDim2.new(1, -12, 0, 130),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		Parent = ui,
	})
	UI.Padding(10).Parent = panel
end

-- Lifecycle ---------------------------------------------------------------------------

function BuildController.IsActive(): boolean
	return active
end

function BuildController.Enter(stackKey: string?)
	if not plotCFrame() then
		Registry.NotifyController.Error("Your base is still loading")
		return
	end
	Registry.HudController.Close()
	if not active then
		active = true
		ui.Visible = true
		Registry.HudController.SetMode("Build")
		rebuildGrid()
		rebuildPath()
		resetCamera()
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		renderConn = RunService.RenderStepped:Connect(function()
			applyCamera()
			if (placingKey or movingUid) and usingMouse then
				aimAt(UserInputService:GetMouseLocation())
			end
		end)
	end
	placingKey = stackKey
	movingUid = nil
	selectStructure(nil)
	clearGhost()
	renderHotbar()
	if stackKey and not usingMouse then
		aimAt(Workspace.CurrentCamera.ViewportSize / 2)
		confirmButton.Visible = true
	end
	BuildController.Entered:Fire(stackKey)
end

function BuildController.Exit()
	if not active then
		return
	end
	active = false
	placingKey, movingUid = nil, nil
	clearGhost()
	selectStructure(nil)
	ui.Visible = false
	gridFolder:ClearAllChildren()
	pathFolder:ClearAllChildren()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	Registry.HudController.SetMode("Normal")
	BuildController.Exited:Fire()
end

function BuildController.Toggle()
	if active then
		BuildController.Exit()
	else
		BuildController.Enter(nil)
	end
end

function BuildController.Init()
	overlay = Instance.new("Folder")
	overlay.Name = "BuildOverlay"
	overlay.Parent = Workspace
	gridFolder = Instance.new("Folder")
	gridFolder.Name = "Grid"
	gridFolder.Parent = overlay
	pathFolder = Instance.new("Folder")
	pathFolder.Name = "Path"
	pathFolder.Parent = overlay
	footprint = newPart({ Name = "Footprint", Size = Vector3.new(4, 0.25, 4), Transparency = 1, Parent = overlay })
	selectionBox = Instance.new("SelectionBox")
	selectionBox.Color3 = Theme.Accent
	selectionBox.LineThickness = 0.12
	selectionBox.Parent = overlay

	buildUI(Registry.HudController.Root())

	State.Watch({ "Base", "Inventory", "Derived", "Coins" }, function()
		if not active then
			return
		end
		rebuildGrid()
		rebuildPath()
		renderHotbar()
		renderPanel()
		if previewSet then
			updatePreview()
		end
	end)

	-- Mouse / keyboard
	local rightDown = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDown = true
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			BuildController.Toggle()
			return
		end
		if not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			BuildController.Rotate()
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
			if placingKey or movingUid then
				BuildController.CancelPlacement()
			else
				selectStructure(nil)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if placingKey or movingUid then
				aimAt(UserInputService:GetMouseLocation())
				confirm()
			else
				trySelectAt(UserInputService:GetMouseLocation())
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDown = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			camHeight -= input.Position.Z * 6
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and rightDown then
			local k = camHeight / 400
			camPanX -= input.Delta.X * k
			camPanZ -= input.Delta.Y * k
		end
	end)

	-- Touch
	UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
		if not active or processedByUI then
			return
		end
		if placingKey or movingUid then
			aimAt(pos)
			confirmButton.Visible = true
		else
			trySelectAt(pos)
		end
	end)
	local lastPan = Vector2.zero
	UserInputService.TouchPan:Connect(function(positions, translation, _velocity, state, processed)
		if not active or processed or #positions ~= 1 then
			return
		end
		-- translation is cumulative; convert to per-event delta.
		if state == Enum.UserInputState.Begin then
			lastPan = Vector2.zero
		end
		local delta = translation - lastPan
		lastPan = translation
		local k = camHeight / 300
		camPanX -= delta.X * k
		camPanZ -= delta.Y * k
	end)
	local pinchStart = camHeight
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if not active or processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = camHeight
		end
		camHeight = pinchStart / math.max(scale, 0.1)
	end)
end

return BuildController

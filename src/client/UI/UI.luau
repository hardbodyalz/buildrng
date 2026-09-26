--[[
	UI
	Declarative-ish instance builder + the handful of styled components every
	screen uses. Everything is built in code (no hand-made GUI assets), sized
	with Scale + UIScale so it works from phones to monitors.

	UI.new(className, props, children)
	  props: any writable property; function values bound to events of the
	  same name (e.g. Activated = fn). Parent is applied last.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModelBuilder = require(Shared.Util.ModelBuilder)
local Theme = require(script.Parent.Theme)

local UI = {}

-- Hook set by SoundController so every button clicks.
UI.ClickSound = function() end

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif type(value) == "function" then
				(inst :: any)[key]:Connect(value)
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.Tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

function UI.Corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function UI.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.Padding(all: number, top: number?, bottom: number?, left: number?, right: number?): UIPadding
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, top or all),
		PaddingBottom = UDim.new(0, bottom or all),
		PaddingLeft = UDim.new(0, left or all),
		PaddingRight = UDim.new(0, right or all),
	})
end

function UI.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UI.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function UI.Label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Text = "",
	}
	for k, v in props do
		if k ~= "MaxTextSize" then
			defaults[k] = v
		end
	end
	local label = UI.new("TextLabel", defaults)
	if defaults.TextScaled then
		UI.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 28, MinTextSize = 8, Parent = label })
	end
	return label
end

-- Styled button with press feedback. props.Color = background.
function UI.Button(props: { [string]: any }): TextButton
	local color = props.Color or Theme.PanelLight
	local onClick = props.OnClick
	local btn = UI.new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(120, 44),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = props.Text or "",
		TextColor3 = props.TextColor or Theme.Text,
		Font = props.Font or Theme.FontBlack,
		TextScaled = true,
		Visible = if props.Visible == nil then true else props.Visible,
		ZIndex = props.ZIndex,
		Parent = props.Parent,
	}, {
		UI.Corner(props.Radius or 10),
		UI.Stroke(props.StrokeColor or color:Lerp(Color3.new(0, 0, 0), 0.35), props.StrokeThickness or 2),
		UI.Padding(props.TextPadding or 6),
		UI.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 24, MinTextSize = 8 }),
		UI.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
	})
	local scale = UI.new("UIScale", { Parent = btn })
	btn.MouseEnter:Connect(function()
		UI.Tween(scale, 0.1, { Scale = 1.04 })
	end)
	btn.MouseLeave:Connect(function()
		UI.Tween(scale, 0.1, { Scale = 1 })
	end)
	btn.MouseButton1Down:Connect(function()
		UI.Tween(scale, 0.06, { Scale = 0.94 })
	end)
	btn.MouseButton1Up:Connect(function()
		UI.Tween(scale, 0.1, { Scale = 1 })
	end)
	if onClick then
		btn.Activated:Connect(function()
			UI.ClickSound()
			onClick()
		end)
	end
	return btn
end

function UI.SetButtonColor(btn: TextButton, color: Color3)
	btn.BackgroundColor3 = color
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
	end
end

-- Remove a container's content but keep its decoration (corner, stroke,
-- padding, size constraints, scale). Layouts are removed so callers re-add them.
local KEEP = {
	UICorner = true,
	UIStroke = true,
	UIPadding = true,
	UISizeConstraint = true,
	UIScale = true,
	UIGradient = true,
}
function UI.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if not KEEP[child.ClassName] then
			child:Destroy()
		end
	end
end

-- Rounded dark panel.
function UI.Panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}
	for k, v in props do
		if k ~= "Radius" and k ~= "StrokeColor" then
			defaults[k] = v
		end
	end
	local frame = UI.new("Frame", defaults)
	UI.Corner(props.Radius or 12).Parent = frame
	UI.Stroke(props.StrokeColor or Theme.Stroke, 2, 0.2).Parent = frame
	return frame
end

-- Horizontal progress bar. Returns container, fill, label.
function UI.Bar(props: { [string]: any }): (Frame, Frame, TextLabel)
	local container = UI.new("Frame", {
		Name = props.Name or "Bar",
		Size = props.Size or UDim2.new(1, 0, 0, 16),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = props.BackColor or Color3.fromRGB(12, 12, 18),
		BorderSizePixel = 0,
		Parent = props.Parent,
	}, { UI.Corner(props.Radius or 8) })
	local fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = props.Color or Theme.Good,
		BorderSizePixel = 0,
		Parent = container,
	}, { UI.Corner(props.Radius or 8), UI.Gradient(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180)) })
	local label = UI.Label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		TextStrokeTransparency = 0.4,
		MaxTextSize = props.MaxTextSize or 16,
		Parent = container,
	})
	return container, fill, label
end

function UI.SetBar(fill: Frame, frac: number, animate: boolean?)
	frac = math.clamp(frac, 0, 1)
	if animate then
		UI.Tween(fill, 0.2, { Size = UDim2.fromScale(frac, 1) })
	else
		fill.Size = UDim2.fromScale(frac, 1)
	end
end

-- Window: centered panel with title + close button. Returns frame, content.
function UI.Window(props: { [string]: any }): (Frame, Frame)
	local frame = UI.Panel({
		Name = props.Name,
		Size = props.Size or UDim2.fromScale(0.62, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 10,
		Parent = props.Parent,
	})
	UI.new("UISizeConstraint", { MaxSize = props.MaxSize or Vector2.new(980, 640), MinSize = Vector2.new(300, 260), Parent = frame })
	local header = UI.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = props.HeaderColor or Theme.PanelLight,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UI.Corner(12) })
	UI.Label({
		Text = props.Title or "",
		Size = UDim2.new(1, -110, 1, -10),
		Position = UDim2.fromOffset(16, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.FontBlack,
		MaxTextSize = 26,
		Parent = header,
	})
	local close = UI.Button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(1, -6, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Bad,
		Parent = header,
		OnClick = props.OnClose,
	})
	close.ZIndex = 12
	local content = UI.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -20, 1, -60),
		Position = UDim2.fromOffset(10, 52),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	return frame, content
end

-- ScrollingFrame with auto canvas.
function UI.Scroll(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for k, v in props do
		defaults[k] = v
	end
	return UI.new("ScrollingFrame", defaults)
end

-- ViewportFrame showing a spinning-free preview of an item model.
function UI.ItemViewport(def: any, mutationId: string?, props: { [string]: any }?): ViewportFrame
	local vp = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1.5, -1),
	})
	if props then
		for k, v in props do
			(vp :: any)[k] = v
		end
	end
	local ok, model = pcall(ModelBuilder.BuildItem, def, mutationId, { Ghost = false })
	if ok and model then
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
				d:Destroy()
			end
		end
		model.Parent = vp
		local cf, size = model:GetBoundingBox()
		local radius = size.Magnitude * 0.5
		local cam = Instance.new("Camera")
		cam.FieldOfView = 40
		local dist = radius / math.tan(math.rad(20)) * 1.05
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.6, dist * 0.55, dist * 0.6), cf.Position)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end
	return vp
end

return UI

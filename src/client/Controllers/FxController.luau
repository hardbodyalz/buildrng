--[[
	FxController
	Turns batched server combat events into visuals and sound: tracers,
	explosions, beams, chain lightning, frost pulses, deaths, coin pop-ups,
	wave / boss banners and camera shake. Everything uses pooled parts with a
	hard cap so big fights stay smooth on low-end mobile.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Config.Items)
local Grid = require(Shared.Util.Grid)
local UI = require(script.Parent.Parent.UI.UI)
local Theme = require(script.Parent.Parent.UI.Theme)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)

local player = Players.LocalPlayer
local CS = GameConfig.Grid.CellSize
local HIDDEN = CFrame.new(0, -600, 0)
local MAX_ACTIVE = 220

local FxController = {}

local folder: Folder
local pools: { [string]: { BasePart } } = { Block = {}, Ball = {}, Cylinder = {} }
local activeCount = 0
local lastPulse: { [string]: number } = {}
local lastPopup = 0

local function newPart(shape: string): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Transparency = 1
	p.CFrame = HIDDEN
	p.Parent = folder
	return p
end

local function take(shape: string): BasePart?
	if activeCount >= MAX_ACTIVE then
		return nil
	end
	activeCount += 1
	local pool = pools[shape]
	return table.remove(pool) or newPart(shape)
end

local function give(shape: string, p: BasePart)
	activeCount -= 1
	p.Transparency = 1
	p.CFrame = HIDDEN
	table.insert(pools[shape], p)
end

local function fade(shape: string, p: BasePart, life: number, goal: { [string]: any }?)
	local g = goal or {}
	g.Transparency = 1
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), g):Play()
	task.delay(life, give, shape, p)
end

function FxController.Tracer(from: Vector3, to: Vector3, color: Color3, width: number, life: number)
	local p = take("Block")
	if not p then
		return
	end
	local dist = (to - from).Magnitude
	p.Size = Vector3.new(width, width, math.max(dist, 0.1))
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	p.Color = color
	p.Transparency = 0.05
	fade("Block", p, life)
end

function FxController.Burst(pos: Vector3, radius: number, color: Color3, life: number)
	local p = take("Ball")
	if not p then
		return
	end
	p.Size = Vector3.one * math.max(radius * 0.4, 0.3)
	p.CFrame = CFrame.new(pos)
	p.Color = color
	p.Transparency = 0.2
	fade("Ball", p, life, { Size = Vector3.one * radius * 2 })
end

function FxController.Ring(pos: Vector3, radius: number, color: Color3, life: number)
	local p = take("Cylinder")
	if not p then
		return
	end
	p.Size = Vector3.new(0.2, 1, 1)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	p.Color = color
	p.Transparency = 0.4
	fade("Cylinder", p, life, { Size = Vector3.new(0.2, radius * 2, radius * 2) })
end

function FxController.PlaceBurst(pos: Vector3, color: Color3)
	FxController.Ring(pos - Vector3.new(0, 0.9, 0), 5, color, 0.4)
	FxController.Burst(pos, 2.5, color, 0.3)
end

function FxController.Popup(pos: Vector3, text: string, color: Color3)
	local now = os.clock()
	if now - lastPopup < 0.08 then
		return
	end
	lastPopup = now
	local anchor = take("Block")
	if not anchor then
		return
	end
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(pos)
	anchor.Transparency = 1
	local gui = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(80, 30),
		StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
		MaxDistance = 150,
		Adornee = anchor,
		Parent = anchor,
	})
	local label = UI.Label({ Text = text, TextColor3 = color, Font = Theme.FontBlack, TextStrokeTransparency = 0.2, MaxTextSize = 22, Parent = gui })
	UI.Tween(gui, 0.8, { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) })
	UI.Tween(label, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(0.8, function()
		gui:Destroy()
		give("Block", anchor)
	end)
end

-- Camera shake via Humanoid.CameraOffset (only in the normal camera).
local shakeUntil, shakeAmount = 0, 0
function FxController.Shake(intensity: number, duration: number)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
	shakeAmount = math.max(shakeAmount, intensity)
end

local function plotModel(plotId: number): Model?
	local plots = Workspace:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. plotId) :: Model?
end

local function cellPos(cf: CFrame, x: number, z: number, y: number): Vector3
	local lx, lz = Grid.CellToLocal(x, z)
	return (cf * CFrame.new(lx, y, lz)).Position
end

-- Muzzle position of a structure, and turn its head toward `target`.
local function muzzle(plot: Model, uid: string, target: Vector3?): Vector3?
	local structures = plot:FindFirstChild("Structures")
	local model = structures and structures:FindFirstChild(uid) :: Model?
	if not model or not model.PrimaryPart then
		return nil
	end
	local head = model:FindFirstChild("Head") :: Model?
	if head and head.PrimaryPart then
		local pivot = head.PrimaryPart.Position
		if target then
			head:PivotTo(CFrame.lookAt(pivot, Vector3.new(target.X, pivot.Y, target.Z)))
		end
		return pivot
	end
	local def = Items.Get(model:GetAttribute("ItemId") or "")
	local h = if def then def.FxHeight * CS else 2
	return model.PrimaryPart.Position + Vector3.new(0, h, 0)
end

local function rarityColorOf(plot: Model, uid: string): Color3
	local structures = plot:FindFirstChild("Structures")
	local model = structures and structures:FindFirstChild(uid)
	local def = model and Items.Get(model:GetAttribute("ItemId") or "")
	return if def then Theme.Rarity(def.Rarity) else Theme.Accent
end

local function handle(plotId: number, plot: Model, cf: CFrame, ev: any, own: boolean)
	local k = ev.k
	local sound = Registry.SoundController
	if k == "fx" then
		local kind = ev.kind
		if kind == "shot" then
			local to = cellPos(cf, ev.x, ev.z, 2)
			local from = muzzle(plot, ev.s, to)
			if from then
				FxController.Tracer(from, to, Color3.fromRGB(255, 236, 150), 0.14, 0.08)
				sound.Play("Shot", { Position = from, Throttle = 0.07 })
			end
		elseif kind == "splash" then
			local to = cellPos(cf, ev.x, ev.z, 1)
			local from = muzzle(plot, ev.s, to)
			if from then
				FxController.Tracer(from, to, Color3.fromRGB(60, 60, 60), 0.35, 0.12)
			end
			FxController.Burst(to, (ev.r or 1) * CS * 0.8, Color3.fromRGB(255, 140, 40), 0.35)
			sound.Play("Cannon", { Position = to, Throttle = 0.12 })
		elseif kind == "beam" then
			local to = cellPos(cf, ev.x, ev.z, 2)
			local from = muzzle(plot, ev.s, to)
			if from then
				FxController.Tracer(from, Vector3.new(to.X, from.Y * 0.5 + to.Y * 0.5, to.Z), rarityColorOf(plot, ev.s), 0.55, 0.22)
				sound.Play("Laser", { Position = from, Throttle = 0.1 })
			end
		elseif kind == "chain" then
			local pts = ev.pts or {}
			local first = if #pts >= 2 then cellPos(cf, pts[1], pts[2], 2) else nil
			local prev = muzzle(plot, ev.s, first)
			for i = 1, #pts - 1, 2 do
				local p = cellPos(cf, pts[i], pts[i + 1], 2)
				if prev then
					local mid = (prev + p) / 2 + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.5
					FxController.Tracer(prev, mid, Color3.fromRGB(140, 230, 255), 0.25, 0.15)
					FxController.Tracer(mid, p, Color3.fromRGB(140, 230, 255), 0.25, 0.15)
				end
				prev = p
			end
			sound.Play("Zap", { Position = first, Throttle = 0.1 })
		elseif kind == "pulse" then
			local now = os.clock()
			local key = plotId .. ev.s
			if not lastPulse[key] or now - lastPulse[key] > 0.9 then
				lastPulse[key] = now
				local from = muzzle(plot, ev.s, nil)
				if from then
					FxController.Ring(Vector3.new(from.X, cf.Position.Y + 0.3, from.Z), (ev.r or 2) * CS, Color3.fromRGB(150, 225, 255), 0.6)
				end
			end
		elseif kind == "trap" then
			local from = muzzle(plot, ev.s, nil)
			if from then
				FxController.Burst(from + Vector3.new(0, 0.6, 0), 1.6, Color3.fromRGB(255, 70, 70), 0.15)
			end
		end
	elseif k == "kill" then
		local pos = cellPos(cf, ev.x, ev.z, 1.5)
		FxController.Burst(pos, if ev.boss then 12 else 1.8, if ev.boss then Theme.Accent else Color3.fromRGB(200, 200, 200), if ev.boss then 0.8 else 0.25)
		sound.Play("EnemyDeath", { Position = pos, Throttle = 0.05 })
		if own and ev.coins and ev.coins > 0 then
			FxController.Popup(pos, "+" .. ev.coins, Theme.Coins)
		end
		if ev.boss and own then
			FxController.Shake(1.2, 0.8)
		end
	elseif k == "destroyed" then
		local structures = plot:FindFirstChild("Structures")
		local model = structures and structures:FindFirstChild(ev.uid) :: Model?
		if model and model.PrimaryPart then
			FxController.Burst(model.PrimaryPart.Position + Vector3.new(0, 1.5, 0), 5, Color3.fromRGB(140, 110, 80), 0.5)
			sound.Play("StructureDestroyed", { Position = model.PrimaryPart.Position })
		end
		if own then
			FxController.Shake(0.4, 0.3)
		end
	elseif k == "coreHit" then
		local ground = plot:FindFirstChild("Ground")
		local core = ground and ground:FindFirstChild("Core")
		local crystal = core and core:FindFirstChild("Crystal") :: BasePart?
		if crystal then
			FxController.Burst(crystal.Position, 6, Theme.Bad, 0.4)
			sound.Play("CoreHit", { Position = crystal.Position })
		end
		if own then
			FxController.Shake(0.8, 0.35)
		end
	elseif own and k == "waveStart" then
		if ev.boss then
			Registry.NotifyController.Banner("BOSS INCOMING", Theme.Bad, string.upper(ev.bossName or "") .. "  -  wave " .. ev.wave, 3)
			sound.Play("BossPhase")
			FxController.Shake(1, 1)
			sound.PlayMusic(ev.music)
		else
			Registry.NotifyController.Banner("WAVE " .. ev.wave, Theme.Text, nil, 1.4)
		end
	elseif own and k == "waveCleared" then
		Registry.NotifyController.Banner("WAVE " .. ev.wave .. " CLEARED", Theme.Good, "+" .. ev.bonus .. " coins", 1.6)
		sound.Play("WaveCleared")
		sound.StopMusic()
	elseif own and k == "bossPhase" then
		if ev.text then
			Registry.NotifyController.Banner(string.upper(ev.name or ""), Theme.Warn, ev.text, 2.5)
		end
		sound.Play("BossPhase")
		FxController.Shake(1, 0.6)
	elseif own and k == "coreDestroyed" then
		FxController.Shake(2, 1)
		sound.Play("CoreHit", { Pitch = 0.5 })
	end
end

function FxController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = Workspace

	Net.On("DefenseEvents", function(payload)
		if type(payload) ~= "table" or type(payload.Events) ~= "table" then
			return
		end
		local plot = plotModel(payload.PlotId)
		if not plot or not plot.PrimaryPart then
			return
		end
		local own = payload.PlotId == player:GetAttribute("PlotId")
		local cf = plot.PrimaryPart.CFrame
		for _, ev in payload.Events do
			local ok, err = pcall(handle, payload.PlotId, plot, cf, ev, own)
			if not ok then
				warn("[FxController] " .. tostring(err))
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		if os.clock() < shakeUntil then
			local a = shakeAmount
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, (math.random() - 0.5) * a)
		elseif shakeAmount > 0 then
			shakeAmount = 0
			hum.CameraOffset = Vector3.zero
		end
	end)
end

return FxController

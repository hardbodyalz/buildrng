--[[
	SoundController
	Plays entries from Config/Sounds. Non-positional (SoundService) with
	distance attenuation when a world position is given, and per-sound
	throttling so a machine-gun nest can't spam 60 sounds a second.
]]

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local UI = require(script.Parent.Parent.UI.UI)

local SoundController = {}

local lastPlayed: { [string]: number } = {}
local MIN_INTERVAL = 0.06
local music: Sound? = nil

local function play(entry: any, key: string, opts: { [string]: any }?)
	if not entry or not entry.Id or entry.Id == "" then
		return
	end
	local now = os.clock()
	local throttle = (opts and opts.Throttle) or MIN_INTERVAL
	if lastPlayed[key] and now - lastPlayed[key] < throttle then
		return
	end
	lastPlayed[key] = now
	local volume = (entry.Volume or 0.5) * ((opts and opts.Volume) or 1)
	if opts and opts.Position then
		local cam = Workspace.CurrentCamera
		local dist = (cam.CFrame.Position - opts.Position).Magnitude
		volume *= math.clamp(1 - dist / 220, 0, 1)
		if volume <= 0.01 then
			return
		end
	end
	local s = Instance.new("Sound")
	s.SoundId = entry.Id
	s.Volume = volume
	s.PlaybackSpeed = (entry.Pitch or 1) * ((opts and opts.Pitch) or 1)
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function SoundController.Play(name: string, opts: { [string]: any }?)
	play(Sounds[name], name, opts)
end

function SoundController.PlayReveal(tier: number)
	for t = 1, math.clamp(tier, 1, 6) do
		-- Higher tiers layer every lower tier's sound for an escalating hit.
		if t == tier or t >= 3 then
			play(Sounds.Reveal[t], "Reveal" .. t, { Throttle = 0 })
		end
	end
end

function SoundController.PlayMusic(id: string?)
	SoundController.StopMusic()
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0.4
	s.Parent = SoundService
	s:Play()
	music = s
end

function SoundController.StopMusic()
	if music then
		music:Destroy()
		music = nil
	end
end

function SoundController.Init()
	UI.ClickSound = function()
		SoundController.Play("UIClick")
	end
end

return SoundController

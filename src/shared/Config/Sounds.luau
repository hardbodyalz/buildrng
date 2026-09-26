--[[
	Sounds
	Central sound table. The defaults use sounds that ship inside the Roblox
	client (rbxasset://) so the slice makes noise out of the box; swap in
	uploaded rbxassetid:// ids for the real audio identity (see docs/DESIGN.md).
	Missing/invalid ids fail silently in SoundController.
]]

local Sounds = {
	UIClick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.4 },
	RollTick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25 },
	Place = { Id = "rbxasset://sounds/button.wav", Volume = 0.5 },
	Invalid = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 0.5 },
	Sell = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 1.4 },
	Upgrade = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.2 },

	-- Reveal sounds by rarity RevealTier (1..6). Layers stack for higher tiers.
	Reveal = {
		[1] = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 1 },
		[2] = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.25 },
		[3] = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, Pitch = 0.8 },
		[4] = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.6, Pitch = 0.7 },
		[5] = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.8, Pitch = 0.45 },
		[6] = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 1, Pitch = 0.3 },
	},

	-- Combat (played at world positions, throttled client-side).
	Shot = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.15, Pitch = 2.2 },
	Cannon = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.35, Pitch = 0.9 },
	Laser = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 0.6 },
	Zap = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 2 },
	EnemyDeath = { Id = "rbxasset://sounds/collide.wav", Volume = 0.2, Pitch = 1.3 },
	CoreHit = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Pitch = 0.6 },
	StructureDestroyed = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Pitch = 0.5 },
	WaveCleared = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 0.9 },
	BossPhase = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.8, Pitch = 0.35 },

	-- Music (empty = none). Boss-specific music lives on the boss definition (MusicId).
	DefaultBossMusic = { Id = "", Volume = 0.4 },
}

return Sounds

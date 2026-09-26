--[[
	RateLimiter
	Per-player token buckets keyed by bucket name (see GameConfig.RateLimits).
]]

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.GameConfig)

local RateLimiter = {}

local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

function RateLimiter.Allow(player: Player, bucketName: string): boolean
	local cfg = GameConfig.RateLimits[bucketName] or GameConfig.RateLimits.Default
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local b = playerBuckets[bucketName]
	if not b then
		b = { tokens = cfg.Burst, last = now }
		playerBuckets[bucketName] = b
	end
	b.tokens = math.min(cfg.Burst, b.tokens + (now - b.last) * cfg.Rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function RateLimiter.Clear(player: Player)
	buckets[player] = nil
end

return RateLimiter

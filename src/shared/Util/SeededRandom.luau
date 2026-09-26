--[[
	SeededRandom
	Tiny deterministic PRNG (xorshift32) usable outside Roblox (tests) and
	for reproducible content like procedural waves. Not for reward rolls -
	RollService uses Roblox's Random.
]]

local SeededRandom = {}

function SeededRandom.new(seed: number): () -> number
	local state = bit32.band(math.floor(seed) * 2654435761 + 1, 0xFFFFFFFF)
	if state == 0 then
		state = 0x9E3779B9
	end
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

return SeededRandom

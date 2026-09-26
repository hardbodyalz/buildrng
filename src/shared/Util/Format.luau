--[[
	Format
	Number/time/odds formatting for UI.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.Abbrev(n: number): string
	n = n or 0
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local fmt = if n >= 100 then "%.0f%s" elseif n >= 10 then "%.1f%s" else "%.2f%s"
	return sign .. string.format(fmt, n, SUFFIXES[i])
end

function Format.Commas(n: number): string
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

function Format.OneIn(chance: number): string
	if chance <= 0 then
		return "-"
	end
	local n = 1 / chance
	if n < 10 then
		return string.format("1 in %.1f", n)
	end
	return "1 in " .. Format.Commas(math.floor(n + 0.5))
end

function Format.Date(t: number): string
	return os.date("%Y-%m-%d", t) :: string
end

return Format

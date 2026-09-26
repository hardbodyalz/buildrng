--[[
	Validate
	Tiny guards for untrusted remote arguments.
]]

local Validate = {}

function Validate.Int(v: any, min: number, max: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= min and v <= max
end

function Validate.String(v: any, maxLen: number): boolean
	return type(v) == "string" and #v > 0 and #v <= maxLen
end

function Validate.Bool(v: any): boolean
	return type(v) == "boolean"
end

return Validate

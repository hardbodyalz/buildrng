--[[
	Registry
	Services register themselves here at boot (see init.server.luau) so they
	can reference each other at call time without circular requires.
]]
return {} :: { [string]: any }

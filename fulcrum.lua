package.path = package.path .. ";?.lua"

if not arg[1] then
	print("Usage: fulcrum (config.lc)")
	return
end

local fulcrum = require "fulcrum.master"

fulcrum.init(arg[1])
fulcrum.run()
#! /usr/bin/env luajit

package.path = package.path .. ";?.lua"

if not arg[1] then
	print("Usage: fulcrum (config.lc)")
	return
end

local fulcrum = require "fulcrum.master"

local ok, err = fulcrum.init(arg[1])
if not ok then
	print(err)
	os.exit(1)
end

fulcrum.main_loop()
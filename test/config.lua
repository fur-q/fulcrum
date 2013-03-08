local lc = require "lc"

local cfg = { username = "lc", reconnect = false }

lc.load("example.lc", cfg)

assert(cfg.hostname == "localhost")
assert(cfg.username == "lc")
assert(cfg.reconnect == true)
assert(cfg.attempts == 10)
assert(cfg.ignore[1] == "user1")
assert(cfg.ignore[2] == "user2")
assert(cfg.channels[1] == "#channel1")
assert(cfg.channels[4] == "#channel4")

local out, err = lc.load("example2.lc", nil)
print(out, err)
if out then table.foreach(out, print) end
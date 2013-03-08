local log = require "fulcrum.log"

local sl = log.new("syslog")
local fl = log.new()

sl:open("fulcrumtest", log.INFO)
fl:open("fulcrumtest.log", log.INFO)

sl("Testing, %s, %d %d %d", "testing", 1, 2, 3)
fl("Testing, %s, %d %d %d", "testing", 1, 2, 3)

sl:write(log.WARN, "This is another test")
fl:write(log.WARN, "This is another test")

sl:write(log.DEBUG, "This should never be seen")
fl:write(log.DEBUG, "This should never be seen")

sl:close()
fl:close()

-- test attempted write before open/after close


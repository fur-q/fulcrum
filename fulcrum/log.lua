local ffi = require "ffi"

ffi.cdef [[
	int  setlogmask(int mask);
    void openlog(const char *ident, int option, int facility);
    void syslog(int priority, const char *format, ...);
    void closelog(void);
]]

local FACILITY = 24     -- LOG_DAEMON
local OPTIONS  = 0      -- nothing for now
local levels   = { 'EMERG', 'ALERT', 'CRIT', 'ERR', 'WARNING', 'NOTICE', 'INFO', 'DEBUG' }

local syslog, filelog = {}, {}

for i,v in pairs(levels) do
    syslog[v]  = i-1
    filelog[v] = i-1
end

local function log_makepri(fac, pri)
	return bit.bor(bit.lshift(fac, 3), pri)
end

local function log_upto(pri)
	return bit.lshift(1, pri+1) - 1
end

local function is_pri(pri)
	return type(pri) == "number" and pri >= syslog.EMERG and pri <= syslog.DEBUG and pri
end

local function quicklog(self, fmt, ...)
	self:write(log.INFO, fmt, ...)
end

function syslog:open(name, max)
	ffi.C.setlogmask(log_upto(is_pri(max) or syslog.INFO))
    ffi.C.openlog(name, OPTIONS, FACILITY)
    return true
end

function syslog:write(pri, fmt, ...)
	pri = is_pri(pri) or syslog.INFO
    ffi.C.syslog(log_makepri(FACILITY, pri), fmt, ...)
end

function syslog:close()
    ffi.C.closelog()
end

function filelog:open(name, max)
	self.max  = is_pri(max) or syslog.INFO
	if io.type(name) == "file" then
		self.file = name
		return true
	end
	local fd, err = io.open(name, "a")
	if not fd then return false, err end
	self.file = fd
	return true
end

function filelog:write(pri, fmt, ...)
	pri = is_pri(pri) or log.INFO
	if io.type(self.file) ~= "file" then
		return false, "Log file closed"
	end
	self.file:write(os.date("%Y-%m-%d %H:%M:%S "), string.format(fmt, ...), "\n")
	self.file:flush()
end

function filelog:close()
	self.file:close()
end

return { 
	new = function(where)
		return where == "syslog" and setmetatable({}, { __index = syslog }) or
	    	                         setmetatable({}, { __index = filelog})	
	end 
}
local cqueues = require "cqueues"
local socket  = require "cqueues.socket"
local signal  = require "cqueues.signal"
local thread  = require "cqueues.thread"
local config  = require "fulcrum.config"
local daemon  = require "fulcrum.daemon"
local worker  = require "fulcrum.worker"
local log     = require "fulcrum.log"

local fulcrum = {}

local workers, cq = {}, cqueues.new()
local cfg, logger, master

function fulcrum.init(lc)
	cfg, err = assert((config(lc)), ";_;")
	daemon(cfg)
	logger, err = assert(log.new(cfg.error_log))
	assert(logger:open(cfg.error_log or io.stdout, log.INFO))
	fulcrum.cfg, fulcrum.log = cfg, log
end

function fulcrum.run()
	local master  = assert(socket.listen { path = "/tmp/fulcrum.sock" })
	local workers = {}
	local cq      = cqueues.new()

	-- spawn threads

    local function spawn_thread(i)
    	local thr, ipc, err = thread.start(worker, i)
		workers[ipc] = thr
		ipc:sendfd("fd", master)
		cq:wrap(function()
			local x, err = ipc:read()
			log("Child %d respawning: %s", i, err)
			spawn_thread(i)
		end)
	end

	for i = 1, (cfg.threads or 1) do
		spawn_thread(i)
	end

	-- handle signals

    cq:wrap(function()
        local sl = signal.listen(signal.SIGHUP, signal.SIGQUIT)
        signal.block(signal.SIGHUP, signal.SIGQUIT)

        while true do
            local sig = sl:wait()
            if sig == signal.SIGHUP then
            	log("SIGINT received; reloading the config")
            	-- reload()
            elseif sig == signal.SIGQUIT then
            	log("SIGQUIT received; shutting down gracefully")
            	master:close()
            	for k, _ in ipairs(workers) do
            		k:close()
            	end
            end
        end
    end)

    -- start mainloop

	while not cq:empty() do
	    local ok, err = cq:step()
	    if not ok then
	    	log(err)
	    end
	end

	log("Shutting down")

end

return fulcrum
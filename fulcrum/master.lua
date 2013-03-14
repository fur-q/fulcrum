local cqueues = require "cqueues"
local socket  = require "cqueues.socket"
local signal  = require "cqueues.signal"
local worker  = require "fulcrum.worker"
local config  = require "fulcrum.config"
local daemon  = require "fulcrum.daemon"
local logger  = require "fulcrum.log"
local ffi     = require "ffi"

FC_VERSION = "fulcrum/0.1"
local sf = string.format

getmetatable("").__mod = function(s, t) return type(t) == "table" and sf(s, unpack(t)) or sf(s, t) end

local fc = {
    alive   = false,
    workers = {},
    cq      = cqueues.new()
}

function fc.load(path)
    local cfg, err = config(path)
    if not cfg then return nil, err end
    if not cfg.apps then return nil, "No apps set in config" end
    fc.path, fc.cfg = path, cfg

    -- change gid/uid before we open any files
    if cfg.group then
        ok, err = daemon.setgroup(cfg.group)
        if not ok then return nil, err end
    end

    if cfg.user then
        ok, err = daemon.setuser(cfg.user)
        if not ok then return nil, err end
    end

    local log, err = logger(cfg.syslog)
    if not log then return nil, err end
    local ok, err = log:open(cfg.syslog or cfg.logfile or io.stdout, log.INFO)
    if not ok then return nil, err end
    cfg.log, fc.log = log, log

    for k,v in pairs(cfg.apps) do
        if not v.socket and not v.port then 
            return nil, "No port or socket set in app config: %s" % k
        end
        if not v.app then
            return nil, "No app set in config: %s" % k
        end
        local app, err = loadfile(v.app)
        if not app then return nil, err end
        local sock, err = v.socket and socket.listen{ path = v.socket, unlink = true }
                                    or socket.listen{ host = "0.0.0.0", port = v.port }
        if not sock then return nil, err end
        if not v.syslog or not v.logfile or v.syslog == cfg.syslog or v.logfile == cfg.logfile then
            v.log = fc.log
        else
            local log, err = logger(cfg.syslog)
            if not log then return nil, err end
            local ok, err = log:open(cfg.syslog or cfg.logfile or io.stdout, log.INFO)
            if not ok then return nil, err end
            v.log = log
        end
        v._app, v._sock = app, sock

    end

    return cfg
end

function fc.unload()
    if not fc.cfg then return nil, err end
    -- clean up any fds we may have left open
    for k,v in pairs(fc.cfg.apps) do
        if v._sock then v._sock:close() end
        if v.log and v.log ~= fc.cfg.log and v.log ~= io.stdout then v.log:close() end
    end
    if fc.cfg.log and fc.cfg.log ~= io.stdout then fc.cfg.log:close() end
    return nil, err
end

function fc.spawn_worker(id)
    local ipc_rd, ipc_wr = socket.pair()
    local pid = ffi.C.fork()

    if pid == -1 then
        local errno = ffi.errno()
        ipc_rd:close()
        ipc_wr:close()
        return nil, ffi.string(ffi.C.strerror(errno))

    elseif pid == 0 then
        ipc_rd:close()
        daemon.setproctitle("fulcrum: worker")
        worker(fc.cfg, ipc_wr, id)
        os.exit(0)
    end

    ipc_wr:close()
    fc.workers[ipc_wr] = pid
    fc.cq:wrap(function()
        while true do
            local x, err = ipc_rd:read()
            if not x then
                if not fc.alive then break end
                fc.log("Child %d died (respawning): %s", id, err)
                fc.workers[ipc_rd] = nil
                fc.spawn_worker(id)
                break
            end
        end
    end)
end

function fc.signals()
    local sl = signal.listen(signal.SIGHUP, signal.SIGINT, signal.SIGQUIT)
    signal.block(signal.SIGHUP, signal.SIGINT, signal.SIGQUIT)

    while true do
        local sig = sl:wait()
        if sig == signal.SIGHUP then
            fc.log("SIGHUP received; reloading the config")
            local cfg, err = fc.load(fc.path)
            if not cfg then
                fc.log("Reloading config failed: %s", err)
                return
            end
            fc.cfg = cfg
            for k, _ in pairs(fc.workers) do
                k:close()
                fc.workers[k] = nil
            end
            for i in 1, cfg.workers do
                spawn_worker(i)
            end
        elseif sig == signal.SIGQUIT or sig == signal.SIGINT then
            fc.log("Shutting down")
            fc.alive = false
            for k, _ in pairs(fc.workers) do
                k:close()
                fc.workers[k] = nil
            end
            fc.unload()
            os.exit(0) -- we should be able to just break here :(
            --break
        end
    end
end

function fc.init(lc)
    local cfg, err = fc.load(lc)
    if not cfg then return fc.unload() end

    if cfg.daemon then
        local ok,  err = daemon.daemonise()
        if not ok then return nil, err end
    end

    return true
end

function fc.main_loop()
    fc.alive = true
	
    for i = 1, (fc.cfg.workers or 2) do
        fc.spawn_worker(i)
	end

    fc.cq:wrap(fc.signals)

    fc.log("%s is up and running", FC_VERSION)

	while not fc.cq:empty() do
	    local ok, err = fc.cq:step(1)
	    if not ok then
	    	fc.log:err(err)
	    end
	end

	fc.log("Shutting down")
end

return fc
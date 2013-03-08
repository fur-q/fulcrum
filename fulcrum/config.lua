local function include(name, env)
    local cfg, err = assert(loadfile(name, "t", env))
    if _G.setfenv then setfenv(cfg, env) end
    cfg()
    return env
end

local function config(name, env)
    local env, mt = env or {}, getmetatable(env) or { __index = {} }
    if type(mt.__index) == "table" then
        mt.__index.include = function(f) return include(f, env) end
    end
    setmetatable(env, mt)
    local ok, env = pcall(function()
        debug.sethook(function() error("timed out") end, "", 1e5)
        local out = include(name, env)
        debug.sethook()
        return out
    end)
    return ok and env or nil, env
end

return config
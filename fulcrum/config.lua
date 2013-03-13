local function include(name, env)
    local cfg, err = assert(loadfile(name, "t", env))
    if _G.setfenv then setfenv(cfg, env) end
    cfg()
    return env
end

return function(name, env)
    local env, mt = env or {}, getmetatable(env) or { __index = {} }
    if type(mt.__index) == "table" and not mt.__index.include then
        mt.__index.include = function(f, t) return include(f, t or env) end
    end
    local ok, env = pcall(function()
        debug.sethook(function() error("timed out") end, "", 1e5)
        local out = include(name, setmetatable(env, mt))
        debug.sethook()
        return out
    end)
    return ok and env or nil, env
end
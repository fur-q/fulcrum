local sgmatch = string.gmatch

local status = {
  [100] = 'Continue',
  [101] = 'Switching Protocols',
  [102] = 'Processing',                 -- RFC 2518, obsoleted by RFC 4918
  [200] = 'OK',
  [201] = 'Created',
  [202] = 'Accepted',
  [203] = 'Non-Authoritative Information',
  [204] = 'No Content',
  [205] = 'Reset Content',
  [206] = 'Partial Content',
  [207] = 'Multi-Status',               -- RFC 4918
  [300] = 'Multiple Choices',
  [301] = 'Moved Permanently',
  [302] = 'Moved Temporarily',
  [303] = 'See Other',
  [304] = 'Not Modified',
  [305] = 'Use Proxy',
  [307] = 'Temporary Redirect',
  [400] = 'Bad Request',
  [401] = 'Unauthorized',
  [402] = 'Payment Required',
  [403] = 'Forbidden',
  [404] = 'Not Found',
  [405] = 'Method Not Allowed',
  [406] = 'Not Acceptable',
  [407] = 'Proxy Authentication Required',
  [408] = 'Request Time-out',
  [409] = 'Conflict',
  [410] = 'Gone',
  [411] = 'Length Required',
  [412] = 'Precondition Failed',
  [413] = 'Request Entity Too Large',
  [414] = 'Request-URI Too Large',
  [415] = 'Unsupported Media Type',
  [416] = 'Requested Range Not Satisfiable',
  [417] = 'Expectation Failed',
  [418] = 'I\'m a teapot',              -- RFC 2324
  [422] = 'Unprocessable Entity',       -- RFC 4918
  [423] = 'Locked',                     -- RFC 4918
  [424] = 'Failed Dependency',          -- RFC 4918
  [425] = 'Unordered Collection',       -- RFC 4918
  [426] = 'Upgrade Required',           -- RFC 2817
  [500] = 'Internal Server Error',
  [501] = 'Not Implemented',
  [502] = 'Bad Gateway',
  [503] = 'Service Unavailable',
  [504] = 'Gateway Time-out',
  [505] = 'HTTP Version not supported',
  [506] = 'Variant Also Negotiates',    -- RFC 2295
  [507] = 'Insufficient Storage',       -- RFC 4918
  [509] = 'Bandwidth Limit Exceeded',
  [510] = 'Not Extended'                -- RFC 2774
}

for k,v in pairs(status) do
  status[k] = tostring(k) .. " " .. v
end

local function read_request(sock)
	local size, b = 0
	while true do
		b = sock:read(1)
		if b == ":" then break end
		local c = tonumber(b)
		if not c then return nil, "Malformed request" end
		size = (size * 10) + c
		if size > 1048576 then
			return nil, "Request header too big (>1MB)"
		end
	end

	local env = {}

	local hdr, err = sock:read(size) -- !! TODO figure out how to add a timeout here
	if err then
		return nil, "Timed out"
	end

	local sep, err = sock:read(1)
	if sep ~= "," then
		return nil, "Malformed request"
	end

	for k, v in sgmatch(hdr, "(%Z+)%z(%Z-)%z") do
		if env[k] then return nil, "Duplicate header: %s" % k end
		env[k] = v
	end

	if not env.CONTENT_LENGTH or not tonumber(env.CONTENT_LENGTH) then
		return nil, "Invalid Content-Length header"
	end

	if env.SCGI ~= "1" then
		return nil, "Invalid SCGI header"
	end

	env.input = sock

	return env
end

local function write_response(sock, resp)
	if not status[resp.status] then
		return nil, "Invalid response status"
	end

	local headers = type(resp.headers) == "table" and resp.headers or {}
	headers["X-Powered-By"] = FC_VERSION

	sock:write("Status: ", status[resp.status], "\n")
	for k,v in pairs(headers) do
		sock:write(k, ": ", v, "\n")
	end

	sock:write("\n")

	if not resp.body then
		if headers["Content-Length"] then -- transfer-encoding?
			return nil, "Content-Length set with no body"
		end
		return true
	end

	if type(resp.body) == "string" then
		headers["Content-Length"] = headers["Content-Length"] or #resp.body
		sock:write(resp.body, "\n")
		return true
	end

	if type(resp.body) == "function" then
		if tonumber(headers["Content-Length"]) then
			for _, str in resp.body() do
				sock:write(str)
			end
		elseif headers["Transfer-Encoding"] == "chunked" then
			for len, str in resp.body() do
				sock:write(sf("%x", len), "\n")
				sock:write(str, "\n")
			end
			sock:write("0", "\n\n")
		else
			return nil, "Body set with no Content-Length or Transfer-Encoding"
		end
	end

	return true
end

return function(cfg, ipc, n)
	local cqueues = require "cqueues"
	local socket  = require "cqueues.socket"
	local signal  = require "cqueues.signal"

	local cq = cqueues.new()
	signal.block(signal.SIGHUP, signal.SIGINT, signal.SIGQUIT)

	-- TODO add SIGQUIT listener

	cq:wrap(function()
		while true do
			local x, err = ipc:read()
			if not x then
				if err ~= 32 then -- EPIPE; master went down
					cfg.log:err(err)
				end
				break
			end
		end
	end)

	for k,v in pairs(cfg.apps) do
		local app = v._app()
		cq:wrap(function()
		    for cl in v._sock:clients() do
		        cq:wrap(function()
		            cl:setmode("bn", "tl")
		            local env, err = read_request(cl)
		            if env then
		            	ok, err = xpcall(app, debug.traceback, env)
		            	if ok then env, err = err, nil end
		            end
		            if not env then
		            	v.log:err("error processing request: %s", err)
		            	env = { response = { status = 500, headers = {} } }
		            end
		            write_response(cl, env.response)
		            cl:close()
		        end)
		    end
		end)
	end

	while not cq:empty() do
	    local ok, err = cq:step()
	    if not ok then
	    	cfg.log:err(err)
	    end
	end

end
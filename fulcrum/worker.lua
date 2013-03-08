return function(ipc, n)
	local cqueues = require "cqueues"
	local socket  = require "cqueues.socket"
	local signal  = require "cqueues.signal"
	local thread  = require "cqueues.thread"	

	local ok, master = ipc:recvfd()
	if not ok then
		print("recvfd failed")
		return
	end

	local sgmatch = string.gmatch

	local function read_request(sock)

		local size, b = 0

		repeat
			b = sock:read(1)
			if b == ":" then break end
			local c = tonumber(b)
			if not c then return nil, "Invalid syntax in request" end
			size = (size * 10) + c
		until size > 104857600 -- 100MB

		local env = {}

		local h = sock:read(size)
		for k, v in sgmatch(h, "(%Z+)%z(%Z-)%z") do
			if env[k] then return nil, "Duplicate header" end
			env[k] = v
		end

		if not env.CONTENT_LENGTH or not tonumber(env.CONTENT_LENGTH) then
			return nil, "Invalid Content-Length header"
		end

		if env.SCGI ~= "1" then
			return nil, "Invalid SCGI header"
		end

		return env
	end

	local cq = cqueues.new()

	cq:wrap(function()
		while true do
			local x, err = ipc:read()
			print(x, err)
			break
		end
	end)

	cq:wrap(function()
	    for cl in master:clients() do
	        cq:wrap(function()
	            cl:setmode("bn", "tl")
	            local env, err = read_request(cl)
	            cl:write("Status: 200 OK\n")
	            cl:write("Content-Type: text/plain\n")
	            cl:write("Content-Length: 13\n")
	            cl:write("X-Powered-By: fulcrum/0.1\n")
	            cl:write("\n")
	            cl:write("it works \\o/\n")
	            cl:close()
	        end)
	    end
	end)

	while not cq:empty() do
	    local ok, err = cq:step()
	    if not ok then
	    	print(err)
	    end
	end

end
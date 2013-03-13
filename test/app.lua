return function(env)
	env.response = {
		status  = 200,
		headers = { ["Content-Type"] = "text/plain" },
		body    = "jimmy\nlied\nabout\nhaving\ncancer \\o/"
	}
	return env
end
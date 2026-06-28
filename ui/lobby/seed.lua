SPDRN.generate_seed = function()
	local chars = 'ABCDEFGHIJKLMNPQRSTUVWXYZ123456789'
	local seed = ''
	for i = 1, 8 do
		local idx = math.random(1, #chars)
		seed = seed .. chars:sub(idx, idx)
	end
	return seed
end

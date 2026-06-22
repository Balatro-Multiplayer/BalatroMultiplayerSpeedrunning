BInt.register_test('spdrn:seed_length_is_8', function(test)
	test:assert_eq(#SPDRN.generate_seed(), 8, 'seed should be 8 chars')
end)

BInt.register_test('spdrn:seed_uses_valid_charset', function(test)
	local valid = 'ABCDEFGHIJKLMNPQRSTUVWXYZ123456789'
	local seed = SPDRN.generate_seed()
	for i = 1, #seed do
		local c = seed:sub(i, i)
		test:assert_true(valid:find(c, 1, true) ~= nil, "char '" .. c .. "' not in valid charset")
	end
end)

BInt.register_test('spdrn:seed_varies_across_calls', function(test)
	local seen = {}
	for _ = 1, 10 do
		seen[SPDRN.generate_seed()] = true
	end
	local count = 0
	for _ in pairs(seen) do
		count = count + 1
	end
	test:assert_true(count >= 2, 'expected at least 2 distinct seeds across 10 calls')
end)

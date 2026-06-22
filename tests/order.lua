-----------------------------
-- Layer activation
-----------------------------

BInt.register_test('spdrn:order_layer_active_with_spdrn_order_ruleset', function(test)
	local lobby = MPAPI.testing.mock_lobby({ metadata = { ruleset = 'spdrn_order' } })
	MPAPI.testing.set_current_lobby(lobby)
	local ok, err = pcall(function()
		test:assert_true(MPAPI.should_use_the_order(), 'should_use_the_order should be true for spdrn_order')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:order_layer_inactive_with_spdrn_vanilla_ruleset', function(test)
	local lobby = MPAPI.testing.mock_lobby({ metadata = { ruleset = 'spdrn_vanilla' } })
	MPAPI.testing.set_current_lobby(lobby)
	local ok, err = pcall(function()
		test:assert_false(MPAPI.should_use_the_order(), 'should_use_the_order should be false for spdrn_vanilla')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:order_layer_inactive_with_no_lobby', function(test)
	MPAPI.testing.reset()
	test:assert_false(MPAPI.should_use_the_order(), 'should_use_the_order should be false with no lobby')
end)

-----------------------------
-- Center reworks on start_run
-----------------------------

BInt.register_test('spdrn:order_reworks_j8ball_on_start_run', function(test)
	local lobby = MPAPI.testing.mock_lobby({ metadata = { ruleset = 'spdrn_order' } })
	MPAPI.testing.set_current_lobby(lobby)
	test:start_run({ seed = 'ORDERRW' })

	local ok, err = pcall(function()
		local center = G.P_CENTERS['j_8_ball']
		test:assert_true(center ~= nil, 'j_8_ball should exist')
		test:assert_eq(center.config and center.config.extra, 2,
			'j_8_ball extra should be 2 under The Order (got ' .. tostring(center.config and center.config.extra) .. ')')
	end)
	MPAPI.LoadReworks('spdrn_vanilla')
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:order_vanilla_j8ball_extra_not_reworked', function(test)
	local lobby = MPAPI.testing.mock_lobby({ metadata = { ruleset = 'spdrn_vanilla' } })
	MPAPI.testing.set_current_lobby(lobby)
	test:start_run({ seed = 'VANILRW' })

	local ok, err = pcall(function()
		local center = G.P_CENTERS['j_8_ball']
		test:assert_true(center ~= nil, 'j_8_ball should exist')
		local extra = center.config and center.config.extra
		test:assert_true(extra ~= 2,
			'j_8_ball extra should NOT be 2 under vanilla (got ' .. tostring(extra) .. ')')
	end)
	MPAPI.LoadReworks('spdrn_vanilla')
	MPAPI.testing.reset()
	assert(ok, err)
end)

-----------------------------
-- Ranked lobby_ready sets ruleset
-----------------------------

BInt.register_test('spdrn:order_ranked_lobby_ready_sets_ruleset_as_host', function(test)
	test:start_run({ seed = 'SEED' })

	local handle = MPAPI.testing.mock_match_handle()
	local restore_queue = MPAPI.testing.mock_matchmaking_queue(handle)
	local saved_handle = SPDRN._current_match_handle

	SPDRN._join_ranked_queue('spdrn_gold_stake_single')

	local captured = nil
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, metadata = {} })
	lobby.set_metadata = function(self, meta) captured = meta; self._metadata = meta end

	local orig_setup = SPDRN.setup_lobby_events
	SPDRN.setup_lobby_events = function() end

	local ok, err = pcall(function()
		handle:_fire('lobby_ready', lobby)
		test:assert_eq(captured and captured.ruleset, 'spdrn_order',
			'host should set ruleset=spdrn_order on ranked lobby_ready')
		test:assert_eq(captured and captured.gamemode, 'spdrn_gold_stake_single',
			'host should set gamemode key on ranked lobby_ready')
	end)

	SPDRN.setup_lobby_events = orig_setup
	SPDRN._current_match_handle = saved_handle
	restore_queue()
	assert(ok, err)
end)

BInt.register_test('spdrn:order_ranked_lobby_ready_guest_does_not_set_metadata', function(test)
	test:start_run({ seed = 'SEED' })

	local handle = MPAPI.testing.mock_match_handle()
	local restore_queue = MPAPI.testing.mock_matchmaking_queue(handle)
	local saved_handle = SPDRN._current_match_handle

	SPDRN._join_ranked_queue('spdrn_gold_stake_single')

	local set_metadata_called = false
	local lobby = MPAPI.testing.mock_lobby({ is_host = false, metadata = {} })
	lobby.set_metadata = function() set_metadata_called = true end

	local orig_setup = SPDRN.setup_lobby_events
	SPDRN.setup_lobby_events = function() end

	local ok, err = pcall(function()
		handle:_fire('lobby_ready', lobby)
		test:assert_false(set_metadata_called, 'guest should not call set_metadata on ranked lobby_ready')
	end)

	SPDRN.setup_lobby_events = orig_setup
	SPDRN._current_match_handle = saved_handle
	restore_queue()
	assert(ok, err)
end)

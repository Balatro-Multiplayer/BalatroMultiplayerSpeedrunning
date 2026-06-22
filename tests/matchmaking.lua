-----------------------------
-- Queue
-----------------------------

BInt.register_test('spdrn:mm_queue_sends_correct_params', function(test)
	test:start_run({ seed = 'SEED' })
	local handle = MPAPI.testing.mock_match_handle()
	local restore = MPAPI.testing.mock_matchmaking_queue(handle)
	local saved_handle = SPDRN._current_match_handle

	local ok, err = pcall(function()
		SPDRN._join_ranked_queue('spdrn_gold_stake_single')
		local opts = MPAPI.testing._last_queue_opts
		test:assert_eq(opts and opts.mod_id, SPDRN.id, 'mod_id should match SPDRN.id')
		test:assert_eq(opts and opts.game_mode, 'ranked:spdrn_gold_stake_single', 'game_mode key')
		test:assert_eq(opts and opts.min_players, 2, 'min_players should be 2')
		test:assert_eq(opts and opts.max_players, 2, 'max_players should be ranked cap (2)')
	end)
	SPDRN._current_match_handle = saved_handle
	restore()
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_queue_max_players_from_gamemode', function(test)
	test:start_run({ seed = 'SEED' })
	local handle = MPAPI.testing.mock_match_handle()
	local restore = MPAPI.testing.mock_matchmaking_queue(handle)
	local saved_handle = SPDRN._current_match_handle

	local ok, err = pcall(function()
		SPDRN._join_ranked_queue('spdrn_white_stake_triple')
		local opts = MPAPI.testing._last_queue_opts
		test:assert_eq(opts and opts.max_players, 2, 'WST ranked cap should be 2')
	end)
	SPDRN._current_match_handle = saved_handle
	restore()
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_cancel_calls_leave', function(test)
	test:start_run({ seed = 'SEED' })
	local handle = MPAPI.testing.mock_match_handle()
	local restore = MPAPI.testing.mock_matchmaking_queue(handle)
	local saved_handle = SPDRN._current_match_handle

	local ok, err = pcall(function()
		SPDRN._join_ranked_queue('spdrn_gold_stake_single')
		SPDRN._cancel_queue()
		test:assert_true(handle.leave_called, 'handle:leave() should be called')
		test:assert_true(SPDRN._current_match_handle == nil, '_current_match_handle should be nil')
	end)
	SPDRN._current_match_handle = saved_handle
	restore()
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_cancel_when_no_handle', function(test)
	test:start_run({ seed = 'SEED' })
	local saved_handle = SPDRN._current_match_handle
	SPDRN._current_match_handle = nil

	local ok, err = pcall(function()
		SPDRN._cancel_queue()
	end)
	SPDRN._current_match_handle = saved_handle
	assert(ok, err)
end)

-----------------------------
-- Is In Ranked Match
-----------------------------

BInt.register_test('spdrn:mm_is_in_ranked_match_false_no_handle', function(test)
	test:start_run({ seed = 'SEED' })
	local saved_handle = SPDRN._current_match_handle
	SPDRN._current_match_handle = nil

	local ok, err = pcall(function()
		test:assert_false(SPDRN._is_in_ranked_match(), 'no handle means not in match')
	end)
	SPDRN._current_match_handle = saved_handle
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_is_in_ranked_match_false_no_match_id', function(test)
	test:start_run({ seed = 'SEED' })
	local saved_handle = SPDRN._current_match_handle
	SPDRN._current_match_handle = MPAPI.testing.mock_match_handle({ match_id = nil })

	local ok, err = pcall(function()
		test:assert_false(SPDRN._is_in_ranked_match(), 'nil match_id means not in match')
	end)
	SPDRN._current_match_handle = saved_handle
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_is_in_ranked_match_true', function(test)
	test:start_run({ seed = 'SEED' })
	local saved_handle = SPDRN._current_match_handle
	SPDRN._current_match_handle = MPAPI.testing.mock_match_handle({ match_id = 'match123' })

	local ok, err = pcall(function()
		test:assert_true(SPDRN._is_in_ranked_match(), 'valid match_id means in match')
	end)
	SPDRN._current_match_handle = saved_handle
	assert(ok, err)
end)

-----------------------------
-- Report Result
-----------------------------

BInt.register_test('spdrn:mm_report_result_correct_placements', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' }, { id = 'p2' } },
		player_id = 'p1',
	})
	MPAPI.testing.set_current_lobby(lobby)
	local saved_handle = SPDRN._current_match_handle
	local handle = MPAPI.testing.mock_match_handle({ match_id = 'm1' })
	SPDRN._current_match_handle = handle

	local ok, err = pcall(function()
		SPDRN.report_match_result('p1')
		local placements = handle.report_result_args and handle.report_result_args.placements
		test:assert_true(placements ~= nil, 'report_result should have been called')
		local p1_place, p2_place
		for _, p in ipairs(placements) do
			if p.playerId == 'p1' then
				p1_place = p.place
			elseif p.playerId == 'p2' then
				p2_place = p.place
			end
		end
		test:assert_eq(p1_place, 1, 'winner p1 should have place 1')
		test:assert_eq(p2_place, 2, 'loser p2 should have place 2')
	end)
	SPDRN._current_match_handle = saved_handle
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_report_result_nonhost_noop', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = false, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local saved_handle = SPDRN._current_match_handle
	local handle = MPAPI.testing.mock_match_handle({ match_id = 'm1' })
	SPDRN._current_match_handle = handle

	local ok, err = pcall(function()
		SPDRN.report_match_result('p1')
		test:assert_true(handle.report_result_args == nil, 'non-host should not call report_result')
	end)
	SPDRN._current_match_handle = saved_handle
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:mm_report_result_no_handle_noop', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local saved_handle = SPDRN._current_match_handle
	SPDRN._current_match_handle = nil

	local ok, err = pcall(function()
		SPDRN.report_match_result('p1')
	end)
	SPDRN._current_match_handle = saved_handle
	MPAPI.testing.reset()
	assert(ok, err)
end)

-----------------------------
-- Gold Stake Single
-----------------------------

BInt.register_test('spdrn:gss_win_fires_at_ante_9', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' }, { id = 'p2' } },
		player_id = 'p1',
	})
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_ante_change(9)
		test:assert_eq(#lobby.recorded_broadcasts, 1, 'should broadcast 1 action')
		test:assert_eq(lobby.recorded_broadcasts[1].action_key, 'spdrn_player_won', 'action key')
		test:assert_eq(lobby.recorded_broadcasts[1].params.player_id, lobby.player_id, 'player_id')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_win_guard_prevents_double', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' }, { id = 'p2' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_ante_change(9)
		instance:on_ante_change(9)
		test:assert_eq(#lobby.recorded_broadcasts, 1, 'guard should prevent double-fire')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_no_win_below_ante_9', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' }, { id = 'p2' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_ante_change(8)
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'no broadcast before ante 9')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_ante_reset_clears_guard', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' }, { id = 'p2' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_ante_change(9)
		instance:on_ante_change(1) -- reset flag
		instance:on_ante_change(9)
		test:assert_eq(#lobby.recorded_broadcasts, 2, 'should fire twice after flag reset')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_no_lobby_no_broadcast', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(nil)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_ante_change(9) -- no lobby, should be silent
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'no lobby means no broadcast')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_forfeit_last_player_wins', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' }, { id = 'p2' } },
		player_id = 'p1',
	})
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_player_forfeit('p2')
		test:assert_eq(#lobby.recorded_broadcasts, 1, 'remaining player should win')
		test:assert_eq(lobby.recorded_broadcasts[1].action_key, 'spdrn_player_won')
		test:assert_eq(lobby.recorded_broadcasts[1].params.player_id, 'p1')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_forfeit_non_host_silent', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		is_host = false,
		players = { { id = 'p1' }, { id = 'p2' } },
		player_id = 'p1',
	})
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_player_forfeit('p2')
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'non-host should not broadcast')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:gss_forfeit_already_sole_player', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' } },
		player_id = 'p1',
	})
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()

	local ok, err = pcall(function()
		instance:on_player_forfeit('p1')
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'no remaining players means no win broadcast')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

-----------------------------
-- White Stake Triple
-----------------------------

BInt.register_test('spdrn:wst_first_run_starts_second', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()

	local start_run_calls = 0
	instance.start_run = function()
		start_run_calls = start_run_calls + 1
	end

	local ok, err = pcall(function()
		instance:on_ante_change(9)
		test:assert_eq(instance._run_count, 1, '_run_count should be 1')
		test:assert_eq(start_run_calls, 1, 'start_run should be called once')
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'no win broadcast yet')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:wst_second_run_starts_third', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()
	instance._run_count = 1
	instance._ante9_fired = false

	local start_run_calls = 0
	instance.start_run = function()
		start_run_calls = start_run_calls + 1
	end

	local ok, err = pcall(function()
		instance:on_ante_change(9)
		test:assert_eq(instance._run_count, 2, '_run_count should be 2')
		test:assert_eq(start_run_calls, 1, 'start_run called once')
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'no win broadcast yet')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:wst_third_run_fires_win', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()
	instance._run_count = 2
	instance._ante9_fired = false

	local ok, err = pcall(function()
		instance:on_ante_change(9)
		test:assert_eq(instance._run_count, 0, '_run_count resets to 0')
		test:assert_eq(#lobby.recorded_broadcasts, 1, 'should broadcast win')
		test:assert_eq(lobby.recorded_broadcasts[1].action_key, 'spdrn_player_won')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:wst_ante_reset_clears_flag', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, players = { { id = 'p1' } }, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()
	instance._ante9_fired = true

	local ok, err = pcall(function()
		instance:on_ante_change(1)
		test:assert_false(instance._ante9_fired, '_ante9_fired should clear on ante < 9')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:wst_forfeit_triggers_win_for_remaining', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' }, { id = 'p2' } },
		player_id = 'p1',
	})
	MPAPI.testing.set_current_lobby(lobby)
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()

	local ok, err = pcall(function()
		instance:on_player_forfeit('p2')
		test:assert_eq(#lobby.recorded_broadcasts, 1, 'remaining player should win')
		test:assert_eq(lobby.recorded_broadcasts[1].action_key, 'spdrn_player_won')
		test:assert_eq(lobby.recorded_broadcasts[1].params.player_id, 'p1')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:wst_start_run_uses_correct_stake', function(test)
	test:start_run({ seed = 'SEED' })
	local captured_opts
	local orig = G.FUNCS.start_run
	G.FUNCS.start_run = function(e, opts)
		captured_opts = opts
	end

	local ok, err = pcall(function()
		MPAPI.GameModes['spdrn_white_stake_triple']:start_run()
		test:assert_eq(captured_opts and captured_opts.stake, 1, 'WST stake should be 1 (white)')
	end)
	G.FUNCS.start_run = orig
	assert(ok, err)
end)

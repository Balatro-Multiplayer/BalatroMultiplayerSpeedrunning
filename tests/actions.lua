-----------------------------
-- spdrn_player_won
-----------------------------

BInt.register_test('spdrn:action_player_won_shows_win_screen', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)

	local win_called = false
	local orig_win = SPDRN.show_win_screen
	SPDRN.show_win_screen = function()
		win_called = true
	end
	local orig_add_event = G.E_MANAGER.add_event
	G.E_MANAGER.add_event = function(self, event)
		if event and event.func then
			event.func()
		end
	end

	local at = MPAPI.ActionTypes['spdrn_player_won']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', { player_id = 'p1' })
		test:assert_true(win_called, 'win screen should be shown')
	end)
	SPDRN.show_win_screen = orig_win
	G.E_MANAGER.add_event = orig_add_event
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_player_won_shows_lose_screen', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)

	local lose_called = false
	local orig_lose = SPDRN.show_lose_screen
	SPDRN.show_lose_screen = function()
		lose_called = true
	end
	local orig_add_event = G.E_MANAGER.add_event
	G.E_MANAGER.add_event = function(self, event)
		if event and event.func then
			event.func()
		end
	end

	local at = MPAPI.ActionTypes['spdrn_player_won']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', { player_id = 'p2' })
		test:assert_true(lose_called, 'lose screen should be shown')
	end)
	SPDRN.show_lose_screen = orig_lose
	G.E_MANAGER.add_event = orig_add_event
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_player_won_no_lobby', function(test)
	test:start_run({ seed = 'SEED' })
	MPAPI.testing.set_current_lobby(nil)

	local at = MPAPI.ActionTypes['spdrn_player_won']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', { player_id = 'p1' })
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_player_won_no_params', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)

	local at = MPAPI.ActionTypes['spdrn_player_won']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', {})
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_player_won_host_reports_result', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = true, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)

	local reported_winner = nil
	local orig_report = SPDRN.report_match_result
	SPDRN.report_match_result = function(winner_id)
		reported_winner = winner_id
	end
	local orig_add_event = G.E_MANAGER.add_event
	G.E_MANAGER.add_event = function(self, event)
		if event and event.func then
			event.func()
		end
	end

	local at = MPAPI.ActionTypes['spdrn_player_won']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', { player_id = 'p2' })
		test:assert_eq(reported_winner, 'p2', 'host should report result with winner id')
	end)
	SPDRN.report_match_result = orig_report
	G.E_MANAGER.add_event = orig_add_event
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_player_won_nonhost_skip_report', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ is_host = false, player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)

	local report_called = false
	local orig_report = SPDRN.report_match_result
	SPDRN.report_match_result = function()
		report_called = true
	end
	local orig_add_event = G.E_MANAGER.add_event
	G.E_MANAGER.add_event = function(self, event)
		if event and event.func then
			event.func()
		end
	end

	local at = MPAPI.ActionTypes['spdrn_player_won']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', { player_id = 'p2' })
		test:assert_false(report_called, 'non-host should not call report_match_result')
	end)
	SPDRN.report_match_result = orig_report
	G.E_MANAGER.add_event = orig_add_event
	MPAPI.testing.reset()
	assert(ok, err)
end)

-----------------------------
-- spdrn_forfeit
-----------------------------

BInt.register_test('spdrn:action_forfeit_local_shows_lose', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({ player_id = 'p1' })
	MPAPI.testing.set_current_lobby(lobby)

	local lose_called = false
	local orig_lose = SPDRN.show_lose_screen
	SPDRN.show_lose_screen = function()
		lose_called = true
	end
	local orig_add_event = G.E_MANAGER.add_event
	G.E_MANAGER.add_event = function(self, event)
		if event and event.func then
			event.func()
		end
	end

	local at = MPAPI.ActionTypes['spdrn_forfeit']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', {})
		test:assert_true(lose_called, 'local player forfeit should show lose screen')
	end)
	SPDRN.show_lose_screen = orig_lose
	G.E_MANAGER.add_event = orig_add_event
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_forfeit_remote_delegates_gamemode', function(test)
	test:start_run({ seed = 'SEED' })

	local on_forfeit_calls = {}
	local mock_instance = {
		on_player_forfeit = function(self, player_id)
			on_forfeit_calls[#on_forfeit_calls + 1] = player_id
		end,
	}

	local lobby = MPAPI.testing.mock_lobby({
		player_id = 'p1',
		players = { { id = 'p1' }, { id = 'p2' } },
		gamemode_instance = mock_instance,
	})
	MPAPI.testing.set_current_lobby(lobby)

	local lose_called = false
	local orig_lose = SPDRN.show_lose_screen
	SPDRN.show_lose_screen = function()
		lose_called = true
	end

	local at = MPAPI.ActionTypes['spdrn_forfeit']
	local ok, err = pcall(function()
		at.on_receive(at, 'p2', {})
		test:assert_eq(#on_forfeit_calls, 1, 'on_player_forfeit should be called once')
		test:assert_eq(on_forfeit_calls[1], 'p2', 'on_player_forfeit called with forfeiting player id')
		test:assert_false(lose_called, 'remote forfeit should not show lose screen for local player')
	end)
	SPDRN.show_lose_screen = orig_lose
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_forfeit_no_lobby', function(test)
	test:start_run({ seed = 'SEED' })
	MPAPI.testing.set_current_lobby(nil)

	local at = MPAPI.ActionTypes['spdrn_forfeit']
	local ok, err = pcall(function()
		at.on_receive(at, 'p1', {})
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

-----------------------------
-- spdrn_start_game
-----------------------------

BInt.register_test('spdrn:action_start_game_creates_instance', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		metadata = { gamemode = 'spdrn_gold_stake_single', deck = 'Red Deck' },
	})
	MPAPI.testing.set_current_lobby(lobby)

	-- Practice starts synchronously (no countdown); other kinds defer begin_run
	-- behind a 5s countdown, which this synchronous assertion can't observe.
	local saved_kind = SPDRN._lobby_kind
	SPDRN._lobby_kind = 'practice'

	local orig_start_run = G.FUNCS.start_run
	G.FUNCS.start_run = function() end

	local at = MPAPI.ActionTypes['spdrn_start_game']
	local ok, err = pcall(function()
		at.on_receive(at, 'host', { seed = 'TESTSD1' })
		test:assert_true(lobby._gamemode_instance ~= nil, 'gamemode instance should be created')
	end)
	G.FUNCS.start_run = orig_start_run
	SPDRN._lobby_kind = saved_kind
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_start_game_calls_start_run', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		metadata = { gamemode = 'spdrn_gold_stake_single', deck = 'Red Deck' },
	})
	MPAPI.testing.set_current_lobby(lobby)

	-- Practice starts synchronously (see note above).
	local saved_kind = SPDRN._lobby_kind
	SPDRN._lobby_kind = 'practice'

	local captured_opts = nil
	local orig_start_run = G.FUNCS.start_run
	G.FUNCS.start_run = function(e, opts)
		captured_opts = opts
	end

	local at = MPAPI.ActionTypes['spdrn_start_game']
	local ok, err = pcall(function()
		at.on_receive(at, 'host', { seed = 'TESTSD1' })
		test:assert_eq(captured_opts and captured_opts.stake, 8, 'GSS stake should be 8 (gold)')
		test:assert_eq(captured_opts and captured_opts.seed, 'TESTSD1', 'seed should be passed through')
	end)
	G.FUNCS.start_run = orig_start_run
	SPDRN._lobby_kind = saved_kind
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_start_game_unknown_gamemode', function(test)
	test:start_run({ seed = 'SEED' })
	local lobby = MPAPI.testing.mock_lobby({
		metadata = { gamemode = 'nonexistent_mode' },
	})
	MPAPI.testing.set_current_lobby(lobby)

	local at = MPAPI.ActionTypes['spdrn_start_game']
	local ok, err = pcall(function()
		at.on_receive(at, 'host', { seed = 'TESTSD1' })
		test:assert_true(lobby._gamemode_instance == nil, 'unknown gamemode should not create instance')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

BInt.register_test('spdrn:action_start_game_no_lobby', function(test)
	test:start_run({ seed = 'SEED' })
	MPAPI.testing.set_current_lobby(nil)

	local at = MPAPI.ActionTypes['spdrn_start_game']
	local ok, err = pcall(function()
		at.on_receive(at, 'host', { seed = 'TESTSD1' })
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end)

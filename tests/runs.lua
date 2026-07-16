-----------------------------
-- Helpers
-----------------------------

-- Stubs G.E_MANAGER.add_event to execute event functions immediately,
-- so on_receive handlers that queue screen transitions fire synchronously.
-- Only safe for tests that do NOT use the real game loop (beat_blind, play_hand).
-- Returns a restore function.
local function stub_event_manager()
	local orig = G.E_MANAGER.add_event
	G.E_MANAGER.add_event = function(self, event)
		if event and event.func then
			event.func()
		end
	end
	return function()
		G.E_MANAGER.add_event = orig
	end
end

-----------------------------
-- GSS: full game loop to ante 9
-----------------------------

-- Verifies the win hook fires through the real ease_ante call,
-- not by calling ease_ante directly.
-- ease_ante fires during beat_blind's scoring; calculate({ante_change=true}) broadcasts win
-- synchronously before the game reaches ROUND_EVAL, so no cash_out is needed.
BInt.register_test('spdrn:run_gss_win_via_game_loop', function(test)
	test:start_run({ seed = 'GSSRUN1' })

	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' }, { id = 'p2' } },
		player_id = 'p1',
	})
	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()
	lobby._gamemode_instance = instance
	MPAPI.testing.set_current_lobby(lobby)

	local ok, err = pcall(function()
		test:skip_to(8, 'boss')
		test:select_blind():assert()
		test:set_blind_goal(1)
		test:beat_blind():assert()
		-- ease_ante fired → calculate({ante_change=true}) → win broadcast; game goes to win screen (not shop)

		test:assert_eq(#lobby.recorded_broadcasts, 1, 'win should broadcast once after ante 8 boss')
		test:assert_eq(lobby.recorded_broadcasts[1].action_key, 'spdrn_player_won')
		test:assert_eq(lobby.recorded_broadcasts[1].params.player_id, 'p1')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end, { immortal = true })

-----------------------------
-- WST: game loop advances run_count
-----------------------------

-- Verifies WST increments _run_count and calls start_run (not win) on the first boss beat.
-- instance.start_run is stubbed so no actual restart occurs; game goes to win screen
-- (Balatro's internal win_ante logic) but the SPDRN restart path is verified separately.
BInt.register_test('spdrn:run_wst_run_count_via_game_loop', function(test)
	test:start_run({ seed = 'WSTRUN1' })

	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' } },
		player_id = 'p1',
		metadata = { deck = 'Red Deck' },
	})
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()
	lobby._gamemode_instance = instance
	MPAPI.testing.set_current_lobby(lobby)

	local start_run_calls = 0
	instance.start_run = function()
		start_run_calls = start_run_calls + 1
	end

	local ok, err = pcall(function()
		test:skip_to(8, 'boss')
		test:select_blind():assert()
		test:set_blind_goal(1)
		test:beat_blind():assert()
		-- ease_ante fired → calculate({ante_change=true}) → _run_count=1 → instance.start_run() (stubbed)
		-- game goes to win screen (not shop)

		test:assert_eq(instance._run_count, 1, '_run_count should be 1 after first boss beat')
		test:assert_eq(start_run_calls, 1, 'start_run should be called to begin run 2')
		test:assert_eq(#lobby.recorded_broadcasts, 0, 'no win broadcast on run 1 of 3')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end, { immortal = true })

-- Verifies WST fires the win broadcast on the third boss beat.
BInt.register_test('spdrn:run_wst_triple_win_via_game_loop', function(test)
	test:start_run({ seed = 'WSTRUN2' })

	local lobby = MPAPI.testing.mock_lobby({
		is_host = true,
		players = { { id = 'p1' } },
		player_id = 'p1',
		metadata = { deck = 'Red Deck' },
	})
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()
	instance._run_count = 2
	lobby._gamemode_instance = instance
	MPAPI.testing.set_current_lobby(lobby)

	instance.start_run = function() end

	local ok, err = pcall(function()
		test:skip_to(8, 'boss')
		test:select_blind():assert()
		test:set_blind_goal(1)
		test:beat_blind():assert()
		-- ease_ante fired → calculate({ante_change=true}) → _run_count=3 → win broadcast, reset to 0

		test:assert_eq(instance._run_count, 0, '_run_count should reset to 0 after third win')
		test:assert_eq(#lobby.recorded_broadcasts, 1, 'win should broadcast on third boss beat')
		test:assert_eq(lobby.recorded_broadcasts[1].action_key, 'spdrn_player_won')
	end)
	MPAPI.testing.reset()
	assert(ok, err)
end, { immortal = true })

-----------------------------
-- WST: full triple run end-to-end
-----------------------------

-- Drives three real runs through ante 9 via mod-triggered restarts.
-- Verifies _run_count increments correctly and win broadcasts only on the third run.
BInt.register_test('spdrn:run_wst_full_triple', function(test)
	local mesh = MPAPI.testing.create_local_mesh({
		player1 = { id = 'p1', is_host = true },
		player2 = { id = 'p2' },
		metadata = { deck = 'Red Deck' },
	})
	local instance = MPAPI.GameModes['spdrn_white_stake_triple']:new_instance()

	local function setup()
		MPAPI.testing.set_current_lobby(mesh.lobby1)
		mesh.lobby1._gamemode_instance = instance
	end

	test:start_run({ seed = 'WST_FULL', stake = 1 })
	setup()

	-- Run 1 of 3: calculate({ante_change=true}) → _run_count=1 → G.FUNCS.start_run → restart hook fires
	test:on_restart(setup)
	test:skip_to(8, 'boss')
	test:select_blind():assert()
	test:set_blind_goal(1)
	test:beat_blind():assert()
	-- restart occurred; setup() re-injected lobby+instance; test resumes at new BLIND_SELECT

	-- Run 2 of 3: calculate({ante_change=true}) → _run_count=2 → restart
	test:on_restart(setup)
	test:skip_to(8, 'boss')
	test:select_blind():assert()
	test:set_blind_goal(1)
	test:beat_blind():assert()
	-- restart occurred; test resumes at new BLIND_SELECT

	-- Run 3 of 3: calculate({ante_change=true}) → _run_count=3 → resets to 0 → win broadcast
	test:skip_to(8, 'boss')
	test:select_blind():assert()
	test:set_blind_goal(1)
	test:beat_blind():assert()
	-- win broadcast fired; game goes to win screen

	test:assert_eq(instance._run_count, 0, '_run_count should reset to 0 after third win')
	test:assert_eq(#mesh.lobby1.recorded_broadcasts, 1, 'win should broadcast on third run')
	test:assert_eq(mesh.lobby1.recorded_broadcasts[1].action_key, 'spdrn_player_won')

	MPAPI.testing.reset()
end, { immortal = true })

-----------------------------
-- Two-client: start_game action
-----------------------------

-- Verifies that broadcasting spdrn_start_game creates a gamemode instance
-- on both lobby clients, and calls G.FUNCS.start_run once per client.
BInt.register_test('spdrn:run_two_client_start_game', function(test)
	test:start_run({ seed = 'MESH1' })

	local mesh = MPAPI.testing.create_local_mesh({
		player1 = { id = 'p1', is_host = true },
		player2 = { id = 'p2' },
		metadata = { gamemode = 'spdrn_gold_stake_single', deck = 'Red Deck' },
	})
	MPAPI.testing.set_current_lobby(mesh.lobby1)

	-- Practice starts synchronously; matchmaking/private defer begin_run behind a
	-- 5s countdown which this synchronous assertion can't observe.
	local saved_kind = SPDRN._lobby_kind
	SPDRN._lobby_kind = 'practice'

	local start_run_calls = 0
	local orig_start_run = G.FUNCS.start_run
	G.FUNCS.start_run = function(e, opts)
		start_run_calls = start_run_calls + 1
	end

	local at = MPAPI.ActionTypes['spdrn_start_game']
	local ok, err = pcall(function()
		mesh.lobby1:action(at):broadcast({ seed = 'TESTSD1' })

		test:assert_true(mesh.lobby1._gamemode_instance ~= nil, 'lobby1 (p1) should have a gamemode instance')
		test:assert_true(mesh.lobby2._gamemode_instance ~= nil, 'lobby2 (p2) should have a gamemode instance')
		test:assert_eq(start_run_calls, 2, 'start_run called once for each client')
	end)
	G.FUNCS.start_run = orig_start_run
	SPDRN._lobby_kind = saved_kind
	MPAPI.testing.reset()
	assert(ok, err)
end)

-----------------------------
-- Two-client: p1 wins, p2 sees lose screen
-----------------------------

-- Drives p1's game to ante 9 via the real game loop.
-- The mesh dispatches the spdrn_player_won broadcast to both clients:
-- p1 (the winner) shows win screen; p2 shows lose screen.
-- on_receive queues show_win/lose_screen events; these fire before ROUND_EVAL
-- is reached (events are ordered by insertion), so no stub or explicit drain needed.
BInt.register_test('spdrn:run_two_client_p1_wins_p2_sees_lose', function(test)
	test:start_run({ seed = 'MESH2' })

	local mesh = MPAPI.testing.create_local_mesh({
		player1 = { id = 'p1', is_host = true },
		player2 = { id = 'p2' },
	})

	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()
	mesh.lobby1._gamemode_instance = instance
	MPAPI.testing.set_current_lobby(mesh.lobby1)

	local win_called = false
	local lose_called = false
	local orig_win = SPDRN.show_win_screen
	local orig_lose = SPDRN.show_lose_screen
	SPDRN.show_win_screen = function()
		win_called = true
	end
	SPDRN.show_lose_screen = function()
		lose_called = true
	end

	local ok, err = pcall(function()
		test:skip_to(8, 'boss')
		test:select_blind():assert()
		test:set_blind_goal(1)
		test:beat_blind():assert()
		-- ease_ante(1) fired → calculate({ante_change=true}) → mesh broadcasts spdrn_player_won
		-- show_win/show_lose events queued before ROUND_EVAL and fire before beat_blind returns

		test:assert_eq(#mesh.lobby1.recorded_broadcasts, 1, 'p1 should have broadcast the win')
		test:assert_eq(mesh.lobby1.recorded_broadcasts[1].action_key, 'spdrn_player_won')
		test:assert_true(win_called, 'p1 should see the win screen')
		test:assert_true(lose_called, 'p2 should see the lose screen')
	end)
	SPDRN.show_win_screen = orig_win
	SPDRN.show_lose_screen = orig_lose
	MPAPI.testing.reset()
	assert(ok, err)
end, { immortal = true })

-----------------------------
-- Two-client: p2 forfeits, p1 wins
-----------------------------

-- p2 broadcasts spdrn_forfeit. The mesh dispatches it to both clients:
-- p2 (from_player_id matches local) → lose screen queued for p2.
-- p1 (host) → gamemode on_player_forfeit → p1 is sole remaining → win broadcast.
BInt.register_test('spdrn:run_two_client_p2_forfeits_p1_wins', function(test)
	test:start_run({ seed = 'MESH3' })

	local mesh = MPAPI.testing.create_local_mesh({
		player1 = { id = 'p1', is_host = true },
		player2 = { id = 'p2' },
	})

	local instance = MPAPI.GameModes['spdrn_gold_stake_single']:new_instance()
	mesh.lobby1._gamemode_instance = instance
	MPAPI.testing.set_current_lobby(mesh.lobby2)

	local lose_called = false
	local orig_lose = SPDRN.show_lose_screen
	SPDRN.show_lose_screen = function()
		lose_called = true
	end
	local restore_events = stub_event_manager()

	local at = MPAPI.ActionTypes['spdrn_forfeit']
	local ok, err = pcall(function()
		-- p2 forfeits
		mesh.lobby2:action(at):broadcast({})

		-- p2's perspective: saw own forfeit → lose screen
		test:assert_true(lose_called, 'p2 should see the lose screen after forfeiting')

		-- p1's perspective (host): on_player_forfeit('p2') → p1 is sole remaining → win broadcast
		test:assert_eq(#mesh.lobby1.recorded_broadcasts, 1, 'p1 (host) should broadcast win for last remaining player')
		test:assert_eq(mesh.lobby1.recorded_broadcasts[1].action_key, 'spdrn_player_won')
		test:assert_eq(mesh.lobby1.recorded_broadcasts[1].params.player_id, 'p1')
	end)
	SPDRN.show_lose_screen = orig_lose
	restore_events()
	MPAPI.testing.reset()
	assert(ok, err)
end)

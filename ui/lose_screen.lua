-----------------------------
-- Shared end-screen button handlers (used by both win and lose screens)
-----------------------------

G.FUNCS.spdrn_continue_sp = function()
	G.FUNCS.exit_overlay_menu()
	G.SETTINGS.paused = false
	local lobby = MPAPI.get_current_lobby()
	if lobby then
		lobby:leave()
	end
end

G.FUNCS.spdrn_return_to_lobby = function()
	G.FUNCS.exit_overlay_menu()
	G.SETTINGS.paused = false
	G.FUNCS.go_to_menu()
end

G.FUNCS.spdrn_leave_from_game = function()
	G.FUNCS.exit_overlay_menu()
	G.SETTINGS.paused = false
	local lobby = MPAPI.get_current_lobby()
	if lobby then
		lobby:leave()
	end
	G.FUNCS.go_to_menu()
end

-- Practice only: restart the same gamemode on a fresh seed.
G.FUNCS.spdrn_play_again = function()
	G.FUNCS.exit_overlay_menu()
	G.SETTINGS.paused = false
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		G.FUNCS.go_to_menu()
		return
	end
	local meta = lobby:get_metadata()
	SPDRN.begin_run(meta.gamemode, meta.deck or 'Blue Deck', SPDRN.generate_seed())
end

-- Restart the current run after losing it to a blind: same seed, same gamemode
-- instance (so White Stake Triple keeps its run count). Works for every lobby kind.
G.FUNCS.spdrn_restart_run = function()
	G.FUNCS.exit_overlay_menu()
	G.SETTINGS.paused = false
	SPDRN.restart_current_run()
end

-- Buttons for the "lost a run to a blind" screen: retry the same seed, or forfeit.
function SPDRN.run_lost_buttons()
	return MPAPI.end_screen_buttons({
		{ button = 'spdrn_restart_run', label = 'Restart Run', colour = G.C.BLUE },
		{ button = 'spdrn_forfeit', label = 'Forfeit', colour = G.C.RED },
	})
end

-- Builds the end-screen action buttons for the current lobby kind.
--   practice    -> Play Again + Leave
--   matchmaking -> (loser) Continue in Singleplayer + Leave; (winner) Leave only
--   private     -> Continue in Singleplayer + Return to Lobby + Leave
function SPDRN.end_screen_buttons(is_winner)
	local kind = SPDRN.get_lobby_kind()
	local specs = {}
	if kind == 'practice' then
		specs[#specs + 1] = { button = 'spdrn_play_again', label = 'Practice Again', colour = G.C.BLUE }
		specs[#specs + 1] = { button = 'spdrn_leave_from_game', label = 'Back to Main Menu', colour = G.C.RED }
	elseif SPDRN.is_matchmaking(kind) then
		if not is_winner then
			specs[#specs + 1] = { button = 'spdrn_continue_sp', label = 'Continue in Singleplayer', colour = G.C.BLUE }
		end
		specs[#specs + 1] = { button = 'spdrn_leave_from_game', label = 'Leave Lobby', colour = G.C.RED }
	else
		specs[#specs + 1] = { button = 'spdrn_continue_sp', label = 'Continue in Singleplayer', colour = G.C.BLUE }
		specs[#specs + 1] = { button = 'spdrn_return_to_lobby', label = 'Return to Lobby', colour = G.C.GREEN }
		specs[#specs + 1] = { button = 'spdrn_leave_from_game', label = 'Leave Lobby', colour = G.C.RED }
	end

	return MPAPI.end_screen_buttons(specs)
end

-----------------------------
-- Lose screen
-----------------------------

function SPDRN.create_lose_screen(buttons)
	local eased_red = copy_table(G.GAME.round_resets.ante <= G.GAME.win_ante and G.C.RED or G.C.BLUE)
	eased_red[4] = 0
	ease_value(eased_red, 4, 0.8, nil, nil, true)

	local right_col = {
		create_UIBox_round_scores_row('furthest_ante', G.C.FILTER),
		create_UIBox_round_scores_row('furthest_round', G.C.FILTER),
		create_UIBox_round_scores_row('defeated_by'),
		{ n = G.UIT.R, config = { align = 'cm', minh = 0.2, minw = 0.1 }, nodes = {} },
	}
	for _, b in ipairs(buttons or SPDRN.end_screen_buttons(false)) do
		right_col[#right_col + 1] = b
	end

	local t = create_UIBox_generic_options({
		bg_colour = eased_red,
		no_back = true,
		no_esc = true,
		padding = 0,
		contents = {
			{
				n = G.UIT.R,
				config = { align = 'cm' },
				nodes = {
					{ n = G.UIT.O, config = { object = DynaText({ string = { localize('ph_game_over') }, colours = { G.C.RED }, shadow = true, float = true, scale = 1.5, pop_in = 0.4, maxw = 6.5 }) } },
				},
			},
			{
				n = G.UIT.R,
				config = { align = 'cm', padding = 0.15 },
				nodes = {
					{
						n = G.UIT.C,
						config = { align = 'cm' },
						nodes = {
							{
								n = G.UIT.R,
								config = { align = 'cm', padding = 0.05, colour = G.C.BLACK, emboss = 0.05, r = 0.1 },
								nodes = {
									{ n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
										create_UIBox_round_scores_row('hand'),
										create_UIBox_round_scores_row('poker_hand'),
									} },
									{
										n = G.UIT.R,
										config = { align = 'cm' },
										nodes = {
											{
												n = G.UIT.C,
												config = { align = 'cm', padding = 0.08 },
												nodes = {
													create_UIBox_round_scores_row('cards_played', G.C.BLUE),
													create_UIBox_round_scores_row('cards_discarded', G.C.RED),
													create_UIBox_round_scores_row('cards_purchased', G.C.MONEY),
													create_UIBox_round_scores_row('times_rerolled', G.C.GREEN),
													create_UIBox_round_scores_row('new_collection', G.C.WHITE),
													create_UIBox_round_scores_row('seed', G.C.WHITE),
													UIBox_button({ button = 'copy_seed', label = { localize('b_copy') }, colour = G.C.BLUE, scale = 0.3, minw = 2.3, minh = 0.4, focus_args = { nav = 'wide' } }),
												},
											},
											{
												n = G.UIT.C,
												config = { align = 'tr', padding = 0.08 },
												nodes = right_col,
											},
										},
									},
								},
							},
						},
					},
				},
			},
		},
	})

	t.nodes[1] = {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.1 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = 'cm', padding = 2 },
				nodes = {
					{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
						{ n = G.UIT.O, config = { padding = 0, id = 'jimbo_spot', object = Moveable(0, 0, G.CARD_W * 1.1, G.CARD_H * 1.1) } },
					} },
				},
			},
			{ n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = { t.nodes[1] } },
		},
	}

	return t
end

SPDRN.show_lose_screen = function(buttons)
	if SPDRN.timer then
		SPDRN.timer.stop()
	end
	play_sound('negative', 0.5, 0.7)
	play_sound('whoosh2', 0.9, 0.7)
	G.SETTINGS.paused = true
	G.FUNCS.overlay_menu({
		definition = SPDRN.create_lose_screen(buttons),
		config = { no_esc = true },
	})
	G.ROOM.jiggle = G.ROOM.jiggle + 3

	MPAPI.animate_jimbo_quip('lq_', 10)
end

-- Shown when the player loses their run to a blind (as opposed to an opponent
-- winning): same presentation as the lose screen but offering Restart Run / Forfeit.
SPDRN.show_run_lost_screen = function()
	SPDRN.show_lose_screen(SPDRN.run_lost_buttons())
end

-- Balatro has no single "you lost" callback, so we watch the game-over state off
-- the update loop. Fires once per loss, only inside a SPDRN lobby, and only for an
-- actual loss (G.GAME.won is set on a win, whose screen we drive separately).
function SPDRN._check_run_lost()
	if not (MPAPI.is_active(SPDRN.id) and MPAPI.get_current_lobby()) then
		SPDRN._run_lost_shown = false
		return
	end
	local lost = G.STATE == G.STATES.GAME_OVER and not (G.GAME and G.GAME.won)
	if not lost then
		SPDRN._run_lost_shown = false
		return
	end
	if SPDRN._run_lost_shown then
		return
	end
	SPDRN._run_lost_shown = true
	SPDRN.show_run_lost_screen()
end

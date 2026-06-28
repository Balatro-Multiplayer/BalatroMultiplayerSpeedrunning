function SPDRN.create_win_screen()
	local eased_green = copy_table(G.C.GREEN)
	eased_green[4] = 0
	ease_value(eased_green, 4, 0.5, nil, nil, true)

	local right_col = {
		create_UIBox_round_scores_row('furthest_ante', G.C.FILTER),
		create_UIBox_round_scores_row('furthest_round', G.C.FILTER),
		{ n = G.UIT.R, config = { align = 'cm', minh = 0.2, minw = 0.1 }, nodes = {} },
	}
	for _, b in ipairs(SPDRN.end_screen_buttons(true)) do
		right_col[#right_col + 1] = b
	end

	local t = create_UIBox_generic_options({
		padding = 0,
		bg_colour = eased_green,
		colour = G.C.BLACK,
		outline_colour = G.C.EDITION,
		no_back = true,
		no_esc = true,
		contents = {
			{
				n = G.UIT.R,
				config = { align = 'cm' },
				nodes = {
					{ n = G.UIT.O, config = { object = DynaText({ string = { localize('ph_you_win') }, colours = { G.C.EDITION }, shadow = true, float = true, spacing = 10, rotate = true, scale = 1.5, pop_in = 0.4, maxw = 6.5 }) } },
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
											UIBox_button({ button = 'copy_seed', label = { localize('b_copy') }, colour = G.C.BLUE, scale = 0.3, minw = 2.3, minh = 0.4 }),
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
	})

	t.nodes[1] = {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.1 },
		nodes = {
			{ n = G.UIT.C, config = { align = 'cm', padding = 2 }, nodes = {
				{ n = G.UIT.O, config = { padding = 0, id = 'jimbo_spot', object = Moveable(0, 0, G.CARD_W * 1.1, G.CARD_H * 1.1) } },
			} },
			{ n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = { t.nodes[1] } },
		},
	}
	t.config.id = 'spdrn_win_UI'

	return t
end

SPDRN.show_win_screen = function()
	if SPDRN.timer then
		SPDRN.timer.stop()
	end
	play_sound('win')
	G.SETTINGS.paused = true
	local ok, def = pcall(SPDRN.create_win_screen)
	if not ok then
		SPDRN.sendWarnMessage('create_win_screen error: ' .. tostring(def))
		return
	end
	G.FUNCS.overlay_menu({
		definition = def,
		config = { no_esc = true },
	})

	MPAPI.animate_jimbo_quip('wq_', 7)
end

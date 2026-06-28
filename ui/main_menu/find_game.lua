-- One matchmaking section (Ranked or Casual): the two gamemode buttons stacked, with the
-- section label on a readable horizontal row beneath them.
local function queue_section(label, white_btn, gold_btn)
	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.1, r = 0.2, colour = G.C.BLACK },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
				UIBox_button({ button = white_btn, label = { 'White Stake', 'Triple' }, colour = G.C.ETERNAL, minw = 2.5, minh = 1.0, scale = 0.4, col = true }),
			} },
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
				UIBox_button({ button = gold_btn, label = { 'Gold Stake', 'Single' }, colour = G.C.GOLD, minw = 2.5, minh = 1.0, scale = 0.4, col = true }),
			} },
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
				{ n = G.UIT.T, config = { text = label, scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
			} },
		},
	}
end

G.FUNCS.spdrn_find_game = function()
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			contents = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
					{ n = G.UIT.T, config = { text = 'Find Game', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.1 },
					nodes = {
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
							queue_section(localize('k_ranked_cap'), 'spdrn_queue_ranked_white', 'spdrn_queue_ranked_gold'),
						} },
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
							queue_section(localize('k_casual_cap'), 'spdrn_queue_casual_white', 'spdrn_queue_casual_gold'),
						} },
					},
				},
			},
		}),
	})
end

G.FUNCS.spdrn_queue_ranked_white = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN._join_queue(SPDRN.LobbyKind.RANKED, SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end

G.FUNCS.spdrn_queue_ranked_gold = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN._join_queue(SPDRN.LobbyKind.RANKED, SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

G.FUNCS.spdrn_queue_casual_white = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end

G.FUNCS.spdrn_queue_casual_gold = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

G.FUNCS.spdrn_cancel_queue = function()
	SPDRN._cancel_queue()
end

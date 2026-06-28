-- Practice: a client-only (offline) lobby that drops the player straight into a run with no
-- lobby view (suppress_lobby_view) and no countdown. It never allocates a server lobby, so
-- there is nothing to be orphaned if the run is abandoned without using the end-screen buttons.
function SPDRN._start_practice(gamemode_key, decks)
	SPDRN._lobby_kind = SPDRN.LobbyKind.PRACTICE
	local deck_list = type(decks) == 'table' and decks or { decks }
	if #deck_list == 0 then
		deck_list = { SPDRN.Deck.DEFAULT }
	end

	local lobby = MPAPI.create_local_lobby(SPDRN.id, { max_players = 1 })
	if not lobby then
		SPDRN._lobby_kind = nil
		return
	end
	lobby.suppress_lobby_view = true

	SPDRN.setup_lobby_events(lobby)

	lobby:on('connected', function()
		lobby:set_metadata({ gamemode = gamemode_key, deck = SPDRN.meta_deck_value(deck_list), ruleset = SPDRN.Ruleset.ORDER, kind = SPDRN.LobbyKind.PRACTICE })
		SPDRN.begin_run(gamemode_key, deck_list, SPDRN.generate_seed())
	end)
end

G.FUNCS.spdrn_practice = function()
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			contents = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
					{ n = G.UIT.T, config = { text = 'Practice', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.1 },
					nodes = {
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
							UIBox_button({ button = 'spdrn_practice_white', label = { 'White Stake', 'Triple' }, colour = G.C.ETERNAL, minw = 2.5, minh = 2.0, scale = 0.5, col = true }),
						} },
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
							UIBox_button({ button = 'spdrn_practice_gold', label = { 'Gold Stake', 'Single' }, colour = G.C.GOLD, minw = 2.5, minh = 2.0, scale = 0.5, col = true }),
						} },
					},
				},
			},
		}),
	})
end

G.FUNCS.spdrn_practice_white = function()
	G.FUNCS.exit_overlay_menu()
	local count = SPDRN.required_deck_count(MPAPI.GameModes[SPDRN.Gamemode.WHITE_STAKE_TRIPLE])
	SPDRN.open_deck_select(SPDRN.Deck.DEFAULT, function(decks)
		SPDRN._start_practice(SPDRN.Gamemode.WHITE_STAKE_TRIPLE, decks)
	end, count)
end

G.FUNCS.spdrn_practice_gold = function()
	G.FUNCS.exit_overlay_menu()
	local count = SPDRN.required_deck_count(MPAPI.GameModes[SPDRN.Gamemode.GOLD_STAKE_SINGLE])
	SPDRN.open_deck_select(SPDRN.Deck.DEFAULT, function(decks)
		SPDRN._start_practice(SPDRN.Gamemode.GOLD_STAKE_SINGLE, decks)
	end, count)
end

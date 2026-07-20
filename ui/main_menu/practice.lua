-- Practice: a client-only (offline) lobby that drops the player straight into a run with no
-- lobby view (suppress_lobby_view) and no countdown. It never allocates a server lobby, so
-- there is nothing to be orphaned if the run is abandoned without using the end-screen buttons.
-- `extra_meta` (optional) is merged into the lobby metadata -- used by gamemodes that need
-- something beyond gamemode/deck up front (Seed Scout's stake, Challenge's challenge id).
function SPDRN._start_practice(gamemode_key, decks, extra_meta)
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
		local meta = { gamemode = gamemode_key, deck = SPDRN.meta_deck_value(deck_list), ruleset = SPDRN.Ruleset.ORDER, kind = SPDRN.LobbyKind.PRACTICE }
		for k, v in pairs(extra_meta or {}) do
			meta[k] = v
		end
		lobby:set_metadata(meta)
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
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.1 },
					nodes = {
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
							UIBox_button({ button = 'spdrn_practice_seed_scout', label = { 'Seed', 'Scout' }, colour = G.C.BLUE, minw = 2.5, minh = 2.0, scale = 0.5, col = true }),
						} },
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
							UIBox_button({ button = 'spdrn_practice_challenge', label = { 'Challenge' }, colour = G.C.RED, minw = 2.5, minh = 2.0, scale = 0.5, col = true }),
						} },
					},
				},
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.1 },
					nodes = {
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
							UIBox_button({ button = 'spdrn_practice_all_deck', label = { 'All', 'Deck' }, colour = G.C.PURPLE, minw = 2.5, minh = 2.0, scale = 0.5, col = true }),
						} },
						{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
							UIBox_button({ button = 'spdrn_practice_stake_climb', label = { 'Stake', 'Climb' }, colour = G.C.GREEN, minw = 2.5, minh = 2.0, scale = 0.5, col = true }),
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

G.FUNCS.spdrn_practice_stake_climb = function()
	G.FUNCS.exit_overlay_menu()
	local count = SPDRN.required_deck_count(MPAPI.GameModes[SPDRN.Gamemode.STAKE_CLIMB])
	SPDRN.open_deck_select(SPDRN.Deck.DEFAULT, function(decks)
		SPDRN._start_practice(SPDRN.Gamemode.STAKE_CLIMB, decks)
	end, count)
end

-- Deck, then stake, then start -- the only practice flow that chains two pickers.
G.FUNCS.spdrn_practice_seed_scout = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN.open_deck_select(SPDRN.Deck.DEFAULT, function(decks)
		SPDRN.open_stake_select(1, function(stake)
			SPDRN._start_practice(SPDRN.Gamemode.SEED_SCOUT, decks, { stake = stake })
		end)
	end, 1)
end

G.FUNCS.spdrn_practice_challenge = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN.open_challenge_select(nil, function(challenge_id)
		-- The deck is irrelevant to Challenge's start_run (the challenge fixes its own deck);
		-- pass the default so _start_practice's deck-list normalization has something to work
		-- with, same as every other gamemode's deck param.
		SPDRN._start_practice(SPDRN.Gamemode.CHALLENGE, SPDRN.Deck.DEFAULT, { challenge = challenge_id })
	end)
end

-- Practice is solo (max_players = 1) -- MPAPI.BanPick's 2-actor draft would deadlock waiting on
-- a nonexistent second player, so bypass drafting entirely and supply every vanilla deck as a
-- fixed ordered list directly, same mechanism WST/GSS practice already use for their deck
-- list. The real draft only ever runs in a private lobby with a second real player.
G.FUNCS.spdrn_practice_all_deck = function()
	G.FUNCS.exit_overlay_menu()
	SPDRN._start_practice(SPDRN.Gamemode.ALL_DECK, SPDRN.vanilla_deck_pool())
end

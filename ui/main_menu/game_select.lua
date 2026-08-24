-- The shared "choose a gamemode" page (MPAPI page spdrn_game_select), styled after Balatro's
-- own Blind Select pillars (functions/UI_definitions.lua's create_UIBox_blind_choice), minus
-- the run-specific parts (blind chip animation, tag/skip-reward row, run-state colouring) --
-- just the pillar shape: a select button, a name plate, an icon swatch, and a stat box.
--
-- Replaces the three separate gamemode-picker overlays Find Game/Practice/Create Lobby used
-- to open (see ui/main_menu/{find_game,practice,create_lobby}.lua). Which action a pillar
-- click takes depends on how the page was reached (self.params.intent, set by whichever
-- button navigated here): practice starts an offline run, create_lobby opens a private lobby,
-- find_game joins the casual matchmaking queue for that mode (Ranked and live queue counts,
-- which the old Find Game overlay had, are dropped for now).
--
-- Stats shown per pillar are partly real (Players, read from the registered GameMode) and
-- partly placeholder (Best Time -- no leaderboard wiring yet).
local MODES = {
	{
		key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE,
		name = 'White Stake Triple',
		colour = G.C.ETERNAL,
		practice_button = 'spdrn_practice_white',
		lobby_button = 'spdrn_select_white_stake_triple',
		queue_button = 'spdrn_game_select_queue_white_stake_triple',
	},
	{
		key = SPDRN.Gamemode.GOLD_STAKE_SINGLE,
		name = 'Gold Stake Single',
		colour = G.C.GOLD,
		practice_button = 'spdrn_practice_gold',
		lobby_button = 'spdrn_select_gold_stake_single',
		queue_button = 'spdrn_game_select_queue_gold_stake_single',
	},
	{
		key = SPDRN.Gamemode.SEED_SCOUT,
		name = 'Seed Scout',
		colour = G.C.BLUE,
		practice_button = 'spdrn_practice_seed_scout',
		lobby_button = 'spdrn_select_seed_scout',
		queue_button = 'spdrn_game_select_queue_seed_scout',
	},
	{
		key = SPDRN.Gamemode.CHALLENGE,
		name = 'Challenge',
		colour = G.C.RED,
		practice_button = 'spdrn_practice_challenge',
		lobby_button = 'spdrn_select_challenge',
		queue_button = 'spdrn_game_select_queue_challenge',
	},
	{
		key = SPDRN.Gamemode.ALL_DECK,
		name = 'All Deck',
		colour = G.C.PURPLE,
		practice_button = 'spdrn_practice_all_deck',
		lobby_button = 'spdrn_select_all_deck',
		queue_button = 'spdrn_game_select_queue_all_deck',
	},
	{
		key = SPDRN.Gamemode.STAKE_CLIMB,
		name = 'Stake Climb',
		colour = G.C.GREEN,
		practice_button = 'spdrn_practice_stake_climb',
		lobby_button = 'spdrn_select_stake_climb',
		queue_button = 'spdrn_game_select_queue_stake_climb',
	},
}

local function button_for(mode, intent)
	if intent == 'create_lobby' then
		return mode.lobby_button
	elseif intent == 'find_game' then
		return mode.queue_button
	end
	return mode.practice_button
end

local function build_pillar(mode, intent)
	local gm = MPAPI.GameModes[mode.key]
	local players = gm and (tostring(gm:get_min_players(MPAPI.LobbyType.PRIVATE)) .. '-' .. tostring(gm:get_max_players(MPAPI.LobbyType.PRIVATE))) or '?'

	return { n = G.UIT.C, config = { align = 'cm' }, nodes = { {
		n = G.UIT.R,
		config = { id = mode.key, align = 'tm', r = 0.1, padding = 0.05 },
		nodes = { {
			n = G.UIT.R,
			config = { align = 'cm', colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5), r = 0.1, outline = 1, outline_colour = G.C.L_BLACK },
			nodes = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.15 }, nodes = {
					{ n = G.UIT.R, config = {
						align = 'cm', colour = G.C.ORANGE, minh = 0.5, minw = 2.2, padding = 0.06, r = 0.1,
						shadow = true, hover = true, one_press = true, button = button_for(mode, intent),
					}, nodes = {
						{ n = G.UIT.T, config = { text = 'SELECT', scale = 0.4, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
					} },
				} },
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
					{ n = G.UIT.R, config = {
						align = 'cm', r = 0.1, outline = 1, outline_colour = mode.colour, colour = darken(mode.colour, 0.3),
						minw = 2.3, emboss = 0.1, padding = 0.06, line_emboss = 1,
					}, nodes = {
						{ n = G.UIT.T, config = { text = mode.name, scale = 0.35, colour = G.C.WHITE, shadow = true, maxw = 2.2 } },
					} },
				} },
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
					{ n = G.UIT.R, config = { align = 'cm', minh = 1.1 }, nodes = {
						{ n = G.UIT.C, config = { align = 'cm', minw = 1.1, minh = 1.1, r = 0.1, colour = mode.colour, emboss = 0.05 }, nodes = {} },
					} },
					{ n = G.UIT.R, config = { align = 'cm', r = 0.1, padding = 0.06, minw = 2.4, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
						{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
							{ n = G.UIT.T, config = { text = 'Best Time', scale = 0.28, colour = G.C.WHITE, shadow = true } },
						} },
						{ n = G.UIT.R, config = { align = 'cm', minh = 0.45 }, nodes = {
							{ n = G.UIT.T, config = { text = '--:--', scale = 0.55, colour = G.C.RED, shadow = true } },
						} },
						{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
							{ n = G.UIT.T, config = { text = 'Players ', scale = 0.28, colour = G.C.WHITE, shadow = true } },
							{ n = G.UIT.T, config = { text = players, scale = 0.28, colour = G.C.MONEY, shadow = true } },
						} },
					} },
				} },
			},
		} },
	} } }
end

function SPDRN.build_game_select_ui(intent)
	intent = intent or 'practice'
	local row = {}
	for _, mode in ipairs(MODES) do
		row[#row + 1] = build_pillar(mode, intent)
	end

	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', colour = G.C.CLEAR },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.2 }, nodes = {
				{ n = G.UIT.T, config = { text = 'Choose a Gamemode', scale = 0.55, colour = G.C.WHITE, shadow = true } },
			} },
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.2 }, nodes = row },
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
				{ n = G.UIT.C, config = { align = 'cm', minw = 3, minh = 0.6, r = 0.1, colour = G.C.RED, hover = true, shadow = true, button = 'spdrn_game_select_back' }, nodes = {
					{ n = G.UIT.T, config = { text = localize('b_back'), scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
			} },
		},
	}
end

G.FUNCS.spdrn_game_select_back = function()
	MPAPI.pages.back()
end

G.FUNCS.spdrn_game_select_queue_white_stake_triple = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end
G.FUNCS.spdrn_game_select_queue_gold_stake_single = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end
G.FUNCS.spdrn_game_select_queue_seed_scout = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.SEED_SCOUT)
end
G.FUNCS.spdrn_game_select_queue_challenge = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.CHALLENGE)
end
G.FUNCS.spdrn_game_select_queue_all_deck = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.ALL_DECK)
end
G.FUNCS.spdrn_game_select_queue_stake_climb = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.STAKE_CLIMB)
end

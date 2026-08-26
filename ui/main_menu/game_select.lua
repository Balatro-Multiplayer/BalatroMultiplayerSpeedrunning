-- The shared "choose a gamemode" page (MPAPI page spdrn_game_select), styled after Balatro's
-- own Blind Select pillars (functions/UI_definitions.lua's create_UIBox_blind_choice), minus
-- the run-specific parts (blind chip dissolve-in, tag/skip-reward row, run-state colouring) --
-- just the pillar shape: a select button, a name plate, a gamemode chip icon, a description
-- plate, and a stat box, stretched to fill the rest of the page's height.
--
-- Replaces the three separate gamemode-picker overlays Find Game/Practice/Create Lobby used
-- to open (see ui/main_menu/{find_game,practice,create_lobby}.lua). Which pillars are shown
-- and what a pillar click does both depend on how the page was reached (self.params.intent,
-- set by whichever button navigated here): practice starts an offline run, create_lobby opens
-- a private lobby, find_game joins the matchmaking queue for that mode/ranked-tier.
SMODS.Atlas({
	-- SMODS.Atlas keys get this mod's own prefix ("spdrn_") applied automatically, same as any
	-- other SMODS object key -- registers as G.ANIMATION_ATLAS['spdrn_gamemode_chips'].
	key = 'gamemode_chips',
	path = 'mpspdrn_gamemode_chips.png',
	atlas_table = 'ANIMATION_ATLAS',
	frames = 21,
	px = 34,
	py = 34,
})

-- Row index (top to bottom) of each gamemode's chip in the sprite sheet above.
local CHIP_ROW = {
	all_deck = 0,
	stake_climb = 1,
	white_stake_triple = 2,
	white_stake_triple_ranked = 3,
	gold_stake_single = 4,
	gold_stake_single_ranked = 5,
	seed_scout = 6,
	challenge = 7,
}

-- The name plate's background/border colour, per chip row -- sampled from each chip icon's own
-- two dominant colours (circle fill + symbol) rather than a colour picked by hand, so the plate
-- always matches the art. bg is darkened for the plate's own background (keeps white plate text
-- legible); icon is used undarkened for the border.
local CHIP_COLOURS = {
	[CHIP_ROW.all_deck] = { bg = HEX('83E9F8'), icon = HEX('5AABDC') },
	[CHIP_ROW.stake_climb] = { bg = HEX('FD5F55'), icon = HEX('C14139') },
	[CHIP_ROW.white_stake_triple] = { bg = HEX('DCDCDC'), icon = HEX('4F6367') },
	[CHIP_ROW.white_stake_triple_ranked] = { bg = HEX('DCDCDC'), icon = HEX('F5A600') },
	[CHIP_ROW.gold_stake_single] = { bg = HEX('FDCF51'), icon = HEX('C88000') },
	[CHIP_ROW.gold_stake_single_ranked] = { bg = HEX('FDCF51'), icon = HEX('935ADC') },
	[CHIP_ROW.seed_scout] = { bg = HEX('74CCA8'), icon = HEX('459373') },
	[CHIP_ROW.challenge] = { bg = HEX('9E4D6E'), icon = HEX('DCDCDC') },
}

-- Shown in every pillar's description plate, regardless of intent. Always two lines.
local DESCRIPTION = {
	[SPDRN.Gamemode.WHITE_STAKE_TRIPLE] = { 'White Stake.', 'Three Runs.' },
	[SPDRN.Gamemode.GOLD_STAKE_SINGLE] = { 'Gold Stake.', 'One Run.' },
	[SPDRN.Gamemode.SEED_SCOUT] = { '60 Seconds', 'to Scout.' },
	[SPDRN.Gamemode.CHALLENGE] = { 'Challenge', 'Deck.' },
	[SPDRN.Gamemode.ALL_DECK] = { '15', 'Runs.' },
	[SPDRN.Gamemode.STAKE_CLIMB] = { 'Every Stake', 'in Order.' },
}

-- Practice and Create Lobby show all six gamemodes as plain pillars.
local PRACTICE_LOBBY_MODES = {
	{ key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, name = { 'White Stake', 'Triple' }, chip_row = CHIP_ROW.white_stake_triple,
		practice_button = 'spdrn_practice_white', lobby_button = 'spdrn_select_white_stake_triple' },
	{ key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, name = { 'Gold Stake', 'Single' }, chip_row = CHIP_ROW.gold_stake_single,
		practice_button = 'spdrn_practice_gold', lobby_button = 'spdrn_select_gold_stake_single' },
	{ key = SPDRN.Gamemode.SEED_SCOUT, name = 'Seed Scout', chip_row = CHIP_ROW.seed_scout,
		practice_button = 'spdrn_practice_seed_scout', lobby_button = 'spdrn_select_seed_scout' },
	{ key = SPDRN.Gamemode.CHALLENGE, name = 'Challenge', chip_row = CHIP_ROW.challenge,
		practice_button = 'spdrn_practice_challenge', lobby_button = 'spdrn_select_challenge' },
	{ key = SPDRN.Gamemode.ALL_DECK, name = 'All Deck', chip_row = CHIP_ROW.all_deck,
		practice_button = 'spdrn_practice_all_deck', lobby_button = 'spdrn_select_all_deck' },
	{ key = SPDRN.Gamemode.STAKE_CLIMB, name = 'Stake Climb', chip_row = CHIP_ROW.stake_climb,
		practice_button = 'spdrn_practice_stake_climb', lobby_button = 'spdrn_select_stake_climb' },
}

-- Find Game only offers the two matchmade gamemodes, each as a Casual/Ranked pair -- matching
-- the old Find Game overlay's Ranked x Casual x White x Gold matrix, just as 4 pillars instead
-- of a 2x2 grid of stat buttons. Grouped by ranked-status (both Ranked, then both Casual), not
-- by gamemode, so build_game_select_ui's ranked-transition spacer (below) lands in the right
-- place -- keep any future addition to this list sorted the same way (all entries sharing a
-- `ranked` value adjacent to each other).
local FIND_GAME_MODES = {
	{ key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, name = { 'White Stake', 'Triple Ranked' }, chip_row = CHIP_ROW.white_stake_triple_ranked,
		ranked = true, game_mode_stat_key = SPDRN.LobbyKind.RANKED_PREFIX .. SPDRN.Gamemode.WHITE_STAKE_TRIPLE, queue_button = 'spdrn_queue_ranked_white' },
	{ key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, name = { 'Gold Stake', 'Single Ranked' }, chip_row = CHIP_ROW.gold_stake_single_ranked,
		ranked = true, game_mode_stat_key = SPDRN.LobbyKind.RANKED_PREFIX .. SPDRN.Gamemode.GOLD_STAKE_SINGLE, queue_button = 'spdrn_queue_ranked_gold' },
	{ key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, name = { 'White Stake', 'Triple' }, chip_row = CHIP_ROW.white_stake_triple,
		ranked = false, game_mode_stat_key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, queue_button = 'spdrn_game_select_queue_white_stake_triple' },
	{ key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, name = { 'Gold Stake', 'Single' }, chip_row = CHIP_ROW.gold_stake_single,
		ranked = false, game_mode_stat_key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, queue_button = 'spdrn_game_select_queue_gold_stake_single' },
}

-- Live queue/in-game counts while the find_game intent is open. Started from the page's
-- on_enter and stopped from its cleanup (see the MPAPI.Page registration in core.lua) -- a
-- page's own show/leave lifecycle is a simpler, more robust "is this still open" signal than
-- inferring it from UI state, same reasoning the old Find Game overlay's poller comment gave.
local FIND_GAME_POLL_INTERVAL_SECONDS = 5
local _find_game_poller = nil
local _latest_find_game_counts = nil
local _find_game_stat_els = {}

local function refresh_find_game_stats()
	for _, el in pairs(_find_game_stat_els) do
		el:update()
	end
end

function SPDRN.stop_find_game_polling()
	if _find_game_poller then
		_find_game_poller.stop()
		_find_game_poller = nil
	end
	_find_game_stat_els = {}
end

-- See build_chip_sprite's comment: Balatro's own UI teardown never calls :remove() on a
-- G.UIT.O node's embedded object, so the spdrn_game_select page (core.lua) must do it itself
-- in its dispose() hook, passing back the same array SPDRN.build_game_select_ui populated.
function SPDRN.dispose_game_select_sprites(sprites)
	for _, spr in ipairs(sprites or {}) do
		pcall(function() spr:remove() end)
	end
end

-- A G.UIT.O node defaults its embedded object's role to xy_bond = 'Strong' (engine/ui.lua's
-- `self.config.object:set_role(self.config.role or {..., xy_bond = 'Strong', ...})`), which
-- means the layout system recomputes the sprite's position from its parent every frame
-- regardless of what Moveable:drag() just set it to -- confirmed live (G.ANIMATIONS entries for
-- this atlas all reported role.xy_bond == 'Strong'), and it's why the chips visually didn't
-- move under drag even with states.drag.can already true. Must run from on_enter (core.lua),
-- AFTER the UIBox has built the tree and already called the default set_role once -- mutating
-- this in build_chip_sprite itself, before that call happens, would just get overwritten.
function SPDRN.loosen_game_select_sprites(sprites)
	for _, spr in ipairs(sprites or {}) do
		if spr.role then
			spr.role.xy_bond = 'Weak'
		end
	end
end

function SPDRN.start_find_game_polling()
	SPDRN.stop_find_game_polling()
	_latest_find_game_counts = nil
	_find_game_poller = MPAPI.matchmaking.create_queue_counts_poller(SPDRN.id, FIND_GAME_POLL_INTERVAL_SECONDS, function(err, game_modes)
		_latest_find_game_counts = game_modes or {}
		refresh_find_game_stats()
	end)
	_find_game_poller.start()
end

-- `tracker` collects every chip sprite created for the page currently being built, so the
-- page's dispose() (core.lua's spdrn_game_select registration) can :remove() them when the
-- page is torn down -- see MPAPI.pages' _dispose_instance for why that's required (Balatro's
-- own Node:remove() does not cascade into a G.UIT.O node's config.object).
local function build_chip_sprite(row, tracker)
	local spr = AnimatedSprite(0, 0, 1.1, 1.1, G.ANIMATION_ATLAS['spdrn_gamemode_chips'], { x = 0, y = row })
	spr:define_draw_steps({
		{ shader = 'dissolve', shadow_height = 0.05 },
		{ shader = 'dissolve' },
	})
	-- Node/Moveable default every object to collide.can = false (engine/node.lua) -- hover.can
	-- and drag.can already default true, but without collide the object is never hit-tested, so
	-- neither ever actually triggers. Real blind-select chips get this via their own G.UIT.O
	-- node's can_collide config; setting it directly on the sprite here has the same effect and
	-- doesn't depend on that node-level propagation.
	spr.states.collide.can = true
	spr.states.hover.can = true
	spr.states.drag.can = true
	if tracker then
		tracker[#tracker + 1] = spr
	end
	return spr
end

-- Small, secondary-info caption style -- the same scale/colour/no-shadow combination used
-- elsewhere in this codebase (and by vanilla Joker description sub-text) for a dimmer,
-- smaller line under a main label.
local function small_caption(text)
	return { n = G.UIT.R, config = { align = 'cm' }, nodes = {
		{ n = G.UIT.T, config = { text = text, scale = 0.28, colour = G.C.UI.TEXT_INACTIVE, shadow = false } },
	} }
end

-- The upper description plate: what the gamemode is (always two lines), and (find_game only)
-- its time limit.
local function build_description_box(mode, intent)
	local nodes = {}
	for _, line in ipairs(DESCRIPTION[mode.key] or {}) do
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = line, scale = 0.32, colour = G.C.WHITE, shadow = true, maxw = 2.3 } },
		} }
	end
	if intent == 'find_game' then
		local gm = MPAPI.GameModes[mode.key]
		local minutes = gm and gm.duration_cap_seconds and math.floor(gm.duration_cap_seconds / 60)
		nodes[#nodes + 1] = small_caption(minutes and (minutes .. 'm Time Limit') or '')
	end
	return { n = G.UIT.R, config = { align = 'cm', r = 0.1, padding = 0.06, minw = 2.4, colour = G.C.BLACK, emboss = 0.05 }, nodes = nodes }
end

-- practice: Best Time (placeholder -- no leaderboard wiring yet) + Players (real, from the
-- registered GameMode). This is the box's one and only look for practice.
local function build_practice_stat_box(mode)
	local gm = MPAPI.GameModes[mode.key]
	local players = gm and (tostring(gm:get_min_players(MPAPI.LobbyType.PRIVATE)) .. '-' .. tostring(gm:get_max_players(MPAPI.LobbyType.PRIVATE))) or '?'
	return { n = G.UIT.R, config = { align = 'cm', r = 0.1, padding = 0.06, minw = 2.4, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
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
	} }
end

-- create_lobby: just the player range (16-max private lobby for every current gamemode, hence
-- always reading "2-16" -- pulled from the GameMode definition rather than hardcoded).
local function build_lobby_stat_box(mode)
	local gm = MPAPI.GameModes[mode.key]
	local players = gm and (tostring(gm:get_min_players(MPAPI.LobbyType.PRIVATE)) .. '-' .. tostring(gm:get_max_players(MPAPI.LobbyType.PRIVATE))) or '?'
	return { n = G.UIT.R, config = { align = 'cm', r = 0.1, padding = 0.06, minw = 2.4, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = 'Players', scale = 0.3, colour = G.C.WHITE, shadow = true } },
		} },
		{ n = G.UIT.R, config = { align = 'cm', minh = 0.45 }, nodes = {
			{ n = G.UIT.T, config = { text = players, scale = 0.55, colour = G.C.MONEY, shadow = true } },
		} },
	} }
end

-- One half (Queue or In Game) of the find_game stat box, styled after the base game's own
-- Ante/Round HUD boxes (functions/UI_definitions.lua's hud_ante/row_round_text): a label row
-- above a darker inset value box.
local function build_count_half(label, value)
	return { n = G.UIT.C, config = { align = 'cm', padding = 0.04, minw = 1.05, minh = 0.85, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5), emboss = 0.05, r = 0.1 }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = label, scale = 0.24, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = tostring(value), scale = 0.5, colour = G.C.IMPORTANT, shadow = true } },
		} },
	} }
end

-- find_game: the same box footprint as the other intents (minw = 2.4, matching the pillar
-- width), but showing live in-queue/in-match player counts instead of a leaderboard stat.
-- Wrapped in an MPAPI.ui_element so the poller can refresh just these two numbers in place.
local function build_find_game_stat_box(mode)
	local el = MPAPI.ui_element(function()
		local counts = _latest_find_game_counts and _latest_find_game_counts[mode.game_mode_stat_key]
		local queued = counts and counts.queued or 0
		local in_match = counts and counts.inMatch or 0
		return { nodes = { {
			n = G.UIT.R, config = { align = 'cm', r = 0.1, padding = 0.06, minw = 2.4, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
				{ n = G.UIT.C, config = { minw = 0.15 }, nodes = {} },
				build_count_half('In Queue', queued),
				{ n = G.UIT.C, config = { minw = 0.1 }, nodes = {} },
				build_count_half('In Game', in_match),
				{ n = G.UIT.C, config = { minw = 0.15 }, nodes = {} },
			},
		} } }
	end)
	_find_game_stat_els[mode.game_mode_stat_key] = el
	return el.node
end

local function stat_box_for(mode, intent)
	if intent == 'create_lobby' then
		return build_lobby_stat_box(mode)
	elseif intent == 'find_game' then
		return build_find_game_stat_box(mode)
	end
	return build_practice_stat_box(mode)
end

local function button_for(mode, intent)
	if intent == 'create_lobby' then
		return mode.lobby_button
	elseif intent == 'find_game' then
		return mode.queue_button
	end
	return mode.practice_button
end

-- mode.name is either a plain string (one line) or a {line1, line2} table (White/Gold +
-- Ranked, whose names are too long for one line at this width). Coloured from the chip icon's
-- own two dominant colours (CHIP_COLOURS) rather than a hand-picked colour.
local function build_name_plate(mode)
	local lines = type(mode.name) == 'table' and mode.name or { mode.name }
	local text_nodes = {}
	for _, line in ipairs(lines) do
		text_nodes[#text_nodes + 1] = { n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.T, config = { text = line, scale = 0.35, colour = G.C.WHITE, shadow = true, maxw = 2.2 } },
		} }
	end
	local colours = CHIP_COLOURS[mode.chip_row] or { bg = G.C.BLACK, icon = G.C.WHITE }
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
		{ n = G.UIT.R, config = {
			align = 'cm', r = 0.1, outline = 1, outline_colour = colours.icon, colour = darken(colours.bg, 0.3),
			minw = 2.3, emboss = 0.1, padding = 0.06, line_emboss = 1,
		}, nodes = text_nodes },
	} }
end

local function build_pillar(mode, intent, sprite_tracker)
	local is_disabled = intent == 'find_game' and mode.ranked and not SPDRN._ranked_queue_available()
	local select_config = {
		align = 'cm', minh = 0.5, minw = 2.2, padding = 0.06, r = 0.1,
		colour = is_disabled and G.C.UI.BACKGROUND_INACTIVE or G.C.ORANGE,
	}
	if not is_disabled then
		select_config.shadow = true
		select_config.hover = true
		select_config.one_press = true
		select_config.button = button_for(mode, intent)
	end

	return { n = G.UIT.C, config = { align = 'cm' }, nodes = { {
		n = G.UIT.R,
		config = { id = mode.key .. (mode.ranked and '_ranked' or ''), align = 'tm', r = 0.1, padding = 0.05 },
		nodes = { {
			-- The visible pillar background: align = 'tm' (not 'cm') and a tall minh keep the
			-- content stacked at the top and let the coloured/outlined background itself stretch
			-- down to fill the rest of the page, instead of centering the (shorter) content
			-- inside a tall box and leaving empty gaps above and below it.
			n = G.UIT.R,
			config = { align = 'tm', minh = 7.4, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5), r = 0.1, outline = 1, outline_colour = G.C.L_BLACK },
			nodes = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.15 }, nodes = {
					{ n = G.UIT.R, config = select_config, nodes = {
						{ n = G.UIT.T, config = { text = 'SELECT', scale = 0.4, colour = is_disabled and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT, shadow = not is_disabled } },
					} },
				} },
				build_name_plate(mode),
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.05, minh = 1.1 }, nodes = {
					{ n = G.UIT.O, config = { object = build_chip_sprite(mode.chip_row, sprite_tracker) } },
				} },
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
					build_description_box(mode, intent),
				} },
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
					stat_box_for(mode, intent),
				} },
			},
		} },
	} } }
end

-- sprite_tracker: an array the caller (the spdrn_game_select page's build(), core.lua) owns
-- and later passes to SPDRN.dispose_game_select_sprites to :remove() every chip sprite this
-- call created -- see build_chip_sprite's comment for why that's required.
function SPDRN.build_game_select_ui(intent, sprite_tracker)
	intent = intent or 'practice'
	local modes = intent == 'find_game' and FIND_GAME_MODES or PRACTICE_LOBBY_MODES

	local row = {}
	local prev_ranked = nil
	for _, mode in ipairs(modes) do
		-- Extra gap between the Casual and Ranked groups (find_game only -- prev_ranked stays
		-- nil for every practice/create_lobby mode, none of which set `ranked`, so this never
		-- fires there).
		if prev_ranked ~= nil and mode.ranked ~= prev_ranked then
			row[#row + 1] = { n = G.UIT.C, config = { minw = 0.9 }, nodes = {} }
		end
		prev_ranked = mode.ranked
		row[#row + 1] = build_pillar(mode, intent, sprite_tracker)
	end

	return {
		n = G.UIT.ROOT,
		config = { align = 'tm', colour = G.C.CLEAR },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0 }, nodes = row },
		},
	}
end

G.FUNCS.spdrn_game_select_queue_white_stake_triple = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end
G.FUNCS.spdrn_game_select_queue_gold_stake_single = function()
	SPDRN._join_queue(SPDRN.LobbyKind.CASUAL, SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

-- The shared "choose a gamemode" page (MPAPI page spdrn_game_select), built on MPAPI's generic
-- pillar-row layout (BalatroMultiplayerAPI/api/ui_pillar_row.lua, extracted from an earlier,
-- SPDRN-only version of this same file) -- a select button, a name plate, a gamemode chip icon,
-- a description plate, and a stat box, stretched to fill the rest of the page's height. This
-- file now only supplies SPDRN's own data and content (which gamemodes, their art/colours/
-- descriptions, live queue polling, matchmaking button handlers); the pillar shape itself lives
-- once in MPAPI so any other MPAPI-consuming mod can build its own picker the same way.
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
	[SPDRN.Gamemode.ALL_DECK] = { '15 Runs.' },
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
-- by gamemode, so `mode.ranked` (fed to MPAPI.ui_pillar_row as each item's `group`) lands
-- adjacent entries in the same cluster -- keep any future addition to this list sorted the same
-- way (all entries sharing a `ranked` value adjacent to each other). game_mode_stat_key doubles
-- as the exact wire game_mode string SPDRN._join_queue computes internally (SPDRN._queue_handles
-- is keyed by it too) -- there's deliberately no separate queue_button id per mode: the SELECT
-- button is built dynamically (build_queue_select_button) since it has to flip between
-- QUEUE/CANCEL live as this exact key's own queued state changes.
local FIND_GAME_MODES = {
	{ key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, name = { 'White Stake', 'Triple Ranked' }, chip_row = CHIP_ROW.white_stake_triple_ranked,
		ranked = true, game_mode_stat_key = SPDRN.LobbyKind.RANKED_PREFIX .. SPDRN.Gamemode.WHITE_STAKE_TRIPLE },
	{ key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, name = { 'Gold Stake', 'Single Ranked' }, chip_row = CHIP_ROW.gold_stake_single_ranked,
		ranked = true, game_mode_stat_key = SPDRN.LobbyKind.RANKED_PREFIX .. SPDRN.Gamemode.GOLD_STAKE_SINGLE },
	{ key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, name = { 'White Stake', 'Triple' }, chip_row = CHIP_ROW.white_stake_triple,
		ranked = false, game_mode_stat_key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE },
	{ key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, name = { 'Gold Stake', 'Single' }, chip_row = CHIP_ROW.gold_stake_single,
		ranked = false, game_mode_stat_key = SPDRN.Gamemode.GOLD_STAKE_SINGLE },
}

-- The casual entries: what a private lobby may queue as a group
-- (objects/matchmaking/group_queue.lua).
SPDRN.GROUP_QUEUE_MODES = {}
for _, mode in ipairs(FIND_GAME_MODES) do
	if not mode.ranked then
		SPDRN.GROUP_QUEUE_MODES[#SPDRN.GROUP_QUEUE_MODES + 1] = mode
	end
end

-- Live queue/in-game counts while the find_game intent is open. Started from the page's
-- on_enter and stopped from its cleanup (see the MPAPI.Page registration in core.lua) -- a
-- page's own show/leave lifecycle is a simpler, more robust "is this still open" signal than
-- inferring it from UI state, same reasoning the old Find Game overlay's poller comment gave.
local FIND_GAME_POLL_INTERVAL_SECONDS = 5
local _find_game_poller = nil
local _latest_find_game_counts = nil
local _find_game_stat_els = {}

-- Every find_game pillar's SELECT button, keyed by the same wire game_mode string as
-- SPDRN._queue_handles -- see build_queue_select_button. Refreshed live off queue events
-- (SPDRN.refresh_game_select_queue_state, called from objects/matchmaking/queue.lua), not just
-- the 5s count poll, so a QUEUE click flips to CANCEL immediately.
local _find_game_select_els = {}

local function refresh_find_game_stats()
	for _, el in pairs(_find_game_stat_els) do
		el:update()
	end
end

-- Called from SPDRN._join_queue/_cancel_queue's handle event listeners any time a queue this
-- player is searching starts, ends, or errors -- harmless (and a no-op) when the find_game
-- pillars aren't the page currently on screen, since _find_game_select_els is only populated
-- while they are.
function SPDRN.refresh_game_select_queue_state()
	for _, el in pairs(_find_game_select_els) do
		el:update()
	end
end

-- The queue buttons grey out by the account's standing, which the server can change at any time.
if MPAPI.on_standing_changed then
	MPAPI.on_standing_changed(function()
		SPDRN.refresh_game_select_queue_state()
	end)
end

local function stop_find_game_poller_only()
	if _find_game_poller then
		_find_game_poller.stop()
		_find_game_poller = nil
	end
end

-- Called from the page's dispose() (core.lua) when leaving find_game entirely -- safe to drop
-- both els tables here since the page (and every node they point at) is going away with it.
function SPDRN.stop_find_game_polling()
	stop_find_game_poller_only()
	_find_game_stat_els = {}
	_find_game_select_els = {}
end

-- Called from on_enter (core.lua), which runs AFTER build() has already populated
-- _find_game_stat_els/_find_game_select_els for this same page transition -- must only stop a
-- previous poller, not route through the public SPDRN.stop_find_game_polling(), which also
-- wipes both els tables (correct when actually leaving the page, but here it would discard the
-- very elements build() just created, permanently breaking their live refresh for the rest of
-- this page visit -- confirmed live: the QUEUE/CANCEL button and the In Queue/In Game counts
-- both never updated in place because of this).
function SPDRN.start_find_game_polling()
	stop_find_game_poller_only()
	_latest_find_game_counts = nil
	_find_game_poller = MPAPI.matchmaking.create_queue_counts_poller(SPDRN.id, FIND_GAME_POLL_INTERVAL_SECONDS, function(err, game_modes)
		_latest_find_game_counts = game_modes or {}
		refresh_find_game_stats()
	end)
	_find_game_poller.start()
end

-- Plain Sprite, not AnimatedSprite: AnimatedSprite:animate() (engine/animatedsprite.lua)
-- unconditionally free-runs through every column of its row based on elapsed real time --
-- confirmed live (a screenshot taken mid-drag caught the sheet's later, part-faded columns
-- showing as an unintended diagonal-stripe overlay). Vanilla's blind chips use AnimatedSprite
-- because they have a real dissolve-in transition to play; this icon is meant to sit static, so
-- a plain Sprite (no per-frame column cycling) is what "static" actually requires. Deliberately
-- non-interactive too, matching vanilla's own blind chip (create_UIBox_blind_choice embeds its
-- chip animation as a bare decoration with no hover/collide/drag config at all) -- MPAPI.ui_pillar_row
-- embeds and tracks whatever's handed to it as `item.icon` for disposal; it never needs to be
-- interactive itself.
local function build_chip_sprite(row)
	return Sprite(0, 0, 1.1, 1.1, G.ANIMATION_ATLAS['spdrn_gamemode_chips'], { x = 0, y = row })
end

-- The upper description plate: what the gamemode is (always two lines), and (find_game only)
-- its time limit.
local function build_description_box(mode, intent)
	local caption = nil
	if intent == 'find_game' then
		local gm = MPAPI.GameModes[mode.key]
		local minutes = gm and gm.duration_cap_seconds and math.floor(gm.duration_cap_seconds / 60)
		caption = minutes and (minutes .. 'm Time Limit') or ''
	end
	return MPAPI.ui_pillar_description_box({ lines = DESCRIPTION[mode.key] or {}, caption = caption })
end

-- One half (Queue or In Game) of the find_game stat box, styled after the base game's own
-- Ante/Round HUD boxes (functions/UI_definitions.lua's hud_ante/row_round_text): a label row
-- above a darker inset value box.
local function build_count_half(label, value)
	return { n = G.UIT.C, config = { align = 'cm', padding = 0.02, minw = 1.0, minh = 0.85, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5), emboss = 0.05, r = 0.1 }, nodes = {
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
		return { nodes = { MPAPI.ui_embossed_box({ minw = 2.4, nodes = {
			build_count_half('In Queue', queued),
			{ n = G.UIT.C, config = { minw = 0.06 }, nodes = {} },
			build_count_half('In Game', in_match),
		} }) } }
	end)
	_find_game_stat_els[mode.game_mode_stat_key] = el
	return el.node
end

-- find_game only, shown below the In Queue/In Game card: every matchmade mode runs under
-- MPAPI's "Order" (SPDRN.Ruleset.ORDER, see core.lua's lobby metadata) deterministic-RNG
-- system, so this surfaces the existing (main-menu-less, per ui/the_order.lua's own comment)
-- explainer overlay from here instead.
local function build_order_card()
	return MPAPI.ui_embossed_box({ minw = 2.4, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
			{ n = G.UIT.C, config = {
				align = 'cm', minw = 2.2, minh = 0.6, padding = 0.06, r = 0.1,
				colour = G.C.BLUE, shadow = true, hover = true, one_press = true, button = 'the_order_open',
			}, nodes = {
				{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
					{ n = G.UIT.T, config = { text = 'Uses', scale = 0.32, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
				{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
					{ n = G.UIT.T, config = { text = 'The Order', scale = 0.32, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
			} },
		} },
	} })
end

local function stat_box_for(mode, intent)
	if intent == 'create_lobby' then
		local gm = MPAPI.GameModes[mode.key]
		local players = gm and (tostring(gm:get_min_players(MPAPI.LobbyType.PRIVATE)) .. '-' .. tostring(gm:get_max_players(MPAPI.LobbyType.PRIVATE))) or '?'
		return MPAPI.ui_pillar_stat_box({ label = 'Players', value = players, value_colour = G.C.MONEY })
	elseif intent == 'find_game' then
		return build_find_game_stat_box(mode)
	end
	-- practice: just Best Time (placeholder -- no leaderboard wiring yet). No player count here
	-- -- practice is always solo.
	return MPAPI.ui_pillar_stat_box({ label = 'Best Time', value = '--:--', value_colour = G.C.RED })
end

local function button_for(mode, intent)
	if intent == 'create_lobby' then
		return mode.lobby_button
	end
	return mode.practice_button
end

local function select_label_for(intent)
	if intent == 'create_lobby' then
		return 'CREATE'
	end
	return 'START'
end

-- find_game's SELECT button, rebuilt in place (via MPAPI.ui_element) any time this exact
-- mode's own queued state changes: QUEUE while not searching, CANCEL (red) while searching.
-- ref_table carries what the single shared toggle handler (spdrn_game_select_toggle_queue,
-- below) needs to act -- either leave this queue or join it, keyed by the same wire game_mode
-- string SPDRN._queue_handles uses. Fully custom (not MPAPI.ui_pillar_select_button) since it
-- needs this reactive two-state colour flip, which is SPDRN's own queueing concern.
--
-- A pillar the account's standing refuses (MPAPI.can_queue: Casual needs a valid or verified
-- account, Ranked on the Official server a launcher-verified one) is greyed, and pressing it
-- says why (spdrn_game_select_standing_refused) instead of queueing.
local function build_queue_select_button(mode, is_disabled)
	local el = MPAPI.ui_element(function()
		local queued = SPDRN._queue_handles[mode.game_mode_stat_key] ~= nil
		-- No solo queue while this client's lobby is queueing as a group.
		local Group = MPAPI.matchmaking.group
		local group_busy = Group and Group.is_active and Group.is_active() and not queued
		local may_queue, refusal = MPAPI.can_queue(mode.ranked and MPAPI.QueueKind.RANKED or MPAPI.QueueKind.CASUAL)
		local standing_refused = not queued and not may_queue
		local is_disabled = is_disabled or group_busy or standing_refused
		local config = {
			align = 'cm', minh = 0.5, minw = 2.2, padding = 0.06, r = 0.1,
			colour = is_disabled and G.C.UI.BACKGROUND_INACTIVE or (queued and G.C.RED or G.C.ORANGE),
		}
		if standing_refused and not group_busy then
			config.hover = true
			config.button = 'spdrn_game_select_standing_refused'
			config.ref_table = { refusal = refusal }
		end
		if not is_disabled then
			config.shadow = true
			config.hover = true
			config.one_press = true
			config.button = 'spdrn_game_select_toggle_queue'
			config.ref_table = queued
				and { game_mode = mode.game_mode_stat_key }
				or { game_mode = mode.game_mode_stat_key, kind = mode.ranked and SPDRN.LobbyKind.RANKED or SPDRN.LobbyKind.CASUAL, gamemode_key = mode.key }
		end
		return { nodes = { { n = G.UIT.R, config = config, nodes = {
			{ n = G.UIT.T, config = { text = queued and 'CANCEL' or 'QUEUE', scale = 0.4, colour = is_disabled and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT, shadow = not is_disabled } },
		} } } }
	end)
	_find_game_select_els[mode.game_mode_stat_key] = el
	return el.node
end

-- The single handler behind every find_game pillar's SELECT/CANCEL button. Whether this join
-- or leaves depends on ref_table.kind's presence, not any state read here -- the button that
-- was actually clicked already encoded, at the moment it was rendered, which action it means
-- (see build_queue_select_button) -- so this can't race against a queue state change that
-- happens between click and handling.
G.FUNCS.spdrn_game_select_toggle_queue = function(e)
	local rt = e.config.ref_table
	if not rt then
		return
	end
	if rt.kind then
		SPDRN._join_queue(rt.kind, rt.gamemode_key)
	else
		SPDRN._cancel_queue(rt.game_mode)
	end
end

-- A standing-refused pillar's press: MPAPI's ui/mods_not_allowed_overlay.lua says why.
G.FUNCS.spdrn_game_select_standing_refused = function(e)
	local rt = e.config.ref_table
	if rt and rt.refusal then
		MPAPI.show_standing_refusal(rt.refusal)
	end
end

-- In group mode (opened from a private lobby's Group Queue button, ui/lobby/group_panel.lua)
-- a pillar's QUEUE queues the whole lobby for its mode instead (objects/matchmaking/
-- group_queue.lua). A mode the lobby doesn't fit is greyed; one a member's standing refuses
-- is greyed but still pressable, so the server's refusal says which mods.
local function build_group_select(mode)
	local el = MPAPI.ui_element(function()
		local available, standing_refused = SPDRN.group_mode_available(MPAPI.get_current_lobby(), mode.key)
		local lit = available and not standing_refused
		local config = {
			align = 'cm', minh = 0.5, minw = 2.2, padding = 0.06, r = 0.1,
			colour = lit and G.C.ORANGE or G.C.UI.BACKGROUND_INACTIVE,
		}
		if available then
			config.shadow = lit
			config.hover = true
			config.one_press = true
			config.button = 'spdrn_group_queue_mode'
			config.ref_table = { gamemode_key = mode.key }
		end
		return { nodes = { { n = G.UIT.R, config = config, nodes = {
			{ n = G.UIT.T, config = { text = 'QUEUE', scale = 0.4, colour = lit and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE, shadow = lit } },
		} } } }
	end)
	_find_game_select_els[mode.game_mode_stat_key] = el
	return el.node
end

-- Group mode's header: the way back to the lobby.
local function build_group_header()
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
		{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
			UIBox_button({ button = 'spdrn_group_queue_back', label = { localize('b_back') }, colour = G.C.ORANGE, minw = 2.4, minh = 0.6, scale = 0.4 }),
		} },
		{ n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
			UIBox_button({ button = 'nil', label = { localize('k_group_queue') }, colour = G.C.BLUE, minw = 3.0, minh = 0.6, scale = 0.4 }),
		} },
	} }
end

local function build_select(mode, intent, is_disabled, group)
	if group then
		return build_group_select(mode)
	end
	if intent == 'find_game' then
		return build_queue_select_button(mode, is_disabled)
	end
	return MPAPI.ui_pillar_select_button({
		label = select_label_for(intent),
		button = button_for(mode, intent),
		disabled = is_disabled,
	})
end

-- Builds the pillar-row controller (MPAPI.ui_pillar_row's return value: {definition, row_node,
-- dispose}) for the given intent. The caller (spdrn_game_select's MPAPI.Page registration in
-- core.lua) owns the controller for this page's lifetime: hand `.definition` to build(), and
-- call `:dispose()` from the page's own dispose() hook so every tracked chip icon gets
-- :remove()'d -- see api/ui_pillar_row.lua's header comment for why that's required.
-- `group` (find_game only) builds the casual pillars for queueing the current private lobby
-- as a group, with a back-to-lobby header above them.
function SPDRN.build_game_select_ui(intent, group)
	intent = intent or 'practice'
	group = group and intent == 'find_game'
	local modes = group and SPDRN.GROUP_QUEUE_MODES or intent == 'find_game' and FIND_GAME_MODES or PRACTICE_LOBBY_MODES

	local items = {}
	for _, mode in ipairs(modes) do
		-- find_game's queue buttons grey themselves by the account's standing
		-- (build_queue_select_button); nothing else is disabled up front.
		local is_disabled = false
		local colours = CHIP_COLOURS[mode.chip_row] or { bg = G.C.BLACK, icon = G.C.WHITE }
		items[#items + 1] = {
			id = mode.key .. (mode.ranked and '_ranked' or ''),
			group = mode.ranked,
			icon = build_chip_sprite(mode.chip_row),
			select = build_select(mode, intent, is_disabled, group),
			name_plate = MPAPI.ui_pillar_name_plate({
				lines = mode.name,
				bg_colour = darken(colours.bg, 0.3),
				outline_colour = colours.icon,
			}),
			description = build_description_box(mode, intent),
			stat_box = stat_box_for(mode, intent),
			extra = intent == 'find_game' and build_order_card() or nil,
		}
	end

	-- Getting the pillars to sit lower on the page is NOT done here: a spacer row above this
	-- one, and a node's own `offset`, were both tried and measurably did nothing -- the box's
	-- position is re-anchored every frame regardless of this content. The actual fix is in
	-- core.lua's on_enter, which nudges G.MAIN_MENU_UI.alignment.offset.y directly (the same
	-- field api/page/manager.lua itself sets to 0 after construction).
	local pillar_row = MPAPI.ui_pillar_row({ items = items, group_gap = 0.9 })
	if group then
		table.insert(pillar_row.definition.nodes, 1, build_group_header())
	end
	return pillar_row
end

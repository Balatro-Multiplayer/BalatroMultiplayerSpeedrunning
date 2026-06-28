-----------------------------
-- STATE VARIABLES
-----------------------------

local _lobby_options_button
local _leave_lobby_button
local _start_game_button
local _ready_button
local _view_code_button
local _copy_code_button
local _lobby_buttons_initialized = false

local _current_lobby_ref = nil
local _current_lobby_ui_ref = nil

-- This client's own ready flag (guest, private lobbies).
local _local_ready = false
local _ready_args
-- Host guard so the matchmaking auto-start only fires a single start broadcast.
local _start_broadcasted = false
-- Host-side ready tracker. Used to gate START (private) and to trigger the
-- matchmaking auto-start once everyone has loaded.
local _ready = MPAPI.ReadyTracker()
-- Seed-change votes. A unanimous vote restarts the match on a fresh seed.
local _seed_votes = MPAPI.VoteTracker()

-----------------------------
-- LOBBY KIND
-----------------------------

-- Authoritative client-side lobby kind. Every entry path (create / join / queue /
-- practice) sets SPDRN._lobby_kind before the lobby view is built, so UI and start
-- logic never have to wait on async metadata. Defaults to 'private'.
function SPDRN.get_lobby_kind()
	return SPDRN._lobby_kind or 'private'
end

function SPDRN.is_matchmaking(kind)
	kind = kind or SPDRN.get_lobby_kind()
	return kind == 'ranked' or kind == 'casual'
end

-----------------------------
-- UI FUNCTIONS
-----------------------------

local create_lobby_buttons

-- Green/black code panel reused by the private control bar.
local function code_panel()
	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.1, r = 0.2, colour = G.C.BLACK },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = 'cm', maxh = 1.4 },
				nodes = {
					{ n = G.UIT.T, config = { text = localize('k_lobby_code_cap'), scale = 0.45, colour = G.C.UI.TEXT_LIGHT, vert = true, maxh = 1.4 } },
				},
			},
			{
				n = G.UIT.C,
				config = { align = 'cm', padding = 0.1 },
				nodes = {
					{ n = G.UIT.R, config = { align = 'cm' }, nodes = { _view_code_button.node } },
					{ n = G.UIT.R, config = { align = 'cm' }, nodes = { _copy_code_button.node } },
				},
			},
		},
	}
end

-- Private lobbies: host gets START + LOBBY OPTIONS; guests get a READY toggle.
-- Both sides get the code panel and LEAVE.
-- Lobby deck control: a host-only button that opens the deck picker and sets the
-- lobby-wide deck; guests see the chosen deck as a read-only label. Rebuilt with the
-- lobby view, so it reflects the current metadata deck (refreshed on metadata_changed).
local function deck_panel()
	local meta = (_current_lobby_ref and _current_lobby_ref:get_metadata()) or {}
	local deck_name = SPDRN.deck_label(meta.deck)
	if _current_lobby_ref and _current_lobby_ref.is_host then
		return { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
			UIBox_button({ id = 'spdrn_choose_deck', button = 'spdrn_choose_deck', colour = G.C.PURPLE, minw = 2.65, minh = 1.35, label = { 'Deck', deck_name }, scale = 0.4, col = true }),
		} }
	end
	return { n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.1, colour = G.C.L_BLACK, minw = 2.65, minh = 1.35, emboss = 0.05 }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = 'Deck', scale = 0.32, colour = G.C.UI.TEXT_INACTIVE } } } },
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = deck_name, scale = 0.42, colour = G.C.UI.TEXT_LIGHT, shadow = true } } } },
	} }
end

local function build_private_controls()
	local row_nodes = {}
	if _current_lobby_ref and _current_lobby_ref.is_host then
		row_nodes[#row_nodes + 1] = _start_game_button.node
		row_nodes[#row_nodes + 1] = _lobby_options_button.node
	else
		row_nodes[#row_nodes + 1] = _ready_button.node
	end
	row_nodes[#row_nodes + 1] = deck_panel()
	row_nodes[#row_nodes + 1] = code_panel()
	row_nodes[#row_nodes + 1] = _leave_lobby_button.node

	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.1, r = 0.1, emboss = 0.1, colour = G.C.L_BLACK, mid = true },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = row_nodes },
		},
	}
end

-- Host-only: open the deck picker and, on confirm, set the deck for the whole lobby via
-- metadata (synced to all clients, who see it on the read-only deck label).
G.FUNCS.spdrn_choose_deck = function()
	local lobby = _current_lobby_ref
	if not lobby or not lobby.is_host then
		return
	end
	local meta = lobby:get_metadata() or {}
	local gm = meta.gamemode and MPAPI.GameModes[meta.gamemode]
	local count = SPDRN.required_deck_count(gm)
	SPDRN.open_deck_select(meta.deck or 'Blue Deck', function(decks)
		local m = lobby:get_metadata() or {}
		local new_meta = {}
		for k, v in pairs(m) do
			new_meta[k] = v
		end
		new_meta.deck = SPDRN.meta_deck_value(decks)
		lobby:set_metadata(new_meta)
	end, count)
end

-- Matchmaking lobbies (ranked / casual): no action buttons at all. Just a status
-- line; the run auto-starts once every client has signalled ready.
local function build_matchmaking_controls()
	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.2, r = 0.1, emboss = 0.1, colour = G.C.L_BLACK, mid = true },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
				{ n = G.UIT.T, config = { id = 'spdrn_mm_status', text = localize('k_waiting_for_players') or 'Waiting for players...', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
			} },
		},
	}
end

SPDRN.build_in_lobby_ui = function()
	local lobby = MPAPI.get_current_lobby()

	-- Practice has no lobby view. If we land here with a practice lobby still engaged
	-- (e.g. a run abandoned without using the end-screen buttons), drop it and show
	-- the main menu instead of building a lobby view for it.
	if lobby and SPDRN.get_lobby_kind() == 'practice' then
		local dead = lobby
		G.E_MANAGER:add_event(Event({ func = function()
			dead:leave()
			return true
		end }))
		return SPDRN.build_pre_lobby_ui()
	end

	-- Defensive: re-create the player-card UI if its ref was lost, and fall back to
	-- the pre-lobby menu rather than indexing a nil ref if there is no active lobby.
	if lobby and not _current_lobby_ui_ref then
		_current_lobby_ref = lobby
		_current_lobby_ui_ref = MPAPI.create_lobby_ui(lobby)
	end
	if not _current_lobby_ui_ref then
		return SPDRN.build_pre_lobby_ui()
	end

	create_lobby_buttons()
	MPAPI.set_logo_offset(-10, true)

	local controls = SPDRN.is_matchmaking() and build_matchmaking_controls() or build_private_controls()

	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = 'cm' },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = 'cm', padding = 0.1, mid = true },
						nodes = {
							_current_lobby_ui_ref.node,
						},
					},
					{
						n = G.UIT.R,
						config = { minh = 0.2 },
					},
					{
						n = G.UIT.R,
						config = { align = 'cm' },
						nodes = { controls },
					},
				},
			},
		},
	}
end

create_lobby_buttons = function()
	if not _lobby_buttons_initialized then
		_start_game_button = MPAPI.disableable_button({
			id = 'spdrn_start_game',
			button = 'spdrn_start_game',
			colour = G.C.BLUE,
			minw = 3.65,
			minh = 1.55,
			label = { 'START GAME' },
			scale = 0.7,
			enabled = function()
				if not _current_lobby_ref or not _current_lobby_ref.is_host then
					return false
				end
				local meta = _current_lobby_ref:get_metadata()
				local gm = meta.gamemode and MPAPI.GameModes[meta.gamemode]
				if not gm then
					return false
				end
				local players = _current_lobby_ref:get_players()
				if #players < gm:get_min_players('private') then
					return false
				end
				-- Multi-deck modes (e.g. White Stake Triple) need one deck per run chosen
				-- up front via the deck picker; block START until enough are saved.
				local need = SPDRN.required_deck_count(gm)
				if need > 1 then
					local have = type(meta.deck) == 'table' and #meta.deck or 1
					if have < need then
						return false
					end
				end
				-- Host can only start once every guest has readied up.
				for _, p in ipairs(players) do
					if p.id ~= _current_lobby_ref.player_id and not _ready:is_ready(p.id) then
						return false
					end
				end
				return true
			end,
		})
		_ready_args = {
			id = 'spdrn_ready',
			button = 'spdrn_toggle_ready',
			colour = G.C.GREEN,
			minw = 3.65,
			minh = 1.55,
			label = { localize('b_ready_cap') or 'READY' },
			scale = 0.7,
			col = true,
			enabled = true,
		}
		_ready_button = MPAPI.disableable_button(_ready_args)
		_lobby_options_button = MPAPI.disableable_button({
			id = 'spdrn_lobby_options',
			button = 'spdrn_lobby_options',
			colour = G.C.ORANGE,
			minw = 2.65,
			minh = 1.35,
			label = localize('b_lobby_options_cap'),
			scale = 0.7,
			col = true,
			enabled = true,
		})
		_view_code_button = MPAPI.disableable_button({
			id = 'spdrn_view_code',
			button = 'spdrn_view_code',
			colour = G.C.GREEN,
			minw = 3.65,
			minh = 0.6,
			label = { localize('b_view_code_cap') },
			scale = 0.45,
			enabled = true,
		})
		_copy_code_button = MPAPI.disableable_button({
			id = 'spdrn_copy_code',
			button = 'spdrn_copy_code',
			colour = G.C.PURPLE,
			minw = 3.65,
			minh = 0.6,
			label = { localize('b_copy_code_cap') },
			scale = 0.45,
			enabled = true,
		})
		_leave_lobby_button = MPAPI.disableable_button({
			id = 'spdrn_leave_lobby',
			button = 'spdrn_leave_lobby',
			colour = G.C.RED,
			minw = 3.65,
			minh = 1.55,
			label = localize('b_leave_lobby_cap'),
			scale = 0.7,
			col = true,
			enabled = true,
		})
	end

	_lobby_buttons_initialized = true
end

-----------------------------
-- LOGIC FUNCTIONS
-----------------------------

SPDRN.setup_lobby_events = function(lobby)
	_current_lobby_ref = lobby
	_current_lobby_ui_ref = MPAPI.create_lobby_ui(lobby)
	_ready:reset()
	_seed_votes:reset()
	_local_ready = false
	_start_broadcasted = false
	-- One-shot guard for the guest's ready re-announce (see player_ready action).
	SPDRN._ready_resent = false

	local update_game_buttons = function()
		if _start_game_button then
			_start_game_button:update()
		end
		SPDRN.refresh_matchmaking_status()
	end

	lobby:on('player_joined', function(player_id)
		SPDRN.sendDebugMessage('Player joined: ' .. tostring(player_id))
		update_game_buttons()
		-- A late arrival may complete the ready set.
		SPDRN.maybe_autostart()
	end)

	lobby:on('player_left', function(player_id)
		SPDRN.sendDebugMessage('Player left: ' .. tostring(player_id))
		_ready:remove(player_id)
		_seed_votes:remove(player_id)
		update_game_buttons()
	end)

	lobby:on('connected', function()
		update_game_buttons()
	end)

	-- Private lobbies build their control bar from lobby state at build time (deck label,
	-- host's START/OPTIONS vs guest's READY), so a deck or host change has to rebuild the
	-- view, not just patch the START button. Matchmaking lobbies have only a status line,
	-- so they keep the light path (and avoid player-card flicker).
	lobby:on('metadata_changed', function(metadata)
		if not SPDRN.is_matchmaking() then
			MPAPI.refresh_current_view()
		end
		update_game_buttons()
	end)

	lobby:on('host_changed', function()
		if not SPDRN.is_matchmaking() then
			MPAPI.refresh_current_view()
		end
		update_game_buttons()
	end)

	lobby:on('error', function(err)
		SPDRN.sendWarnMessage('Lobby error: ' .. tostring(err))
	end)

	lobby:on('disconnected', function()
		SPDRN.sendDebugMessage('Disconnected from lobby')
		_current_lobby_ref = nil
		_current_lobby_ui_ref = nil
		_lobby_buttons_initialized = false
		_ready:reset()
		_seed_votes:reset()
		_local_ready = false
		_start_broadcasted = false
		SPDRN._lobby_kind = nil
		-- The match handle is independent of the lobby (lobby:leave() does not fire the
		-- handle's 'left'). Drop it here so a later solo run's win path can't report a
		-- result against the finished match.
		SPDRN._current_match_handle = nil
	end)
end

-----------------------------
-- READY SYSTEM
-----------------------------

-- Broadcast this client's ready state. The host (including itself, via the
-- broadcast loopback) tallies these in the ready tracker.
function SPDRN.signal_ready(ready)
	local lobby = _current_lobby_ref
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_player_ready'])
	action:broadcast({ ready = ready and true or false })
end

-- Matchmaking safety net for the lobby-join race: re-broadcast our ready a few times
-- over the first several seconds (via MPAPI.ready_resync). Idempotent (set_player_ready
-- just re-records true), and self-terminates once the start broadcast lands
-- (SPDRN.stop_ready_resync) or after the attempt cap. Covers the case where the initial
-- ready was published before the peer had subscribed to the actions topic.
function SPDRN.start_ready_resync()
	if not SPDRN.is_matchmaking() then
		return
	end
	SPDRN._ready_resync_stop = MPAPI.ready_resync({
		send = function()
			SPDRN.signal_ready(true)
		end,
		should_continue = function()
			return _current_lobby_ref ~= nil and SPDRN.is_matchmaking()
		end,
	})
end

-- Stop the ready re-announce loop (called once the start broadcast lands).
function SPDRN.stop_ready_resync()
	if SPDRN._ready_resync_stop then
		SPDRN._ready_resync_stop()
		SPDRN._ready_resync_stop = nil
	end
end

-- Clear all ready state. Called locally on every client when the game starts so a
-- subsequent return to the lobby starts everyone un-readied, and resets the guest's
-- READY toggle visuals. Safe to call when no lobby UI is mounted (updates no-op).
function SPDRN.reset_ready_state()
	_ready:reset()
	_local_ready = false
	_start_broadcasted = false
	if _ready_args then
		_ready_args.label = { localize('b_ready_cap') or 'READY' }
		_ready_args.colour = G.C.GREEN
	end
	if _ready_button then
		_ready_button:update()
	end
	if _start_game_button then
		_start_game_button:update()
	end
end

-- Host-only: record a player's ready state and react (refresh START for private
-- lobbies, or kick off the auto-start for matchmaking).
function SPDRN.set_player_ready(player_id, ready)
	if not _current_lobby_ref or not _current_lobby_ref.is_host then
		return
	end
	_ready:set(player_id, ready)
	if SPDRN.is_matchmaking() then
		SPDRN.refresh_matchmaking_status()
		SPDRN.maybe_autostart()
	elseif _start_game_button then
		_start_game_button:update()
	end
end

-- True when every player currently in the lobby has signalled ready.
local function all_players_ready()
	return _ready:all_ready()
end

-- Host-only matchmaking auto-start: once all clients are ready (and min players
-- met) broadcast the start exactly once.
function SPDRN.maybe_autostart()
	if _start_broadcasted then
		return
	end
	if not _current_lobby_ref or not _current_lobby_ref.is_host then
		return
	end
	if not SPDRN.is_matchmaking() then
		return
	end
	local meta = _current_lobby_ref:get_metadata()
	local gm = meta.gamemode and MPAPI.GameModes[meta.gamemode]
	local min_players = gm and gm:get_min_players('ranked') or 2
	if #_current_lobby_ref:get_players() < min_players then
		return
	end
	if not all_players_ready() then
		return
	end
	_start_broadcasted = true
	SPDRN.broadcast_start(SPDRN.generate_seed())
end

-- Finds a live UI element by id across the open UIBoxes (the lobby controls live
-- in the main-menu UIBox, not an overlay).
local function find_uie(id)
	local uiboxes = G.I and G.I.UIBOX
	if not uiboxes then
		return nil
	end
	for _, box in ipairs(uiboxes) do
		if box.get_UIE_by_ID then
			local found = box:get_UIE_by_ID(id)
			if found then
				return found
			end
		end
	end
	return nil
end

-- Updates the matchmaking lobby's status line in place (no-op otherwise).
function SPDRN.refresh_matchmaking_status()
	if not SPDRN.is_matchmaking() then
		return
	end
	local text_e = find_uie('spdrn_mm_status')
	if not text_e or not text_e.config then
		return
	end
	local txt = all_players_ready() and (localize('k_get_ready') or 'Get ready!')
		or (localize('k_waiting_for_players') or 'Waiting for players...')
	if text_e.config.text ~= txt then
		text_e.config.text = txt
		if text_e.UIBox then
			text_e.UIBox:recalculate()
		end
	end
end

G.FUNCS.spdrn_lobby_options = function()
	local contents = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Lobby Options', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	}

	if _current_lobby_ref and _current_lobby_ref.is_host then
		local meta = _current_lobby_ref:get_metadata()
		local current_key = meta.gamemode
		local current_ruleset = meta.ruleset or 'spdrn_order'
		contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Change Gamemode', scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} }
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_change_white_stake_triple',
					label = { 'White Stake Triple' .. (current_key == 'spdrn_white_stake_triple' and ' *' or '') },
					colour = current_key == 'spdrn_white_stake_triple' and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_change_gold_stake_single',
					label = { 'Gold Stake Single' .. (current_key == 'spdrn_gold_stake_single' and ' *' or '') },
					colour = current_key == 'spdrn_gold_stake_single' and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
		contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Change Ruleset', scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} }
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_set_ruleset_order',
					label = { 'The Order' .. (current_ruleset == 'spdrn_order' and ' *' or '') },
					colour = current_ruleset == 'spdrn_order' and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_set_ruleset_vanilla',
					label = { 'Vanilla' .. (current_ruleset == 'spdrn_vanilla' and ' *' or '') },
					colour = current_ruleset == 'spdrn_vanilla' and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
	end

	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({ contents = contents }),
	})
end

local function change_gamemode(key)
	if _current_lobby_ref and _current_lobby_ref.is_host then
		local meta = _current_lobby_ref:get_metadata()
		-- If the new mode needs a different number of decks, the saved deck(s) no longer fit;
		-- reset to the default so the host re-picks the right count via the deck button.
		local need = SPDRN.required_deck_count(MPAPI.GameModes[key])
		local have = type(meta.deck) == 'table' and #meta.deck or 1
		local deck = (have == need and meta.deck) or 'Blue Deck'
		_current_lobby_ref:set_metadata({ gamemode = key, deck = deck, ruleset = meta.ruleset or 'spdrn_order' })
	end
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.spdrn_change_white_stake_triple = function()
	change_gamemode('spdrn_white_stake_triple')
end

G.FUNCS.spdrn_change_gold_stake_single = function()
	change_gamemode('spdrn_gold_stake_single')
end

local function change_ruleset(key)
	if _current_lobby_ref and _current_lobby_ref.is_host then
		local meta = _current_lobby_ref:get_metadata()
		_current_lobby_ref:set_metadata({ gamemode = meta.gamemode, deck = meta.deck or 'Blue Deck', ruleset = key })
	end
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.spdrn_set_ruleset_order = function()
	change_ruleset('spdrn_order')
end

G.FUNCS.spdrn_set_ruleset_vanilla = function()
	change_ruleset('spdrn_vanilla')
end

SPDRN.generate_seed = function()
	local chars = 'ABCDEFGHIJKLMNPQRSTUVWXYZ123456789'
	local seed = ''
	for i = 1, 8 do
		local idx = math.random(1, #chars)
		seed = seed .. chars:sub(idx, idx)
	end
	return seed
end

-----------------------------
-- RUN START / COUNTDOWN
-----------------------------

-- Start (or restart) a Balatro run safely. G.FUNCS.start_run does not tear down an
-- existing run, so calling it mid-game leaves the old run's board and HUD alive --
-- and the dangling blind HUD crashes the blind-HUD update assert (smods
-- src/overrides.lua), reliably at high game speed. So delete the current run first,
-- then start fresh on the next event tick (the same clean-restart path the game and
-- the base multiplayer mod use).
local function safe_start_run(instance, deck, seed)
	-- Tear the current run down now (synchronously, before this frame's UIBox update
	-- loop can touch the old blind HUD and assert), then start the new run on the
	-- next event tick so the teardown fully settles first.
	pcall(function()
		if G.STAGE == G.STAGES.RUN and G.delete_run then
			G:delete_run()
		end
		G.HUD_blind = nil
	end)
	G.E_MANAGER:add_event(Event({
		blocking = false,
		blockable = false,
		func = function()
			instance:start_run(deck, seed)
			return true
		end,
	}))
end

-- How many decks a gamemode needs chosen up front for a practice/private run: one per
-- run it plays. White Stake Triple is best-of-3 (ban_pick.keep == 3), so it needs three;
-- single-run modes need one. (Matchmaking draws its decks from the ban-pick draft instead,
-- so this is only consulted by the deck picker / start gate for practice + private.)
function SPDRN.required_deck_count(gm_def)
	if gm_def and gm_def.ban_pick and gm_def.ban_pick.keep then
		return gm_def.ban_pick.keep
	end
	return 1
end

-- Normalize a chosen-deck value for metadata: a multi-deck list is stored as a list, a
-- single deck as a plain string (keeps the single-deck shape that existing readers expect).
function SPDRN.meta_deck_value(decks)
	if type(decks) == 'table' then
		if #decks > 1 then
			return decks
		end
		return decks[1] or 'Blue Deck'
	end
	return decks or 'Blue Deck'
end

-- A short human label for a metadata deck value (string or list), for the lobby deck panel.
function SPDRN.deck_label(meta_deck)
	if type(meta_deck) == 'table' then
		if #meta_deck == 0 then
			return 'Blue Deck'
		end
		if #meta_deck == 1 then
			return meta_deck[1]
		end
		return #meta_deck .. ' decks'
	end
	return meta_deck or 'Blue Deck'
end

-- Resolve a deck reference to a Back center KEY. Accepts either a center key already
-- (e.g. 'b_red', as produced by the ban-pick draft) or a display name (e.g. 'Blue Deck',
-- as stored in lobby metadata). Returns nil if it matches no deck. The deck is applied at
-- run start via G.GAME.viewed_back = G.P_CENTERS[key] (see the gamemode start_run methods).
function SPDRN.resolve_back_key(deck)
	if not deck or deck == '' then
		return nil
	end
	-- Already a center key?
	local center = G.P_CENTERS[deck]
	if center and center.set == 'Back' then
		return deck
	end
	-- Otherwise match by display name.
	for _, c in ipairs(G.P_CENTER_POOLS.Back or {}) do
		if c.name == deck then
			return c.key
		end
	end
	return nil
end

-- Instantiate the gamemode for the current lobby and start the Balatro run.
-- Shared by the start_game action, practice, play-again, and seed-vote restart.
-- `decks` is either a single deck ref (single-deck flow) or a list of deck refs from a
-- ban-pick draft (e.g. White Stake Triple's three survivors, one per run). A "ref" is a
-- center key or display name; see SPDRN.resolve_back_key.
function SPDRN.begin_run(gamemode_key, decks, seed)
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local gm_def = gamemode_key and MPAPI.GameModes[gamemode_key]
	if not gm_def then
		SPDRN.sendWarnMessage('begin_run: unknown gamemode: ' .. tostring(gamemode_key))
		return
	end
	-- Normalize to a list so the gamemode can index per-run decks uniformly.
	local deck_list = type(decks) == 'table' and decks or { decks }
	-- Starting the game clears everyone's ready state (every client assumes this
	-- locally, no broadcast needed), so returning to the lobby requires re-readying.
	SPDRN.reset_ready_state()
	_seed_votes:reset()
	-- Client-side run clock (gates the seed-change window) and the deck(s) used for
	-- this run (so a same-seed restart can reuse them).
	SPDRN._run_started_at = love.timer.getTime()
	SPDRN._run_deck = deck_list[1]
	SPDRN._run_decks = deck_list
	-- Start the on-screen match timer (or take over an installed SystemClock).
	if SPDRN.timer then
		SPDRN.timer.start()
	end
	local instance = gm_def:new_instance()
	instance._run_decks = deck_list
	lobby._gamemode_instance = instance
	safe_start_run(instance, deck_list[1], seed)
end

-- Restart the *current* run on its current seed without creating a new gamemode
-- instance, so per-format progress (e.g. White Stake Triple's run count) is kept.
-- Used by the lose screen's "Restart Run".
function SPDRN.restart_current_run()
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local instance = lobby:get_gamemode_instance()
	if not instance then
		return
	end
	local seed = G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed
	-- Replay the current run's deck. With a draft (or a multi-deck mode), that's the deck
	-- for the run in progress (_run_count counts completed runs, so the live run is index + 1).
	local run_idx = (instance._run_count or 0) + 1
	local meta_deck = (lobby:get_metadata() or {}).deck
	local meta_deck_for_run = type(meta_deck) == 'table' and (meta_deck[run_idx] or meta_deck[1]) or meta_deck
	local deck = (instance._run_decks and instance._run_decks[run_idx])
		or SPDRN._run_deck or meta_deck_for_run or 'Blue Deck'
	_seed_votes:reset()
	SPDRN._run_started_at = love.timer.getTime()
	if SPDRN.timer then
		SPDRN.timer.start()
	end
	safe_start_run(instance, deck, seed)
end

-- Host broadcasts the start so every client (itself included, via the loopback)
-- runs the same synced countdown and starts on the same seed.
function SPDRN.broadcast_start(seed)
	local lobby = _current_lobby_ref or MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_start_game'])
	action:broadcast({ seed = seed or SPDRN.generate_seed() })
end

-- One face-down deck-back tile (the deck's back sprite + its name), built with the same
-- bypass_back Card pattern as the lobby player cards. `ref` is a deck name or center key.
local function deck_back_tile(ref)
	local key = SPDRN.resolve_back_key(ref) or 'b_red'
	local center = G.P_CENTERS[key]
	local name = (center and center.name) or key
	local area = CardArea(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, G.CARD_W, G.CARD_H, { card_limit = 1, type = 'title', highlight_limit = 0, collection = true })
	local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, nil, G.P_CENTERS['j_joker'], { bypass_back = center.pos })
	card.no_ui = true
	card.states.drag.can = false
	card:flip()
	area:emplace(card, nil, true)
	return { n = G.UIT.C, config = { align = 'cm', padding = 0.12 }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = area } } } },
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
			{ n = G.UIT.T, config = { text = name, scale = 0.3, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	} }
end

-- A row of deck-back tiles for the countdown overlay. `decks` is a single deck ref or an
-- ordered list (e.g. the ban-pick survivors, one run each).
local function deck_backs_row(decks)
	local refs = type(decks) == 'table' and decks or { decks }
	local cols = {}
	for _, ref in ipairs(refs) do
		cols[#cols + 1] = deck_back_tile(ref)
	end
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = cols }
end

-- 5s synced countdown overlay, then on_complete(). Used for private + matchmaking
-- starts (practice skips it and calls begin_run directly). Delegates to the generic
-- MPAPI.show_countdown, supplying the speedrun-localized label and the selected deck
-- back(s). `decks` is a single deck ref or an ordered list.
function SPDRN.show_countdown(on_complete, decks)
	local opts = {
		label = function(n)
			return (localize('k_starting_in') or 'Starting in') .. ' ' .. n
		end,
	}
	if decks then
		opts.contents = { deck_backs_row(decks) }
	end
	MPAPI.show_countdown(opts, on_complete)
end

-- Host (private) clicks START -> broadcast the start to everyone.
G.FUNCS.spdrn_start_game = function()
	if not _current_lobby_ref or not _current_lobby_ref.is_host then
		return
	end
	SPDRN.broadcast_start(SPDRN.generate_seed())
end

-- Guest READY toggle (private lobbies).
G.FUNCS.spdrn_toggle_ready = function()
	_local_ready = not _local_ready
	if _ready_args and _ready_button then
		_ready_args.label = { _local_ready and (localize('b_unready_cap') or 'UNREADY') or (localize('b_ready_cap') or 'READY') }
		_ready_args.colour = _local_ready and G.C.ORANGE or G.C.GREEN
		_ready_button:update()
	end
	SPDRN.signal_ready(_local_ready)
end

-----------------------------
-- SEED-CHANGE VOTE
-----------------------------

-- Broadcast a vote to restart the match on a new seed.
function SPDRN.cast_seed_vote()
	local lobby = _current_lobby_ref or MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_seed_vote'])
	action:broadcast({})
end

-- Runs on every client when any vote arrives (broadcast reaches all). Each client
-- tallies independently and shows progress; the host restarts on a unanimous vote.
function SPDRN.register_seed_vote(voter_id)
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end

	local count, total, unanimous = _seed_votes:record(voter_id)

	-- Surface vote progress in the chat log (works even when chat send is disabled)
	-- rather than as an on-screen toast.
	if MPAPI.chat and MPAPI.chat.addMessage then
		MPAPI.chat.addMessage(
			(localize('k_seed_vote') or 'Vote to change seed') .. ': ' .. count .. '/' .. total,
			G.C.BLUE
		)
	end

	if lobby.is_host and unanimous then
		_seed_votes:reset()
		SPDRN.broadcast_start(SPDRN.generate_seed())
	end
end

-- Lightweight in-run toast.
function SPDRN.notify(text)
	if G.STAGE ~= G.STAGES.RUN then
		return
	end
	pcall(function()
		attention_text({
			scale = 0.7,
			text = text,
			hold = 2,
			align = 'cm',
			offset = { x = 0, y = -3.5 },
			major = G.play or G.ROOM_ATTACH,
		})
	end)
end

G.FUNCS.spdrn_leave_lobby = function()
	if _current_lobby_ref then
		_current_lobby_ref:leave()
	end
end

G.FUNCS.spdrn_view_code = function(e)
	local text_config = e.children[1].children[1].config
	local code = _current_lobby_ref and _current_lobby_ref.code
	if not code then
		return
	end
	if text_config.text ~= code then
		e.config.colour = G.C.ETERNAL
		text_config.text = code
	else
		e.config.colour = G.C.GREEN
		text_config.text = localize('b_view_code_cap')
	end
	e.UIBox:recalculate()
end

G.FUNCS.spdrn_copy_code = function(e)
	local code = _current_lobby_ref and _current_lobby_ref.code
	if not code then
		return
	end
	love.system.setClipboardText(code)

	local text_config = e.children[1].children[1].config
	e.config.colour = G.C.ETERNAL
	text_config.text = localize('k_copied_cap')
	e.UIBox:recalculate()

	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 1.5,
		func = function()
			e.config.colour = G.C.PURPLE
			text_config.text = localize('b_copy_code_cap')
			e.UIBox:recalculate()
			return true
		end,
	}))
end

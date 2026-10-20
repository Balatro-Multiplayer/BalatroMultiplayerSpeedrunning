-- Group casual queue (MPAPI.matchmaking.group): the host of a private lobby
-- queues the whole lobby for a casual mode; the group meets strangers in a
-- public match and comes back to this lobby (same code, same host) after it.
-- MPAPI runs the queue; this wires its handles like a solo casual queue's
-- (objects/matchmaking/queue.lua) and says how to rejoin the home lobby.

-- The host's pick in the group panel (index into the eligible list).
SPDRN._group_mode_choice = SPDRN._group_mode_choice or 1

local function mode_name(mode)
	if type(mode.name) == 'table' then
		return table.concat(mode.name, ' ')
	end
	return tostring(mode.name or mode.key)
end

-- Every group-queueable mode: { key, display, max_players, teams }.
function SPDRN.group_queue_modes()
	local modes = {}
	for _, mode in ipairs(SPDRN.GROUP_QUEUE_MODES or {}) do
		local gm = MPAPI.GameModes[mode.key]
		if gm then
			modes[#modes + 1] = {
				key = mode.key,
				display = mode_name(mode),
				max_players = (gm.max_players and gm.max_players.public) or 2,
				teams = false,
			}
		end
	end
	return modes
end

function SPDRN.group_mode_display(key)
	for _, mode in ipairs(SPDRN.group_queue_modes()) do
		if mode.key == key then
			return mode.display
		end
	end
	return tostring(key)
end

-- The modes this lobby may queue as a group now, and the first refusal that
-- applies whatever the mode.
function SPDRN.group_queue_options(lobby)
	local Group = MPAPI.matchmaking.group
	local facts = Group.facts_from_lobby(lobby)
	local lobby_refusal = Group.eligibility(facts, nil)
	local eligible = {}
	-- A member refused for their standing (MEMBER_REFUSED) still leaves the
	-- modes listed: the panel greys the button and names them.
	for _, entry in ipairs(Group.rank_modes(Group.without_standings(facts), SPDRN.group_queue_modes())) do
		if not entry.refusal then
			eligible[#eligible + 1] = entry.mode
		end
	end
	return eligible, lobby_refusal
end

-- A group queue's handle, host's or member's: the public match it finds is
-- set up as a solo casual match is.
function SPDRN._wire_group_handle(handle, gamemode_key)
	local kind = SPDRN.LobbyKind.CASUAL
	local function refresh()
		pcall(MPAPI.refresh_current_view)
		SPDRN.refresh_game_select_queue_state()
	end

	handle:on('error', function(err)
		SPDRN.sendWarnMessage('[group] queue error: ' .. tostring(err))
		refresh()
	end)

	handle:on('queued', function()
		SPDRN.sendDebugMessage('[group] queued for ' .. tostring(gamemode_key))
		refresh()
	end)

	handle:on('match_found', function(data)
		SPDRN.sendDebugMessage('[group] match found: ' .. tostring(data and data.matchId))
		-- Out of the home lobby (MPAPI parked our seat there) and into a
		-- matchmade one.
		SPDRN._lobby_kind = kind
		local L = SPDRN.lobby
		L.ref = nil
		L.ui_ref = nil
		L.buttons_initialized = false
	end)

	handle:on('lobby_ready', function(lobby)
		SPDRN.sendDebugMessage('[group] lobby ready: ' .. tostring(lobby.code))
		SPDRN._current_match_handle = handle
		SPDRN._lobby_kind = kind
		SPDRN._cancel_other_queues(nil)
		SPDRN.setup_lobby_events(lobby)
		if lobby.is_host then
			lobby:set_metadata({ gamemode = gamemode_key, ruleset = SPDRN.Ruleset.ORDER, kind = kind })
		end
		SPDRN.signal_ready(true)
		SPDRN.start_ready_resync()
	end)

	handle:on('match_resolved', function()
		if SPDRN._current_match_handle == handle then
			SPDRN._current_match_handle = nil
		end
	end)

	handle:on('left', function()
		if SPDRN._current_match_handle == handle then
			SPDRN._current_match_handle = nil
		end
		refresh()
	end)
end

-- Host: queue the current private lobby as a group for `gamemode_key`.
-- Returns the handle, or nil and the refusal text.
function SPDRN._join_group_queue(gamemode_key)
	local Group = MPAPI.matchmaking.group
	local gm = MPAPI.GameModes[gamemode_key]
	if not gm then
		return nil, 'unknown mode ' .. tostring(gamemode_key)
	end
	local handle, refusal = MPAPI.matchmaking.queue_group({
		mod_id = SPDRN.id,
		game_mode = gamemode_key,
		min_players = 2,
		max_players = (gm.max_players and gm.max_players.public) or 2,
	})
	if not handle then
		local text = Group.refusal_text(refusal)
		SPDRN.sendWarnMessage('[group] queue refused: ' .. tostring(text))
		if MPAPI.show_notice then
			MPAPI.show_notice('k_group_queue_failed_title', text)
		end
		return nil, text
	end
	SPDRN._wire_group_handle(handle, gamemode_key)
	pcall(MPAPI.refresh_current_view)
	return handle
end

-- Any member: give up the group queue (the server ends it for everyone).
function SPDRN._cancel_group_queue()
	MPAPI.matchmaking.group.cancel(function()
		pcall(MPAPI.refresh_current_view)
	end)
end

if MPAPI.matchmaking.group and MPAPI.matchmaking.group.register then
	MPAPI.matchmaking.group.register(SPDRN.id, {
		on_member_handle = function(handle, view)
			SPDRN._wire_group_handle(handle, view.mode)
			pcall(MPAPI.refresh_current_view)
		end,
		return_home = function(code)
			SPDRN._join_lobby_with_code(code)
			return MPAPI.get_current_lobby()
		end,
	})
end

G.FUNCS.spdrn_group_queue = function()
	local eligible = SPDRN.group_queue_options(MPAPI.get_current_lobby())
	local mode = eligible[math.max(1, math.min(SPDRN._group_mode_choice or 1, #eligible))]
	if not mode then
		return
	end
	SPDRN._join_group_queue(mode.key)
end

G.FUNCS.spdrn_group_cancel = function()
	SPDRN._cancel_group_queue()
end

G.FUNCS.spdrn_group_mode_cycle = function(args)
	SPDRN._group_mode_choice = args.to_key
end

G.FUNCS.spdrn_group_return = function()
	MPAPI.matchmaking.group.return_home()
end

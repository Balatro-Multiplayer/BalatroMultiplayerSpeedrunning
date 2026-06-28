-----------------------------
-- MATCH STATE
-----------------------------

SPDRN._current_match_handle = nil

-----------------------------
-- QUEUE STATUS TIMER
-----------------------------

-- While queued, the account panel shows a live "Queueing m:ss" status. The
-- timer measures wall-clock time since the 'queued' event fired (server-
-- agnostic). Text is kept short so the fixed-width panel does not reflow.
local _queue_timer_active = false
local _queue_timer_start = nil
local _queue_timer_last = nil

local function _format_queue_status()
	local elapsed = math.floor(love.timer.getTime() - _queue_timer_start)
	return string.format('%s %d:%02d', localize('k_status_queueing'), math.floor(elapsed / 60), elapsed % 60)
end

local function _schedule_queue_tick()
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.25,
		blockable = false,
		blocking = false,
		func = function()
			if not _queue_timer_active then
				return true
			end
			local t = _format_queue_status()
			if t ~= _queue_timer_last then
				_queue_timer_last = t
				MPAPI.set_connection_status(t)
			end
			_schedule_queue_tick()
			return true
		end,
	}))
end

local function _start_queue_timer()
	if _queue_timer_active then
		return
	end
	_queue_timer_active = true
	_queue_timer_start = love.timer.getTime()
	_queue_timer_last = nil
	MPAPI.set_connection_status(_format_queue_status())
	_schedule_queue_tick()
end

local function _stop_queue_timer()
	_queue_timer_active = false
	_queue_timer_start = nil
	_queue_timer_last = nil
	MPAPI.set_connection_status(nil)
end

-----------------------------
-- QUEUE
-----------------------------

-- Join a matchmaking queue. kind is 'ranked' or 'casual'. The server treats any
-- game_mode without a 'ranked:' prefix as casual, so casual queues use the bare key.
function SPDRN._join_queue(kind, gamemode_key)
	SPDRN._lobby_kind = kind

	local gm = MPAPI.GameModes[gamemode_key]
	local mm_max = gm and gm.max_players and gm.max_players.ranked or 2
	local game_mode = (kind == 'ranked') and ('ranked:' .. gamemode_key) or gamemode_key

	local handle = MPAPI.matchmaking.queue({
		mod_id = SPDRN.id,
		game_mode = game_mode,
		min_players = 2,
		max_players = mm_max,
	})

	if not handle then
		SPDRN.sendWarnMessage('Failed to create matchmaking handle')
		SPDRN._lobby_kind = nil
		return
	end

	SPDRN._current_match_handle = handle

	handle:on('error', function(err)
		SPDRN.sendWarnMessage('Matchmaking error: ' .. tostring(err))
		SPDRN._current_match_handle = nil
		_stop_queue_timer()
		SPDRN._show_searching_state(false)
		SPDRN.update_main_menu_buttons()
	end)

	handle:on('queued', function(position)
		SPDRN.sendDebugMessage('Queued at position: ' .. tostring(position))
		SPDRN._show_searching_state(true)
		_start_queue_timer()
	end)

	handle:on('match_found', function(data)
		SPDRN.sendDebugMessage('Match found: ' .. tostring(data.matchId))
		SPDRN._show_searching_state(false)
		_stop_queue_timer()
	end)

	handle:on('lobby_ready', function(lobby)
		SPDRN.sendDebugMessage(kind .. ' lobby ready: ' .. tostring(lobby.code))
		SPDRN._lobby_kind = kind
		SPDRN.setup_lobby_events(lobby)
		if lobby.is_host then
			lobby:set_metadata({ gamemode = gamemode_key, ruleset = 'spdrn_order', kind = kind })
		end
		-- lobby_ready fires from inside the lobby's own 'connected' handler, so a
		-- 'connected' listener registered above would never fire. Signal ready now;
		-- the host auto-starts once every client has reported in.
		SPDRN.signal_ready(true)
		-- Re-announce a few times in case this first ready raced ahead of the peer's
		-- actions-topic subscription (otherwise the host can stall waiting for it).
		SPDRN.start_ready_resync()
	end)

	handle:on('match_resolved', function(ratings)
		SPDRN.sendDebugMessage('Match resolved')
		SPDRN._current_match_handle = nil
	end)

	handle:on('left', function()
		SPDRN._current_match_handle = nil
		SPDRN._lobby_kind = nil
		SPDRN._show_searching_state(false)
		_stop_queue_timer()
	end)
end

-- Back-compat alias (used by tests and older callers).
function SPDRN._join_ranked_queue(gamemode_key)
	return SPDRN._join_queue('ranked', gamemode_key)
end

function SPDRN._cancel_queue()
	local handle = SPDRN._current_match_handle
	if handle then
		handle:leave()
		SPDRN._current_match_handle = nil
	end
	SPDRN._lobby_kind = nil
	SPDRN._show_searching_state(false)
	_stop_queue_timer()
end

function SPDRN._is_in_ranked_match()
	return SPDRN._current_match_handle ~= nil and SPDRN._current_match_handle.match_id ~= nil
end

-----------------------------
-- RUN TIMING
-----------------------------

-- Host-only: tell the server the run has begun so it can measure completion time
-- (the speedrun leaderboard's fastest-time metric is server-clock measured).
function SPDRN.mark_run_started()
	local handle = SPDRN._current_match_handle
	if not handle or not handle.match_id then
		return
	end

	local lobby = MPAPI.get_current_lobby()
	if not lobby or not lobby.is_host then
		return
	end

	handle:mark_started(function(err)
		if err then
			SPDRN.sendWarnMessage('mark_run_start error: ' .. tostring(err))
		end
	end)
end

-----------------------------
-- RESULT REPORTING
-----------------------------

function SPDRN.report_match_result(winner_player_id)
	-- The server decides whether a match is rated from its game_mode (casual matches
	-- carry no 'ranked:' prefix), so we always report and let it sort that out.
	local handle = SPDRN._current_match_handle
	if not handle or not handle.match_id then
		return
	end

	local lobby = MPAPI.get_current_lobby()
	if not lobby or not lobby.is_host then
		return
	end

	local placements = {}
	for _, p in ipairs(lobby:get_players()) do
		placements[#placements + 1] = {
			playerId = p.id,
			place = (p.id == winner_player_id) and 1 or 2,
		}
	end

	handle:report_result(placements, function(err)
		if err then
			SPDRN.sendWarnMessage('report_result error: ' .. tostring(err))
		end
	end)
end

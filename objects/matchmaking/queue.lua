-- Join a matchmaking queue. kind is RANKED or CASUAL. The server treats any game_mode
-- without the ranked prefix as casual, so casual queues use the bare gamemode key. A player
-- can have several of these searching at once (see objects/matchmaking/state.lua) -- each
-- tracked independently under SPDRN._queue_handles, keyed by the wire game_mode string.
function SPDRN._join_queue(kind, gamemode_key)
	-- §16.2: casual scales via the gamemode's own .public field (2-16, already
	-- modeled correctly on every gamemode -- this just used to ignore it and
	-- always read .ranked instead, capping casual SPDRN at 2 players).
	local gm = MPAPI.GameModes[gamemode_key]
	local max_players_field = (kind == SPDRN.LobbyKind.RANKED) and 'ranked' or 'public'
	local mm_max = gm and gm.max_players and gm.max_players[max_players_field] or 2
	local game_mode = (kind == SPDRN.LobbyKind.RANKED) and (SPDRN.LobbyKind.RANKED_PREFIX .. gamemode_key) or gamemode_key

	if SPDRN._queue_handles[game_mode] then
		return
	end

	-- No normal UI path reaches this while already mid-run (the in-run pause menu has no
	-- Find Game button) -- this is defense-in-depth, not a fix for something reachable today.
	-- Queueing while a run is live would let a real match's lobby_ready later interrupt this
	-- run via focus.lua's on_lobby_connected (MPAPI.exit_to_menu(), which has no idea SPDRN
	-- per-run state like Seed Scout's scouting-phase dollars override exists) -- the same class
	-- of "abandoned run, stale global state" hazard fixed in reset_match_progress, just from
	-- the opposite direction (queue second instead of first).
	if G.STAGE == G.STAGES.RUN then
		SPDRN.sendWarnMessage('[mmdbg] _join_queue refused: already in a run (G.STAGE == RUN)')
		return
	end

	SPDRN.sendDebugMessage('[mmdbg] _join_queue kind=' .. tostring(kind) .. ' gamemode_key=' .. tostring(gamemode_key) .. ' -> game_mode=' .. tostring(game_mode) .. ' mm_max=' .. tostring(mm_max))

	local handle = MPAPI.matchmaking.queue({
		mod_id = SPDRN.id,
		game_mode = game_mode,
		min_players = 2,
		max_players = mm_max,
		-- Without this, MPAPI.matchmaking.queue() has no way to know this is a
		-- ranked attempt (it can't infer that from game_mode's "ranked:" prefix
		-- alone - see that function's own doc comment), so its launcher-anti-cheat
		-- gate silently never ran for a real ranked queue attempt here. The
		-- server-side launcher-integrity gate is unaffected either way (it's
		-- independent, keyed off the game_mode prefix), but this client-side
		-- layer of defense-in-depth was a no-op for every ranked SPDRN queue.
		ranked = kind == SPDRN.LobbyKind.RANKED,
	})

	if not handle then
		SPDRN.sendWarnMessage('[mmdbg] Failed to create matchmaking handle')
		return
	end

	SPDRN._queue_handles[game_mode] = handle

	handle:on('error', function(err)
		SPDRN.sendWarnMessage('[mmdbg] Matchmaking error: ' .. tostring(err))
		SPDRN._queue_handles[game_mode] = nil
		SPDRN.refresh_game_select_queue_state()
	end)

	handle:on('queued', function(position)
		SPDRN.sendDebugMessage('[mmdbg] Queued at position: ' .. tostring(position))
		SPDRN.refresh_game_select_queue_state()
	end)

	handle:on('match_found', function(data)
		SPDRN.sendDebugMessage('[mmdbg] Match found: ' .. tostring(data.matchId) .. ' lobbyCode=' .. tostring(data.lobbyCode) .. ' gameMode=' .. tostring(data.gameMode))
	end)

	handle:on('lobby_ready', function(lobby)
		SPDRN.sendDebugMessage('[mmdbg] ' .. tostring(kind) .. ' lobby ready: ' .. tostring(lobby.code))
		SPDRN._current_match_handle = handle
		SPDRN._lobby_kind = kind
		SPDRN._queue_handles[game_mode] = nil
		-- Committing to a real match: drop every OTHER queue this player was searching --
		-- can't play more than one match at a time even though several could be searching.
		SPDRN._cancel_other_queues(game_mode)
		SPDRN.setup_lobby_events(lobby)
		if lobby.is_host then
			lobby:set_metadata({ gamemode = gamemode_key, ruleset = SPDRN.Ruleset.ORDER, kind = kind })
		end
		-- lobby_ready fires from inside the lobby's own 'connected' handler, so a 'connected'
		-- listener registered above would never fire. Signal ready now; the host auto-starts
		-- once every client has reported in. Re-announce a few times in case this first ready
		-- raced ahead of the peer's actions-topic subscription (else the host can stall).
		SPDRN.signal_ready(true)
		SPDRN.start_ready_resync()
	end)

	handle:on('match_resolved', function(ratings)
		SPDRN.sendDebugMessage('[mmdbg] Match resolved')
		if SPDRN._current_match_handle == handle then
			SPDRN._current_match_handle = nil
		end
	end)

	handle:on('left', function()
		SPDRN.sendDebugMessage('[mmdbg] handle left (queue dropped)')
		SPDRN._queue_handles[game_mode] = nil
		if SPDRN._current_match_handle == handle then
			SPDRN._current_match_handle = nil
			SPDRN._lobby_kind = nil
		end
		SPDRN.refresh_game_select_queue_state()
	end)

	SPDRN.refresh_game_select_queue_state()
end

-- Leaves every actively-searching queue except (optionally) one -- used when a match forms
-- for one queue so every other one this player was also searching gets dropped too. Copies
-- the handle list first since handle:leave() mutates SPDRN._queue_handles (via its own
-- 'left' listener above), which would break live iteration.
function SPDRN._cancel_other_queues(except_game_mode)
	local to_leave = {}
	for game_mode, handle in pairs(SPDRN._queue_handles) do
		if game_mode ~= except_game_mode then
			to_leave[#to_leave + 1] = handle
		end
	end
	for _, handle in ipairs(to_leave) do
		handle:leave()
	end
end

-- Back-compat alias (used by tests and older callers).
function SPDRN._join_ranked_queue(gamemode_key)
	return SPDRN._join_queue(SPDRN.LobbyKind.RANKED, gamemode_key)
end

-- Cancels one specific search (identified by its wire game_mode string, e.g.
-- mode.game_mode_stat_key in ui/main_menu/game_select.lua) -- not the match already formed,
-- if any; leaving an active lobby/run is a separate, pre-existing flow.
function SPDRN._cancel_queue(game_mode)
	local handle = SPDRN._queue_handles[game_mode]
	if handle then
		handle:leave()
	end
end

function SPDRN._is_in_ranked_match()
	return SPDRN._current_match_handle ~= nil and SPDRN._current_match_handle.match_id ~= nil
end

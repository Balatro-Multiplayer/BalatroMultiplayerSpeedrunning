-- Collected per-player results for the current match, keyed by player id --
-- populated as each player's own client broadcasts its final progress (see
-- objects/actions/player_result.lua). Reset per match in reset_match_progress.
SPDRN._collected_results = SPDRN._collected_results or {}

-- §16.8: ranks the winner first, then every other player by furthest ante
-- (descending), then furthest round within that ante (descending), then by
-- arrival time at that ante (ascending -- got there sooner outranks got there
-- later). Returns nil until every player in `player_ids` has reported, except
-- those in `gone` (left the lobby or timed out of it mid-game): they will never
-- report, and are placed below everyone who did.
local function build_placements(winner_id, player_ids, gone)
	local entries = {}
	for _, id in ipairs(player_ids) do
		local r = SPDRN._collected_results[id]
		if not r and gone and gone[id] then
			r = { furthest_ante = -1, furthest_round = -1, arrived_at = math.huge }
		end
		if not r then
			return nil
		end
		entries[#entries + 1] = {
			playerId = id,
			is_winner = (id == winner_id),
			furthest_ante = r.furthest_ante or 1,
			furthest_round = r.furthest_round or 0,
			arrived_at = r.arrived_at or 0,
			best_run_time_ms = r.best_run_time_ms,
		}
	end

	table.sort(entries, function(a, b)
		if a.is_winner ~= b.is_winner then
			return a.is_winner
		end
		if a.furthest_ante ~= b.furthest_ante then
			return a.furthest_ante > b.furthest_ante
		end
		if a.furthest_round ~= b.furthest_round then
			return a.furthest_round > b.furthest_round
		end
		return a.arrived_at < b.arrived_at
	end)

	local placements = {}
	for i, e in ipairs(entries) do
		local entry = { playerId = e.playerId, place = i }
		-- §11.7: every player's own fastest individual run time rides along, not
		-- just the winner's -- the server only ever updates a player's own
		-- seasonBest from their own entry.
		if e.best_run_time_ms then
			entry.metric = e.best_run_time_ms
		end
		placements[#placements + 1] = entry
	end
	return placements
end

-- A server-refereed lobby: every client reports the same placements for the
-- players the game started with, once all of their results are in. A draw
-- places everyone first. Sent once per game.
local function report_to_server(lobby, winner_id)
	local started = lobby._game.started
	if not started or SPDRN._reported_run_id == started.run_id then
		return
	end
	local ids = {}
	for _, p in ipairs(started.players or {}) do
		ids[#ids + 1] = p.id
	end
	local seated = {}
	for _, p in ipairs(lobby:get_players()) do
		seated[p.id] = true
	end
	local gone = {}
	for _, id in ipairs(ids) do
		if not seated[id] then
			gone[id] = true
		end
	end
	local placements = build_placements(winner_id, ids, gone)
	if not placements then
		return
	end
	if SPDRN._match_drawn then
		for _, entry in ipairs(placements) do
			entry.place = 1
		end
	end
	SPDRN._reported_run_id = started.run_id
	lobby:report_result(placements, function(err)
		if err then
			SPDRN.sendWarnMessage('report_result error: ' .. tostring(err))
		end
	end)
end

-- §11.6: every player reports, not just the host -- tried once per newly
-- collected result. All clients compute from the same converged
-- _collected_results, so their placements agree. Local lobbies report nothing.
function SPDRN._maybe_report_result(winner_id)
	local lobby = MPAPI.get_current_lobby()
	if MPAPI.has_server_referee(lobby) then
		report_to_server(lobby, winner_id)
	end
end

-- Called once, when this client's own match involvement ends (it won, it
-- personally forfeited, or a draw vote resolved -- see objects/actions/player_won.lua
-- and objects/actions/match_draw.lua's receive handlers): finalizes and broadcasts
-- its own progress, then checks whether every player has now reported.
-- `opts.draw` (a unanimous draw vote, objects/actions/match_draw.lua) places
-- everyone first.
function SPDRN.report_match_result(winner_id, opts)
	opts = opts or {}
	SPDRN._current_winner_id = winner_id
	SPDRN._match_result_pending = true
	SPDRN._match_drawn = opts.draw or nil

	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end

	local progress = SPDRN.finalize_match_progress()
	-- Closes this MATCH's RLOG block (end_run is now once-per-match, see
	-- ui/lobby/run_start.lua's begin_run) -- this is this client's own
	-- match-ending event (it won, lost to someone else winning, hit the
	-- duration-cap timeout with no single winner, or a draw vote resolved).
	-- Idempotent (end_run no-ops once already closed), so harmless if
	-- objects/actions/forfeit.lua's own end_run already closed the block
	-- first for a terminal forfeit.
	MPAPI.replay.end_run({
		result = opts.draw and 'draw' or (winner_id == nil and 'timeout' or (winner_id == lobby.player_id and 'win' or 'loss')),
	})
	-- §16.10/17: jokers/deck_back/deck ride along for the win/lose screen's
	-- per-player jokers+deck viewer only -- build_placements (above)
	-- deliberately never reads them, so this stays a pure display
	-- concern with no effect on ranking/server reporting.
	SPDRN._collected_results[lobby.player_id] = {
		furthest_ante = progress.furthest_ante,
		furthest_round = progress.furthest_round,
		arrived_at = progress.arrived_at,
		best_run_time_ms = progress.best_run_time_ms,
		jokers = progress.jokers,
		deck_back = progress.deck_back,
		deck = progress.deck,
		match_completion_ms = progress.match_completion_ms,
		times_skipped = progress.times_skipped,
		best_hand_amt = progress.best_hand_amt,
	}
	lobby:action(MPAPI.ActionTypes['spdrn_player_result']):broadcast({
		player_id = lobby.player_id,
		furthest_ante = progress.furthest_ante,
		furthest_round = progress.furthest_round,
		arrived_at = progress.arrived_at,
		best_run_time_ms = progress.best_run_time_ms,
		jokers = progress.jokers,
		deck_back = progress.deck_back,
		deck = progress.deck,
		match_completion_ms = progress.match_completion_ms,
		times_skipped = progress.times_skipped,
		best_hand_amt = progress.best_hand_amt,
	})

	-- Reported even for a draw: the server ends the game once everyone has
	-- reported.
	SPDRN._maybe_report_result(winner_id)
end

-- Switching which player's own recorded perspective a replay/rejoin session is watching,
-- landing at the same REAL point in time (not the same ante/checkpoint) in the target player's
-- own timeline. Triggered from ui/replay/checkpoint_picker.lua's roster section.
--
-- Every player in an SPDRN match shares one seed/deck/stake per run (SPDRN.broadcast_start,
-- ui/lobby/run_start.lua) -- it's a genuine race, not independently-random games -- so
-- switching perspective is meaningfully "the same underlying game, viewed through a different
-- player's own choices," not a different match entirely.
--
-- Each recorded event's own `t` is elapsed-ms since THAT recording client's own local clock
-- capture at begin_run() (api/replay/recorder.lua) -- NOT a shared clock, and real skew exists
-- between players (network latency receiving the match-start broadcast, ban-pick draft
-- duration, each client's own local countdown starting independently -- ui/lobby/countdown.lua).
-- Comparing raw `t` between two different players' events is therefore not meaningful. The
-- correct anchor is each player's own match_manifest.start_epoch_ms (a real os.time()*1000
-- wall-clock epoch, captured synchronously with that player's own t=0 -- api/replay/
-- framing_codes.lua, SPDRN._find_bootstrap in replay_browser.lua) -- converting both players'
-- positions to absolute epoch (start_epoch_ms + t) makes them directly comparable.

-- "Right now" for `session`, as an absolute epoch. Scans backward from the driver's own cursor
-- for the most recently dispatched entry belonging to session.my_id -- correct specifically
-- because SPDRN's non-POV dispatch is a confirmed full no-op (every handler in
-- playback_handlers.lua starts `if not ctx.is_pov then return end`), so "now" for a session
-- genuinely IS its own last-dispatched entry; nothing else has touched live state. Falls back
-- to the session's own start_epoch_ms (i.e. "the very beginning") if nothing has dispatched yet.
local function current_epoch(session)
	local driver = session.driver
	local cursor = driver and driver._cursor or 1
	for i = cursor - 1, 1, -1 do
		local entry = session.timeline[i]
		if entry and entry.player_id == session.my_id then
			return session.bootstrap.start_epoch_ms + entry.t
		end
	end
	return session.bootstrap.start_epoch_ms
end

-- Finds the event_index in `timeline` belonging to `target_player_id` whose own absolute epoch
-- (target_bootstrap.start_epoch_ms + entry.t) is closest to `target_epoch`. A plain linear scan
-- -- runs once per switch click, on timelines of at most a few thousand entries, not per-frame.
--
-- No distance clamp: if the target player's own timeline is sparse near target_epoch (already
-- finished their run, or was AFK), "closest" can land arbitrarily far away in real time with no
-- hard failure -- surfaced as a debug-log gap rather than silently hidden or blocking the
-- switch outright, since whether to ever refuse a switch on a large gap is a product call, not
-- a correctness one. TODO: revisit whether a large gap should surface a player-facing warning,
-- not just a log line, once this has some real usage to judge against.
local function closest_event_index(timeline, target_player_id, target_bootstrap, target_epoch)
	local best_idx, best_delta = nil, nil
	for i, entry in ipairs(timeline) do
		if entry.player_id == target_player_id then
			local delta = math.abs((target_bootstrap.start_epoch_ms + entry.t) - target_epoch)
			if not best_delta or delta < best_delta then
				best_idx, best_delta = i, delta
			end
		end
	end
	if not best_idx then
		return 1, nil
	end
	MPAPI.sendDebugMessage('[perspective_switch] landed ' .. tostring(best_delta) .. 'ms from the requested moment for player ' .. tostring(target_player_id))
	return best_idx + 1, best_delta
end

function SPDRN._switch_perspective(target_player_id)
	local old = SPDRN._active_replay_session
	if not old or old.seeking then
		return
	end
	local target_bootstrap = SPDRN._find_bootstrap(old.timeline, target_player_id)
	if not target_bootstrap then
		-- Shouldn't happen live -- checkpoint_picker.lua's own roster section already filters
		-- to players SPDRN._find_bootstrap succeeds for -- but stay defensive rather than
		-- assume the UI layer's filter is the only path here.
		SPDRN.sendWarnMessage('[perspective_switch] no bootstrap data found for player ' .. tostring(target_player_id) .. ' -- refusing to switch')
		return
	end

	local target_epoch = current_epoch(old)
	local target_event_index = closest_event_index(old.timeline, target_player_id, target_bootstrap, target_epoch)

	if old.driver then
		old.driver:stop()
	end
	SPDRN._show_seek_overlay('Syncing game state...')
	SPDRN._open_replay_session({
		bootstrap = target_bootstrap,
		timeline = old.timeline,
		my_id = target_player_id,
		paced = old.paced,
		on_session_complete = old.on_session_complete,
	}, target_event_index)
end

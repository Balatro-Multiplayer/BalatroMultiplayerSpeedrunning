-- Seeking a replay session (built by ante_index.lua) to a specific ante -- the operation
-- ui/replay/ante_picker.lua's popup buttons trigger, and the one SPDRN._open_replay_session
-- below reuses to unify "start watching from the beginning" with "the player clicked an ante"
-- into a single code path.
--
-- State correctness after any seek is automatic, not something this file has to reconstruct:
-- both branches below (forward fast-forward and full restart) dispatch through the exact same
-- MPAPI.playback.dispatch('spdrn', ...) calls, via the exact same registered handlers in
-- objects/replay_log/playback_handlers.lua, that normal-pace playback already uses -- only how
-- many real frames elapse between dispatches changes, never what gets applied. See
-- api/playback/driver.lua's own header comment for why this is the whole point of this
-- codebase's replay architecture (never a parallel fake-state renderer).

local function find_ante_index_entry(index, run_idx, ante)
	for _, e in ipairs(index or {}) do
		if e.run_idx == run_idx and e.ante == ante then
			return e
		end
	end
	return nil
end

function SPDRN._seek_to_ante(run_idx, ante)
	local session = SPDRN._active_replay_session
	if not session or session.seeking then
		return
	end
	local entry = find_ante_index_entry(session.ante_index, run_idx, ante)
	if not entry then
		return
	end

	session.seeking = true
	SPDRN._ante_seek_show_overlay(run_idx, ante)

	-- Shared completion for both branches below: clear the seeking flag, hide the overlay,
	-- re-wire the ante-click handler (a restart rebuilds G.HUD from scratch, losing it every
	-- time -- harmless no-op on the forward-seek branch, where G.HUD never changed), then
	-- resume normal-pace playback automatically -- per the agreed video-scrubber convention,
	-- no separate "resume" click.
	local function finish_seek(driver)
		session.driver = driver
		session.seeking = false
		SPDRN._wire_ante_click()
		SPDRN._ante_seek_hide_overlay()
		driver:play()
	end

	local driver = session.driver
	if driver and entry.event_index >= driver._cursor then
		driver:fast_forward_to(entry.event_index, {
			pause_gate = SPDRN._ff_pause_gate,
			on_done = function()
				finish_seek(driver)
			end,
		})
	else
		-- Backward seek (target is behind or at the current position), OR the very first seek
		-- of a session (session.driver is still nil): the only correct way to reach an earlier
		-- point is a full restart from the recorded seed and a fresh forward dispatch -- there
		-- is no partial/checkpointed resume anywhere in this codebase (see api/playback/
		-- driver.lua's own header comment; the closest precedent, api/unlock_overlay/
		-- snapshot.lua, is a narrow cosmetic-flag capture/restore, not reusable for gameplay
		-- state).
		SPDRN._restart_session_and_seek(session, entry.event_index, finish_seek)
	end
end

-- Restarts `session`'s run from its own recorded bootstrap (seed/deck/stake) and fast-forwards
-- the resulting fresh driver up to `target_event_index`, then calls on_ready(driver).
--
-- SPDRN._start_playback is reused completely as-is, no variant -- it already does exactly "boot
-- a fresh local run from the recorded seed/deck/stake" (objects/replay_log/playback_launch.lua),
-- which is precisely what a from-scratch seek needs. Its own documented, still-unsolved v1 gap
-- (a fresh gamemode instance always starts _run_count=0, so bootstrapping DIRECTLY into a later
-- run of a multi-run format computes the wrong stake) never bites here: every seek in this
-- design restarts at run 1 and dispatches forward through every run_died/run_restarted/
-- multi-run-advance opcode in true recorded order -- never jumps straight into run 2/3's own
-- bootstrap. A genuine multi-run advance is a replay no-op at the RLOG layer by design (see
-- run_transition_codes.lua) -- it happens automatically as a side effect of the gamemode's own
-- calculate() handler once the real ante-9 cashout is actually dispatched, exactly as it would
-- live, so nothing here needs to special-case it.
function SPDRN._restart_session_and_seek(session, target_event_index, on_ready)
	if session.driver then
		-- Must stop the OLD driver before _start_playback tears the run down, or it would keep
		-- ticking (MPAPI.playback._active_drivers still holds it) against a rebuilt game state
		-- it no longer matches.
		session.driver:stop()
	end
	SPDRN._start_playback(session.bootstrap, function()
		local driver = MPAPI.playback.new_driver(session.timeline, {
			mod_id = 'spdrn',
			pov_player_id = session.my_id,
			schema_version = session.bootstrap.schema_version,
			on_complete = session.on_session_complete,
		})
		driver:finish()
		driver:fast_forward_to(target_event_index, {
			pause_gate = SPDRN._ff_pause_gate,
			on_done = function()
				on_ready(driver)
			end,
		})
	end)
end

-- Starts viewing a replay/rejoin session from the very beginning. `session` must already have
-- {bootstrap, timeline, my_id, on_session_complete} set (see replay_browser.lua's
-- _launch_replay) -- this fills in `ante_index`/`driver`/`seeking` and shows the loading
-- overlay for the whole open sequence.
--
-- Two bootstraps, deliberately: SPDRN._start_playback is called once here just to reach a live
-- BLIND_SELECT for the ante-index build to actually dispatch against (a disposable driver still
-- needs a real running game to drive), and again inside _seek_to_ante(1,1)'s own restart branch
-- below for the real viewing session -- this is a known, flagged cost (see this feature's own
-- design doc, "double-bootstrap"), not an oversight; SPDRN._start_playback's own cost is
-- unquantified in this codebase and worth measuring during validation.
--
-- Builds the ante index first (a full fast-forward pass over the WHOLE timeline, via a
-- disposable driver ante_index.lua creates and discards internally -- session.driver is never
-- set by that pass), THEN calls _seek_to_ante(1, 1). Since session.driver is still nil at that
-- point, _seek_to_ante's own branching above unconditionally takes the restart branch -- i.e.
-- "start watching from the beginning" and "the player clicked ante 1" are the exact same code
-- path, with no third, separately-tested flow.
function SPDRN._open_replay_session(session)
	SPDRN._active_replay_session = session
	SPDRN._ante_seek_show_overlay(1, 1)
	SPDRN._start_playback(session.bootstrap, function()
		SPDRN._build_ante_index(session, function(ante_index)
			session.ante_index = ante_index
			SPDRN._seek_to_ante(1, 1)
		end)
	end)
end

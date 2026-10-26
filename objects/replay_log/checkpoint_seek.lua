-- Seeking a replay session (built by checkpoint_index.lua) to a specific ante/blind checkpoint
-- -- the operation ui/replay/checkpoint_picker.lua's popup buttons trigger, and the one
-- SPDRN._open_replay_session below reuses to unify "start watching from the beginning", "the
-- player clicked a checkpoint", and "the player switched perspective" (objects/replay_log/
-- perspective_switch.lua) into a single code path.
--
-- State correctness after any seek is automatic, not something this file has to reconstruct:
-- both branches below (forward fast-forward and full restart) dispatch through the exact same
-- MPAPI.playback.dispatch('spdrn', ...) calls, via the exact same registered handlers in
-- objects/replay_log/playback_handlers.lua, that normal-pace playback already uses -- only how
-- many real frames elapse between dispatches changes, never what gets applied. See
-- api/playback/driver.lua's own header comment for why this is the whole point of this
-- codebase's replay architecture (never a parallel fake-state renderer).

-- CONFIRMED LIVE BUG, fixed by returning the LAST match rather than the first: a mid-run restart
-- (a real player's own "Restart Run" click after a blind loss, or the divergent-death auto-
-- restart fallback, ui/lose_screen.lua's SPDRN._check_run_lost) resets G.GAME.round_resets.ante
-- back to whatever ante the fresh attempt starts from, so checkpoint_index.lua's own flat index
-- can and does record the SAME (run_idx, ante, blind) key more than once -- once per attempt.
-- checkpoint_index.lua's own dedup only collapses CONSECUTIVE identical keys (see that file's
-- header comment); a restart's key is never consecutive with whatever came immediately before it,
-- so every attempt's entries all survive independently, in chronological order. Scanning
-- forward and returning the FIRST match therefore always seeks to the earliest, ABANDONED attempt
-- at that ante/blind -- never the final one the recording actually continued from, which is the
-- only one a viewer could sensibly want (the abandoned attempt's own timeline dead-ends at the
-- next restart, so seeking into it just strands the viewer mid-run with no way to reach anything
-- past that restart via this same checkpoint). Reproduced live against a real production match
-- (4bab3028.../41038e0d..., gold_stake_single) that restarted from Ante 1 five times via the
-- divergent-death fallback above -- SPDRN._seek_to_checkpoint(1, 1, 'Big') landed on the FIRST
-- attempt's Big Blind (event_index 13) instead of the actually-played final attempt's (event_index
-- 747). Matches ui/replay/checkpoint_picker.lua's own group_checkpoints fix (same root cause,
-- same "last attempt wins" resolution) so the popup's displayed blinds and this lookup's seek
-- target always agree.
local function find_checkpoint_entry(index, run_idx, ante, blind)
	local found = nil
	for _, e in ipairs(index or {}) do
		if e.run_idx == run_idx and e.ante == ante and e.blind == blind then
			found = e
		end
	end
	return found
end

-- `blind` defaults to 'Small' -- an ante-only seek (SPDRN._seek_to_checkpoint(run_idx, ante)) is
-- just a checkpoint seek to that ante's first blind, since checkpoint_index.lua's own boundary
-- detection already records that as a normal entry (see that file's header comment on why ante-
-- and blind-level checkpoints are one flat index, not two parallel ones).
function SPDRN._seek_to_checkpoint(run_idx, ante, blind)
	blind = blind or 'Small'
	local session = SPDRN._active_replay_session
	if not session or session.seeking then
		return
	end
	local entry = find_checkpoint_entry(session.checkpoint_index, run_idx, ante, blind)
	if not entry then
		return
	end

	session.seeking = true
	local label = 'Seeking to Ante ' .. ante .. (blind ~= 'Small' and (', ' .. blind .. ' Blind') or '') .. '...'
	SPDRN._show_seek_overlay(label)

	-- Shared completion for both branches below: clear the seeking flag, hide the overlay,
	-- re-wire the checkpoint-click handler (a restart rebuilds G.HUD from scratch, losing it
	-- every time -- harmless no-op on the forward-seek branch, where G.HUD never changed), then
	-- resume normal-pace playback automatically -- per the agreed video-scrubber convention,
	-- no separate "resume" click.
	local function finish_seek(driver)
		session.driver = driver
		session.seeking = false
		SPDRN._wire_checkpoint_click()
		SPDRN._hide_seek_overlay()
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
-- live, so nothing here needs to special-case it. Also used, unmodified, by
-- objects/replay_log/perspective_switch.lua's cross-player switch, where `session.bootstrap` is
-- simply a DIFFERENT player's own bootstrap over the SAME shared timeline.
function SPDRN._restart_session_and_seek(session, target_event_index, on_ready)
	MPAPI.playback.restart_session_and_seek(session, target_event_index, on_ready, {
		mod_id = 'spdrn',
		start_run = SPDRN._start_playback,
		pause_gate = SPDRN._ff_pause_gate,
		-- SPDRN._start_playback just tore down and rebuilt the room, which silently orphans the
		-- seek overlay UIBox (see SPDRN._reshow_seek_overlay's comment, ui/replay/checkpoint_picker.lua).
		-- No-op if nothing is currently supposed to be showing.
		on_run_started = SPDRN._reshow_seek_overlay,
	})
end

-- Starts viewing a replay/rejoin session, landing at `target_event_index` (defaults to 1, the
-- very beginning). `session` must already have {bootstrap, timeline, my_id, on_session_complete}
-- set (see replay_browser.lua's _launch_replay for the initial-open case, or
-- perspective_switch.lua's SPDRN._switch_perspective for the cross-player case) -- this fills in
-- `checkpoint_index`/`driver`/`seeking`.
--
-- Two bootstraps, deliberately: SPDRN._start_playback is called once here just to reach a live
-- BLIND_SELECT for the checkpoint-index build to actually dispatch against (a disposable driver
-- still needs a real running game to drive), and again inside _restart_session_and_seek below for
-- the real viewing session -- this is a known, flagged cost (see this feature's own design doc,
-- "double-bootstrap"), not an oversight; SPDRN._start_playback's own cost is unquantified in this
-- codebase and worth measuring during validation.
--
-- Builds the checkpoint index first (a full fast-forward pass over the WHOLE timeline, via a
-- disposable driver checkpoint_index.lua creates and discards internally -- session.driver is
-- never set by that pass), THEN restarts and seeks to target_event_index. Since session.driver is
-- always nil at that point (this function is the only place session.driver ever gets its FIRST
-- value), _restart_session_and_seek unconditionally does a real restart -- i.e. "start watching
-- from the beginning", "the player clicked a checkpoint before the index existed yet", and "the
-- player switched perspective" all funnel through the exact same restart-and-seek path, with no
-- separately-tested flow.
--
-- The caller is responsible for showing its own seek overlay text BEFORE calling this (different
-- callers want different text -- "Seeking to Ante 1..." vs "Syncing game state..." -- see
-- ui/replay/checkpoint_picker.lua's SPDRN._show_seek_overlay) and this function hides it once
-- ready, via _restart_session_and_seek's own on_ready callback.
function SPDRN._open_replay_session(session, target_event_index)
	session.seeking = true
	SPDRN._active_replay_session = session
	SPDRN._start_playback(session.bootstrap, function()
		-- Same re-show as _restart_session_and_seek's own on_ready above -- this bootstrap builds
		-- the checkpoint index via its own long-running fast-forward pass (checkpoint_index.lua),
		-- which is exactly the phase confirmed live to run with the overlay silently gone.
		SPDRN._reshow_seek_overlay()
		SPDRN._build_checkpoint_index(session, function(index)
			session.checkpoint_index = index
			SPDRN._restart_session_and_seek(session, target_event_index or 1, function(driver)
				session.driver = driver
				session.seeking = false
				SPDRN._wire_checkpoint_click()
				SPDRN._hide_seek_overlay()
				driver:play()
			end)
		end)
	end)
end

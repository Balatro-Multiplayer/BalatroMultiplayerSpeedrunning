-- Bootstraps a local, single-player run seeded to reproduce a previously
-- recorded RLOG run's exact seed/deck/stake/gamemode -- ported from
-- BalatroMultiplayerPvP's lib/playback_launch.lua. Reuses SPDRN's own
-- practice-mode bootstrap (SPDRN._start_practice, ui/main_menu/practice.lua)
-- almost verbatim: both are a local lobby (MPAPI.create_local_lobby, no
-- `.code`) that calls SPDRN.begin_run -- the same reason RLOG never
-- re-records during a playback session applies here unchanged (rlog_active(),
-- objects/replay_log/record.lua, gates on the current lobby having a code).
--
-- Known v1 gap: SPDRN.begin_run creates a FRESH gamemode instance
-- (_run_count = 0), so a multi-run format's (Stake Climb, White Stake Triple)
-- own per-run stake computed from _run_count reproduces correctly for a
-- match's FIRST run, but not exactly for a later run replayed on its own --
-- the instance would need its run-count fast-forwarded first. Gold Stake
-- Single/All Deck/Seed Scout/Challenge (single-run-focused formats) are
-- unaffected. Not solved this pass -- flagged, not silently wrong: a
-- mismatched stake would still play back the recorded actions, just at a
-- different (usually lower) stake than the original run.
function SPDRN._start_playback(manifest, on_ready)
	local current = MPAPI.get_current_lobby()
	if current and current.code then
		SPDRN.sendWarnMessage('_start_playback: refusing to start while connected to a real lobby (' .. tostring(current.code) .. ')')
		return
	end

	SPDRN._drop_playback_waiters()
	SPDRN._lobby_kind = SPDRN.LobbyKind.PRACTICE
	local lobby = MPAPI.create_local_lobby(SPDRN.id, { max_players = 1 })
	if not lobby then
		SPDRN._lobby_kind = nil
		return
	end
	lobby.suppress_lobby_view = true
	SPDRN.setup_lobby_events(lobby)

	lobby:on('connected', function()
		lobby:set_metadata({
			gamemode = manifest.gamemode,
			deck = manifest.deck,
			-- Recorded lobby_info's own ruleset field, NOT a hardcoded guess: forcing
			-- every replay onto ORDER regardless of what the original match actually
			-- used swaps in the_order.lua's entirely different RNG-consuming hooks
			-- (create_card/reset_idol_card/pseudoshuffle/etc, api/the_order.lua) from
			-- round 1 -- confirmed live as the cause of a replay desyncing from its
			-- own recording almost immediately (wrong cards resolved for play/discard,
			-- eventually crashing deep in vanilla scoring code). Falls back to ORDER
			-- only for pre-existing recordings from before lobby_info carried a real
			-- ruleset value (see run_start.lua's lobby_info:write call, which had its
			-- own bug passing gamemode_key instead of the real ruleset -- fixed
			-- alongside this). Validated against the known enum (not just "truthy"):
			-- recordings made before that fix have the corrupted value (a gamemode
			-- key, e.g. 'spdrn_white_stake_triple') baked into their stored args
			-- forever, and it would otherwise pass straight through as a bogus
			-- ruleset.
			ruleset = (manifest.ruleset == SPDRN.Ruleset.ORDER or manifest.ruleset == SPDRN.Ruleset.VANILLA)
					and manifest.ruleset
				or SPDRN.Ruleset.ORDER,
			kind = SPDRN.LobbyKind.PRACTICE,
		})
		SPDRN.begin_run(manifest.gamemode, manifest.deck, manifest.seed)
	end)

	SPDRN._playback_wait_for(function()
		return G.STATE == G.STATES.BLIND_SELECT
	end, on_ready)
end

-- Mid-replay run-transition handler for run_died/run_restarted (see
-- run_transition_codes.lua's header comment for why run_complete doesn't use
-- this). Pauses the driver, programmatically reproduces what clicking
-- "Restart Run" would have done (SPDRN.restart_current_run() -- real restart
-- machinery, not a reimplementation, so every teardown/rebuild side effect
-- fires exactly as live play would), then resumes once the fresh run's
-- BLIND_SELECT is actually ready. Safe to call from inside a dispatch the
-- driver itself just invoked: Driver:_tick (api/playback/driver.lua) is a
-- single top-to-bottom function with no reentrancy, so pausing mid-dispatch
-- just stops the NEXT tick from advancing, it doesn't unwind this one.
function SPDRN._playback_handle_run_transition(_kind, ctx)
	local driver = ctx.driver
	if not driver then return end
	driver:pause()
	-- CONFIRMED LIVE BUG, fixed by this exit_overlay_menu() call: dispatching the real recorded
	-- actions that lead up to a run_died is not a simulation of dying -- it IS dying, for real,
	-- so SPDRN's own live per-frame watcher (SPDRN._check_run_lost, ui/lose_screen.lua) fires
	-- exactly as it would for a real player and shows the real "OOPS! Restart Run / Forfeit"
	-- lose-screen overlay, no_esc=true, G.SETTINGS.paused=true. SPDRN.restart_current_run()
	-- below only resets the underlying run/gamemode state (safe_start_run) -- it does NOT touch
	-- G.OVERLAY_MENU or G.SETTINGS.paused, unlike the live "Restart Run" button's own handler
	-- (G.FUNCS.spdrn_restart_run, ui/lose_screen.lua), which explicitly calls exit_overlay_menu()
	-- before restarting for exactly this reason. Without this call here, that lose-screen overlay
	-- is left stuck on top forever with the game paused: reproduced live via cctl eval polling a
	-- real recording's own checkpoint-index-build/restart-seek -- G.SETTINGS.paused=true blocks
	-- G.E_MANAGER's own queue draining, which MPAPI.playback._queues_empty() (every dispatch
	-- path's own gate, normal-pace and fast_forward_to's tight loop alike) depends on, so the
	-- cursor froze permanently at its pre-death value, silently hanging the whole replay/rejoin/
	-- checkpoint-index-build, not just this one blind. Unconditionally safe to call here: this
	-- function is exclusively reached from run_died/run_restarted's own .replay() handler
	-- (run_transition_codes.lua, gated on ctx.is_pov), never from live real-time play, so there
	-- is no real "Restart Run" click this could ever incorrectly steal from a real player.
	-- G.FUNCS.exit_overlay_menu() itself already no-ops safely if no overlay is currently up.
	G.FUNCS.exit_overlay_menu()
	SPDRN.restart_current_run()
	SPDRN._playback_wait_for(function()
		return G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
	end, function()
		-- The exit_overlay_menu() call above may have just dismissed OUR OWN active seek/sync
		-- overlay instead of a stale lose-screen (same single G.OVERLAY_MENU slot either way) --
		-- re-show it now, mirroring checkpoint_seek.lua's own SPDRN._reshow_seek_overlay() call
		-- sites for the identical "a restart wiped some piece of UI state" reason. No-op if no
		-- seek overlay was active (e.g. this run_died happened to land exactly between seeks).
		SPDRN._reshow_seek_overlay()
		driver:play()
	end)
end

-- Minimal, self-contained one-shot condition poll -- same shape as PvP's own
-- (lib/playback_launch.lua), kept as SPDRN's own copy rather than a shared
-- MPAPI utility since MPAPI.playback's driver (api/playback/driver.lua)
-- already owns the per-EVENT pacing; this is only for the one-time
-- bootstrap-to-BLIND_SELECT wait before a driver even exists.
SPDRN._playback_waiters = SPDRN._playback_waiters or {}

function SPDRN._playback_wait_for(predicate, callback)
	SPDRN._playback_waiters[#SPDRN._playback_waiters + 1] = { predicate = predicate, callback = callback }
end

-- A waiter belongs to the run it was made in: a fresh playback run drops the
-- rest. Left in, one would act on the new run -- a rejoin's checkpoint-index
-- pass ends as soon as its last entry is dispatched, so a recording ending on
-- skip_blind left that skip's retry waiter polling, and it skipped the fresh
-- run's Small Blind again on top of the real pass's own skip.
function SPDRN._drop_playback_waiters()
	SPDRN._playback_waiters = {}
end

local _playback_launch_update_ref = Game.update
function Game:update(dt)
	_playback_launch_update_ref(self, dt)
	local waiters = SPDRN._playback_waiters
	for i = #waiters, 1, -1 do
		-- A callback that started a fresh run dropped the rest of these.
		if waiters ~= SPDRN._playback_waiters then
			break
		end
		local w = waiters[i]
		if w.predicate() then
			table.remove(waiters, i)
			w.callback()
		end
	end
end

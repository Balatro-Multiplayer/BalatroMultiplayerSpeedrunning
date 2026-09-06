-- Rejoin (crash-relaunch resume): fast-forwards through the player's own
-- buffered RLOG events for the still-active run via the same bootstrap/
-- driver machinery "My Replays" uses (playback_launch.lua/
-- playback_handlers.lua), then hands off to live play by rejoining the real
-- lobby instead of ending in a "replay finished" toast. SPDRN is solo (no
-- opponent to catch up), so live hand-off is just MPAPI.join_lobby -- there
-- is no opponent-HUD projection state that needs a separate catch-up pass
-- here.
--
-- Takes `active` (MPAPI.replay.get_active_run's own response shape --
-- {runId, lobbyCode, modId, events}) rather than fetching by run_id itself:
-- an ACTIVE run has no DB-persisted matchRunLogs row yet (only written at
-- finalize), so MPAPI.replay.get(run_id) 403s "not a participant" for a
-- genuinely active run's own participant -- confirmed live. `events` is
-- already this player's own buffered stream (server-side getTail against
-- the live in-memory buffer), so no second fetch is needed at all.
function SPDRN._launch_rejoin(active)
	local conn = MPAPI.get_connection()
	local my_id = conn and conn.player_id
	-- Confirmed live: a connection object can exist (MPAPI.get_connection() non-nil) while its
	-- own player_id is still unset (e.g. a Steam-auth handshake that hasn't completed) -- every
	-- timeline entry built below gets player_id = my_id, so a nil my_id here means every entry
	-- gets player_id = nil. Driver:_dispatch_next (api/playback/driver.lua) keys its per-player
	-- card-resolver table BY player_id, and a nil table key crashes that assignment outright ("
	-- table index is nil") the moment the FIRST entry dispatches -- not a graceful desync, a hard
	-- crash. Guarding here (same early-return style as the bootstrap-completeness check just
	-- below) stops a bad connection state from ever reaching the driver at all, rather than
	-- relying solely on driver.lua's own defensive guard (belt-and-suspenders, not redundant --
	-- see that guard's own comment for why both layers matter).
	if not my_id then
		SPDRN.sendWarnMessage('[rejoin] no connection player_id available -- refusing to rejoin rather than dispatch a driver with an unidentified player')
		return
	end

	-- Merges the first match_manifest (schema_version) + first lobby_info
	-- (gamemode/ruleset) + first run_info (seed/deck/stake) event, same as
	-- replay_browser.lua's find_bootstrap -- kept as an inline loop here
	-- since `active.events` isn't a built timeline (no player_id per entry;
	-- it's already this player's own single stream).
	local bootstrap, found = {}, {}
	local timeline = {}
	for _, ev in ipairs(active.events or {}) do
		if not found.match_manifest and ev.opcode == 'match_manifest' then
			found.match_manifest = true
			bootstrap.schema_version = ev.args.schema_version
		elseif not found.lobby_info and ev.opcode == 'lobby_info' then
			found.lobby_info = true
			bootstrap.gamemode = ev.args.gamemode
			bootstrap.ruleset = ev.args.ruleset
		elseif not found.run_info and ev.opcode == 'run_info' then
			found.run_info = true
			bootstrap.seed = ev.args.seed
			bootstrap.deck = ev.args.deck
			bootstrap.stake = ev.args.stake
		end
		timeline[#timeline + 1] = { t = ev.t, player_id = my_id, opcode = ev.opcode, args = ev.args }
	end
	if not (found.lobby_info and found.run_info) then
		SPDRN.sendWarnMessage('[rejoin] no bootstrap data in active run ' .. tostring(active.runId))
		return
	end
	if not MPAPI.replay.is_schema_compatible(bootstrap.schema_version) then
		SPDRN.sendWarnMessage(
			'[rejoin] recording schema_version ' .. tostring(bootstrap.schema_version)
			.. ' is newer than this client understands (' .. tostring(MPAPI.replay.SCHEMA_VERSION) .. '); refusing to rejoin'
		)
		return
	end

	-- Faster catch-up: fast-forward through as much of the player's own history as safely
	-- possible, then finish the remaining tail at normal pace before handing off to live play
	-- -- reusing the exact same session/index/restart machinery "My Replays" uses
	-- (objects/replay_log/checkpoint_index.lua, checkpoint_seek.lua), not a rejoin-specific
	-- reimplementation.
	--
	-- Deliberately TWO bootstraps here (SPDRN._start_playback called once to build the ante
	-- index, again inside _restart_session_and_seek for the real catch-up run), same as
	-- replay-viewing's own _open_replay_session -- an earlier version of this design considered
	-- a single fast-forward pass with a live-adjusting target to avoid the second bootstrap, but
	-- that requires knowing where "the second-to-last ante" is BEFORE dispatching, which (like
	-- the index itself) can only be learned by actually dispatching -- doing that safely inside
	-- a live-adjusting target would need a new early-stop primitive on Driver with no other
	-- caller, more moving parts, for a saving that's unmeasured and likely small once both
	-- passes are fast-forwarded rather than real-time. Reusing the already-built, already-
	-- correct two-step path is the simpler, safer choice for a mechanism this codebase has
	-- never used before (see this feature's own design doc's GAMESPEED-validation section).
	--
	-- The buffered `active.events` this whole function's timeline is built from is a ONE-TIME
	-- snapshot, not live-updating (MPAPI.replay.get_active_run's own getTail call) -- but that's
	-- not a gap here: a player's own event stream can only grow while THEIR OWN client is
	-- actively running and recording, which by definition it isn't while disconnected, so this
	-- snapshot is already the complete history up to the crash. Nothing is caught up to "now"
	-- beyond that snapshot by this mechanism -- whatever live re-sync happens after
	-- MPAPI.join_lobby hands off to real play (unchanged, out of scope here) is what closes any
	-- remaining gap, exactly as it already does today.
	local session = {
		bootstrap = bootstrap,
		timeline = timeline,
		my_id = my_id,
		on_session_complete = function()
			local lobby = MPAPI.join_lobby(SPDRN.id, active.lobbyCode)
			-- Opt out of on_lobby_connected's "match formed while practicing,
			-- exit the run" behavior (api/mod_registry/focus.lua) -- we're
			-- reconnecting to the SAME run we just fast-forwarded, not
			-- discovering a new one; must be set before the async connect
			-- callback fires. Confirmed live: without this, rejoin silently
			-- exited the just-restored run back to the main menu.
			if lobby then lobby._skip_run_exit_on_connect = true end
			SPDRN._active_replay_session = nil
		end,
	}
	SPDRN._active_replay_session = session

	SPDRN._start_playback(bootstrap, function()
		SPDRN._build_checkpoint_index(session, function(index)
			session.checkpoint_index = index
			-- Cutoff = the START of the second-to-last known ANTE (not blind -- deliberately
			-- coarser than checkpoint_index.lua's own blind-level granularity, via
			-- SPDRN._checkpoint_ante_boundaries), not literally "now" -- leaves at least one
			-- full ante's worth of real events for the normal-pace tail, and lands that tail at
			-- a clean shop/blind-select boundary rather than an arbitrary mid-hand cutoff, where
			-- playback_handlers.lua's own readiness gates (with_shop_ready,
			-- wait_for_blind_select_screen, etc) are least likely to be caught mid-transition.
			-- If fewer than 2 ante boundaries exist yet (a very short/fresh run), there's
			-- nothing meaningful to skip -- replay the whole thing at normal pace, same as
			-- today.
			local ante_boundaries = SPDRN._checkpoint_ante_boundaries(index)
			local n = #ante_boundaries
			local cutoff = n >= 2 and ante_boundaries[n - 1].event_index or 1
			SPDRN._restart_session_and_seek(session, cutoff, function(driver)
				session.driver = driver
				driver:play() -- normal-pace tail from here on -- unchanged existing behavior
			end)
		end)
	end)
end

MPAPI.playback.register_rejoin(SPDRN.id, SPDRN._launch_rejoin)

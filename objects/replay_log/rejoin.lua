-- SPDRN's side of the crash rejoin. The flow itself (join the lobby first, skip to the last
-- checkpoint, play the tail, resume) is MPAPI's: BalatroMultiplayerAPI/api/playback/rejoin.lua.
-- SPDRN supplies the hooks: what its run start needs from the log, how to boot the catch-up run,
-- and the state to restore before the run goes live (the race clocks, the lobby events).
-- SPDRN is a race, so nothing waits for a racer who is catching up and it sets no catch-up limit.

-- The catch-up must know every deck of a multi-run format (White Stake Triple, All Deck): with
-- only run 1's deck, the run after the first win restarts on that same deck.
local function read_lobby_info(args, bootstrap)
	local decks = args.decks
	if type(decks) == 'table' and #decks > 1 then
		bootstrap.deck = decks
	end
end

local function read_run_info(args, bootstrap)
	bootstrap.deck = bootstrap.deck or args.deck
end

-- The race clocks restart from zero in the catch-up playback (SPDRN.begin_run), but the race went
-- on: carry them on from the recorded stream. `t` is milliseconds into the match (the RLOG clock),
-- so the match clock stands at the last recorded event's t and the clock of the run in progress at
-- the t its run_info was written. The time spent away is not in the stream (ticket 07 makes the
-- clock real time).
local function restore_race_clocks(events)
	local last_t, run_t = 0, 0
	for _, ev in ipairs(events or {}) do
		if type(ev.t) == 'number' then
			if ev.t > last_t then
				last_t = ev.t
			end
			if ev.opcode == 'run_info' then
				run_t = ev.t
			end
		end
	end
	local now = love.timer.getTime()
	SPDRN._run_started_at = now - last_t / 1000
	SPDRN._current_run_started_at = now - math.max(last_t - run_t, 0) / 1000
end

local function attach(lobby, ctx)
	restore_race_clocks(ctx.events)
	-- The live lobby replaces the local playback one, which still holds SPDRN.lobby.ref and left
	-- _lobby_kind on PRACTICE: wire SPDRN's lobby events to the real lobby (its result, end
	-- screen, votes) and take its kind from the server-reported type, as the waiting-room
	-- reconnect does (ui/lobby/reconnect.lua). Without this the rejoined player got the practice
	-- end screen (Practice Again) for a lobby game.
	SPDRN._lobby_kind = SPDRN.LobbyKind.PRIVATE
	SPDRN.setup_lobby_events(lobby)
	lobby:on('connected', function()
		SPDRN._lobby_kind = SPDRN.rejoined_lobby_kind(lobby)
	end)
	SPDRN._active_replay_session = nil
end

MPAPI.playback.register_rejoin_hooks(SPDRN.id, {
	playback_mod_id = 'spdrn',
	read_lobby_info = read_lobby_info,
	read_run_info = read_run_info,
	start_run = function(bootstrap, on_ready)
		SPDRN._start_playback(bootstrap, on_ready)
	end,
	checkpoint_options = function()
		return {
			boundary_opcodes = SPDRN._CHECKPOINT_BOUNDARY_OPCODES,
			run_index = function()
				return SPDRN.current_run(MPAPI.get_current_lobby())
			end,
			pause_gate = SPDRN._ff_pause_gate,
		}
	end,
	before_play = function(session)
		SPDRN._active_replay_session = session
	end,
	attach = attach,
	aborted = function()
		SPDRN._active_replay_session = nil
	end,
})

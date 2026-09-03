-- Builds a { {run_idx, ante, event_index}, ... } index of a replay/rejoin session's own
-- timeline, so SPDRN._seek_to_ante (ante_seek.lua) and SPDRN._launch_rejoin (rejoin.lua) know
-- exactly which Driver._cursor value to MPAPI.playback's Driver:fast_forward_to for any given
-- ante. No recorded opcode carries an ante or run number anywhere (play/discard/buy/sell/
-- select_blind/skip_blind/cashout/money_delta/run_info/lobby_info/match_manifest/run_died/
-- run_restarted -- checked exhaustively) -- the only way to know "ante N starts at event index
-- M" is to actually dispatch through a disposable driver and read live
-- G.GAME.round_resets.ante (same field read the same way elsewhere, e.g. objects/matchmaking/
-- progress.lua and location.lua) after every dispatched opcode that could plausibly have
-- changed it, via MPAPI.playback.new_driver's on_after_dispatch hook (api/playback/driver.lua).

-- Shared pause_gate for every fast_forward_to call this mod makes (index-building, seeking,
-- rejoin's shortened catch-up alike): a tight same-frame dispatch loop can race ahead of
-- SPDRN's own deferred-by-one-real-frame run-transition poll (SPDRN._pending_run_transition,
-- set synchronously by request_run_transition -- ui/lobby/run_start.lua -- but only actually
-- consumed by SPDRN._check_pending_run_transition on the NEXT real Game:update frame, per
-- core.lua's own per-frame poll chain). Every multi-run gamemode's calculate() calls
-- request_run_transition synchronously as a side effect of a dispatched opcode (e.g. a
-- cashout completing the ante-9 blind), so without this gate a fast-forward could dispatch the
-- NEXT run's own opcodes into the still-torn-down previous run's game state. Returning true
-- here means "don't dispatch another entry this frame" -- see Driver:fast_forward_to's own
-- header comment (api/playback/driver.lua) for the full rationale.
function SPDRN._ff_pause_gate()
	return SPDRN._pending_run_transition ~= nil
end

function SPDRN._build_ante_index(session, on_built)
	local index = {}
	local last_key = nil

	-- Only select_blind/skip_blind/run_died/run_restarted can ever change
	-- G.GAME.round_resets.ante or SPDRN.current_run's own _run_count -- gating on opcode here
	-- (rather than checking after every single dispatched entry, which would also work since
	-- this no-ops when nothing's changed) keeps the hot path -- play/discard/buy/sell/reorder/
	-- use/pack_pick/reroll, the overwhelming majority of a real match's opcodes -- from paying
	-- for a lobby/instance lookup it can never need.
	local function maybe_record_boundary(opcode, cursor)
		if opcode ~= 'select_blind' and opcode ~= 'skip_blind'
			and opcode ~= 'run_died' and opcode ~= 'run_restarted' then
			return
		end
		if not G.GAME then
			return
		end
		local run_idx = SPDRN.current_run(MPAPI.get_current_lobby())
		local ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
		local key = run_idx .. ':' .. ante
		if key == last_key then
			return
		end
		last_key = key
		index[#index + 1] = { run_idx = run_idx, ante = ante, event_index = cursor }
	end

	local driver = MPAPI.playback.new_driver(session.timeline, {
		mod_id = 'spdrn',
		pov_player_id = session.my_id,
		schema_version = session.bootstrap.schema_version,
		on_after_dispatch = function(entry, ctx)
			-- ctx.driver._cursor has already advanced PAST the entry that was just dispatched
			-- (Driver:_dispatch_next increments it before calling dispatch/on_after_dispatch) --
			-- exactly the "cursor value immediately after the entry that produced this ante"
			-- fast_forward_to's target_cursor expects.
			maybe_record_boundary(entry.opcode, ctx.driver._cursor)
		end,
	})

	-- Ante 1 of run 1 starts at the very beginning, before any select_blind/skip_blind opcode
	-- has fired -- seed the index with event_index=1 so a seek to "ante 1" (including the
	-- implicit one every "open a replay" call makes, see ante_seek.lua's own comment) always
	-- has an entry to find, with no "index is still empty" special case anywhere else.
	local start_run_idx = SPDRN.current_run(MPAPI.get_current_lobby())
	local start_ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
	last_key = start_run_idx .. ':' .. start_ante
	index[1] = { run_idx = start_run_idx, ante = start_ante, event_index = 1 }

	driver:finish()
	driver:fast_forward_to(#session.timeline + 1, {
		pause_gate = SPDRN._ff_pause_gate,
		on_stalled = function(cursor, target)
			MPAPI.sendWarnMessage('[ante_index] build stalled at ' .. tostring(cursor) .. '/' .. tostring(target) .. ' -- degrading to normal-pace dispatch to finish it')
		end,
		on_done = function()
			on_built(index)
		end,
	})
end

-- Sums the money_delta opcodes recorded between ante_index[i]'s own event_index and the next
-- entry's (or the end of the timeline, for the last entry) -- no per-ante money ledger exists
-- anywhere in this codebase today, so this is freshly derived from the raw timeline each time,
-- then memoized onto the index entry itself (the timeline never changes once built). Used only
-- for the ante popup's own money-spent-by-ante labels (ui/replay/ante_picker.lua) -- purely a
-- UI nicety, no seek/fast-forward logic depends on this.
--
-- money_delta's own recorded `args` is a BARE NUMBER, not a positional array, unlike buy/sell/
-- reorder/etc -- verified against api/replay/generic_codes.lua's own write = function(self,
-- delta) self:record(delta) end. Do not index it as args[1].
function SPDRN._ante_money_spent(session, i)
	local index = session.ante_index
	local entry = index and index[i]
	if not entry then
		return 0
	end
	if entry._money_spent ~= nil then
		return entry._money_spent
	end
	local from = entry.event_index
	local to = (index[i + 1] and index[i + 1].event_index or (#session.timeline + 1)) - 1
	local total = 0
	for j = from, to do
		local ev = session.timeline[j]
		if ev and ev.opcode == 'money_delta' and type(ev.args) == 'number' then
			total = total + ev.args
		end
	end
	entry._money_spent = total
	return total
end

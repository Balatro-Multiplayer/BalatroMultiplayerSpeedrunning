-- Builds a { {run_idx, ante, blind, event_index}, ... } checkpoint index of a replay/rejoin
-- session's own timeline, so SPDRN._seek_to_checkpoint (checkpoint_seek.lua) and
-- SPDRN._launch_rejoin (rejoin.lua) know exactly which Driver._cursor value to
-- MPAPI.playback's Driver:fast_forward_to for any given ante or blind. No recorded opcode
-- carries an ante/run/blind number anywhere (play/discard/buy/sell/select_blind/skip_blind/
-- cashout/money_delta/run_info/lobby_info/match_manifest/run_died/run_restarted -- checked
-- exhaustively) -- the only way to know "ante N's Big Blind starts at event index M" is to
-- actually dispatch through a disposable driver and read live G.GAME.round_resets.ante/
-- G.GAME.blind_on_deck (same fields read the same way elsewhere, e.g. objects/matchmaking/
-- progress.lua/location.lua and this file's own do_select_blind precedent in
-- playback_handlers.lua) after every dispatched opcode that could plausibly have changed
-- them, via MPAPI.playback.new_driver's on_after_dispatch hook (api/playback/driver.lua).
--
-- One checkpoint tier, not two parallel structures: select_blind/skip_blind already fire once
-- per BLIND, not once per ante (Small/Big/Boss are three separate clicks) -- G.GAME.blind_on_deck
-- cycles 'Small' -> 'Big' -> 'Boss' and resets to 'Small' exactly on ante advance, so "the first
-- blind of a new ante" and "the ante's own boundary" are literally the same recorded row. Ante-
-- level views (the popup's own per-ante row, rejoin's catch-up cutoff) are derived from this same
-- flat index via SPDRN._checkpoint_ante_boundaries below, not tracked separately.

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

function SPDRN._build_checkpoint_index(session, on_built)
	local index = {}
	local last_key = nil

	-- Records a checkpoint for the CURRENT live G.GAME state at `cursor`, deduped against the
	-- last-recorded key. Only ever called once the caller is sure state has actually settled --
	-- see maybe_record_boundary's own comment below for why that's never "immediately after
	-- dispatching the opcode that triggers it".
	local function record_if_new(cursor)
		if not G.GAME then
			return
		end
		local run_idx = SPDRN.current_run(MPAPI.get_current_lobby())
		local ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
		local blind = G.GAME.blind_on_deck or 'Small'
		local key = run_idx .. ':' .. ante .. ':' .. blind
		if key == last_key then
			return
		end
		last_key = key
		index[#index + 1] = { run_idx = run_idx, ante = ante, blind = blind, event_index = cursor }
	end

	-- Only select_blind/skip_blind/run_died/run_restarted can ever change
	-- G.GAME.round_resets.ante/G.GAME.blind_on_deck or SPDRN.current_run's own _run_count --
	-- gating on opcode here (rather than checking after every single dispatched entry, which
	-- would also work since this no-ops when nothing's changed) keeps the hot path --
	-- play/discard/buy/sell/reorder/use/pack_pick/reroll, the overwhelming majority of a real
	-- match's opcodes -- from paying for a lobby/instance lookup it can never need.
	--
	-- CONFIRMED LIVE BUG, fixed by the `pending`/deferred-check scheme below: select_blind/
	-- skip_blind/run_died/run_restarted's own replay handlers (playback_handlers.lua/
	-- playback_launch.lua) apply their real effect ASYNCHRONOUSLY -- each one calls
	-- driver:pause() and only calls driver:play() again once SPDRN._playback_wait_for's
	-- Game:update-polled condition confirms the transition actually landed (earliest possible
	-- resolution is the NEXT real frame, never synchronous -- _playback_wait_for only ever
	-- appends to a waiters list, it never checks its predicate immediately). Reading
	-- G.GAME.round_resets.ante/blind_on_deck synchronously in on_after_dispatch, as this
	-- function's first version did, therefore races that async settle: reproduced against two
	-- real production matches via MPAPI.playback.build_timeline (local Postgres import) --
	-- one case silently DROPPED an entire ante's worth of checkpoints (deduped against stale
	-- pre-transition state that never changed by the time the next boundary opcode's own
	-- premature check fired), another caught a TORN read mid-transition, recording the
	-- logically-impossible `{ante=2, blind='Boss'}` (Boss is always an ante's LAST blind, never
	-- its first -- ante had already bumped to 2 but blind_on_deck hadn't yet been reset to
	-- 'Small'). Fix: since the driver cannot dispatch ANYTHING further (any opcode, any player)
	-- while paused, the next entry to actually dispatch -- whichever it is -- can only happen
	-- once the async chain the PREVIOUS boundary opcode kicked off has fully resolved. So defer
	-- the read by exactly one dispatched entry: stash the cursor of a boundary-triggering
	-- opcode as `pending`, and resolve it (record_if_new, using now-guaranteed-settled state)
	-- on the very next on_after_dispatch call, before considering whether THAT entry is itself
	-- a new boundary trigger. Also flushed at fast_forward_to's own on_done, for a boundary
	-- opcode that happens to be the last entry in the whole timeline.
	local pending_cursor = nil
	local function maybe_record_boundary(opcode, cursor)
		if pending_cursor then
			record_if_new(pending_cursor)
			pending_cursor = nil
		end
		if opcode == 'select_blind' or opcode == 'skip_blind'
			or opcode == 'run_died' or opcode == 'run_restarted' then
			pending_cursor = cursor
		end
	end

	local driver = MPAPI.playback.new_driver(session.timeline, {
		mod_id = 'spdrn',
		pov_player_id = session.my_id,
		schema_version = session.bootstrap.schema_version,
		on_after_dispatch = function(entry, ctx)
			-- ctx.driver._cursor has already advanced PAST the entry that was just dispatched
			-- (Driver:_dispatch_next increments it before calling dispatch/on_after_dispatch) --
			-- exactly the "cursor value immediately after the entry that produced this
			-- checkpoint" fast_forward_to's target_cursor expects.
			maybe_record_boundary(entry.opcode, ctx.driver._cursor)
		end,
	})

	-- Ante 1's Small Blind starts at the very beginning, before any select_blind/skip_blind
	-- opcode has fired -- seed the index with event_index=1 so a seek to "ante 1" (including
	-- the implicit one every "open a replay" call makes, see checkpoint_seek.lua's own comment)
	-- always has an entry to find, with no "index is still empty" special case anywhere else.
	local start_run_idx = SPDRN.current_run(MPAPI.get_current_lobby())
	local start_ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
	local start_blind = G.GAME.blind_on_deck or 'Small'
	last_key = start_run_idx .. ':' .. start_ante .. ':' .. start_blind
	index[1] = { run_idx = start_run_idx, ante = start_ante, blind = start_blind, event_index = 1 }

	driver:finish()
	driver:fast_forward_to(#session.timeline + 1, {
		pause_gate = SPDRN._ff_pause_gate,
		on_stalled = function(cursor, target)
			MPAPI.sendWarnMessage('[checkpoint_index] build stalled at ' .. tostring(cursor) .. '/' .. tostring(target) .. ' -- degrading to normal-pace dispatch to finish it')
		end,
		on_done = function()
			-- Flush a boundary opcode that never got a following entry to defer onto (the
			-- recording's very last dispatched entry was itself select_blind/skip_blind/
			-- run_died/run_restarted). NOT fully safe from the same race the `pending` scheme
			-- above closes for every other case: Driver:_fast_forward_tick's own on_done trigger
			-- (`self._cursor >= self._ff_target`) fires as soon as the cursor reaches the end,
			-- with no check for whether the driver is still paused mid-async-settle from that
			-- very last dispatch -- unlike every other boundary opcode, there's no NEXT entry
			-- whose dispatch could only happen after the pause naturally resolved. Reading here
			-- can therefore still race a trailing, log-truncated transition (recording ends
			-- exactly on a blind-select/death opcode with nothing after it). Left as a narrow,
			-- flagged residual gap rather than adding a further deferred-frame wait for it: this
			-- specific shape (log truncated mid-transition, e.g. a disconnect right after
			-- selecting a blind) is inherently ambiguous -- the original recording may never have
			-- resolved it either -- and not worth the added complexity of another async hop for
			-- what "the very last checkpoint of an already-finished pass" is worth.
			if pending_cursor then
				record_if_new(pending_cursor)
				pending_cursor = nil
			end
			on_built(index)
		end,
	})
end

-- Collapses a blind-granular checkpoint index down to one entry per distinct (run_idx, ante) --
-- the FIRST blind checkpoint of each ante, which by construction (blind_on_deck resets to
-- 'Small' exactly on ante advance -- see this file's own header comment) is always that ante's
-- own boundary. Used anywhere that wants "one row per ante" semantics: the popup's own top-level
-- ante rows/money labels, and rejoin.lua's catch-up cutoff (which deliberately wants an
-- ante-level safety margin, not a blind-level one -- see that file's own comment).
function SPDRN._checkpoint_ante_boundaries(index)
	local out, last = {}, nil
	for _, e in ipairs(index or {}) do
		local key = e.run_idx .. ':' .. e.ante
		if key ~= last then
			last = key
			out[#out + 1] = e
		elseif e.blind == 'Small' then
			-- CONFIRMED LIVE BUG (same root cause as checkpoint_seek.lua's find_checkpoint_entry
			-- and ui/replay/checkpoint_picker.lua's group_checkpoints -- both already fixed to
			-- prefer the LAST attempt, this function was the one place still missing the same
			-- fix): a mid-run restart (a real "Restart Run" click, or ui/lose_screen.lua's
			-- divergent-death auto-restart fallback) resets G.GAME.round_resets.ante back to
			-- whatever ante the fresh attempt starts from, so the flat index can record the SAME
			-- (run_idx, ante) more than once -- once per attempt, never deduped across the restart
			-- (this function's own `key ~= last` check only collapses CONSECUTIVE identical keys,
			-- and every entry within one ante shares that key regardless of blind, so without this
			-- branch the very first `if key ~= last` already swallows every later attempt's own
			-- entries as "already seen", permanently keeping the abandoned FIRST attempt's boundary
			-- -- silently wrong money labels (SPDRN._checkpoint_money_spent) and rejoin.lua's own
			-- catch-up cutoff, both computed FROM this function's output. A Small Blind checkpoint
			-- always starts a genuinely fresh attempt at that ante (blind_on_deck's own reset, see
			-- checkpoint_index.lua's header comment) -- so seeing 'Small' again for an ante this
			-- loop already recorded a boundary for is the reliable "a restart happened" signal, not
			-- a duplicate frame of the same attempt (Big/Boss entries of the SAME still-current
			-- attempt correctly fall through this branch untouched, leaving the boundary pointing
			-- at that attempt's own Small, exactly as intended).
			out[#out] = e
		end
	end
	return out
end

-- Sums the money_delta opcodes recorded between two ADJACENT entries of whatever index array is
-- passed in (event_index of entries[i] up to, but not including, entries[i+1]'s event_index, or
-- the end of the timeline for the last entry) -- no per-checkpoint money ledger exists anywhere
-- in this codebase today, so this is freshly derived from the raw timeline each time, then
-- memoized onto the entry table itself (the timeline never changes once built). Used only for
-- the popup's own money-spent labels (ui/replay/checkpoint_picker.lua) -- purely a UI nicety, no
-- seek/fast-forward logic depends on this.
--
-- Callers computing an ANTE-level label must pass SPDRN._checkpoint_ante_boundaries(index)'s
-- output here, not the raw blind-granular index -- passing the raw index for an ante row would
-- silently sum only "money spent since the last blind" instead of "money spent this ante".
--
-- money_delta's own recorded `args` is a BARE NUMBER, not a positional array, unlike buy/sell/
-- reorder/etc -- verified against api/replay/generic_codes.lua's own write = function(self,
-- delta) self:record(delta) end. Do not index it as args[1].
function SPDRN._checkpoint_money_spent(session, entries, i)
	local entry = entries and entries[i]
	if not entry then
		return 0
	end
	if entry._money_spent ~= nil then
		return entry._money_spent
	end
	local from = entry.event_index
	local to = (entries[i + 1] and entries[i + 1].event_index or (#session.timeline + 1)) - 1
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

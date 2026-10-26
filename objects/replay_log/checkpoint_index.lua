-- SPDRN's side of the checkpoint index. The index itself (build, ante boundaries, money labels)
-- is MPAPI's: BalatroMultiplayerAPI/api/playback/checkpoint_index.lua. SPDRN adds what is its own:
-- the run counter, the opcodes that change a run, and the pause gate below.
-- SPDRN._seek_to_checkpoint (checkpoint_seek.lua) and the rejoin hooks (rejoin.lua) read it.

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

SPDRN._CHECKPOINT_BOUNDARY_OPCODES = { 'select_blind', 'skip_blind', 'run_died', 'run_restarted' }

function SPDRN._build_checkpoint_index(session, on_built)
	MPAPI.playback.build_checkpoint_index(session, {
		mod_id = 'spdrn',
		boundary_opcodes = SPDRN._CHECKPOINT_BOUNDARY_OPCODES,
		run_index = function()
			return SPDRN.current_run(MPAPI.get_current_lobby())
		end,
		pause_gate = SPDRN._ff_pause_gate,
	}, on_built)
end

SPDRN._checkpoint_ante_boundaries = MPAPI.playback.checkpoint_ante_boundaries
SPDRN._checkpoint_money_spent = MPAPI.playback.checkpoint_money_spent

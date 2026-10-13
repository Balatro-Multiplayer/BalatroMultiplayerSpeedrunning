-- Handles for queues currently being searched, keyed by wire game_mode string (e.g.
-- 'spdrn_gold_stake_single' or 'ranked:spdrn_gold_stake_single') -- a player can search
-- several SPDRN modes at once (one Nakama matchmaker ticket each). Cleared per-key as
-- each queue is left, errors out, or turns into a real match.
SPDRN._queue_handles = {}

-- The handle of the match actually formed (nil when not in a match). Distinct from
-- _queue_handles: forming a match cancels every other queue (see queue.lua's
-- _cancel_other_queues), since a player is only ever in one lobby/run at a time even though
-- they could be searching several queues at once. Kept as a settable SPDRN field because
-- tests inject a mock handle here (MPAPI.testing.mock_match_handle).
SPDRN._current_match_handle = nil

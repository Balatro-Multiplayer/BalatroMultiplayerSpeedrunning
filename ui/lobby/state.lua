-- Shared, per-session lobby state. Every ui/lobby/* module reads and writes these refs at
-- call time (never captured as a load-time upvalue), so the split modules stay decoupled and
-- load order between them does not matter. SPDRN._lobby_kind and SPDRN._current_match_handle
-- deliberately stay top-level SPDRN fields because tests read/assign them directly.
--
-- Fields are filled defensively: a sibling module may create a partial SPDRN.lobby table (with
-- just `buttons`) before this file loads, so we fill any missing field rather than replacing
-- the table, which keeps the ready/seed-vote trackers single-instance for the session.
SPDRN.lobby = SPDRN.lobby or {}
local L = SPDRN.lobby

L.buttons = L.buttons or {}
L.ready = L.ready or MPAPI.ReadyTracker()
L.seed_votes = L.seed_votes or MPAPI.VoteTracker()
if L.local_ready == nil then
	L.local_ready = false
end
if L.start_broadcasted == nil then
	L.start_broadcasted = false
end
if L.buttons_initialized == nil then
	L.buttons_initialized = false
end

-- The active matchmaking handle (nil when not queued/in a match). Kept as a settable SPDRN
-- field because tests inject a mock handle here (MPAPI.testing.mock_match_handle).
SPDRN._current_match_handle = nil

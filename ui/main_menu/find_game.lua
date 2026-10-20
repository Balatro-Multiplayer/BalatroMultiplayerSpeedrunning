-- Whether the Ranked queue buttons should actually be clickable right now:
-- MPAPI's confirmation that the *server* accepted our launcher-integrity
-- challenge response (see MPAPI.is_launcher_verified() in
-- api/connection/lifecycle.lua - NOT a client-side-only "did BET answer"
-- check, the actual server verdict). Nakama's ranked queue hook enforces this
-- same requirement independently either way - this only avoids sending a
-- request that's going to be refused, and gives the player an
-- honest button state instead of a click that silently does nothing or
-- bounces off an error toast. Ranked play itself used to also be gated
-- behind a separate, always-off SPDRN.RANKED_ENABLED kill switch (a
-- client-side mirror of the server's own RANKED_ENABLED env flag) - removed
-- now that Ranked is actually live; the server's assertRankedEnabled()
-- guard in matchmaking.route.ts is still the real switch if it ever needs
-- to come back.
--
-- Now asked through MPAPI.can_queue (MPAPI api/connection/standing.lua), which
-- also refuses a game whose reported mods aren't allowed.
function SPDRN._ranked_queue_available()
	return (MPAPI.can_queue(MPAPI.QueueKind.RANKED))
end

-- Routes to the shared gamemode-select page (ui/main_menu/game_select.lua) instead of this
-- file's old dedicated overlay. This button always says "Find Game" and always lands here,
-- regardless of any queue already in progress -- per-pillar QUEUE/CANCEL buttons on that page
-- (see game_select.lua's spdrn_game_select_toggle_queue) are the only way to join/leave a
-- specific queue now, so the page has to stay reachable at any time to manage them.
G.FUNCS.spdrn_find_game = function()
	MPAPI.pages.show('spdrn_game_select', { intent = 'find_game' })
end

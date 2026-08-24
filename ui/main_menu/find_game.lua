-- Whether the Ranked queue buttons should actually be clickable right now:
-- MPAPI's confirmation that the *server* accepted our launcher-integrity
-- challenge response (see MPAPI.is_launcher_verified() in
-- api/connection/lifecycle.lua - NOT a client-side-only "did BET answer"
-- check, the actual server verdict). server.joinQueue() enforces this same
-- requirement independently either way (matchmaking.service.ts) - this only
-- avoids sending a request that's going to 403, and gives the player an
-- honest button state instead of a click that silently does nothing or
-- bounces off an error toast. Ranked play itself used to also be gated
-- behind a separate, always-off SPDRN.RANKED_ENABLED kill switch (a
-- client-side mirror of the server's own RANKED_ENABLED env flag) - removed
-- now that Ranked is actually live; the server's assertRankedEnabled()
-- guard in matchmaking.route.ts is still the real switch if it ever needs
-- to come back.
function SPDRN._ranked_queue_available()
	return MPAPI.is_launcher_verified()
end

-- Routes to the shared gamemode-select page (ui/main_menu/game_select.lua) instead of this
-- file's old dedicated overlay. That page's find_game intent only offers Casual queueing for
-- now (no live queue counts, no Ranked) -- spdrn_queue_ranked_white/gold below are kept,
-- unreferenced, for when Ranked gets its own place on that page.
G.FUNCS.spdrn_find_game = function()
	MPAPI.pages.show('spdrn_game_select', { intent = 'find_game' })
end

G.FUNCS.spdrn_queue_ranked_white = function()
	if not SPDRN._ranked_queue_available() then
		return
	end
	SPDRN._join_queue(SPDRN.LobbyKind.RANKED, SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end

G.FUNCS.spdrn_queue_ranked_gold = function()
	if not SPDRN._ranked_queue_available() then
		return
	end
	SPDRN._join_queue(SPDRN.LobbyKind.RANKED, SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

G.FUNCS.spdrn_cancel_queue = function()
	SPDRN._cancel_queue()
end

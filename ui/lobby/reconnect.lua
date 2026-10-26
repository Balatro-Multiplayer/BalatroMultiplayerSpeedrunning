-- Crash-relaunch reconnect: called once the lobby object itself has already
-- been recreated (MPAPI._internal.create_reconnected_lobby, driven by
-- ui/reconnect_prompt.lua) and there's no active RLOG match run to hand off
-- to instead (that's the OTHER branch of that file's Reconnect handler --
-- this one only ever runs pre-match: waiting room or mid-ban-pick-draft).

-- The lobby kind of a lobby rejoined after a restart. Every other entry path
-- (ui/main_menu/join.lua / create_lobby.lua / practice.lua) sets
-- SPDRN._lobby_kind from the button the player actually clicked (Create
-- Private / Find Game / Practice); a reconnect has no such click to read, so
-- it's derived from the lobby's own server-reported type instead.
-- MPAPI.LobbyType has no CASUAL value of its own (only PUBLIC/PRIVATE/RANKED)
-- -- SPDRN's own "casual" matchmaking queue is what a plain PUBLIC lobby type
-- means here.
function SPDRN.rejoined_lobby_kind(lobby)
	if lobby.type == MPAPI.LobbyType.RANKED then
		return SPDRN.LobbyKind.RANKED
	elseif lobby.type == MPAPI.LobbyType.PUBLIC then
		return SPDRN.LobbyKind.CASUAL
	end
	return SPDRN.LobbyKind.PRIVATE
end

MPAPI.register_lobby_reconnect(SPDRN.id, function(lobby)
	SPDRN._lobby_kind = SPDRN.rejoined_lobby_kind(lobby)

	SPDRN.setup_lobby_events(lobby)

	-- Rejoin a game still in its Draft: the server's snapshot already
	-- restored the Setup state (lobby._game.setup), so the game start runs
	-- again and MPAPI.BanPick picks up where the Draft is, or finishes at once
	-- when its result is in.
	local started = lobby._game and lobby._game.started
	local setup = lobby._game and lobby._game.setup
	local in_setup = setup and (setup.open or next(setup.results or {}))
	if MPAPI.has_server_referee(lobby) and started and not started.restarted and in_setup then
		SPDRN.on_game_start(lobby, { seed = started.seed })
	end
end)

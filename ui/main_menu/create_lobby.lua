local _pending_gamemode_key = nil

G.FUNCS.spdrn_create_lobby = function()
	MPAPI.pages.show('spdrn_game_select', { intent = 'create_lobby' })
end

local function create_lobby_with_gamemode(key)
	_pending_gamemode_key = key
	SPDRN._lobby_kind = SPDRN.LobbyKind.PRIVATE
	G.FUNCS.exit_overlay_menu()

	local gm = MPAPI.GameModes[key]
	local lobby = MPAPI.create_lobby(SPDRN.id, { max_players = gm and gm:get_max_players('private') or 16 })
	if not lobby then
		_pending_gamemode_key = nil
		SPDRN._lobby_kind = nil
		return
	end

	SPDRN.setup_lobby_events(lobby)

	lobby:on('connected', function()
		SPDRN.sendDebugMessage('Lobby created: ' .. tostring(lobby.code))
		love.system.setClipboardText(lobby.code)
		if _pending_gamemode_key then
			-- stake = 1 (White) is a harmless universal default -- only Seed Scout's start_run
			-- falls back to it (self._meta_stake, if a draft survivor is ever missing a .stake),
			-- everyone else ignores it, same as how `deck` defaults to Blue Deck for every mode
			-- regardless of whether that mode actually uses a single deck.
			lobby:set_metadata({ gamemode = _pending_gamemode_key, deck = SPDRN.Deck.DEFAULT, ruleset = SPDRN.Ruleset.ORDER, kind = SPDRN.LobbyKind.PRIVATE, stake = 1 })
			_pending_gamemode_key = nil
		end
	end)
end

-- A Party lobby (MPAPI.Party): no gamemode of its own; its players queue together for a
-- Casual mode (objects/matchmaking/group_queue.lua) and come back to it after the race.
G.FUNCS.spdrn_select_party = function()
	G.FUNCS.exit_overlay_menu()
	MPAPI.Party.create(SPDRN.id, function(lobby)
		SPDRN._lobby_kind = SPDRN.LobbyKind.PRIVATE
		SPDRN.setup_lobby_events(lobby)
	end)
end

G.FUNCS.spdrn_select_white_stake_triple = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end

G.FUNCS.spdrn_select_gold_stake_single = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

G.FUNCS.spdrn_select_seed_scout = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.SEED_SCOUT)
end

G.FUNCS.spdrn_select_challenge = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.CHALLENGE)
end

G.FUNCS.spdrn_select_all_deck = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.ALL_DECK)
end

G.FUNCS.spdrn_select_stake_climb = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.STAKE_CLIMB)
end

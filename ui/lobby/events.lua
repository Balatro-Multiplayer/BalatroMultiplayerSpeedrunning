SPDRN.setup_lobby_events = function(lobby)
	local L = SPDRN.lobby
	-- Who reported a result in the last lobby's match means nothing in
	-- another lobby: a group back home from its public match otherwise saw
	-- everyone crossed out on the home lobby's cards
	-- (objects/player_status_provider.lua).
	if L.ref ~= lobby then
		SPDRN._collected_results = {}
	end
	L.ref = lobby
	L.ui_ref = MPAPI.create_lobby_ui(lobby)
	L.ready:reset()
	L.seed_votes:reset()
	L.draw_votes:reset()
	L.local_ready = false
	L.start_broadcasted = false
	-- One-shot guard for the guest's ready re-announce (see player_ready action).
	SPDRN._ready_resent = false

	local function update_game_buttons()
		if L.buttons.start_game then
			L.buttons.start_game:update()
		end
		SPDRN.refresh_matchmaking_status()
	end

	-- A private lobby's group panel (ui/lobby/group_panel.lua) says whether
	-- the lobby may queue as a group from its size, so a join or leave
	-- rebuilds the view as a metadata change does.
	local function refresh_private_view()
		if not SPDRN.is_matchmaking() then
			MPAPI.refresh_current_view()
		end
	end

	lobby:on('player_joined', function(player_id)
		SPDRN.sendDebugMessage('Player joined: ' .. tostring(player_id))
		refresh_private_view()
		update_game_buttons()
		-- A late arrival may complete the ready set.
		SPDRN.maybe_autostart()
	end)

	lobby:on('player_left', function(player_id)
		SPDRN.sendDebugMessage('Player left: ' .. tostring(player_id))
		L.ready:remove(player_id)
		-- A full reset, not just this player's own vote: §16.5 resets everyone's
		-- vote whenever membership changes (an "unanimous" bar computed against
		-- the old roster would otherwise misfire once someone leaves).
		L.seed_votes:reset()
		L.draw_votes:reset()
		refresh_private_view()
		-- Leaving mid-run (or timing out of the server's grace period) is a
		-- forfeit, as in PvP: the gamemode's host-authoritative hook decides
		-- whether the rest have won. A player who already forfeited through
		-- spdrn_forfeit was handled there.
		local inst = lobby:get_gamemode_instance()
		if inst and inst.on_player_forfeit and G.STAGE == G.STAGES.RUN
			and not (inst._forfeited and inst._forfeited[player_id]) then
			MPAPI._handle_gamemode_result(inst, inst:on_player_forfeit(player_id))
		end
		update_game_buttons()
	end)

	-- The group panel also refuses while a player is away: follow players
	-- dropping and coming back (a group member back from a public match after
	-- its host).
	lobby:on('player_disconnected', function()
		refresh_private_view()
	end)

	lobby:on('player_reconnected', function(player_id)
		SPDRN.sendDebugMessage('Player reconnected: ' .. tostring(player_id))
		-- The host may have changed while we were away (domain/sender.lua).
		if player_id == lobby.player_id then
			SPDRN.Sender.forget_host(lobby)
		end
		refresh_private_view()
		-- §16.5: votes reset on a reconnect too, same as a leave -- a stale
		-- unanimous vote from before the drop shouldn't fire again the instant
		-- the reconnecting player's own client re-syncs.
		L.seed_votes:reset()
		L.draw_votes:reset()
	end)

	lobby:on('connected', function()
		update_game_buttons()
	end)

	-- Private lobbies build their control bar from lobby state at build time (deck label,
	-- host's START/OPTIONS vs guest's READY), so a deck or host change has to rebuild the
	-- view, not just patch the START button. Matchmaking lobbies have only a status line, so
	-- they keep the light path (and avoid player-card flicker).
	lobby:on('metadata_changed', function(metadata)
		if not SPDRN.is_matchmaking() then
			MPAPI.refresh_current_view()
		end
		update_game_buttons()
	end)

	-- The group panel (the waiting room's) also names a player whose standing
	-- refuses the group, so a change that moves that verdict rebuilds it.
	-- Only those: a joiner's first standing lands just after the join, and a
	-- rebuild then would close an overlay the host had just opened. Not once
	-- a game is on: a rejoin's playback starts from the main menu, and a
	-- rebuild under it replays its first actions twice.
	lobby:on(MPAPI.LobbyEvent.PLAYER_STANDING_CHANGED, function(_, standing, before)
		if not MPAPI.matchmaking.group.changes_refusal(before, standing) then
			return
		end
		if not SPDRN.is_matchmaking() and not lobby:is_game_started() then
			MPAPI.refresh_current_view()
		end
	end)

	-- The group queue panel (ui/lobby/group_panel.lua) follows the queue.
	if MPAPI.LobbyEvent.GROUP_QUEUE then
		lobby:on(MPAPI.LobbyEvent.GROUP_QUEUE, function()
			MPAPI.refresh_current_view()
		end)
	end

	lobby:on('host_changed', function(host_id)
		-- Host-only actions are taken from this player now (domain/sender.lua).
		SPDRN.Sender.note_host(lobby, host_id)
		if not SPDRN.is_matchmaking() then
			MPAPI.refresh_current_view()
		end
		update_game_buttons()
	end)

	-- Server-refereed lobbies: ready, start and the end of a game come from the server
	-- rather than from SPDRN's own actions (whose handlers do the same work otherwise).
	lobby:on(MPAPI.LobbyEvent.PLAYER_READY_CHANGED, function(player_id, ready)
		if MPAPI.has_server_referee(lobby) then
			SPDRN.set_player_ready(player_id, ready)
		end
	end)

	lobby:on(MPAPI.LobbyEvent.GAME_STARTED, function(started)
		SPDRN.on_game_start(lobby, { seed = started.seed })
	end)

	lobby:on(MPAPI.LobbyEvent.GAME_ENDED, function(ended)
		SPDRN.sendDebugMessage('Game ended: ' .. tostring(ended.status))
		SPDRN.last_game_ended = ended
		SPDRN.reset_ready_state()
		update_game_buttons()
	end)

	lobby:on('error', function(err)
		SPDRN.sendWarnMessage('Lobby error: ' .. tostring(err))
	end)

	lobby:on('disconnected', function()
		SPDRN.sendDebugMessage('Disconnected from lobby')
		L.ref = nil
		L.ui_ref = nil
		L.buttons_initialized = false
		L.ready:reset()
		L.seed_votes:reset()
		L.draw_votes:reset()
		L.local_ready = false
		L.start_broadcasted = false
		SPDRN._lobby_kind = nil
		-- The match handle is independent of the lobby (lobby:leave() does not fire the
		-- handle's 'left'). Drop it here so a later solo run's win path can't report a result
		-- against the finished match.
		SPDRN._current_match_handle = nil
	end)
end

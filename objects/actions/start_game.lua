MPAPI.ActionType({
	key = 'spdrn_start_game',
	on_receive = function(action_type, from_player_id, params)
		local lobby = MPAPI.get_current_lobby()
		if not lobby then
			return
		end
		local meta = lobby:get_metadata()
		local gm_def = meta.gamemode and MPAPI.GameModes[meta.gamemode]
		if not gm_def then
			SPDRN.sendWarnMessage('spdrn_start_game: unknown gamemode: ' .. tostring(meta.gamemode))
			return
		end

		-- decks is meta.deck (string) for the single-deck flow, or the list of survivors
		-- from the ban-pick draft. begin_run accepts either form.
		local function proceed(decks)
			-- Stamp the server-side run start when the run actually begins (after the
			-- ban-pick + countdown) so the leaderboard time uses the server clock and
			-- excludes draft time. Self-guards to matchmaking matches (no-op without a
			-- match handle).
			if lobby.is_host then
				SPDRN.mark_run_started()
			end
			SPDRN.begin_run(meta.gamemode, decks, params.seed)
		end

		-- The start has landed; stop the ready re-announce loop.
		SPDRN.stop_ready_resync()

		if SPDRN.get_lobby_kind() == SPDRN.LobbyKind.PRACTICE then
			proceed(meta.deck)
		elseif gm_def.ban_pick and SPDRN.is_matchmaking() then
			-- Matchmaking (always 2 players): run the deck draft, then the synced
			-- countdown on the surviving decks. Every client runs this off the same
			-- broadcast, so the draft stays in lockstep. The draft renders inline in the
			-- matchmaking lobby controls (see build_matchmaking_controls).
			MPAPI.BanPick.start(lobby, {
				pool_size = gm_def.ban_pick.pool_size,
				keep = gm_def.ban_pick.keep,
				state_action = 'spdrn_ban_pick_state',
				ban_action = 'spdrn_ban_pick_ban',
				on_refresh = function()
					SPDRN.lobby.refresh_mm_status()
				end,
			}, function(survivors)
				SPDRN.show_countdown(function()
					proceed(survivors)
				end, survivors)
			end)
		else
			-- Private + matchmaking without a draft: synced 5s countdown, single deck.
			SPDRN.show_countdown(function()
				proceed(meta.deck)
			end, meta.deck)
		end
	end,
})

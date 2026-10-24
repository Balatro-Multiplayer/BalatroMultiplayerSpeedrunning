-- The defined winning code path: a gamemode's calculate/on_player_forfeit just
-- returns { winner = player_id } and never touches this ActionType directly.
MPAPI.on_winner_declared(function(winner_id)
	-- A Replay re-runs recorded events, so it reaches the recorded ante-9 win.
	-- Broadcasting it would open the win screen and pause the Replay.
	if SPDRN.is_replay_driving() then
		return
	end
	local lobby = MPAPI.get_current_lobby()
	if lobby then
		lobby:action(MPAPI.ActionTypes['spdrn_player_won']):broadcast({ player_id = winner_id })
	end
end)

MPAPI.ActionType({
	key = 'spdrn_player_won',
	on_receive = function(action_type, from_player_id, params)
		local lobby = MPAPI.get_current_lobby()
		if not lobby then
			return
		end
		local winner_id = params and params.player_id
		if not winner_id then
			return
		end
		-- A player declares its own win; only the host declares another's (a
		-- forfeit's last survivor, MPAPI's check_single_survivor runs on the host).
		if winner_id ~= from_player_id and not SPDRN.Sender.is_host(lobby, from_player_id) then
			SPDRN.sendDebugMessage(
				'Ignored spdrn_player_won for ' .. tostring(winner_id) .. ' from ' .. tostring(from_player_id)
			)
			return
		end

		local won = (winner_id == lobby.player_id)

		G.E_MANAGER:add_event(Event({
			func = function()
				if G.STAGE == G.STAGES.RUN then
					if won then
						SPDRN.show_win_screen()
					else
						SPDRN.show_lose_screen()
					end
				end
				return true
			end,
		}))

		-- §11.6/§16.8: every player reports its own result now, not just the
		-- host -- see result.lua's report_match_result.
		SPDRN.report_match_result(winner_id)
	end,
})

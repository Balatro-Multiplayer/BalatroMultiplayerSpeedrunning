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

		local won = (winner_id == lobby.player_id)

		G.E_MANAGER:add_event(Event({
			func = function()
				if won then
					SPDRN.show_win_screen()
				else
					SPDRN.show_lose_screen()
				end
				return true
			end,
		}))

		if lobby.is_host then
			SPDRN.report_match_result(winner_id)
		end
	end,
})

MPAPI.ActionType({
	key = 'spdrn_forfeit',
	on_receive = function(action_type, from_player_id, params)
		local lobby = MPAPI.get_current_lobby()
		if not lobby then
			return
		end

		if from_player_id == lobby.player_id then
			G.E_MANAGER:add_event(Event({
				func = function()
					SPDRN.show_lose_screen()
					return true
				end,
			}))
		end

		local instance = lobby:get_gamemode_instance()
		if instance and instance.on_player_forfeit then
			instance:on_player_forfeit(from_player_id)
		end
	end,
})

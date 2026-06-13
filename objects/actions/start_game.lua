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
		local instance = gm_def:new_instance()
		lobby._gamemode_instance = instance
		instance:start_run(meta.deck, params.seed)
	end,
})

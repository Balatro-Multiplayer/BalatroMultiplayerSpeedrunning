-- Guest -> host: a request to ban a deck. Only the host applies it (authority), then
-- rebroadcasts the new state via spdrn_ban_pick_state. The engine lives in MPAPI.BanPick.
MPAPI.ActionType({
	key = 'spdrn_ban_pick_ban',
	parameters = {
		{ key = 'item_key', type = 'string', required = true },
	},
	on_receive = function(action_type, from_player_id, params)
		local lobby = MPAPI.get_current_lobby()
		if not lobby or not lobby.is_host then
			return
		end
		if MPAPI.BanPick.apply_ban(lobby, from_player_id, params.item_key) then
			MPAPI.BanPick.broadcast_state(lobby)
		end
	end,
})

-- Host -> all: the full canonical ban-pick state, rebroadcast after every change.
-- Registered from the SPDRN mod so it routes on the SPDRN lobby (a lobby only attaches
-- ActionTypes whose mod.id matches). The engine lives in MPAPI.BanPick.
MPAPI.ActionType({
	key = 'spdrn_ban_pick_state',
	parameters = {
		{ key = 'state', type = 'table', required = true },
	},
	on_receive = function(action_type, from_player_id, params)
		local lobby = MPAPI.get_current_lobby()
		if not lobby then
			return
		end
		MPAPI.BanPick.on_state(lobby, params.state)
	end,
})

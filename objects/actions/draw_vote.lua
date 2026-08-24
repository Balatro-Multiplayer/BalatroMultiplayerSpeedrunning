MPAPI.ActionType({
	key = 'spdrn_draw_vote',
	on_receive = function(action_type, from_player_id, params)
		-- Broadcast reaches every client, so each tallies the vote and shows progress
		-- independently; the host declares the draw once the vote is unanimous.
		SPDRN.register_draw_vote(from_player_id)
	end,
})

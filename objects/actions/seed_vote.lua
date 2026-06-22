MPAPI.ActionType({
	key = 'spdrn_seed_vote',
	on_receive = function(action_type, from_player_id, params)
		-- Broadcast reaches every client, so each tallies the vote and shows progress
		-- independently; the host restarts the match once the vote is unanimous.
		SPDRN.register_seed_vote(from_player_id)
	end,
})

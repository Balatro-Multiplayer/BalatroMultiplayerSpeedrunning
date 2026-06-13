MPAPI.GameMode({
	key = 'spdrn_gold_stake_single',
	display_name = 'Gold Stake Single',
	has_ranked_mode = true,
	max_players = {
		public = 16,
		private = 16,
		ranked = 2,
	},
	init = function(self)
		self._win_fired = false
		self._forfeited = {}
	end,
	on_ante_change = function(self, ante)
		if ante < 9 then
			self._win_fired = false
			return
		end
		if self._win_fired then
			return
		end
		self._win_fired = true

		local lobby = MPAPI.get_current_lobby()
		if not lobby then
			return
		end
		local action = lobby:action(MPAPI.ActionTypes['spdrn_player_won'])
		action:broadcast({ player_id = lobby.player_id })
	end,
	on_player_forfeit = function(self, player_id)
		self._forfeited[player_id] = true

		local lobby = MPAPI.get_current_lobby()
		if not lobby or not lobby.is_host then
			return
		end

		local remaining = {}
		for _, p in ipairs(lobby:get_players()) do
			if not self._forfeited[p.id] then
				remaining[#remaining + 1] = p
			end
		end

		if #remaining == 1 then
			local action = lobby:action(MPAPI.ActionTypes['spdrn_player_won'])
			action:broadcast({ player_id = remaining[1].id })
		end
	end,
	start_run = function(self, deck_name, seed)
		G.FUNCS.start_run(nil, {
			stake = 8,
			deck = { name = deck_name or 'Red Deck' },
			seed = seed,
		})
	end,
})

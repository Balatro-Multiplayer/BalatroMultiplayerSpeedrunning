MPAPI.GameMode({
	key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE,
	display_name = 'White Stake Triple',
	has_ranked_mode = true,
	-- Best-of-3 across three runs; re-rolling a seed mid-format is not allowed.
	seed_change_allowed = false,
	max_players = {
		public = 16,
		private = 16,
		ranked = 2,
	},
	-- Pre-run deck draft (matchmaking only): 9 random decks, ban down to 3 -- one per run.
	ban_pick = { pool_size = 9, keep = 3 },
	init = function(self)
		self._run_count = 0
		self._ante9_fired = false
		self._forfeited = {}
	end,
	on_ante_change = function(self, ante)
		if ante < 9 then
			self._ante9_fired = false
			return
		end
		if self._ante9_fired then
			return
		end
		self._ante9_fired = true

		self._run_count = self._run_count + 1

		if self._run_count < 3 then
			self._ante9_fired = false
			local lobby = MPAPI.get_current_lobby()
			local meta = lobby and lobby:get_metadata()
			-- The three decks map to runs 1/2/3 in order (ban-pick survivors in matchmaking,
			-- or the host/practice picker's ordered selection elsewhere). _run_count was just
			-- incremented for the completed run, so the next run's deck is index _run_count + 1.
			local run_idx = self._run_count + 1
			local deck = self._run_decks and self._run_decks[run_idx]
			if not deck and meta and meta.deck then
				-- Fall back to the metadata deck: index the per-run list, or reuse the single deck.
				deck = type(meta.deck) == 'table' and (meta.deck[run_idx] or meta.deck[#meta.deck]) or meta.deck
			end
			-- Last-resort guard so the next run never starts with no deck (which black-screens):
			-- reuse the first run's deck rather than handing start_run a nil.
			if not deck then
				deck = (self._run_decks and self._run_decks[1]) or SPDRN.Deck.DEFAULT
			end
			-- on_ante_change runs synchronously inside ease_ante. Calling
			-- G.FUNCS.start_run there restarts the game while the in-flight ante/round
			-- transition still holds references to the old state, which crashes. Defer
			-- the restart to the next event tick so it runs after ease_ante unwinds.
			G.E_MANAGER:add_event(Event({
				func = function()
					self:start_run(deck)
					return true
				end,
			}))
		else
			self._run_count = 0
			local lobby = MPAPI.get_current_lobby()
			if not lobby then
				return
			end
			local action = lobby:action(MPAPI.ActionTypes['spdrn_player_won'])
			action:broadcast({ player_id = lobby.player_id })
		end
	end,
	on_player_forfeit = function(self, player_id)
		local winner_id = self:check_single_survivor(player_id)
		if not winner_id then
			return
		end
		local lobby = MPAPI.get_current_lobby()
		lobby:action(MPAPI.ActionTypes['spdrn_player_won']):broadcast({ player_id = winner_id })
	end,
	start_run = function(self, deck_name, seed)
		-- The deck is applied via G.GAME.viewed_back (the proven pattern); start_run's
		-- `deck` arg is ignored by the base game. Resolve the ref (key or display name)
		-- to a Back center and stage it before starting.
		local key = SPDRN.resolve_back_key(deck_name)
		if G.GAME and key and G.P_CENTERS[key] then
			G.GAME.viewed_back = G.P_CENTERS[key]
		end
		G.FUNCS.start_run(nil, {
			stake = 1,
			seed = seed,
		})
	end,
})

-- Start (or restart) a Balatro run safely. G.FUNCS.start_run does not tear down an existing
-- run, so calling it mid-game leaves the old run's board and HUD alive -- and the dangling
-- blind HUD crashes the blind-HUD update assert (smods src/overrides.lua), reliably at high
-- game speed. So delete the current run first, then start fresh on the next event tick (the
-- same clean-restart path the game and the base multiplayer mod use).
local function safe_start_run(instance, deck, seed)
	pcall(function()
		if G.STAGE == G.STAGES.RUN and G.delete_run then
			G:delete_run()
		end
		G.HUD_blind = nil
	end)
	G.E_MANAGER:add_event(Event({
		blocking = false,
		blockable = false,
		func = function()
			instance:start_run(deck, seed)
			return true
		end,
	}))
end

-- Instantiate the gamemode for the current lobby and start the Balatro run. Shared by the
-- start_game action, practice, play-again, and seed-vote restart. `decks` is either a single
-- deck ref (single-deck flow) or a list of deck refs from a ban-pick draft (one per run). A
-- "ref" is a center key or display name; see SPDRN.resolve_back_key.
function SPDRN.begin_run(gamemode_key, decks, seed)
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local gm_def = gamemode_key and MPAPI.GameModes[gamemode_key]
	if not gm_def then
		SPDRN.sendWarnMessage('begin_run: unknown gamemode: ' .. tostring(gamemode_key))
		return
	end
	local deck_list = type(decks) == 'table' and decks or { decks }
	-- Starting the game clears everyone's ready state (every client assumes this locally, no
	-- broadcast needed), so returning to the lobby requires re-readying.
	SPDRN.reset_ready_state()
	SPDRN.lobby.seed_votes:reset()
	-- Client-side run clock (gates the seed-change window) and the deck(s) used for this run
	-- (so a same-seed restart can reuse them).
	SPDRN._run_started_at = love.timer.getTime()
	SPDRN._run_deck = deck_list[1]
	SPDRN._run_decks = deck_list
	if SPDRN.timer then
		SPDRN.timer.start()
	end
	local instance = gm_def:new_instance()
	instance._run_decks = deck_list
	lobby._gamemode_instance = instance
	safe_start_run(instance, deck_list[1], seed)
end

-- Restart the *current* run on its current seed without creating a new gamemode instance, so
-- per-format progress (e.g. White Stake Triple's run count) is kept. Used by "Restart Run".
function SPDRN.restart_current_run()
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local instance = lobby:get_gamemode_instance()
	if not instance then
		return
	end
	local seed = G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed
	-- Replay the current run's deck. With a draft (or a multi-deck mode), that's the deck for
	-- the run in progress (_run_count counts completed runs, so the live run is index + 1).
	local run_idx = (instance._run_count or 0) + 1
	local meta_deck = (lobby:get_metadata() or {}).deck
	local meta_deck_for_run = type(meta_deck) == 'table' and (meta_deck[run_idx] or meta_deck[1]) or meta_deck
	local deck = (instance._run_decks and instance._run_decks[run_idx])
		or SPDRN._run_deck or meta_deck_for_run or SPDRN.Deck.DEFAULT
	SPDRN.lobby.seed_votes:reset()
	SPDRN._run_started_at = love.timer.getTime()
	if SPDRN.timer then
		SPDRN.timer.start()
	end
	safe_start_run(instance, deck, seed)
end

-- Host broadcasts the start so every client (itself included, via the loopback) runs the same
-- synced countdown and starts on the same seed.
function SPDRN.broadcast_start(seed)
	local lobby = SPDRN.lobby.ref or MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_start_game'])
	action:broadcast({ seed = seed or SPDRN.generate_seed() })
end

-- Host (private) clicks START -> broadcast the start to everyone.
G.FUNCS.spdrn_start_game = function()
	local lobby = SPDRN.lobby.ref
	if not lobby or not lobby.is_host then
		return
	end
	SPDRN.broadcast_start(SPDRN.generate_seed())
end

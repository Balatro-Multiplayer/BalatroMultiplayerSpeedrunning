-----------------------------
-- Custom pause/options screen for active speedrun
-----------------------------

G.FUNCS.spdrn_seed_change = function()
	G.FUNCS.exit_overlay_menu()
	-- Practice is solo: there is nobody to vote with, so restart the run from the
	-- beginning on a fresh seed directly (same effect as "Practice Again").
	if SPDRN.get_lobby_kind() == 'practice' then
		local lobby = MPAPI.get_current_lobby()
		if not lobby then
			return
		end
		local meta = lobby:get_metadata()
		SPDRN.begin_run(meta.gamemode, meta.deck or 'Blue Deck', SPDRN.generate_seed())
		return
	end
	-- A unanimous vote restarts the match on a fresh seed (see seed_vote action).
	SPDRN.cast_seed_vote()
end

G.FUNCS.spdrn_forfeit = function()
	G.FUNCS.exit_overlay_menu()
	-- Practice is solo: forfeiting just ends the run, so show the game-over screen
	-- directly rather than broadcasting a forfeit to players who aren't there.
	if SPDRN.get_lobby_kind() == 'practice' then
		G.E_MANAGER:add_event(Event({
			func = function()
				SPDRN.show_lose_screen()
				return true
			end,
		}))
		return
	end
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_forfeit'])
	action:broadcast({})
end

-- Seed change is only offered for the first few minutes of a run.
SPDRN.SEED_CHANGE_WINDOW = 300

SPDRN.create_run_options = function()
	-- Build each button as its own row inside one column so they stack vertically.
	-- (Adding mixed node types as separate generic-options contents laid the seed
	-- and forfeit buttons out side by side.)
	local rows = {}
	local function add_row(node)
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = { node } }
	end

	add_row(UIBox_button({ button = 'settings', label = { localize('b_settings') }, minw = 5, focus_args = { snap_to = true } }))

	-- Seed Change visibility/enabled state:
	--   * hidden entirely when the gamemode sets seed_change_allowed = false
	--   * shown but disabled once SEED_CHANGE_WINDOW seconds have elapsed
	local lobby = MPAPI.get_current_lobby()
	local meta = lobby and lobby:get_metadata()
	local gm = meta and meta.gamemode and MPAPI.GameModes[meta.gamemode]
	if not gm or gm.seed_change_allowed ~= false then
		local within_window = SPDRN._run_started_at ~= nil
			and (love.timer.getTime() - SPDRN._run_started_at) < SPDRN.SEED_CHANGE_WINDOW
		add_row(MPAPI.disableable_button({
			button = 'spdrn_seed_change',
			label = { 'Seed Change' },
			colour = G.C.BLUE,
			minw = 5,
			enabled = within_window,
		}).node)
	end

	add_row(UIBox_button({ button = 'spdrn_forfeit', label = { 'Forfeit' }, minw = 5, colour = G.C.RED }))

	return create_UIBox_generic_options({
		contents = {
			{ n = G.UIT.C, config = { align = 'cm' }, nodes = rows },
		},
	})
end

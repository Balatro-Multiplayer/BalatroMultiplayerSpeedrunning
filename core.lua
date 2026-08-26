SPDRN = SMODS.current_mod

function SPDRN.sendDebugMessage(msg)
	sendDebugMessage(msg, SPDRN.id)
end

function SPDRN.sendWarnMessage(msg)
	sendWarnMessage(msg, SPDRN.id)
end

function SPDRN.load_spdrn_file(file)
	local chunk, err = SMODS.load_file(file, SPDRN.id)
	if chunk then
		local ok, func = pcall(chunk)
		if ok then
			return func
		else
			SPDRN.sendWarnMessage('Failed to process file: ' .. func)
		end
	else
		SPDRN.sendWarnMessage('Failed to find or compile file: ' .. tostring(err))
	end
	return nil
end

function SPDRN.load_spdrn_dir(directory, recursive)
	recursive = recursive or false

	local dir_path = SPDRN.path .. '/' .. directory
	local items = NFS.getDirectoryItemsInfo(dir_path)

	for _, item in ipairs(items) do
		local path = directory .. '/' .. item.name
		SPDRN.sendDebugMessage('Loading item: ' .. path)
		if item.type ~= 'directory' then
			SPDRN.load_spdrn_file(path)
		elseif recursive then
			SPDRN.load_spdrn_dir(path, recursive)
		end
	end
end

SPDRN.load_spdrn_dir('domain', true)
SPDRN.load_spdrn_dir('ui', true)

MPAPI.on_loaded(function()
	-- cleanup(self, uibox) runs against the OUTGOING page and may return (delay, on_enter) to
	-- animate the transition -- see MPAPI.pages.show in BalatroMultiplayerAPI/api/page/manager.lua.
	MPAPI.Page({
		key = 'spdrn_main_menu',
		category = 'mod_menu',
		build = function(self)
			return SPDRN.build_pre_lobby_ui()
		end,
		cleanup = function(self, uibox)
			MPAPI.set_logo_offset(-2.5)
			uibox.alignment.offset.x = -15
			uibox.alignment.offset.y = 10
			return 0.4, function(new_uibox)
				new_uibox.VT.x = new_uibox.T.x + 15
			end
		end,
	})

	MPAPI.Page({
		key = 'spdrn_lobby',
		category = 'lobby_menu',
		build = function(self)
			return SPDRN.build_in_lobby_ui()
		end,
		cleanup = function(self, uibox)
			uibox.alignment.offset.x = 15
			uibox.alignment.offset.y = 10
			return 0.4, function(new_uibox)
				MPAPI.set_logo_offset(0)
				new_uibox.VT.x = new_uibox.T.x - 15
			end
		end,
	})

	-- Shared "choose a gamemode" page (ui/main_menu/game_select.lua), styled after Balatro's own
	-- Blind Select pillars. Find Game/Practice/Create Lobby all navigate here now instead of
	-- each opening their own overlay; self.params.intent (set by MPAPI.pages.show's caller)
	-- picks which action a pillar click takes.
	MPAPI.Page({
		key = 'spdrn_game_select',
		category = 'game_select',
		build = function(self)
			self._chip_sprites = {}
			return SPDRN.build_game_select_ui(self.params and self.params.intent, self._chip_sprites)
		end,
		-- The find_game intent's pillars show live queue/in-game counts (ui/main_menu/game_select.lua);
		-- the poller driving them starts/stops with this page's own show/leave lifecycle. Also
		-- weakens each chip sprite's xy_bond (see SPDRN.loosen_game_select_sprites) -- must run
		-- here, after the UIBox has actually built the node tree and called set_role on each
		-- sprite, not from build() where the sprite doesn't have a role yet to override.
		on_enter = function(self)
			if self.params and self.params.intent == 'find_game' then
				SPDRN.start_find_game_polling()
			end
			SPDRN.loosen_game_select_sprites(self._chip_sprites)
			-- Directly nudges the whole page UIBox down via the exact field
			-- api/page/manager.lua itself sets to 0 after construction -- content-side spacing
			-- (a spacer row, a node's own `offset`) provably did not move the pillars at all;
			-- this is the actual anchor the framework uses to position the box.
			if G.MAIN_MENU_UI then
				G.MAIN_MENU_UI.alignment.offset.y = 1.5
				G.MAIN_MENU_UI:align_to_major()
			end
			-- Fixes the title logo to the same spot regardless of intent -- entering this page
			-- otherwise leaves whatever offset the PREVIOUS page's own cleanup animation last
			-- set (e.g. spdrn_main_menu's cleanup raises it, spdrn_lobby's resets it to 0), so
			-- which page you came from made the logo land in a different place each time.
			MPAPI.set_logo_offset(-1, true)
		end,
		-- Runs on every way of leaving this page, including going straight into a run
		-- (MPAPI.pages.teardown, not just a normal page swap) -- see MPAPI.pages' own
		-- _dispose_instance comment (api/page/manager.lua) for why that guarantee matters here:
		-- the pillars' chip sprites need an explicit :remove() or they crash the next frame.
		dispose = function(self)
			SPDRN.dispose_game_select_sprites(self._chip_sprites)
			SPDRN.stop_find_game_polling()
		end,
	})

	MPAPI.register_mod({
		id = SPDRN.id,
		name = 'Speedrun',
		colour = G.C.GREEN,
		prevent_pause = true,
		options_builder = SPDRN.create_run_options,
		title = { base = 'spdrn_speedrun_title_base', extra = 'spdrn_speedrun_title_extra' },
		main_menu_ui = 'spdrn_main_menu',
		lobby_ui = 'spdrn_lobby',
	})

	MPAPI.on_connection_state_change(function()
		SPDRN.update_main_menu_buttons()
	end)

	-- Suppress Balatro's native "You Win" overlay during a speedrun run. Beating the
	-- win-ante boss fires the global win_game() (its own overlay + vanilla unlocks);
	-- the gamemode instead drives its own win via SPDRN.show_win_screen, so without
	-- this the native screen shows over (or instead of) ours.
	if not SPDRN._win_game_hooked and type(win_game) == 'function' then
		SPDRN._win_game_hooked = true
		local _orig_win_game = win_game
		function win_game(...)
			if MPAPI.is_active(SPDRN.id) and MPAPI.get_current_lobby() then
				return
			end
			return _orig_win_game(...)
		end
	end

	-- Balatro has no single "you lost" callback, so detect a blind loss off the
	-- update loop (see SPDRN._check_run_lost) and show our Restart/Forfeit screen.
	-- Also polls for a pending run-start/restart request (see SPDRN.request_run_transition
	-- in ui/lobby/run_start.lua) -- this runs after the frame's own EventManager:update()
	-- has already returned, which is why it's the safe place to perform it. Same reasoning
	-- for the deferred starting-money override (Seed Scout's scouting budget), Seed
	-- Scout's own wall-clock scouting-phase timer (defined in objects/gamemodes/seed_scout.lua,
	-- not shared code -- it only inspects Seed-Scout-specific instance state), the
	-- §16.7 match-duration cap (objects/matchmaking/duration.lua), and the §16.11
	-- enemy-location broadcast (objects/matchmaking/location.lua) -- all wall-clock/
	-- poll checks with no single engine event to react to instead.
	if not SPDRN._game_over_hooked then
		SPDRN._game_over_hooked = true
		local _spdrn_update_ref = Game.update
		function Game:update(dt)
			_spdrn_update_ref(self, dt)
			pcall(SPDRN._check_run_lost)
			pcall(SPDRN._check_pending_run_transition)
			pcall(SPDRN._check_pending_run_info)
			pcall(SPDRN._check_pending_dollars_override)
			pcall(SPDRN._check_seed_scout_timer)
			pcall(SPDRN._check_match_duration)
			pcall(SPDRN._check_location_broadcast)
		end
	end

	SPDRN.load_spdrn_dir('objects', true)
end)

SPDRN.is_active = function()
	return MPAPI.is_active(SPDRN.id)
end

-- "My Replays" browser -- ported from BalatroMultiplayerPvP's
-- ui/replay/replay_browser.lua. Lists MPAPI.replay.list_mine, launches a
-- full replay of the picked run via SPDRN._start_playback
-- (playback_launch.lua) + MPAPI.playback (playback_handlers.lua's opcode
-- handlers drive it). v1 scope: no pagination, most-recent-first, capped to
-- the first page list_mine returns -- same scope decision as PvP's browser.

local function format_run_label(run)
	local date = tostring(run.startedAt or ''):match('^(%d%d%d%d%-%d%d%-%d%d)') or '?'
	return date .. '  ' .. tostring(run.lobbyCode or '??????') .. '  [' .. tostring(run.status or '?') .. ']'
end

-- Finds a given player's own bootstrap data in an already-built timeline
-- (MPAPI.playback.build_timeline) -- merges the first match_manifest (for
-- schema_version + start_epoch_ms) + first lobby_info (gamemode/ruleset) + first run_info
-- (seed/deck/stake) event BELONGING TO player_id, replacing the old single 'manifest' event's
-- args now that match framing is split across three events fired at three different scopes
-- (see BalatroMultiplayerAPI/api/replay/framing_codes.lua). Returns the same
-- {seed, deck, gamemode, ...} shape SPDRN._start_playback already expects, plus schema_version
-- for the compatibility gate below.
--
-- Exposed as SPDRN._find_bootstrap (not local) since objects/replay_log/perspective_switch.lua
-- and ui/replay/checkpoint_picker.lua both need to find a DIFFERENT player's own bootstrap from
-- the same shared timeline, not just the current player's -- every player in an SPDRN match
-- shares one seed/deck/stake per run (SPDRN.broadcast_start, ui/lobby/run_start.lua), so a
-- different player's bootstrap has identical seed/deck/stake/gamemode/ruleset, just their own
-- schema_version/start_epoch_ms (each client records its own copy of these, independently).
--
-- start_epoch_ms (a real os.time()*1000 wall-clock epoch, captured synchronously with that
-- player's own t=0 -- api/replay/framing_codes.lua) is what perspective_switch.lua uses to
-- align "the same real point in time" across two different players' own independently-clocked
-- `t` fields -- see that file's own header comment for why raw `t` isn't directly comparable
-- across players.
function SPDRN._find_bootstrap(timeline, player_id)
	local bootstrap = {}
	local found = {}
	for _, entry in ipairs(timeline) do
		if entry.player_id == player_id then
			if not found.match_manifest and entry.opcode == MPAPI.OPCODE.MATCH_MANIFEST then
				found.match_manifest = true
				bootstrap.schema_version = entry.args.schema_version
				bootstrap.start_epoch_ms = entry.args.start_epoch_ms
			elseif not found.lobby_info and entry.opcode == MPAPI.OPCODE.LOBBY_INFO then
				found.lobby_info = true
				bootstrap.gamemode = entry.args.gamemode
				bootstrap.ruleset = entry.args.ruleset
			elseif not found.run_info and entry.opcode == MPAPI.OPCODE.RUN_INFO then
				found.run_info = true
				bootstrap.seed = entry.args.seed
				bootstrap.deck = entry.args.deck
				bootstrap.stake = entry.args.stake
			end
			if found.match_manifest and found.lobby_info and found.run_info then break end
		end
	end
	if not (found.lobby_info and found.run_info) then return nil end
	return bootstrap
end

function SPDRN._launch_replay(run_id)
	MPAPI.replay.get(run_id, function(err, data)
		if err or not data or not data.logs then
			SPDRN.sendWarnMessage('[replay] failed to load run ' .. tostring(run_id) .. ': ' .. tostring(err and err.message))
			return
		end

		local timeline = MPAPI.playback.build_timeline(data.logs)
		local my_id = MPAPI.get_replay_player_id()
		local bootstrap = SPDRN._find_bootstrap(timeline, my_id)
		if not bootstrap then
			SPDRN.sendWarnMessage('[replay] no bootstrap data found for our own player in run ' .. tostring(run_id))
			return
		end
		if not MPAPI.replay.is_schema_compatible(bootstrap.schema_version) then
			SPDRN.sendWarnMessage(
				'[replay] recording schema_version ' .. tostring(bootstrap.schema_version)
				.. ' is newer than this client understands (' .. tostring(MPAPI.replay.SCHEMA_VERSION) .. '); refusing to play'
			)
			return
		end

		-- SPDRN._open_replay_session (objects/replay_log/checkpoint_seek.lua) owns starting
		-- playback itself (it needs to boot the run before it can even build the checkpoint
		-- index -- see that function's own comment on why this costs two bootstraps), builds
		-- the checkpoint index, and lands at event_index 1 (ante 1's Small Blind) -- this is
		-- the SAME code path a mid-replay checkpoint click, or a perspective switch, takes,
		-- just targeting the very beginning.
		SPDRN._show_seek_overlay('Seeking to Ante 1...')
		SPDRN._open_replay_session({
			bootstrap = bootstrap,
			timeline = timeline,
			my_id = my_id,
			paced = true,
			on_session_complete = function()
				-- No `cover` field: confirmed live to crash
				-- (functions/UI_definitions.lua's attention_text expects
				-- a real UI target with its own `.T` transform there, not
				-- a bare {align=...} table) -- `cover` is optional, so
				-- omitting it entirely sidesteps that branch rather than
				-- trying to construct a valid one just for a toast.
				attention_text({
					text = 'Replay finished',
					scale = 1,
					hold = 3,
					pos = { x = 0, y = 0 },
				})
				SPDRN._active_replay_session = nil
			end,
		})
	end)
end

-- Registered under SPDRN.id (the SMODS mod id, what a RunRow's own `modId`
-- carries, since MPAPI.create_lobby/create_local_lobby are always called
-- with SPDRN.id) -- NOT the literal 'spdrn' string used above for
-- mod_id = 'spdrn' / register_handler('spdrn', ...), a separate opcode-
-- dispatch namespace this mod happens to also use the same word for.
MPAPI.playback.register_launcher(SPDRN.id, SPDRN._launch_replay)

-- cursors[i] is the server cursor page i starts from (false for the newest).
-- MPAPI.replay.list_mine_of keeps only SPDRN's runs and reads past pages
-- holding only other mods' runs (runs_mine has no modId filter).
local browser = { cursors = { false }, index = 1 }

local function replay_row(run)
	G.FUNCS['spdrn_replay_pick_' .. run.id] = function()
		G.FUNCS.exit_overlay_menu()
		SPDRN._launch_replay(run.id)
	end
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
		UIBox_button({
			button = 'spdrn_replay_pick_' .. run.id,
			label = { format_run_label(run) },
			colour = G.C.GREEN,
			minw = 5,
			minh = 0.6,
			scale = 0.35,
		}),
	} }
end

local function page_nav()
	local nav = {}
	if browser.index > 1 then
		nav[#nav + 1] = UIBox_button({ button = 'spdrn_replay_newer', label = { 'Newer' }, colour = G.C.ORANGE, minw = 2, minh = 0.6, scale = 0.35 })
	end
	if browser.cursors[browser.index + 1] then
		nav[#nav + 1] = UIBox_button({ button = 'spdrn_replay_older', label = { 'Older' }, colour = G.C.ORANGE, minw = 2, minh = 0.6, scale = 0.35 })
	end
	return nav
end

local function show_page(runs)
	local rows = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'My Replays', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	}

	if #runs == 0 then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 2 }, nodes = {
			{ n = G.UIT.T, config = { text = 'No replays yet.', scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} }
	else
		for _, run in ipairs(runs) do
			rows[#rows + 1] = replay_row(run)
		end
	end

	local nav = page_nav()
	if #nav > 0 then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = nav }
	end

	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = rows }) })
end

local function open_page(index)
	MPAPI.replay.list_mine_of(SPDRN.id, { cursor = browser.cursors[index] or nil }, function(err, data)
		if err then
			SPDRN.sendWarnMessage('[replay] list_mine failed: ' .. tostring(err.message))
			return
		end
		browser.index = index
		browser.cursors[index + 1] = data.cursor or false
		show_page(data.runs)
	end)
end

G.FUNCS.spdrn_open_replay_browser = function()
	browser = { cursors = { false }, index = 1 }
	open_page(1)
end

G.FUNCS.spdrn_replay_newer = function()
	if browser.index > 1 then
		open_page(browser.index - 1)
	end
end

G.FUNCS.spdrn_replay_older = function()
	if browser.cursors[browser.index + 1] then
		open_page(browser.index + 1)
	end
end

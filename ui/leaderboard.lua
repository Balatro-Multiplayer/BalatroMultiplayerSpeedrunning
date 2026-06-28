-- Speedrun leaderboard overlay, built on the generic MPAPI.ui_leaderboard. Only the
-- gamemode tabs, columns and data source are speedrun-specific; pagination, the
-- own-rank footer, tab switching and overlay plumbing live in MPAPI.

local DEFAULT_TAB = SPDRN.Gamemode.WHITE_STAKE_TRIPLE

-- Format a server-measured run time (milliseconds) as m:ss.mmm. nil -> dash.
local function format_time(ms)
	if not ms then return '-' end
	local total_seconds = ms / 1000
	local minutes = math.floor(total_seconds / 60)
	local seconds = total_seconds - minutes * 60
	return string.format('%d:%06.3f', minutes, seconds)
end

-- Built lazily on first open so the G.C colour tables and localization are
-- guaranteed ready (this file loads during the mod's main_file pass, before the
-- game is fully up).
local _leaderboard
local function get_leaderboard()
	if _leaderboard then
		return _leaderboard
	end
	_leaderboard = MPAPI.ui_leaderboard({
		tabs = {
			{ key = SPDRN.Gamemode.WHITE_STAKE_TRIPLE, label = 'White Stake Triple', colour = G.C.ETERNAL },
			{ key = SPDRN.Gamemode.GOLD_STAKE_SINGLE, label = 'Gold Stake Single', colour = G.C.GOLD },
		},
		-- Value columns rendered after rank + player name. Headers are functions so
		-- the localization lookup happens at render time.
		columns = {
			{ header = function() return localize('k_rating_cap') end, colour = G.C.BLUE, width = 0.95, value = function(e) return tostring(e.rating or '?') end },
			{ header = function() return localize('k_best_time_cap') end, colour = G.C.PURPLE, width = 1.25, value = function(e) return format_time(e.seasonBest) end },
			{ header = 'W', header_colour = G.C.GREEN, colour = G.C.GREEN, width = 0.5, value = function(e) return tostring(e.wins or 0) end },
			{ header = 'L', header_colour = G.C.RED, colour = G.C.RED, width = 0.5, value = function(e) return tostring(e.losses or 0) end },
		},
		empty_text = 'No ranked players yet.',
		web_url = 'https://new.balatromp.com/leaderboards',
		-- Leaderboards are the rated queue, so they carry the server's ranked prefix.
		fetch = function(tab_key, cb)
			MPAPI.matchmaking.get_leaderboard(SPDRN.id, SPDRN.LobbyKind.RANKED_PREFIX .. tab_key, nil, {}, cb)
		end,
	})
	return _leaderboard
end

-- Open the leaderboard on a specific gamemode tab (defaults to White Stake Triple).
SPDRN.open_leaderboard = function(gamemode_key, page)
	get_leaderboard():open(gamemode_key or DEFAULT_TAB, page)
end

-- Reopen on the last-viewed tab (the controller remembers it; defaults to the first).
G.FUNCS.spdrn_open_leaderboard = function()
	get_leaderboard():open()
end

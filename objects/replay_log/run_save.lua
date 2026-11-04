-- SPDRN's part of a Run save (MPAPI.run_save): the state of the gamemode instance, which vanilla's
-- save table does not hold. A rejoin from a Run save skips the events that built it (run
-- completions, the win latch, the scout phase), so it has to come back from the save.
--
-- The race clocks are not saved. The race runs on real time from the server's start, so the
-- rejoin sets them from that start (SPDRN.restore_race_clocks), whenever the Run save was taken.
-- Each Run save belongs to one run: MPAPI refuses one from before a later run start in the same
-- match, and the next Blind Select after a run start takes a new one.
local STATE_KEYS = {
	'run_count',
	'run_decks',
	'base_seed',
	'ante9_fired',
	'win_fired',
	'finished',
	'forfeited',
	'meta_challenge',
	'meta_stake',
	'phase',
	'scout_locked',
	'scout_deck',
	'scout_seed',
	'scout_stake',
	'scout_restart_pending',
}

-- The match-wide stats the end screen and the ranked metric read (objects/matchmaking/progress.lua).
-- A run before the one in progress is finished by the time a Run save is taken, so these hold
-- its time and best hand. The log cannot give them back: the catch-up plays it at its own speed.
local PROGRESS_KEYS = {
	'best_run_time_ms',
	'times_skipped',
	'best_hand_amt',
}

local function copy(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = copy(v)
	end
	return out
end

local function current_instance()
	local lobby = MPAPI.get_current_lobby()
	return lobby and lobby:get_gamemode_instance()
end

MPAPI.run_save.register_state(SPDRN.id, {
	save = function()
		if not SPDRN.is_active() then
			return nil
		end
		local instance = current_instance()
		if not instance then
			return nil
		end
		local state = {}
		for _, key in ipairs(STATE_KEYS) do
			state[key] = copy(instance['_' .. key])
		end
		state.progress = {}
		for _, key in ipairs(PROGRESS_KEYS) do
			state.progress[key] = SPDRN._progress and SPDRN._progress[key]
		end
		return state
	end,
	-- The catch-up's instance is a new one that has seen none of the run: every key is set from
	-- the save, and one the save does not hold is cleared.
	load = function(state)
		local instance = current_instance()
		if not instance then
			error('no gamemode instance to load the Run save into')
		end
		for _, key in ipairs(STATE_KEYS) do
			instance['_' .. key] = copy(state[key])
		end
		if SPDRN._progress and type(state.progress) == 'table' then
			for _, key in ipairs(PROGRESS_KEYS) do
				SPDRN._progress[key] = state.progress[key]
			end
		end
	end,
})

-- The first Blind Select of a run takes its Run save before the polls in Game:update that finish
-- the run's start have run: the run_info is written and Seed Scout's scouting budget is set. A save
-- ahead of the run_info is read by a rejoin as the run before's, and one ahead of the budget
-- would come back without it. Do both first, so the save holds the run as it is a frame later.
if MPAPI.run_save.take and not MPAPI.run_save._spdrn_take_wrapped then
	MPAPI.run_save._spdrn_take_wrapped = true
	local take = MPAPI.run_save.take
	MPAPI.run_save.take = function(...)
		if SPDRN.is_active() and G.GAME and G.STATE == G.STATES.BLIND_SELECT then
			pcall(SPDRN._write_pending_run_info)
			pcall(SPDRN._check_pending_dollars_override)
		end
		return take(...)
	end
end

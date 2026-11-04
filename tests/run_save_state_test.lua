-- Run from the repo root: luajit tests/run_save_state_test.lua
local registered
SPDRN = { id = 'MultiplayerSPDRN' }
local active = true
function SPDRN.is_active()
	return active
end
local instance
local lobby = {
	get_gamemode_instance = function()
		return instance
	end,
}
MPAPI = {
	get_current_lobby = function()
		return lobby
	end,
	run_save = {
		register_state = function(mod_id, hooks)
			registered = { mod_id = mod_id, hooks = hooks }
		end,
	},
}
SPDRN._progress = { best_run_time_ms = 172086, times_skipped = 2, best_hand_amt = 900, furthest_ante = 4 }
dofile('objects/replay_log/run_save.lua')
assert(registered and registered.mod_id == 'MultiplayerSPDRN', 'registers under the mod id')

instance = {
	_run_count = 2,
	_run_decks = { 'b_red', { key = 'b_blue', stake = 3 } },
	_base_seed = 'ABC',
	_ante9_fired = false,
	_win_fired = true,
	_forfeited = { p1 = true },
	_phase = 'race',
	new = function() end,
	_pillar_row = { node = {} },
}
local saved = registered.hooks.save()
assert(saved.run_count == 2 and saved.base_seed == 'ABC' and saved.win_fired == true and saved.phase == 'race', 'gives the instance state')
assert(saved.run_decks[2].stake == 3 and saved.forfeited.p1, 'gives the decks and forfeits')
assert(saved.run_decks ~= instance._run_decks and saved.forfeited ~= instance._forfeited, 'as copies')
assert(saved._pillar_row == nil and saved.new == nil, 'and nothing else of the instance')

assert(saved.progress.best_run_time_ms == 172086 and saved.progress.times_skipped == 2 and saved.progress.best_hand_amt == 900, 'gives the match stats')
assert(saved.progress.furthest_ante == nil, 'and only the stats a replay cannot rebuild')

-- load: the saved state goes onto the live instance, and a key the save lacks is cleared.
instance = { _run_count = 0, _run_decks = { 'b_red' }, _base_seed = 'ZZZ', _forfeited = {}, _scout_seed = 'old' }
registered.hooks.load(saved)
assert(instance._run_count == 2 and instance._base_seed == 'ABC' and instance._win_fired == true, 'saved values are back')
assert(instance._run_decks[2].key == 'b_blue' and instance._forfeited.p1, 'tables are back')
assert(instance._scout_seed == nil, 'a value the save does not hold is cleared')

-- the catch-up's progress is a fresh one: the stats come back onto it
SPDRN._progress = { best_run_time_ms = nil, times_skipped = 0, best_hand_amt = nil, furthest_ante = 1 }
registered.hooks.load(saved)
assert(SPDRN._progress.best_run_time_ms == 172086 and SPDRN._progress.times_skipped == 2 and SPDRN._progress.best_hand_amt == 900, 'the match stats are back')
assert(SPDRN._progress.furthest_ante == 1, 'other progress is left alone')

active = false
assert(registered.hooks.save() == nil, 'gives nothing outside an SPDRN match')
active = true
instance = nil
assert(registered.hooks.save() == nil, 'gives nothing without a gamemode instance')
print('run_save_state_test: ok')

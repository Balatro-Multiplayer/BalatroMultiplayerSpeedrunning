-- Run from the repo root: luajit tests/run_save_order_test.lua
-- A run's run_info is written from a Game:update poll, after the Blind Select screen is built. The
-- Run save of that first Blind Select is queued behind the build, so it was taken before the
-- run_info and the rejoin read it as a save from the run before.
local calls = {}
SPDRN = { id = 'MultiplayerSPDRN' }
function SPDRN.is_active()
	return true
end
function SPDRN._write_pending_run_info()
	calls[#calls + 1] = 'run_info'
end
G = { GAME = {}, STATE = 1, STATES = { BLIND_SELECT = 1 } }
MPAPI = {
	get_current_lobby = function() end,
	run_save = {
		register_state = function() end,
		take = function()
			calls[#calls + 1] = 'take'
			return true
		end,
	},
}
dofile('objects/replay_log/run_save.lua')
assert(MPAPI.run_save.take() == true, 'the save is still taken')
assert(table.concat(calls, ',') == 'run_info,take', 'run_info is written before the save is taken, got ' .. table.concat(calls, ','))
print('run_save_order_test: ok')

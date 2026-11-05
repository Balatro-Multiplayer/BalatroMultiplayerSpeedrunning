-- Run from the repo root: luajit tests/run_save_order_test.lua
-- The run_info and the Seed Scout budget are set from Game:update polls, after the first Blind Select
-- of a run is built. The Run save of that screen must follow both.
local calls = {}
SPDRN = { id = 'MultiplayerSPDRN' }
function SPDRN.is_active()
	return true
end
function SPDRN._write_pending_run_info()
	calls[#calls + 1] = 'run_info'
end
G = { GAME = {}, STATE = 1, STATES = { BLIND_SELECT = 1 } }
function SPDRN._apply_pending_dollars_override()
	calls[#calls + 1] = 'budget'
end
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
assert(table.concat(calls, ',') == 'run_info,budget,take', 'the run start is finished before the save is taken, got ' .. table.concat(calls, ','))
print('run_save_order_test: ok')

-- A failing step is logged, and the save is still taken.
local warnings = {}
MPAPI.sendWarnMessage = function(message) warnings[#warnings + 1] = message end
calls = {}
SPDRN._write_pending_run_info = function() error('run_info broke') end
SPDRN._apply_pending_dollars_override = function() error('budget broke') end
assert(MPAPI.run_save.take() == true, 'the save is taken after a failed step')
assert(#warnings == 2, 'each failed step is logged, got ' .. #warnings)
assert(warnings[1]:find('run_info broke', 1, true), 'the log holds the error: ' .. tostring(warnings[1]))
assert(warnings[2]:find('budget broke', 1, true), 'the log holds the error: ' .. tostring(warnings[2]))
print('run_save_order_test: failure log ok')

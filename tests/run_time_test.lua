-- Run from the repo root: luajit tests/run_time_test.lua
SPDRN = {}
MPAPI = { OPCODE = { RUN_INFO = 'run_info', RUN_COMPLETE = 'run_complete', PLAY = 'play' } }
local replay_driving = true
function SPDRN.is_replay_driving()
	return replay_driving
end
love = { timer = { getTime = function() return 20 end } }
MPAPI.RLOGCodes = { run_complete = { write = function() end } }
dofile('objects/matchmaking/progress.lua')
dofile('objects/replay_log/run_time.lua')

local timeline = {
	{ t = 0, opcode = 'run_info' },
	{ t = 5000, opcode = 'play' },
	{ t = 171000, opcode = 'run_complete' },
	{ t = 172000, opcode = 'run_info' },
	{ t = 200000, opcode = 'run_complete' },
	{ t = 230000, opcode = 'run_info' },
	{ t = 400086, opcode = 'run_complete' },
}
assert(SPDRN.logged_run_time_ms(timeline, 3) == 171000, 'run 1 is measured from its run_info')
assert(SPDRN.logged_run_time_ms(timeline, 5) == 28000, 'run 2 is measured from the run_info after run 1')
assert(SPDRN.logged_run_time_ms({ { t = 5, opcode = 'run_complete' } }, 1) == nil, 'no start in the log gives nil')

SPDRN.reset_match_progress()
SPDRN._current_run_started_at = 0
for _, index in ipairs({ 3, 5, 7 }) do
	SPDRN.record_run_completed() -- the playback clock (20 s) must not count
	SPDRN.fold_logged_run_time(timeline, index)
end
assert(SPDRN._progress.best_run_time_ms == 28000, 'the best time is the real fastest run, got ' .. tostring(SPDRN._progress.best_run_time_ms))

replay_driving = false
SPDRN.reset_match_progress()
SPDRN._current_run_started_at = 0
SPDRN.record_run_completed()
assert(SPDRN._progress.best_run_time_ms == 20000, 'a live run still uses the live clock')
print('ok')

-- A replay runs at its own pace, so a run's time comes from the timestamps the event log recorded
-- (`t`, milliseconds into the match), never from the playback clock. Every run writes a run_info
-- when its Blind Select is up (objects/replay_log/record.lua), so a run began at the last run_info
-- before its run_complete. This is the same start the crash rejoin uses (rejoin.lua).

-- The time in ms of the run that ends at `timeline[index]`, or nil when the log has no start for it.
function SPDRN.logged_run_time_ms(timeline, index)
	local ended = timeline and timeline[index]
	if not (ended and type(ended.t) == 'number') then
		return nil
	end
	for i = index - 1, 1, -1 do
		local ev = timeline[i]
		if ev.opcode == MPAPI.OPCODE.RUN_INFO and type(ev.t) == 'number' then
			return math.max(0, math.floor(ended.t - ev.t + 0.5))
		end
	end
	return nil
end

function SPDRN.fold_logged_run_time(timeline, index)
	local run_time_ms = SPDRN.logged_run_time_ms(timeline, index)
	if run_time_ms then
		SPDRN.fold_run_time(run_time_ms)
	end
end

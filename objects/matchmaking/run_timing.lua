-- Host-only: tell the server the run has begun so it can measure completion time (the
-- speedrun leaderboard's fastest-time metric is server-clock measured).
function SPDRN.mark_run_started()
	local handle = SPDRN._current_match_handle
	if not handle or not handle.match_id then
		return
	end

	local lobby = MPAPI.get_current_lobby()
	if not lobby or not lobby.is_host then
		return
	end

	handle:mark_started(function(err)
		if err then
			SPDRN.sendWarnMessage('mark_run_start error: ' .. tostring(err))
		end
	end)
end

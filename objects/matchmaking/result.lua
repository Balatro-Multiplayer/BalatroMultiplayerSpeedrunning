function SPDRN.report_match_result(winner_player_id)
	-- The server decides whether a match is rated from its game_mode (casual matches carry no
	-- ranked prefix), so we always report and let it sort that out.
	local handle = SPDRN._current_match_handle
	if not handle or not handle.match_id then
		return
	end

	local lobby = MPAPI.get_current_lobby()
	if not lobby or not lobby.is_host then
		return
	end

	local placements = {}
	for _, p in ipairs(lobby:get_players()) do
		placements[#placements + 1] = {
			playerId = p.id,
			place = (p.id == winner_player_id) and 1 or 2,
		}
	end

	handle:report_result(placements, function(err)
		if err then
			SPDRN.sendWarnMessage('report_result error: ' .. tostring(err))
		end
	end)
end

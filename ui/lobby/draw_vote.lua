-- Broadcast a vote to end the current match as a draw (see ui/run_options.lua's
-- G.FUNCS.spdrn_draw_vote -- the real, non-practice entry point). Mirrors
-- ui/lobby/seed_vote.lua's cast/register pair exactly.
function SPDRN.cast_draw_vote()
	local lobby = SPDRN.lobby.ref or MPAPI.get_current_lobby()
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_draw_vote'])
	action:broadcast({})
end

-- Runs on every client when any vote arrives (broadcast reaches all). Each client tallies
-- independently and shows progress; the host declares the match a draw (skipping MMR
-- reporting -- see objects/actions/match_draw.lua) once the vote is unanimous, broadcasting
-- it so every client shows the same draw screen rather than each deciding locally.
function SPDRN.register_draw_vote(voter_id)
	local lobby = MPAPI.get_current_lobby()
	if not lobby then
		return
	end

	local count, total, unanimous = SPDRN.lobby.draw_votes:record(voter_id)

	if MPAPI.chat and MPAPI.chat.addMessage then
		MPAPI.chat.addMessage(
			(localize('k_draw_vote') or 'Vote for Draw') .. ': ' .. count .. '/' .. total,
			G.C.BLUE
		)
	end

	if lobby.is_host and unanimous then
		SPDRN.lobby.draw_votes:reset()
		local action = lobby:action(MPAPI.ActionTypes['spdrn_match_draw'])
		action:broadcast({})
	end
end

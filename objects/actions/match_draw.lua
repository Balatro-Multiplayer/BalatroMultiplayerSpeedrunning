-- Broadcast by the host once SPDRN.register_draw_vote (ui/lobby/draw_vote.lua)
-- sees a unanimous spdrn_draw_vote -- every client (host included, via the
-- loopback) shows the draw screen and reports its own result WITHOUT the MMR
-- round-trip (see SPDRN.report_match_result's draw branch, objects/matchmaking/
-- result.lua) -- a drawn match has no winner to rate.
MPAPI.ActionType({
	key = 'spdrn_match_draw',
	on_receive = function(action_type, from_player_id, params)
		G.E_MANAGER:add_event(Event({
			func = function()
				if G.STAGE == G.STAGES.RUN then
					SPDRN.show_draw_screen()
				end
				return true
			end,
		}))
		SPDRN.report_match_result(nil, { draw = true })
	end,
})

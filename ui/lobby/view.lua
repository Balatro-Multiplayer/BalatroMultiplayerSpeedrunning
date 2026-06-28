SPDRN.build_in_lobby_ui = function()
	local L = SPDRN.lobby
	local lobby = MPAPI.get_current_lobby()

	-- Practice has no lobby view. If we land here with a practice lobby still engaged (e.g. a
	-- run abandoned without using the end-screen buttons), drop it and show the main menu.
	if lobby and SPDRN.get_lobby_kind() == SPDRN.LobbyKind.PRACTICE then
		local dead = lobby
		G.E_MANAGER:add_event(Event({ func = function()
			dead:leave()
			return true
		end }))
		return SPDRN.build_pre_lobby_ui()
	end

	-- Defensive: re-create the player-card UI if its ref was lost, and fall back to the
	-- pre-lobby menu rather than indexing a nil ref if there is no active lobby.
	if lobby and not L.ui_ref then
		L.ref = lobby
		L.ui_ref = MPAPI.create_lobby_ui(lobby)
	end
	if not L.ui_ref then
		return SPDRN.build_pre_lobby_ui()
	end

	L.create_buttons()
	MPAPI.set_logo_offset(-10, true)

	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = 'cm' },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = 'cm', padding = 0.1, mid = true },
						nodes = {
							L.ui_ref.node,
						},
					},
					{
						n = G.UIT.R,
						config = { minh = 0.2 },
					},
					{
						n = G.UIT.R,
						config = { align = 'cm' },
						nodes = { L.build_controls() },
					},
				},
			},
		},
	}
end

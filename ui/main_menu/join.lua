G.FUNCS.spdrn_join_lobby_by_code = function()
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			snap_back = true,
			contents = {
				{
					n = G.UIT.R,
					config = { align = 'cm', padding = 0.2, r = 0.1 },
					nodes = {
						{
							n = G.UIT.R,
							config = { align = 'cm', padding = 0.05 },
							nodes = {
								{ n = G.UIT.T, config = { text = localize('k_lobby_code_cap'), scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
							},
						},
						{
							n = G.UIT.R,
							config = { align = 'cm', padding = 0.1 },
							nodes = {
								create_text_input({ id = 'spdrn_lobby_code_input', ref_table = { text = '' }, ref_value = 'text', prompt_text = localize('k_lobby_code_cap'), max_length = 6, all_caps = true, w = 4, h = 0.6 }),
							},
						},
						{
							n = G.UIT.R,
							config = { align = 'cm', padding = 0.1 },
							nodes = {
								UIBox_button({ id = 'spdrn_join_lobby_confirm', button = 'spdrn_join_lobby_confirm', colour = G.C.GREEN, minw = 2, minh = 0.6, label = { localize('k_join_lobby_cap') }, scale = 0.45 }),
							},
						},
					},
				},
			},
		}),
	})
end

G.FUNCS.spdrn_join_lobby_confirm = function()
	local code = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('spdrn_lobby_code_input')
	if code and code.config and code.config.ref_table then
		local text = code.config.ref_table.text or ''
		text = text:match('^%s*(.-)%s*$') or ''
		if #text > 0 then
			G.FUNCS.exit_overlay_menu()
			SPDRN._join_lobby_with_code(text)
		end
	end
end

G.FUNCS.spdrn_join_lobby_from_clipboard = function()
	local code = love.system.getClipboardText() or ''
	code = code:match('^%s*(.-)%s*$') or ''
	if #code > 0 then
		SPDRN._join_lobby_with_code(code)
	end
end

SPDRN._join_lobby_with_code = function(code)
	SPDRN._lobby_kind = SPDRN.LobbyKind.PRIVATE
	local lobby = MPAPI.join_lobby(SPDRN.id, code)
	if not lobby then
		SPDRN._lobby_kind = nil
		return
	end

	SPDRN.setup_lobby_events(lobby)

	lobby:on('connected', function()
		SPDRN.sendDebugMessage('Joined lobby: ' .. tostring(lobby.code))
	end)

	lobby:on('metadata_changed', function(metadata)
		SPDRN.sendDebugMessage('Metadata changed')
	end)
end

-- CONFIRMED LIVE BUG, fixed by capturing this table directly: create_UIBox_generic_options
-- wraps create_text_input's node in a way that leaves config.ref_table nil on the node
-- get_UIE_by_ID(id) resolves back later -- the confirm button used to re-fetch the node by
-- id and read code.config.ref_table.text off of it, which is always nil under this wrapper
-- (reproduced live: the typed code still renders correctly on screen -- create_text_input
-- itself writes into THIS SAME table -- but get_UIE_by_ID's returned node's own
-- .config.ref_table field is nil regardless of input method), so "Join Lobby" silently
-- no-opped on every valid code with no error shown. Capturing the table by closure instead
-- of re-deriving it from the node tree sidesteps whatever create_UIBox_generic_options does
-- to that field, since it's the same physical table object create_text_input mutates either
-- way. See BalatroMultiplayerPvP/ui/pvp_main_menu.lua's mp_pvp_join_lobby_by_code for the
-- same fix against the same copied pattern.
local spdrn_lobby_code_ref = { text = '' }
G.FUNCS.spdrn_join_lobby_by_code = function()
	spdrn_lobby_code_ref.text = ''
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
								create_text_input({ id = 'spdrn_lobby_code_input', ref_table = spdrn_lobby_code_ref, ref_value = 'text', prompt_text = localize('k_lobby_code_cap'), max_length = 6, all_caps = true, w = 4, h = 0.6 }),
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
	local text = spdrn_lobby_code_ref.text or ''
	text = text:match('^%s*(.-)%s*$') or ''
	if #text > 0 then
		G.FUNCS.exit_overlay_menu()
		SPDRN._join_lobby_with_code(text)
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

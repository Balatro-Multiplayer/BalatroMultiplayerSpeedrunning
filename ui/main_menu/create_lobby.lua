local _pending_gamemode_key = nil

G.FUNCS.spdrn_gm_shadows = function(e)
	e.shadow_parrallax = { x = 0, y = -1.5 * e.config.minh ^ 0.25 }
end

G.FUNCS.spdrn_gm_disabled = function() end

-- A greyed, non-interactive placeholder for gamemodes that aren't implemented yet. Takes the
-- SAME args as the original UIBox_button so sizing/layout is unchanged; it's just greyed.
local function disabled_gm_button(args)
	local a = MPAPI.shallow_copy(args)
	a.enabled = false
	a.button = 'spdrn_gm_disabled'
	a.colour = G.C.UI.BACKGROUND_INACTIVE
	return MPAPI.disableable_button(a).node
end

G.FUNCS.spdrn_create_lobby = function()
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			contents = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
					{ n = G.UIT.T, config = { text = 'Select Gamemode', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
				{
					n = G.UIT.R,
					config = { align = 'cm' },
					nodes = {
						{
							n = G.UIT.C,
							config = { align = 'cm', padding = 0.05 },
							nodes = {
								UIBox_button({
									id = 'spdrn_gm_white_triple',
									button = 'spdrn_select_white_stake_triple',
									label = { 'White', 'Stake', 'Triple' },
									colour = G.C.ETERNAL,
									minw = 1,
									minh = 3.2,
									scale = 0.5,
									func = 'spdrn_gm_shadows',
								}),
							},
						},
						{
							n = G.UIT.C,
							config = { align = 'cm' },
							nodes = {
								{
									n = G.UIT.R,
									config = { align = 'cm' },
									nodes = {
										{
											n = G.UIT.C,
											config = { align = 'cm', padding = 0.05 },
											nodes = {
												disabled_gm_button({
													id = 'spdrn_gm_gold_triple',
													label = { 'Seed', 'Scout' },
													minw = 1,
													minh = 2.1,
													scale = 0.5,
													func = 'spdrn_gm_shadows',
												}),
											},
										},
										{
											n = G.UIT.C,
											config = { align = 'cm' },
											nodes = {
												{
													n = G.UIT.R,
													config = { align = 'cm', padding = 0.05 },
													nodes = {
														disabled_gm_button({ id = 'spdrn_gm_challenge', label = { 'Challenge' }, minw = 2.1, minh = 1, scale = 0.5, func = 'spdrn_gm_shadows' }),
													},
												},
												{
													n = G.UIT.R,
													config = { align = 'cm' },
													nodes = {
														{
															n = G.UIT.C,
															config = { align = 'cm', padding = 0.05 },
															nodes = {
																disabled_gm_button({
																	id = 'spdrn_gm_all_deck',
																	label = { 'All', 'Deck' },
																	minw = 1,
																	minh = 1,
																	scale = 0.5,
																	func = 'spdrn_gm_shadows',
																}),
															},
														},
														{
															n = G.UIT.C,
															config = { align = 'cm', padding = 0.05 },
															nodes = {
																disabled_gm_button({
																	id = 'spdrn_gm_stake_climb',
																	label = { 'Stake', 'Climb' },
																	minw = 1,
																	minh = 1,
																	scale = 0.5,
																	func = 'spdrn_gm_shadows',
																}),
															},
														},
													},
												},
											},
										},
									},
								},
								{
									n = G.UIT.R,
									config = { align = 'cm', padding = 0.05 },
									nodes = {
										UIBox_button({ id = 'spdrn_gm_gold', button = 'spdrn_select_gold_stake_single', label = { 'Gold Stake Single' }, colour = G.C.GOLD, minw = 3.2, minh = 1, scale = 0.5, func = 'spdrn_gm_shadows' }),
									},
								},
							},
						},
					},
				},
			},
		}),
	})
end

local function create_lobby_with_gamemode(key)
	_pending_gamemode_key = key
	SPDRN._lobby_kind = SPDRN.LobbyKind.PRIVATE
	G.FUNCS.exit_overlay_menu()

	local gm = MPAPI.GameModes[key]
	local lobby = MPAPI.create_lobby(SPDRN.id, { max_players = gm and gm:get_max_players('private') or 16 })
	if not lobby then
		_pending_gamemode_key = nil
		SPDRN._lobby_kind = nil
		return
	end

	SPDRN.setup_lobby_events(lobby)

	lobby:on('connected', function()
		SPDRN.sendDebugMessage('Lobby created: ' .. tostring(lobby.code))
		love.system.setClipboardText(lobby.code)
		if _pending_gamemode_key then
			lobby:set_metadata({ gamemode = _pending_gamemode_key, deck = SPDRN.Deck.DEFAULT, ruleset = SPDRN.Ruleset.ORDER, kind = SPDRN.LobbyKind.PRIVATE })
			_pending_gamemode_key = nil
		end
	end)
end

G.FUNCS.spdrn_select_white_stake_triple = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end

G.FUNCS.spdrn_select_gold_stake_single = function()
	create_lobby_with_gamemode(SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

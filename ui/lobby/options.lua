G.FUNCS.spdrn_lobby_options = function()
	local lobby = SPDRN.lobby.ref
	local contents = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Lobby Options', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	}

	if lobby and lobby.is_host then
		local meta = lobby:get_metadata()
		local current_key = meta.gamemode
		local current_ruleset = meta.ruleset or SPDRN.Ruleset.ORDER
		contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Change Gamemode', scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} }
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_change_white_stake_triple',
					label = { 'White Stake Triple' .. (current_key == SPDRN.Gamemode.WHITE_STAKE_TRIPLE and ' *' or '') },
					colour = current_key == SPDRN.Gamemode.WHITE_STAKE_TRIPLE and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_change_gold_stake_single',
					label = { 'Gold Stake Single' .. (current_key == SPDRN.Gamemode.GOLD_STAKE_SINGLE and ' *' or '') },
					colour = current_key == SPDRN.Gamemode.GOLD_STAKE_SINGLE and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
		contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Change Ruleset', scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} }
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_set_ruleset_order',
					label = { 'The Order' .. (current_ruleset == SPDRN.Ruleset.ORDER and ' *' or '') },
					colour = current_ruleset == SPDRN.Ruleset.ORDER and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.05 },
			nodes = {
				UIBox_button({
					button = 'spdrn_set_ruleset_vanilla',
					label = { 'Vanilla' .. (current_ruleset == SPDRN.Ruleset.VANILLA and ' *' or '') },
					colour = current_ruleset == SPDRN.Ruleset.VANILLA and G.C.GREEN or G.C.GREY,
					minw = 4,
					minh = 0.6,
					scale = 0.45,
				}),
			},
		}
	end

	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({ contents = contents }),
	})
end

local function change_gamemode(key)
	local lobby = SPDRN.lobby.ref
	if lobby and lobby.is_host then
		local meta = lobby:get_metadata()
		-- If the new mode needs a different number of decks, the saved deck(s) no longer fit;
		-- reset to the default so the host re-picks the right count via the deck button.
		local need = SPDRN.required_deck_count(MPAPI.GameModes[key])
		local have = type(meta.deck) == 'table' and #meta.deck or 1
		local deck = (have == need and meta.deck) or SPDRN.Deck.DEFAULT
		lobby:set_metadata({ gamemode = key, deck = deck, ruleset = meta.ruleset or SPDRN.Ruleset.ORDER })
	end
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.spdrn_change_white_stake_triple = function()
	change_gamemode(SPDRN.Gamemode.WHITE_STAKE_TRIPLE)
end

G.FUNCS.spdrn_change_gold_stake_single = function()
	change_gamemode(SPDRN.Gamemode.GOLD_STAKE_SINGLE)
end

local function change_ruleset(key)
	local lobby = SPDRN.lobby.ref
	if lobby and lobby.is_host then
		local meta = lobby:get_metadata()
		lobby:set_metadata({ gamemode = meta.gamemode, deck = meta.deck or SPDRN.Deck.DEFAULT, ruleset = key })
	end
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.spdrn_set_ruleset_order = function()
	change_ruleset(SPDRN.Ruleset.ORDER)
end

G.FUNCS.spdrn_set_ruleset_vanilla = function()
	change_ruleset(SPDRN.Ruleset.VANILLA)
end

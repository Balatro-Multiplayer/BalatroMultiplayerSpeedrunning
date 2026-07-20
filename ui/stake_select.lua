-- A minimal single-pick stake picker (Seed Scout only) -- cycle through the 8 vanilla stakes
-- (White..Gold) and press Select. Much simpler than ui/deck_select.lua's picker since there's
-- no deck-back/CardArea preview to build, just a labeled cycle. Deliberately hardcoded to
-- indices 1-8: G.P_CENTER_POOLS.Stake can carry additional custom stakes registered by other
-- installed mods (e.g. multiplayer-specific stakes) beyond the 8 vanilla ones, which aren't
-- valid values for G.FUNCS.start_run's plain numeric `stake` opt.

local _on_confirm = nil
local _current_stake = 1

local function stake_name(i)
	local center = G.P_CENTER_POOLS.Stake[i]
	return center and localize({ type = 'name_text', key = center.key, set = 'Stake' }) or ('Stake ' .. i)
end

local function build_stake_select_uibox()
	local names = {}
	for i = 1, 8 do
		names[i] = stake_name(i)
	end

	local contents = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Select Stake', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
		{
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.15 },
			nodes = {
				create_option_cycle({
					options = names,
					opt_callback = 'spdrn_stake_select_cycle',
					current_option = _current_stake,
					colour = G.C.RED,
					w = 4,
				}),
			},
		},
		{
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.15 },
			nodes = {
				UIBox_button({ button = 'spdrn_stake_select_confirm', label = { localize('b_select') or 'Select' }, colour = G.C.BLUE, minw = 3, minh = 0.7, scale = 0.5 }),
			},
		},
	}

	return create_UIBox_generic_options({ contents = contents })
end

-- Open the picker. `current_stake` preselects a stake (1-8, defaults to White/1 if invalid).
-- `on_confirm(stake_number)` runs on confirm with a plain integer; the overlay closes first.
function SPDRN.open_stake_select(current_stake, on_confirm)
	_on_confirm = on_confirm
	_current_stake = (type(current_stake) == 'number' and current_stake >= 1 and current_stake <= 8) and current_stake or 1
	G.FUNCS.overlay_menu({ definition = build_stake_select_uibox() })
end

G.FUNCS.spdrn_stake_select_cycle = function(args)
	_current_stake = args.to_key
end

G.FUNCS.spdrn_stake_select_confirm = function()
	local cb = _on_confirm
	_on_confirm = nil
	if G.OVERLAY_MENU and G.OVERLAY_MENU ~= true then
		G.FUNCS.exit_overlay_menu()
	end
	if cb then
		cb(_current_stake)
	end
end

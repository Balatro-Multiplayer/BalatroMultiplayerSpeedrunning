-- A minimal single-pick picker over Balatro's built-in Challenges (Challenge mode only) --
-- cycle through G.CHALLENGES by display name and press Select. Deliberately MVP scope: shows
-- the name only, not vanilla's full joker/voucher/restriction description panel
-- (create_UIBox_your_collection-style challenge descriptions) -- a picker whose only job is to
-- hand back a challenge id doesn't need that; richer description UI is a reasonable follow-up
-- polish item, not required for a functional picker. Does not gate on
-- SMODS.challenge_is_unlocked -- that's a solo-profile-progression display convention in
-- vanilla's own picker, not something start_run enforces, and whose profile would even apply
-- (host's? guest's?) is ambiguous in a shared lobby -- shows the full list unconditionally.

local _on_confirm = nil
local _current_index = 1

local function build_challenge_select_uibox()
	local names = {}
	for i, c in ipairs(G.CHALLENGES) do
		names[i] = c.name or c.id
	end

	local contents = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Select Challenge', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
		{
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.15 },
			nodes = {
				create_option_cycle({
					options = names,
					opt_callback = 'spdrn_challenge_select_cycle',
					current_option = _current_index,
					colour = G.C.RED,
					w = 5,
				}),
			},
		},
		{
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.15 },
			nodes = {
				UIBox_button({ button = 'spdrn_challenge_select_confirm', label = { localize('b_select') or 'Select' }, colour = G.C.BLUE, minw = 3, minh = 0.7, scale = 0.5 }),
			},
		},
	}

	return create_UIBox_generic_options({ contents = contents })
end

-- Open the picker. `current_challenge_id` preselects a challenge by its stable `.id` (defaults
-- to the first challenge if not found). `on_confirm(challenge_id)` runs on confirm with that
-- stable id string (resolved back to G.CHALLENGES[idx] at run-start time via
-- get_challenge_int_from_id, the same key-not-index pattern SPDRN.resolve_back_key uses for
-- decks); the overlay closes first.
function SPDRN.open_challenge_select(current_challenge_id, on_confirm)
	_on_confirm = on_confirm
	_current_index = 1
	if current_challenge_id then
		local idx = get_challenge_int_from_id(current_challenge_id)
		if idx and idx > 0 then
			_current_index = idx
		end
	end
	G.FUNCS.overlay_menu({ definition = build_challenge_select_uibox() })
end

G.FUNCS.spdrn_challenge_select_cycle = function(args)
	_current_index = args.to_key
end

G.FUNCS.spdrn_challenge_select_confirm = function()
	local cb = _on_confirm
	_on_confirm = nil
	local challenge = G.CHALLENGES[_current_index]
	if G.OVERLAY_MENU and G.OVERLAY_MENU ~= true then
		G.FUNCS.exit_overlay_menu()
	end
	if cb and challenge then
		cb(challenge.id)
	end
end

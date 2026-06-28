-- A pared-down version of the base game's run-setup deck picker (G.UIDEF.run_setup_option):
-- the same deck back preview + left/right cycle + deck description, but with the stake
-- selector, seed toggle and "Play" button removed. Used by practice (after gamemode pick)
-- and by the host's lobby "Choose Deck" button. On confirm it hands the chosen deck(s) to a
-- caller-supplied callback; it never starts a run itself.
--
-- Two modes, chosen by the `count` arg to open_deck_select:
--   * count == 1 (single): cycle to a deck and press Select. Callback gets a one-element list.
--   * count > 1  (multi):  cycle through decks and toggle each one in/out of an ordered
--                          selection. The order you add decks IS the run order (deck 1 -> run
--                          1, etc.), shown as a numbered list. Select unlocks once exactly
--                          `count` decks are chosen. Callback gets the ordered list of names.
-- A gamemode needs `count` decks when it plays `count` runs (see SPDRN.required_deck_count):
-- White Stake Triple is best-of-3, so practice/private must pick three decks up front.
--
-- The cycle reuses the base G.FUNCS.change_viewed_back callback, which mutates
-- G.GAME.viewed_back in place and refreshes the preview elements (matched by the
-- func = 'RUN_SETUP_check_back*' tags). So the setup below must mirror what
-- run_setup_option prepares (viewed_back, the back-card CardArea, G.sticker_card).
-- In multi mode the cycle is wrapped (spdrn_deck_select_cycle) so the side panel can refresh
-- the "Add/Remove" button for the newly viewed deck.

local _on_confirm = nil
-- How many decks the picker requires (1 = single-select, >1 = ordered multi-select).
local _count = 1
-- Ordered list of chosen deck display names (multi mode). Insertion order = run order.
local _selected = {}
-- Reactive side panel (multi mode) rebuilt in place on toggle/cycle via :update().
local _panel_el = nil

-- Resolve any deck ref (display name or center key) to a display name get_deck_from_name
-- understands. Defaults to Blue Deck.
local function to_deck_name(deck)
	if deck then
		local center = G.P_CENTERS[deck]
		if center and center.set == 'Back' then
			return center.name
		end
		-- Assume it is already a display name.
		if get_deck_from_name(deck) then
			return deck
		end
	end
	return SPDRN.Deck.DEFAULT
end

-- Index of a deck display name in the ordered selection, or nil if not selected.
local function selected_index(name)
	for i, v in ipairs(_selected) do
		if v == name then
			return i
		end
	end
	return nil
end

-- Build the back-card preview CardArea and stamp G.sticker_card (mirrors the base
-- run_setup_option setup so change_viewed_back can update the win-sticker in place).
local function build_preview_area()
	local area = CardArea(
		G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h,
		G.CARD_W, G.CARD_H,
		{ card_limit = 5, type = 'deck', highlight_limit = 0, deck_height = 0.75, thin_draw = 1 }
	)
	for i = 1, 10 do
		local card = Card(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, G.CARD_W, G.CARD_H, pseudorandom_element(G.P_CARDS), G.P_CENTERS.c_base, { playing_card = i, viewed_back = true })
		card.sprite_facing = 'back'
		card.facing = 'back'
		area:emplace(card)
		if i == 10 then
			G.sticker_card = card
			card.sticker = get_deck_win_sticker(G.GAME.viewed_back.effect.center)
		end
	end
	return area
end

-- A non-interactive label box, used for the disabled toggle/confirm states (so we never
-- hand UIBox_button a nil button handler).
local function disabled_box(label, minw)
	return {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.05, r = 0.1, colour = G.C.UI.BACKGROUND_INACTIVE, minw = minw, minh = 0.7, emboss = 0.05 },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm' }, nodes = {
				{ n = G.UIT.T, config = { text = label, scale = 0.45, colour = G.C.UI.TEXT_INACTIVE, shadow = false } },
			} },
		},
	}
end

-- Multi-mode side panel: counter, the ordered run list, an Add/Remove button for the
-- currently viewed deck, and the Select button (unlocked at exactly `_count` decks).
-- Returns a node whose `nodes` are the panel rows (MPAPI.ui_element wraps them under a
-- stable id so :update() can swap them in place).
local function build_panel_def()
	local cur = G.GAME.viewed_back and G.GAME.viewed_back.name
	local sel_idx = cur and selected_index(cur) or nil
	local n = #_selected
	local rows = {}

	rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
		{ n = G.UIT.T, config = { text = 'Pick ' .. _count .. ' decks (order sets run order)', scale = 0.34, colour = G.C.UI.TEXT_INACTIVE } },
	} }
	rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
		{ n = G.UIT.T, config = { text = 'Selected ' .. n .. ' / ' .. _count, scale = 0.45, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
	} }

	-- The ordered run list. The deck currently in the preview is highlighted.
	if n > 0 then
		local list_nodes = {}
		for i, name in ipairs(_selected) do
			local hot = (name == cur)
			list_nodes[#list_nodes + 1] = { n = G.UIT.R, config = { align = 'cl', padding = 0.01 }, nodes = {
				{ n = G.UIT.T, config = { text = 'Run ' .. i .. ':  ' .. name, scale = 0.36, colour = hot and G.C.BLUE or G.C.UI.TEXT_LIGHT } },
			} }
		end
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
			{ n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.L_BLACK, minw = 3.5, emboss = 0.05 }, nodes = list_nodes },
		} }
	end

	-- Add / Remove the currently viewed deck (or a disabled hint when the list is full).
	local toggle_node
	if sel_idx then
		toggle_node = UIBox_button({ button = 'spdrn_deck_select_toggle', label = { 'Remove ' .. (cur or 'Deck') }, colour = G.C.RED, minw = 3.5, minh = 0.6, scale = 0.42 })
	elseif n < _count then
		toggle_node = UIBox_button({ button = 'spdrn_deck_select_toggle', label = { 'Add ' .. (cur or 'Deck') }, colour = G.C.GREEN, minw = 3.5, minh = 0.6, scale = 0.42 })
	else
		toggle_node = disabled_box('Selection full', 3.5)
	end
	rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = { toggle_node } }

	-- Confirm, gated on having exactly the required number of decks.
	local confirm_node
	if n == _count then
		confirm_node = UIBox_button({ button = 'spdrn_deck_select_confirm', label = { localize('b_select') or 'Select' }, colour = G.C.BLUE, minw = 3, minh = 0.7, scale = 0.5 })
	else
		confirm_node = disabled_box(localize('b_select') or 'Select', 3)
	end
	rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = { confirm_node } }

	return { n = G.UIT.R, config = { align = 'cm' }, nodes = rows }
end

local function build_deck_select_uibox()
	local area = build_preview_area()

	local ordered_names, viewed_deck = {}, 1
	for k, v in ipairs(G.P_CENTER_POOLS.Back) do
		ordered_names[#ordered_names + 1] = v.name
		if v.name == G.GAME.viewed_back.name then
			viewed_deck = k
		end
	end

	-- The deck back visual + name + description, identical in shape to the base picker's
	-- preview column, minus the stake-completion column.
	local preview = {
		n = G.UIT.R,
		config = { align = 'cm', minh = 3.3, minw = 5 },
		nodes = {
			{ n = G.UIT.C, config = { align = 'cm', colour = G.C.BLACK, padding = 0.15, r = 0.1, emboss = 0.05 }, nodes = {
				{ n = G.UIT.C, config = { align = 'cm' }, nodes = {
					{ n = G.UIT.R, config = { align = 'cm', shadow = false }, nodes = {
						{ n = G.UIT.O, config = { object = area } },
					} },
				} },
				{ n = G.UIT.C, config = { align = 'cm', minh = 1.7, r = 0.1, colour = G.C.L_BLACK, padding = 0.1 }, nodes = {
					{ n = G.UIT.R, config = { align = 'cm', r = 0.1, minw = 4, maxw = 4, minh = 0.6 }, nodes = {
						{ n = G.UIT.O, config = { id = nil, func = 'RUN_SETUP_check_back_name', object = Moveable() } },
					} },
					{ n = G.UIT.R, config = { align = 'cm', colour = G.C.WHITE, minh = 1.7, r = 0.1 }, nodes = {
						{ n = G.UIT.O, config = { id = G.GAME.viewed_back.name, func = 'RUN_SETUP_check_back', object = UIBox { definition = G.GAME.viewed_back:generate_UI(), config = { offset = { x = 0, y = 0 } } } } },
					} },
				} },
			} },
		},
	}

	-- In multi mode wrap the cycle so the side panel refreshes for the newly viewed deck.
	local cycle_callback = (_count > 1) and 'spdrn_deck_select_cycle' or 'change_viewed_back'
	local cycle = {
		n = G.UIT.R,
		config = { align = 'cm', minh = 3.8 },
		nodes = {
			create_option_cycle({ options = ordered_names, opt_callback = cycle_callback, current_option = viewed_deck, colour = G.C.RED, w = 3.5, mid = preview }),
		},
	}

	local title_text = (_count > 1) and ('Select ' .. _count .. ' Decks') or 'Select Deck'
	local contents = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = title_text, scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
		cycle,
	}

	if _count > 1 then
		_panel_el = MPAPI.ui_element(build_panel_def)
		contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm' }, nodes = { _panel_el.node } }
	else
		contents[#contents + 1] = {
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.15 },
			nodes = {
				UIBox_button({ button = 'spdrn_deck_select_confirm', label = { localize('b_select') or 'Select' }, colour = G.C.BLUE, minw = 3, minh = 0.7, scale = 0.5 }),
			},
		}
	end

	return create_UIBox_generic_options({ contents = contents })
end

-- Open the picker. `current_deck` is the preselection: a single ref (name or key) in single
-- mode, or a list of refs in multi mode (e.g. the lobby's saved decks) to prefill the order.
-- `count` is how many decks to require (default 1). `on_confirm(decks)` runs on confirm with
-- the ordered list of chosen display names; the overlay closes first.
function SPDRN.open_deck_select(current_deck, on_confirm, count)
	_on_confirm = on_confirm
	_count = (count and count > 1) and count or 1
	_selected = {}
	_panel_el = nil

	if _count > 1 and type(current_deck) == 'table' then
		-- Prefill the ordered selection from the saved list (display names), capped at _count.
		for _, ref in ipairs(current_deck) do
			local name = to_deck_name(ref)
			if name and not selected_index(name) and #_selected < _count then
				_selected[#_selected + 1] = name
			end
		end
	end

	-- Stage the previewed deck: the first saved deck (multi) or the single ref.
	local first = _selected[1]
		or (type(current_deck) == 'table' and current_deck[1])
		or current_deck
	G.GAME.viewed_back = Back(get_deck_from_name(to_deck_name(first)))
	G.FUNCS.overlay_menu({ definition = build_deck_select_uibox() })
end

-- Multi mode: cycle the previewed deck (base behaviour) then refresh the side panel so the
-- Add/Remove button reflects the newly viewed deck.
G.FUNCS.spdrn_deck_select_cycle = function(args)
	G.FUNCS.change_viewed_back(args)
	if _panel_el then
		_panel_el:update()
	end
end

-- Multi mode: add the previewed deck to the ordered selection, or remove it if already in.
-- Adding is a no-op once the selection is full (the button is disabled then anyway).
G.FUNCS.spdrn_deck_select_toggle = function()
	local name = G.GAME.viewed_back and G.GAME.viewed_back.name
	if not name then
		return
	end
	local idx = selected_index(name)
	if idx then
		table.remove(_selected, idx)
	elseif #_selected < _count then
		_selected[#_selected + 1] = name
	else
		return
	end
	if _panel_el then
		_panel_el:update()
	end
end

G.FUNCS.spdrn_deck_select_confirm = function()
	local result
	if _count > 1 then
		-- Guard: only confirm with the full ordered set (the button is gated to match).
		if #_selected ~= _count then
			return
		end
		result = {}
		for i, v in ipairs(_selected) do
			result[i] = v
		end
	else
		result = { (G.GAME.viewed_back and G.GAME.viewed_back.name) or SPDRN.Deck.DEFAULT }
	end

	local cb = _on_confirm
	_on_confirm = nil
	_panel_el = nil
	_selected = {}
	if G.OVERLAY_MENU and G.OVERLAY_MENU ~= true then
		G.FUNCS.exit_overlay_menu()
	end
	if cb then
		cb(result)
	end
end

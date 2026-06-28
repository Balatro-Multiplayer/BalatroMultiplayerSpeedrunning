-- One face-down deck-back tile (the deck's back sprite + its name), built with the same
-- bypass_back Card pattern as the lobby player cards. `ref` is a deck name or center key.
local function deck_back_tile(ref)
	local key = SPDRN.resolve_back_key(ref) or 'b_red'
	local center = G.P_CENTERS[key]
	local name = (center and center.name) or key
	local area = CardArea(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, G.CARD_W, G.CARD_H, { card_limit = 1, type = 'title', highlight_limit = 0, collection = true })
	local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, nil, G.P_CENTERS['j_joker'], { bypass_back = center.pos })
	card.no_ui = true
	card.states.drag.can = false
	card:flip()
	area:emplace(card, nil, true)
	return { n = G.UIT.C, config = { align = 'cm', padding = 0.12 }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = area } } } },
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
			{ n = G.UIT.T, config = { text = name, scale = 0.3, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	} }
end

-- A row of deck-back tiles for the countdown overlay. `decks` is a single deck ref or an
-- ordered list (e.g. the ban-pick survivors, one run each).
local function deck_backs_row(decks)
	local refs = type(decks) == 'table' and decks or { decks }
	local cols = {}
	for _, ref in ipairs(refs) do
		cols[#cols + 1] = deck_back_tile(ref)
	end
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = cols }
end

-- 5s synced countdown overlay, then on_complete(). Used for private + matchmaking starts
-- (practice skips it and calls begin_run directly). `decks` is a single deck ref or list.
function SPDRN.show_countdown(on_complete, decks)
	local opts = {
		label = function(n)
			return (localize('k_starting_in') or 'Starting in') .. ' ' .. n
		end,
	}
	if decks then
		opts.contents = { deck_backs_row(decks) }
	end
	MPAPI.show_countdown(opts, on_complete)
end

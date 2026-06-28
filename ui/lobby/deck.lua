-- How many decks a gamemode needs chosen up front for a practice/private run: one per run it
-- plays. White Stake Triple is best-of-3 (ban_pick.keep == 3); single-run modes need one.
-- (Matchmaking draws its decks from the ban-pick draft instead.)
function SPDRN.required_deck_count(gm_def)
	if gm_def and gm_def.ban_pick and gm_def.ban_pick.keep then
		return gm_def.ban_pick.keep
	end
	return 1
end

-- Normalize a chosen-deck value for metadata: a multi-deck list stays a list, a single deck
-- becomes a plain string (the single-deck shape existing readers expect).
function SPDRN.meta_deck_value(decks)
	if type(decks) == 'table' then
		if #decks > 1 then
			return decks
		end
		return decks[1] or SPDRN.Deck.DEFAULT
	end
	return decks or SPDRN.Deck.DEFAULT
end

-- A short human label for a metadata deck value (string or list), for the lobby deck panel.
function SPDRN.deck_label(meta_deck)
	if type(meta_deck) == 'table' then
		if #meta_deck == 0 then
			return SPDRN.Deck.DEFAULT
		end
		if #meta_deck == 1 then
			return meta_deck[1]
		end
		return #meta_deck .. ' decks'
	end
	return meta_deck or SPDRN.Deck.DEFAULT
end

-- Resolve a deck reference to a Back center KEY. Accepts either a center key already (e.g.
-- 'b_red', as produced by the ban-pick draft) or a display name (e.g. 'Blue Deck', as stored
-- in lobby metadata). Returns nil if it matches no deck. The deck is applied at run start via
-- G.GAME.viewed_back = G.P_CENTERS[key] (see the gamemode start_run methods).
function SPDRN.resolve_back_key(deck)
	if not deck or deck == '' then
		return nil
	end
	local center = G.P_CENTERS[deck]
	if center and center.set == 'Back' then
		return deck
	end
	for _, c in ipairs(G.P_CENTER_POOLS.Back or {}) do
		if c.name == deck then
			return c.key
		end
	end
	return nil
end

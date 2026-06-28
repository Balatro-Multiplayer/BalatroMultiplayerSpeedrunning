-- Host-only: open the deck picker and, on confirm, set the deck for the whole lobby via
-- metadata (synced to all clients, who see it on the read-only deck label).
G.FUNCS.spdrn_choose_deck = function()
	local lobby = SPDRN.lobby.ref
	if not lobby or not lobby.is_host then
		return
	end
	local meta = lobby:get_metadata() or {}
	local gm = meta.gamemode and MPAPI.GameModes[meta.gamemode]
	local count = SPDRN.required_deck_count(gm)
	SPDRN.open_deck_select(meta.deck or SPDRN.Deck.DEFAULT, function(decks)
		local m = lobby:get_metadata() or {}
		local new_meta = {}
		for k, v in pairs(m) do
			new_meta[k] = v
		end
		new_meta.deck = SPDRN.meta_deck_value(decks)
		lobby:set_metadata(new_meta)
	end, count)
end

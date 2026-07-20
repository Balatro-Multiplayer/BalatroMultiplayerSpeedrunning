-- Host-only: open the stake picker and, on confirm, set the stake for the whole lobby via
-- metadata (synced to all clients, who see it on the read-only stake label). Mirrors
-- ui/lobby/choose_deck.lua exactly. Only relevant to gamemodes with picks_stake = true
-- (Seed Scout).
G.FUNCS.spdrn_choose_stake = function()
	local lobby = SPDRN.lobby.ref
	if not lobby or not lobby.is_host then
		return
	end
	local meta = lobby:get_metadata() or {}
	SPDRN.open_stake_select(tonumber(meta.stake) or 1, function(stake)
		local m = lobby:get_metadata() or {}
		local new_meta = {}
		for k, v in pairs(m) do
			new_meta[k] = v
		end
		new_meta.stake = stake
		lobby:set_metadata(new_meta)
	end)
end

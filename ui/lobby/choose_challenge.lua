-- Host-only: open the challenge picker and, on confirm, set the challenge for the whole lobby
-- via metadata (synced to all clients, who see it on the read-only challenge label). Mirrors
-- ui/lobby/choose_deck.lua exactly. Only relevant to gamemodes with picks_challenge = true
-- (Challenge).
G.FUNCS.spdrn_choose_challenge = function()
	local lobby = SPDRN.lobby.ref
	if not lobby or not lobby.is_host then
		return
	end
	local meta = lobby:get_metadata() or {}
	SPDRN.open_challenge_select(meta.challenge, function(challenge_id)
		local m = lobby:get_metadata() or {}
		local new_meta = {}
		for k, v in pairs(m) do
			new_meta[k] = v
		end
		new_meta.challenge = challenge_id
		lobby:set_metadata(new_meta)
	end)
end

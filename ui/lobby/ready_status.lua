-- Finds a live UI element by id across the open UIBoxes (the lobby controls live in the
-- main-menu UIBox, not an overlay).
local function find_uie(id)
	local uiboxes = G.I and G.I.UIBOX
	if not uiboxes then
		return nil
	end
	for _, box in ipairs(uiboxes) do
		if box.get_UIE_by_ID then
			local found = box:get_UIE_by_ID(id)
			if found then
				return found
			end
		end
	end
	return nil
end

-- Updates the matchmaking lobby's status line in place (no-op otherwise).
function SPDRN.refresh_matchmaking_status()
	if not SPDRN.is_matchmaking() then
		return
	end
	local text_e = find_uie('spdrn_mm_status')
	if not text_e or not text_e.config then
		return
	end
	local txt = SPDRN.lobby.ready:all_ready() and (localize('k_get_ready') or 'Get ready!')
		or (localize('k_waiting_for_players') or 'Waiting for players...')
	if text_e.config.text ~= txt then
		text_e.config.text = txt
		if text_e.UIBox then
			text_e.UIBox:recalculate()
		end
	end
end

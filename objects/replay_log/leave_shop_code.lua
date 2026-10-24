-- Leaving the shop ("Next Round", G.FUNCS.toggle_shop) used to have no opcode of its own:
-- playback only synthesized the click when a later select_blind/skip_blind arrived
-- (playback_handlers.lua's leave_shop_if_needed). A racer who left the shop and was still at
-- the next Blind Select when its game died therefore came back from a rejoin standing in the
-- shop, with the shop's cards still for sale and the blind states reverted. Recording the
-- click closes that gap. Older recordings have no such opcode and keep relying on the
-- synthesized click, which is a no-op once the shop has been left.
MPAPI.RLOG_CODE {
	key = 'leave_shop',
	mods = { 'spdrn' },
	write = function(self)
		self:record(nil, "action:leaveShop")
	end,
	replay = function(self, _args, ctx)
		if ctx.schema_version >= 1 then
			if ctx.is_pov and G.STATE == G.STATES.SHOP then G.FUNCS.toggle_shop({ config = {} }) end
		end
	end,
}

local toggle_shop_ref = G.FUNCS.toggle_shop
G.FUNCS.toggle_shop = function(...)
	if G.STATE == G.STATES.SHOP and MPAPI.replay.is_active() then
		MPAPI.RLOGCodes.leave_shop:write()
	end
	return toggle_shop_ref(...)
end

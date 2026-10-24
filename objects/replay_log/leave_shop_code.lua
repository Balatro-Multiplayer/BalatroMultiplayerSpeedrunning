-- Records the Next Round click so a rejoin or replay lands on Blind Select, not back in the
-- shop. Older recordings have no such opcode and keep the synthesized click (a no-op once the
-- shop is left).
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

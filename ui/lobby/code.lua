G.FUNCS.spdrn_view_code = function(e)
	local text_config = e.children[1].children[1].config
	local code = SPDRN.lobby.ref and SPDRN.lobby.ref.code
	if not code then
		return
	end
	if text_config.text ~= code then
		e.config.colour = G.C.ETERNAL
		text_config.text = code
	else
		e.config.colour = G.C.GREEN
		text_config.text = localize('b_view_code_cap')
	end
	e.UIBox:recalculate()
end

G.FUNCS.spdrn_copy_code = function(e)
	local code = SPDRN.lobby.ref and SPDRN.lobby.ref.code
	if not code then
		return
	end
	love.system.setClipboardText(code)

	local text_config = e.children[1].children[1].config
	e.config.colour = G.C.ETERNAL
	text_config.text = localize('k_copied_cap')
	e.UIBox:recalculate()

	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 1.5,
		func = function()
			e.config.colour = G.C.PURPLE
			text_config.text = localize('b_copy_code_cap')
			e.UIBox:recalculate()
			return true
		end,
	}))
end

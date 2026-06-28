SPDRN.timer = SPDRN.timer or {}
local timer = SPDRN.timer

-- Pull appearance from SystemClock's current preset when available, otherwise SPDRN
-- defaults. Returns: style_name, text_size, colours ({text,back,shadow} or nil), position.
-- When SystemClock is installed the timer inherits all of the user's styling, position and
-- customization without mutating any of their saved settings.
timer._resolve_appearance = function()
	local sc = timer._sysclock()
	if sc and sc.current_preset and sc.current_preset.style then
		local colours
		if type(sc.assign_clock_colours) == 'function' then
			local ok, c = pcall(sc.assign_clock_colours)
			if ok then
				colours = c
			end
		end
		return sc.current_preset.style, sc.current_preset.size or 0.5, colours, sc.current_preset.position
	end

	-- Built-in default (SystemClock not installed). Values copied from a working SystemClock
	-- preset: emboss style, size 0.3, white text on a dark (boss) panel, lower-right corner.
	-- G.C.DYN_UI may not exist without SystemClock, so fall back to black.
	local back = copy_table((G.C.DYN_UI and G.C.DYN_UI.BOSS_MAIN) or G.C.BLACK)
	local colours = {
		text = copy_table(G.C.WHITE),
		back = back,
		shadow = darken(copy_table(back), 0.3),
	}
	return 'emboss', 0.3, colours, { x = 17.9135, y = 8.1022 }
end

timer._remove_box = function()
	if timer._box then
		pcall(function()
			timer._box:remove()
		end)
		timer._box = nil
	end
end

timer._build_box = function()
	local style, size, colours, position = timer._resolve_appearance()
	local def = timer._create_clock_UIBox(style, size, colours)

	-- Mirror SystemClock's placement: empty alignment + absolute world coords with major = G
	-- (proven to render during a run), positioned at the resolved preset/default coords.
	local box = UIBox({
		definition = def,
		config = { align = '', offset = { x = 0, y = 0 }, major = G, bond = 'Weak' },
	})

	local x, y
	if position then
		x, y = position.x, position.y
	else
		local rw = (G.ROOM and G.ROOM.T and G.ROOM.T.w) or 0
		x = rw / 2 - (box.T.w or 0) / 2
		y = 0.5
	end
	box.T.x = x
	box.T.y = y
	box.VT.x = x
	box.VT.y = y

	return box
end

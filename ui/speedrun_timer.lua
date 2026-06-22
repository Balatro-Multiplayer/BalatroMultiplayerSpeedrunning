-- Speedrun match timer for MultiplayerSpeedrunning.
--
-- The on-screen clock UI in this file -- the `get_styles` table, `create_clock_UIBox`,
-- `create_clock_DynaText` and `calc_text_width` -- is a minimal, stripped-down adaptation
-- of the SystemClock mod by Breezebuilder (https://github.com/Breezebuilder/SystemClock),
-- used with the author's permission and under the GNU General Public License v3.0. See the
-- LICENSE file at the root of this mod for the full license text.
--
-- Modifications (2026, MultiplayerSpeedrunning authors): the clock displays elapsed
-- speedrun time instead of the system clock; it uses a plain static (non-draggable)
-- container instead of SystemClock's draggable container; the styling/config plumbing,
-- presets, persistence and config UI are not copied.
--
-- When the full SystemClock mod is installed, this timer does not draw its own clock while
-- the user's clock is already on screen -- instead it overrides SystemClock's live time
-- string for the duration of the match (see _install_sysclock_hook), so the timer inherits
-- all of the user's SystemClock styling, position and customization. If the user keeps their
-- SystemClock hidden, we draw our own clock using their current preset's appearance so a
-- timer still shows, without mutating any of their saved settings.
--
-- The displayed time is the client-side elapsed run time (from SPDRN._run_started_at) and is
-- purely cosmetic; the authoritative ranked time is still measured server-side.

local timer = {}
SPDRN.timer = timer

timer.text = '0:00.00'
timer._active = false
timer._frozen = false
timer._box = nil

-- Forward declarations (Lua needs locals defined before use).
local calc_text_width, get_styles, create_clock_DynaText, create_clock_UIBox
local resolve_appearance, remove_box, build_box

local function sysclock()
	return rawget(_G, 'SystemClock')
end

-----------------------------
-- TIME FORMATTING
-----------------------------

-- m:ss.mm (centiseconds), e.g. 4:29.83
function timer.format(secs)
	if not secs or secs < 0 then
		secs = 0
	end
	local minutes = math.floor(secs / 60)
	local rem = secs - minutes * 60
	-- %05.2f -> "ss.mm" width 5 (two integer digits, dot, two decimals), e.g. "04.83".
	return string.format('%d:%05.2f', minutes, rem)
end

-----------------------------
-- CLOCK UI (adapted from SystemClock, GPL-3.0 -- see header)
-----------------------------

calc_text_width = function(sample, text_size)
	local font = G.LANG.font
	local width = 0
	for _, c in utf8.chars(sample) do
		local dx = font.FONT:getWidth(c) * text_size * G.TILESCALE * font.FONTSCALE
		dx = dx + 3 * G.TILESCALE * font.FONTSCALE
		dx = dx / (G.TILESIZE * G.TILESCALE)
		width = width + dx
	end
	return width
end

-- Built lazily so all G.C colour sets are populated when referenced.
get_styles = function()
	return {
		['simple'] = {},
		['shadow'] = { text_shadow = true },
		['translucent'] = {
			shadow_colour = G.C.UI.TRANSPARENT_DARK,
			shadow_padding = 0.05,
			text_shadow = true,
		},
		['panel'] = {
			shadow_colour = G.C.UI.TRANSPARENT_DARK,
			shadow_padding = 0.02,
			outer_colour_ref = 'back',
			outer_padding = 0.03,
			inner_colour = (G.C.DYN_UI and G.C.DYN_UI.BOSS_DARK) or G.C.BLACK,
			inner_padding = 0.05,
			text_padding = 0.05,
			text_shadow = true,
		},
		['emboss'] = {
			shadow_colour_ref = 'shadow',
			outer_colour_ref = 'back',
			emboss_amount = 0.05,
			inner_padding = 0.1,
			text_shadow = true,
		},
		['throwback'] = {
			shadow_colour_ref = 'shadow',
			outer_colour_ref = 'back',
			inner_colour = (G.C.DYN_UI and G.C.DYN_UI.BOSS_DARK) or G.C.BLACK,
			outer_width = 1.45,
			outer_height = 1.15,
			outer_padding = 0.01,
			inner_width = 1.2,
			inner_height = 0.7,
			emboss_amount = 0.05,
			text_shadow = true,
			-- SystemClock's "throwback" style draws a localized heading; omitted here.
		},
	}
end

create_clock_DynaText = function(text_size, colours, shadow)
	local dynaText = DynaText({
		string = { { ref_table = timer, ref_value = 'text' } },
		colours = colours,
		scale = text_size,
		shadow = shadow,
		pop_in_rate = 9999999,
		silent = true,
	})

	return {
		n = G.UIT.O,
		config = {
			align = 'cm',
			id = 'spdrn_clock_text',
			object = dynaText,
		},
	}
end

create_clock_UIBox = function(style_name, text_size, colours)
	style_name = style_name or 'shadow'
	text_size = text_size or 0.5
	colours = colours or {
		text = G.C.UI.TEXT_LIGHT,
		back = G.C.BLACK,
		shadow = G.C.UI.TRANSPARENT_DARK,
	}

	local style = get_styles()[style_name] or {}

	local panel_outer_colour = style.outer_colour or (style.outer_colour_ref and colours[style.outer_colour_ref]) or G.C.CLEAR
	local panel_inner_colour = style.inner_colour or (style.inner_colour_ref and colours[style.inner_colour_ref]) or G.C.CLEAR
	local panel_shadow_colour = style.shadow_colour or (style.shadow_colour_ref and colours[style.shadow_colour_ref]) or G.C.CLEAR
	local text_colours = style.text_colours
		or (style.text_colour and { style.text_colour })
		or (style.text_colour_ref and { colours[style.text_colour_ref] })
		or { colours.text }

	local text_width = math.max(style.inner_width or 0, calc_text_width('00:00.00', text_size))

	return {
		n = G.UIT.ROOT,
		config = {
			align = 'tm',
			colour = panel_shadow_colour,
			padding = style.shadow_padding,
			minw = 0.1,
			r = 0.1,
		},
		nodes = {
			{
				n = G.UIT.R,
				config = {
					align = 'cm',
					colour = panel_outer_colour,
					padding = style.outer_padding,
					minh = style.outer_height,
					minw = style.outer_width,
					r = 0.1,
				},
				nodes = {
					{
						n = G.UIT.C,
						config = { padding = style.outer_padding },
						nodes = {
							{
								n = G.UIT.R,
								config = {
									align = 'cm',
									colour = panel_inner_colour,
									padding = style.inner_padding,
									minh = style.inner_height,
									minw = style.inner_width,
									r = 0.1,
								},
								nodes = {
									{
										n = G.UIT.C,
										config = {
											align = 'cm',
											padding = style.text_padding,
											minw = text_width,
											r = 0.1,
										},
										nodes = { create_clock_DynaText(text_size, text_colours, style.text_shadow) },
									},
								},
							},
						},
					},
				},
			},
			{
				n = G.UIT.R,
				config = { minh = style.emboss_amount },
			},
		},
	}
end

-----------------------------
-- RENDERING / ATTACHMENT
-----------------------------

-- Pull appearance from SystemClock's current preset when available, otherwise SPDRN
-- defaults. Returns: style_name, text_size, colours ({text,back,shadow} or nil), position.
resolve_appearance = function()
	local sc = sysclock()
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

remove_box = function()
	if timer._box then
		pcall(function()
			timer._box:remove()
		end)
		timer._box = nil
	end
end

build_box = function()
	local style, size, colours, position = resolve_appearance()
	local def = create_clock_UIBox(style, size, colours)

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

-----------------------------
-- SYSTEMCLOCK TAKEOVER
-----------------------------

-- While the timer is active, make SystemClock's live time string return our elapsed run
-- time. SystemClock computes its displayed time every frame via get_formatted_time(nil, ...)
-- (the live call passes no format_string); config previews pass an explicit format_string,
-- so guarding on `format_string == nil` leaves those untouched. Dormant when inactive, so
-- the clock reverts to wall-clock automatically -- nothing to restore.
function timer._install_sysclock_hook()
	if SPDRN._sysclock_hooked then
		return
	end
	local sc = sysclock()
	if not (sc and type(sc.get_formatted_time) == 'function') then
		return
	end
	SPDRN._sysclock_hooked = true
	local orig = sc.get_formatted_time
	sc.get_formatted_time = function(format_string, leading_zero, time, hour_offset)
		if timer._active and format_string == nil then
			return timer.text
		end
		return orig(format_string, leading_zero, time, hour_offset)
	end
end

-----------------------------
-- LIFECYCLE
-----------------------------

-- Begin (or restart) the on-screen timer. Called from SPDRN.begin_run /
-- SPDRN.restart_current_run right after SPDRN._run_started_at is set.
function timer.start()
	timer._active = true
	timer._frozen = false
	timer._entered_run = false
	timer.text = timer.format(0)
	timer._install_sysclock_hook()
end

-- Freeze the timer at its final value (kept showing on the win/lose screen). The display is
-- torn down by the update loop when the run/lobby ends.
function timer.stop()
	timer._frozen = true
end

function timer._tick()
	if not timer._active then
		return
	end

	-- start() is called from begin_run *before* the stage flips to RUN, so we must not tear
	-- down just because we aren't on the RUN stage yet. Only tear down once we have actually
	-- entered the run and then left it (back to menu, or "Continue in Singleplayer" which
	-- drops the lobby while staying on the RUN stage).
	local in_match = (G.STAGE == G.STAGES.RUN) and MPAPI.is_active(SPDRN.id) and MPAPI.get_current_lobby() and true or false

	if in_match then
		timer._entered_run = true
	elseif timer._entered_run then
		remove_box()
		timer._active = false
		timer._entered_run = false
		return
	else
		-- Not in the run yet (gap between start() and the stage flip). Wait.
		return
	end

	if not timer._frozen then
		local started = SPDRN._run_started_at
		local elapsed = started and (love.timer.getTime() - started) or 0
		timer.text = timer.format(elapsed)
	end

	-- Renderer selection: if the user's own SystemClock is on screen, the get_formatted_time
	-- override already feeds it our time -- don't draw a second clock. Otherwise draw our own
	-- (styled from their preset when SystemClock is installed, else SPDRN defaults).
	if sysclock() and G.HUD_clock then
		remove_box()
	elseif not timer._box then
		local ok, box = pcall(build_box)
		if ok then
			timer._box = box
		end
	end
end

-- Tick off the frame loop. Mirrors SystemClock's own Game:update wrap; Game exists at load.
if not SPDRN._timer_update_hooked then
	SPDRN._timer_update_hooked = true
	local _timer_update_ref = Game.update
	function Game:update(dt)
		_timer_update_ref(self, dt)
		pcall(timer._tick)
	end
end

return timer

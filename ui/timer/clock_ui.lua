-- The on-screen clock UI in this file -- the `_get_styles` table, `_create_clock_UIBox`,
-- `_create_clock_DynaText` and `_calc_text_width` -- is a minimal, stripped-down adaptation
-- of the SystemClock mod by Breezebuilder (https://github.com/Breezebuilder/SystemClock),
-- used with the author's permission and under the GNU General Public License v3.0. See the
-- LICENSE file at the root of this mod for the full license text.
--
-- Modifications (2026, MultiplayerSpeedrunning authors): the clock displays elapsed speedrun
-- time instead of the system clock; it uses a plain static (non-draggable) container; the
-- styling/config plumbing, presets, persistence and config UI are not copied.

SPDRN.timer = SPDRN.timer or {}
local timer = SPDRN.timer

timer._calc_text_width = function(sample, text_size)
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
timer._get_styles = function()
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

timer._create_clock_DynaText = function(text_size, colours, shadow)
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

timer._create_clock_UIBox = function(style_name, text_size, colours)
	style_name = style_name or 'shadow'
	text_size = text_size or 0.5
	colours = colours or {
		text = G.C.UI.TEXT_LIGHT,
		back = G.C.BLACK,
		shadow = G.C.UI.TRANSPARENT_DARK,
	}

	local style = timer._get_styles()[style_name] or {}

	local panel_outer_colour = style.outer_colour or (style.outer_colour_ref and colours[style.outer_colour_ref]) or G.C.CLEAR
	local panel_inner_colour = style.inner_colour or (style.inner_colour_ref and colours[style.inner_colour_ref]) or G.C.CLEAR
	local panel_shadow_colour = style.shadow_colour or (style.shadow_colour_ref and colours[style.shadow_colour_ref]) or G.C.CLEAR
	local text_colours = style.text_colours
		or (style.text_colour and { style.text_colour })
		or (style.text_colour_ref and { colours[style.text_colour_ref] })
		or { colours.text }

	local text_width = math.max(style.inner_width or 0, timer._calc_text_width('00:00.00', text_size))

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
										nodes = { timer._create_clock_DynaText(text_size, text_colours, style.text_shadow) },
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

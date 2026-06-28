SPDRN.timer = SPDRN.timer or {}
local timer = SPDRN.timer

timer.text = timer.text or '0:00.00'
timer._active = timer._active or false
timer._frozen = timer._frozen or false

-- m:ss.mm (centiseconds), e.g. 4:29.83. The displayed time is the client-side elapsed run
-- time (from SPDRN._run_started_at) and is purely cosmetic; the authoritative ranked time
-- is measured server-side.
function timer.format(secs)
	if not secs or secs < 0 then
		secs = 0
	end
	local minutes = math.floor(secs / 60)
	local rem = secs - minutes * 60
	-- %05.2f -> "ss.mm" width 5 (two integer digits, dot, two decimals), e.g. "04.83".
	return string.format('%d:%05.2f', minutes, rem)
end

SPDRN.timer = SPDRN.timer or {}
local timer = SPDRN.timer

timer._sysclock = function()
	return rawget(_G, 'SystemClock')
end

-- While the timer is active, make SystemClock's live time string return our elapsed run
-- time. SystemClock computes its displayed time every frame via get_formatted_time(nil, ...)
-- (the live call passes no format_string); config previews pass an explicit format_string,
-- so guarding on `format_string == nil` leaves those untouched. Dormant when inactive, so
-- the clock reverts to wall-clock automatically -- nothing to restore.
function timer._install_sysclock_hook()
	if SPDRN._sysclock_hooked then
		return
	end
	local sc = timer._sysclock()
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

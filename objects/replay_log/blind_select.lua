-- True when a run's Blind Select screen is up and built. G.STATE leaves BLIND_SELECT when a run
-- ends and returns to it only once the next run's setup has finished, so this also says "the new
-- run is ready".
function SPDRN.blind_select_is_up()
	return SPDRN.blind_select_is_up()
end

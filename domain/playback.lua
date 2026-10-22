-- The namespace SPDRN's playback handlers and drivers use (MPAPI.playback.register_handler /
-- new_driver's mod_id). Every mod's drivers share MPAPI.playback._active_drivers, so "an SPDRN
-- replay is driving" must be asked by namespace, never as next(_active_drivers).
SPDRN.PLAYBACK_NS = 'spdrn'

function SPDRN.is_replay_driving()
	return MPAPI.playback.is_driving(SPDRN.PLAYBACK_NS)
end

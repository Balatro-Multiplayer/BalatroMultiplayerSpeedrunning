-- While queued, the account panel shows a live "Queueing m:ss" status, measured against
-- wall-clock time since the 'queued' event. The text is kept short so the fixed-width panel
-- does not reflow.
SPDRN.matchmaking_status = SPDRN.matchmaking_status or {}
local status = SPDRN.matchmaking_status

local _active = false
local _start_time = nil
local _last_text = nil

local function format_status()
	local elapsed = math.floor(love.timer.getTime() - _start_time)
	return string.format('%s %d:%02d', localize('k_status_queueing'), math.floor(elapsed / 60), elapsed % 60)
end

local function schedule_tick()
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.25,
		blockable = false,
		blocking = false,
		func = function()
			if not _active then
				return true
			end
			local t = format_status()
			if t ~= _last_text then
				_last_text = t
				MPAPI.set_connection_status(t)
			end
			schedule_tick()
			return true
		end,
	}))
end

function status.start()
	if _active then
		return
	end
	_active = true
	_start_time = love.timer.getTime()
	_last_text = nil
	MPAPI.set_connection_status(format_status())
	schedule_tick()
end

function status.stop()
	_active = false
	_start_time = nil
	_last_text = nil
	MPAPI.set_connection_status(nil)
end

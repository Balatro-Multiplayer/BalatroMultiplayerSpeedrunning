-- Who may send a match-deciding action. The server drops these from the wrong
-- sender already (nakama/src/lobby/sender_guard.ts); this is the client's own
-- check, so a forged one is ignored here too.
--
-- MPAPI keeps only our own is_host, so a guest learns the host from
-- host_changed (ui/lobby/events.lua); until it has seen one it can't tell the
-- host from another guest.
SPDRN.Sender = {}

local heard_host = setmetatable({}, { __mode = 'k' })

function SPDRN.Sender.note_host(lobby, host_id)
	heard_host[lobby] = host_id
end

function SPDRN.Sender.forget_host(lobby)
	heard_host[lobby] = nil
end

-- Whether `from` is the host of `lobby`. No lobby: a direct local call.
function SPDRN.Sender.is_host(lobby, from)
	if not lobby then
		return true
	end
	if lobby.is_host then
		return from == lobby.player_id
	end
	if from == lobby.player_id then
		return false
	end
	local host = heard_host[lobby]
	return host == nil or host == from
end

-- `on_receive` for a host-only action: an action from anyone else is ignored.
function SPDRN.Sender.host_only(key, on_receive)
	return function(action_type, from_player_id, params)
		if not SPDRN.Sender.is_host(MPAPI.get_current_lobby(), from_player_id) then
			SPDRN.sendDebugMessage('Ignored ' .. key .. ' from ' .. tostring(from_player_id) .. ': not the host')
			return
		end
		return on_receive(action_type, from_player_id, params)
	end
end

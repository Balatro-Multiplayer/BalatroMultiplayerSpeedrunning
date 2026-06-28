-- Broadcast this client's ready state. The host (including itself, via the broadcast
-- loopback) tallies these in the ready tracker.
function SPDRN.signal_ready(ready)
	local lobby = SPDRN.lobby.ref
	if not lobby then
		return
	end
	local action = lobby:action(MPAPI.ActionTypes['spdrn_player_ready'])
	action:broadcast({ ready = ready and true or false })
end

-- Matchmaking safety net for the lobby-join race: re-broadcast our ready a few times over the
-- first several seconds. Idempotent, and self-terminates once the start broadcast lands or
-- after the attempt cap. Covers the case where the initial ready was published before the peer
-- had subscribed to the actions topic.
function SPDRN.start_ready_resync()
	if not SPDRN.is_matchmaking() then
		return
	end
	SPDRN._ready_resync_stop = MPAPI.ready_resync({
		send = function()
			SPDRN.signal_ready(true)
		end,
		should_continue = function()
			return SPDRN.lobby.ref ~= nil and SPDRN.is_matchmaking()
		end,
	})
end

function SPDRN.stop_ready_resync()
	if SPDRN._ready_resync_stop then
		SPDRN._ready_resync_stop()
		SPDRN._ready_resync_stop = nil
	end
end

-- Clear all ready state. Called locally on every client when the game starts so a subsequent
-- return to the lobby starts everyone un-readied, and resets the guest's READY toggle visuals.
function SPDRN.reset_ready_state()
	local b = SPDRN.lobby.buttons
	SPDRN.lobby.ready:reset()
	SPDRN.lobby.local_ready = false
	SPDRN.lobby.start_broadcasted = false
	if b.ready_args then
		b.ready_args.label = { localize('b_ready_cap') or 'READY' }
		b.ready_args.colour = G.C.GREEN
	end
	if b.ready then
		b.ready:update()
	end
	if b.start_game then
		b.start_game:update()
	end
end

-- Host-only: record a player's ready state and react (refresh START for private lobbies, or
-- kick off the auto-start for matchmaking).
function SPDRN.set_player_ready(player_id, ready)
	local lobby = SPDRN.lobby.ref
	if not lobby or not lobby.is_host then
		return
	end
	SPDRN.lobby.ready:set(player_id, ready)
	if SPDRN.is_matchmaking() then
		SPDRN.refresh_matchmaking_status()
		SPDRN.maybe_autostart()
	elseif SPDRN.lobby.buttons.start_game then
		SPDRN.lobby.buttons.start_game:update()
	end
end

-- Host-only matchmaking auto-start: once all clients are ready (and min players met) broadcast
-- the start exactly once.
function SPDRN.maybe_autostart()
	local L = SPDRN.lobby
	if L.start_broadcasted then
		return
	end
	if not L.ref or not L.ref.is_host then
		return
	end
	if not SPDRN.is_matchmaking() then
		return
	end
	local meta = L.ref:get_metadata()
	local gm = meta.gamemode and MPAPI.GameModes[meta.gamemode]
	local min_players = gm and gm:get_min_players('ranked') or 2
	if #L.ref:get_players() < min_players then
		return
	end
	if not L.ready:all_ready() then
		return
	end
	L.start_broadcasted = true
	SPDRN.broadcast_start(SPDRN.generate_seed())
end

-- Guest READY toggle (private lobbies).
G.FUNCS.spdrn_toggle_ready = function()
	local L = SPDRN.lobby
	L.local_ready = not L.local_ready
	if L.buttons.ready_args and L.buttons.ready then
		L.buttons.ready_args.label = { L.local_ready and (localize('b_unready_cap') or 'UNREADY') or (localize('b_ready_cap') or 'READY') }
		L.buttons.ready_args.colour = L.local_ready and G.C.ORANGE or G.C.GREEN
		L.buttons.ready:update()
	end
	SPDRN.signal_ready(L.local_ready)
end

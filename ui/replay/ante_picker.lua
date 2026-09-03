-- Ante-seek UI for replay/rejoin playback: makes the vanilla ante HUD number clickable while
-- (and only while) SPDRN is actively driving a replay/rejoin session, opens a popup listing
-- every ante that occurs in the current session's timeline, and shows a loading overlay while
-- a seek is in flight. The actual seek mechanics (index-building, fast-forwarding, restarting)
-- live in objects/replay_log/ante_index.lua and ante_seek.lua -- this file is UI only.

-- Vanilla's ante HUD node (functions/UI_definitions.lua's create_UIBox_HUD, id='hud_ante') is a
-- plain DynaText bound to G.GAME.round_resets.ante -- it was never constructed with
-- config.button set, so it was never armed for click at construction time (engine/ui.lua only
-- arms click/collide state for nodes that set button/button_UIE up front). Simply setting
-- .config.button post-hoc (the way some ALREADY-interactive nodes get repurposed elsewhere in
-- this codebase) does not retroactively arm it -- the state flags themselves must be forced,
-- same technique already proven for retrofitting interactivity onto an existing vanilla node
-- in BalatroMultiplayerAPI/ui/enemy_location.lua.
--
-- Called once the ante index finishes building (SPDRN._build_ante_index's on_built, via
-- SPDRN._open_replay_session in ante_seek.lua) and again after every restart-driven seek
-- (SPDRN._restart_session_and_seek rebuilds G.HUD from scratch via a fresh begin_run, which
-- loses this wiring every time). Idempotent per G.HUD instance via a marker field on the node
-- itself, since a fresh G.HUD is a genuinely new table each restart.
function SPDRN._wire_ante_click()
	if not G.HUD then
		return
	end
	local uie = G.HUD:get_UIE_by_ID('hud_ante')
	if not uie or uie._spdrn_ante_click_wired then
		return
	end
	uie._spdrn_ante_click_wired = true
	uie.states.collide.can = true
	uie.states.click.can = true
	uie.config.button = 'spdrn_open_ante_picker'
end

-- The actual click handler is gated live (not just at wiring time) on
-- MPAPI.playback._active_drivers being non-empty -- the one reliable "a replay/rejoin driver
-- is actively driving input" signal anywhere in this codebase -- so a click is correctly a
-- no-op if it somehow fires outside an active session, regardless of whether some earlier
-- G.HUD instance's wiring is still lingering.
G.FUNCS.spdrn_open_ante_picker = function()
	if not next(MPAPI.playback._active_drivers) then
		return
	end
	local session = SPDRN._active_replay_session
	if not session or session.seeking then
		return
	end
	SPDRN._open_ante_picker(session)
end

local function format_money_label(amount)
	if not amount or amount == 0 then
		return nil
	end
	return (amount > 0 and '+$' or '-$') .. tostring(math.abs(amount))
end

-- Same "N dynamically-generated buttons" recipe already used 3x elsewhere in this codebase
-- (objects/replay_log/replay_browser.lua's spdrn_open_replay_browser is the closest analogue:
-- per-item UIBox_button with a per-item dynamic `button` key, plus a matching G.FUNCS entry
-- registered alongside each row), wrapped in create_UIBox_generic_options and opened via
-- G.FUNCS.overlay_menu the same simple one-shot way replay_browser.lua's own picker is (this
-- popup doesn't need to rebuild itself in place, unlike e.g. api/ban_pick.lua's own overlay).
function SPDRN._open_ante_picker(session)
	local rows = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Seek to Ante', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	}

	local index = session.ante_index or {}
	-- Only show "Run N" group headers when this match ever actually reached a second run
	-- (White Stake Triple/Stake Climb/All Deck) -- single-run formats (Gold Stake Single,
	-- Challenge) always have run_idx=1 throughout, per SPDRN.current_run's own fallback.
	local has_multiple_runs = index[#index] and index[#index].run_idx > 1

	local last_run = nil
	for i, entry in ipairs(index) do
		if entry.run_idx ~= last_run then
			last_run = entry.run_idx
			if has_multiple_runs then
				rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
					{ n = G.UIT.T, config = { text = 'Run ' .. entry.run_idx, scale = 0.4, colour = G.C.UI.TEXT_INACTIVE } },
				} }
			end
		end

		local money = format_money_label(SPDRN._ante_money_spent(session, i))
		local button_key = 'spdrn_seek_ante_' .. entry.run_idx .. '_' .. entry.ante
		local label = { 'Ante ' .. entry.ante }
		if money then
			label[#label + 1] = money
		end
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
			UIBox_button({
				button = button_key,
				label = label,
				colour = G.C.GREEN,
				minw = 4,
				minh = 0.6,
				scale = 0.35,
			}),
		} }
		G.FUNCS[button_key] = function()
			G.FUNCS.exit_overlay_menu()
			SPDRN._seek_to_ante(entry.run_idx, entry.ante)
		end
	end

	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = rows }) })
end

-- Shown for the whole duration of a seek's fast-forward (§ scope decision: the actual
-- fast-motion gameplay underneath is never shown, only this). no_esc=true is required, not
-- cosmetic -- the player must not be able to interact with a half-fast-forwarded game
-- underneath a dismissed overlay.
local _seek_overlay = nil

function SPDRN._ante_seek_show_overlay(_run_idx, ante)
	_seek_overlay = MPAPI.ui_element(function()
		return {
			n = G.UIT.ROOT,
			config = { align = 'cm', minw = 1 },
			nodes = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.2, minh = 1.5 }, nodes = {
					{ n = G.UIT.T, config = { text = 'Seeking to Ante ' .. tostring(ante) .. '...', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
			},
		}
	end)
	_seek_overlay:as_overlay({ no_esc = true })
end

function SPDRN._ante_seek_hide_overlay()
	_seek_overlay = nil
	if G.OVERLAY_MENU and G.OVERLAY_MENU ~= true then
		G.FUNCS.exit_overlay_menu()
	end
end

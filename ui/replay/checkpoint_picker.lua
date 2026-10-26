-- Checkpoint-seek UI for replay/rejoin playback: makes the vanilla ante HUD number clickable
-- while (and only while) SPDRN is actively driving a replay/rejoin session, opens a nested
-- Run -> Ante -> Blind popup listing every checkpoint the current session's timeline reaches
-- (plus a perspective-switch section for other players in the same match), and shows a loading
-- overlay while a seek/switch is in flight. The actual seek/switch mechanics (index-building,
-- fast-forwarding, restarting) live in objects/replay_log/checkpoint_index.lua,
-- checkpoint_seek.lua, and perspective_switch.lua -- this file is UI only.

-- Vanilla's ante HUD node (functions/UI_definitions.lua's create_UIBox_HUD, id='hud_ante') is a
-- plain DynaText bound to G.GAME.round_resets.ante -- it was never constructed with
-- config.button set, so it was never armed for click at construction time (engine/ui.lua only
-- arms click/collide state for nodes that set button/button_UIE up front). Simply setting
-- .config.button post-hoc (the way some ALREADY-interactive nodes get repurposed elsewhere in
-- this codebase) does not retroactively arm it -- the state flags themselves must be forced,
-- same technique already proven for retrofitting interactivity onto an existing vanilla node
-- in BalatroMultiplayerAPI/ui/enemy_location.lua.
--
-- Called once the checkpoint index finishes building (SPDRN._build_checkpoint_index's on_built,
-- via SPDRN._open_replay_session in checkpoint_seek.lua) and again after every restart-driven
-- seek (SPDRN._restart_session_and_seek rebuilds G.HUD from scratch via a fresh begin_run, which
-- loses this wiring every time). Idempotent per G.HUD instance via a marker field on the node
-- itself, since a fresh G.HUD is a genuinely new table each restart.
function SPDRN._wire_checkpoint_click()
	if not G.HUD then
		return
	end
	local uie = G.HUD:get_UIE_by_ID('hud_ante')
	if not uie or uie._spdrn_checkpoint_click_wired then
		return
	end
	uie._spdrn_checkpoint_click_wired = true
	uie.states.collide.can = true
	uie.states.click.can = true
	uie.config.button = 'spdrn_open_checkpoint_picker'
end

-- The actual click handler is gated live (not just at wiring time) on
-- MPAPI.playback._active_drivers being non-empty -- the one reliable "a replay/rejoin driver
-- is actively driving input" signal anywhere in this codebase -- so a click is correctly a
-- no-op if it somehow fires outside an active session, regardless of whether some earlier
-- G.HUD instance's wiring is still lingering.
G.FUNCS.spdrn_open_checkpoint_picker = function()
	if not SPDRN.is_replay_driving() then
		return
	end
	local session = SPDRN._active_replay_session
	if not session or session.seeking then
		return
	end
	SPDRN._open_checkpoint_picker()
end

local function format_money_label(amount)
	if not amount or amount == 0 then
		return nil
	end
	return (amount > 0 and '+$' or '-$') .. tostring(math.abs(amount))
end

-- Single expanded run + single expanded ante at a time (accordion, not free-multi-expand) --
-- keeps the popup's height bounded for long multi-run, multi-ante matches rather than showing
-- every blind of every ante of every run at once. `expanded_ante` is keyed 'run_idx:ante' (not
-- just `ante`) so expanding ante 3 of run 1 doesn't also appear expanded after switching to
-- run 2. Reset on every fresh open (SPDRN._open_checkpoint_picker), preserved across in-place
-- :update() calls within one open, same split as BalatroMultiplayerAPI/ui/account_overlay.lua's
-- own `_state`/`account_overlay_inner` pattern (its own comment documents this exact "reset on
-- fresh open, survive in-place updates" split), which this whole popup's reactive-rebuild
-- approach otherwise mirrors closely.
local _picker_state = { expanded_run = nil, expanded_ante = nil, roster_expanded = false }
local _picker_el = nil

-- Stable, shared button handlers reading e.config.ref_table -- registered once at file load,
-- not a fresh G.FUNCS[per_item_key] closure on every popup rebuild (the recipe this file's own
-- ante-only predecessor used, and every accordion toggle now rebuilds the popup, so that old
-- recipe would leak an ever-growing set of dead G.FUNCS entries). Mirrors
-- BalatroMultiplayerAPI/ui/account_overlay.lua's own mpapi_account_select_tab handler.
G.FUNCS.spdrn_checkpoint_toggle_roster = function(_e)
	_picker_state.roster_expanded = not _picker_state.roster_expanded
	if _picker_el then
		_picker_el:update()
	end
end

G.FUNCS.spdrn_checkpoint_toggle_run = function(e)
	local run_idx = e.config and e.config.ref_table and e.config.ref_table.run_idx
	if not run_idx then
		return
	end
	_picker_state.expanded_run = (_picker_state.expanded_run == run_idx) and nil or run_idx
	_picker_state.expanded_ante = nil
	if _picker_el then
		_picker_el:update()
	end
end

G.FUNCS.spdrn_checkpoint_toggle_ante = function(e)
	local rt = e.config and e.config.ref_table
	if not (rt and rt.run_idx and rt.ante) then
		return
	end
	local key = rt.run_idx .. ':' .. rt.ante
	_picker_state.expanded_ante = (_picker_state.expanded_ante == key) and nil or key
	if _picker_el then
		_picker_el:update()
	end
end

G.FUNCS.spdrn_checkpoint_seek = function(e)
	local rt = e.config and e.config.ref_table
	if not (rt and rt.run_idx and rt.ante) then
		return
	end
	G.FUNCS.exit_overlay_menu()
	SPDRN._seek_to_checkpoint(rt.run_idx, rt.ante, rt.blind)
end

G.FUNCS.spdrn_checkpoint_switch_player = function(e)
	local target_player_id = e.config and e.config.ref_table and e.config.ref_table.player_id
	if not target_player_id then
		return
	end
	G.FUNCS.exit_overlay_menu()
	SPDRN._switch_perspective(target_player_id)
end

-- Groups a flat blind-granular checkpoint index (checkpoint_index.lua) into an ordered
-- run -> ante -> blind[] tree for the nested popup, in one pass. Ordering matches the flat
-- index's own first-occurrence order at every level.
local function group_checkpoints(index)
	local runs_order, runs_by_idx = {}, {}
	for _, e in ipairs(index or {}) do
		local run = runs_by_idx[e.run_idx]
		if not run then
			run = { run_idx = e.run_idx, antes_order = {}, antes_by_num = {} }
			runs_by_idx[e.run_idx] = run
			runs_order[#runs_order + 1] = run
		end
		local ante = run.antes_by_num[e.ante]
		if not ante then
			ante = { ante = e.ante, blinds = {} }
			run.antes_by_num[e.ante] = ante
			run.antes_order[#run.antes_order + 1] = ante
		elseif e.blind == 'Small' and #ante.blinds > 0 then
			-- CONFIRMED LIVE BUG, fixed by this reset: a mid-run restart (a real player's own
			-- "Restart Run" click after a blind loss, or the divergent-death auto-restart
			-- fallback, ui/lose_screen.lua's SPDRN._check_run_lost) resets G.GAME.round_resets.ante
			-- back to whatever ante the fresh attempt starts from, so the flat checkpoint index
			-- (checkpoint_index.lua) can and does record the SAME (run_idx, ante) more than once --
			-- one set of blind entries per attempt, never deduped across the restart (that file's
			-- own dedup only collapses CONSECUTIVE identical keys, and a restart's own key is never
			-- consecutive with whatever came right before it). Without this reset, antes_by_num
			-- being keyed purely by ante NUMBER meant every attempt's blinds just kept accumulating
			-- into the SAME row forever, so a restarted "Ante 1" showed a nonsensical merged list of
			-- blinds from every abandoned attempt AND the real, kept one, with no way to tell which
			-- was which. A Small Blind checkpoint always starts a genuinely fresh attempt at that
			-- ante (select_blind/skip_blind's own blind_on_deck reset, see checkpoint_index.lua's
			-- header comment) -- so seeing 'Small' again for an ante this loop has already built a
			-- row for is the reliable signal a restart happened, not a duplicate frame of the same
			-- attempt. Reproduced live against a real production match (4bab3028.../
			-- 41038e0d..., gold_stake_single) that restarted from Ante 1 five times via the
			-- divergent-death fallback above. Matches checkpoint_seek.lua's own find_checkpoint_entry
			-- fix (same root cause, same "last attempt wins" resolution) so this popup's displayed
			-- blinds and that lookup's seek target always agree.
			ante.blinds = {}
		end
		ante.blinds[#ante.blinds + 1] = e
	end
	return runs_order
end

local function build_run_header_row(run_idx)
	local expanded = _picker_state.expanded_run == run_idx
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
		{ n = G.UIT.C, config = {
			button = 'spdrn_checkpoint_toggle_run',
			ref_table = { run_idx = run_idx },
			colour = expanded and G.C.GREY or G.C.CLEAR,
			minw = 4,
			padding = 0.05,
		}, nodes = {
			{ n = G.UIT.T, config = { text = (expanded and '\226\150\190 ' or '\226\150\184 ') .. 'Run ' .. run_idx, scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} },
	} }
end

-- The ante row's own label click seeks directly to that ante's Small Blind (preserving the
-- one-click "seek to ante" behavior from this popup's ante-only predecessor); a separate
-- disclosure control on the same row toggles the blind sub-rows without seeking or closing the
-- popup.
local function build_ante_row(entry, money_label)
	local key = entry.run_idx .. ':' .. entry.ante
	local expanded = _picker_state.expanded_ante == key
	local label = { 'Ante ' .. entry.ante }
	if money_label then
		label[#label + 1] = money_label
	end
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
		UIBox_button({
			button = 'spdrn_checkpoint_seek',
			ref_table = { run_idx = entry.run_idx, ante = entry.ante, blind = 'Small' },
			label = label,
			colour = G.C.GREEN,
			minw = 3.4,
			minh = 0.6,
			scale = 0.35,
		}),
		{ n = G.UIT.C, config = { minw = 0.15 } },
		{ n = G.UIT.C, config = {
			button = 'spdrn_checkpoint_toggle_ante',
			ref_table = { run_idx = entry.run_idx, ante = entry.ante },
			colour = G.C.CLEAR,
			minw = 0.5,
			minh = 0.6,
		}, nodes = {
			{ n = G.UIT.T, config = { text = expanded and '\226\150\180' or '\226\150\182', scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} },
	} }
end

local function build_blind_row(run_idx, ante, blind)
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
		{ n = G.UIT.C, config = { minw = 0.6 } },
		UIBox_button({
			button = 'spdrn_checkpoint_seek',
			ref_table = { run_idx = run_idx, ante = ante, blind = blind },
			label = { blind .. ' Blind' },
			colour = G.C.BLUE,
			minw = 3,
			minh = 0.5,
			scale = 0.3,
		}),
	} }
end

-- Roster comes from the recorded lobby_info opcode's own `players` field (an array of
-- {id, is_host} -- every client independently writes an equivalent copy of this, built from
-- the live lobby's own get_players(), confirmed via ui/lobby/run_start.lua's SPDRN.begin_run --
-- not host-exclusive data), not a scan of distinct player_ids actually present in the timeline,
-- since build_timeline (api/playback/timeline.lua) silently drops a whole player's log on
-- decompress/decode failure -- the recorded roster stays correct even if that happens.
--
-- KNOWN GAP: the recorded roster only carries {id, is_host}, no display name -- SPDRN's own
-- live end-game panel (ui/end_game_panel.lua) shows real names, but those come from a live
-- lobby object's own get_players(), not anything recorded into the replay log. A replay session
-- has no live lobby to ask, so player buttons here fall back to a shortened player_id. Fixing
-- this properly would mean recording a display name into lobby_info's own write() call
-- (ui/lobby/run_start.lua) -- a write-side change that would only help FUTURE recordings, not
-- the real match data already imported locally -- left as a follow-up, not solved here.
local function find_roster(session)
	for _, entry in ipairs(session.timeline) do
		if entry.opcode == MPAPI.OPCODE.LOBBY_INFO and entry.args and entry.args.players then
			return entry.args.players
		end
	end
	return {}
end

local function short_id(id)
	return tostring(id):sub(1, 8)
end

local function build_roster_section(session)
	local rows = {}
	local expanded = _picker_state.roster_expanded
	rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
		{ n = G.UIT.C, config = {
			button = 'spdrn_checkpoint_toggle_roster',
			colour = expanded and G.C.GREY or G.C.CLEAR,
			minw = 4.5,
			padding = 0.05,
		}, nodes = {
			{ n = G.UIT.T, config = { text = (expanded and '\226\150\190 ' or '\226\150\184 ') .. 'Viewing: ' .. short_id(session.my_id), scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
		} },
	} }
	if not expanded then
		return rows
	end
	for _, p in ipairs(find_roster(session)) do
		if p.id ~= session.my_id and SPDRN._find_bootstrap(session.timeline, p.id) then
			rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
				{ n = G.UIT.C, config = { minw = 0.6 } },
				UIBox_button({
					button = 'spdrn_checkpoint_switch_player',
					ref_table = { player_id = p.id },
					label = { short_id(p.id) },
					colour = G.C.PURPLE,
					minw = 3,
					minh = 0.5,
					scale = 0.3,
				}),
			} }
		end
	end
	return rows
end

local function build_checkpoint_picker()
	local session = SPDRN._active_replay_session
	local rows = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = 'Seek to Checkpoint', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	}
	if not session then
		return { n = G.UIT.ROOT, config = { align = 'cm' }, nodes = rows }
	end

	for _, row in ipairs(build_roster_section(session)) do
		rows[#rows + 1] = row
	end

	local runs = group_checkpoints(session.checkpoint_index or {})
	-- Only show "Run N" group headers when this match ever actually reached a second run
	-- (White Stake Triple/Stake Climb/All Deck) -- single-run formats (Gold Stake Single,
	-- Challenge) always have run_idx=1 throughout, per SPDRN.current_run's own fallback.
	local has_multiple_runs = #runs > 1
	local ante_boundaries = MPAPI.playback.checkpoint_ante_boundaries(session.checkpoint_index or {})
	local ante_boundary_i = 0

	for _, run in ipairs(runs) do
		if has_multiple_runs then
			rows[#rows + 1] = build_run_header_row(run.run_idx)
		end
		if not has_multiple_runs or _picker_state.expanded_run == run.run_idx then
			for _, ante in ipairs(run.antes_order) do
				ante_boundary_i = ante_boundary_i + 1
				local money = format_money_label(MPAPI.playback.checkpoint_money_spent(session, ante_boundaries, ante_boundary_i))
				local first_entry = ante.blinds[1]
				rows[#rows + 1] = build_ante_row(first_entry, money)
				local key = run.run_idx .. ':' .. ante.ante
				if _picker_state.expanded_ante == key then
					for _, blind_entry in ipairs(ante.blinds) do
						if blind_entry.blind ~= 'Small' then
							rows[#rows + 1] = build_blind_row(run.run_idx, ante.ante, blind_entry.blind)
						end
					end
				end
			end
		end
	end

	return { n = G.UIT.ROOT, config = { align = 'cm' }, nodes = rows }
end

function SPDRN._open_checkpoint_picker()
	_picker_state = { expanded_run = nil, expanded_ante = nil, roster_expanded = false }
	if not _picker_el then
		_picker_el = MPAPI.ui_element(build_checkpoint_picker)
	end
	_picker_el:as_overlay()
end

-- Shown for the whole duration of a seek/switch's fast-forward (the actual fast-motion gameplay
-- underneath is deliberately never shown, only this). no_esc=true is required, not cosmetic --
-- the player must not be able to interact with a half-fast-forwarded game underneath a
-- dismissed overlay. Text-agnostic (formerly ante-only "Seeking to Ante N...") since
-- checkpoint_seek.lua's own seeks and perspective_switch.lua's cross-player sync both need this
-- same non-interactive wait state, differing only in what the text says.
local _seek_overlay = nil
local _seek_overlay_text = nil

function SPDRN._show_seek_overlay(text)
	_seek_overlay_text = text
	_seek_overlay = MPAPI.ui_element(function()
		return {
			n = G.UIT.ROOT,
			config = { align = 'cm', minw = 1 },
			nodes = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.2, minh = 1.5 }, nodes = {
					{ n = G.UIT.T, config = { text = text, scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
			},
		}
	end)
	_seek_overlay:as_overlay({ no_esc = true })
end

function SPDRN._hide_seek_overlay()
	_seek_overlay = nil
	_seek_overlay_text = nil
	if G.OVERLAY_MENU and G.OVERLAY_MENU ~= true then
		G.FUNCS.exit_overlay_menu()
	end
end

-- CONFIRMED LIVE BUG, fixed by this re-show hook: vanilla's own G.FUNCS.overlay_menu (called by
-- MPAPI.ui_element's :as_overlay, api/ui_element.lua) attaches the created UIBox to
-- G.ROOM_ATTACH with `bond = 'Weak'` (functions/button_callbacks.lua) -- vanilla itself only
-- ever expects an overlay to outlive a single room's lifetime (e.g. the options menu, opened and
-- closed without the room underneath ever changing). A restart-based seek/switch is not that:
-- SPDRN._start_playback (playback_launch.lua) tears the old room down and boots a genuinely NEW
-- one (a fresh local lobby + SPDRN.begin_run), mid-seek, every time _open_replay_session or
-- _restart_session_and_seek (checkpoint_seek.lua) runs -- i.e. on EVERY restart-based seek:
-- opening a replay from the very beginning, any backward seek, and every perspective switch
-- alike. That room change silently orphans the weakly-bonded overlay UIBox partway through --
-- reproduced live via cctl eval polling G.OVERLAY_MENU during a real seek: it read `nil` for the
-- entire multi-second checkpoint-index-build fast-forward pass, with session.seeking still true
-- the whole time -- leaving the player looking at raw, un-narrated fast-forward gameplay instead
-- of this overlay, for the dominant majority of the seek's real duration. Fix: re-display the
-- SAME text (remembered in _seek_overlay_text above) once each fresh room reaches BLIND_SELECT --
-- called from checkpoint_seek.lua's own on_ready callbacks, the exact same two points
-- SPDRN._wire_checkpoint_click is already re-called from for the identical "a restart silently
-- wipes some piece of UI state" reason (see that function's own comment). No-op if no seek
-- overlay is currently supposed to be showing (_seek_overlay_text nil -- normal play, not seeking).
--
-- Residual, flagged gap: this closes the overlay-less gap for the fast-forward pass itself (the
-- long part, confirmed multi-second-to-minutes on a real recording), but NOT the brief window
-- between the old driver stopping (which releases G.CONTROLLER.locks.mpapi_playback, since no
-- driver is active yet) and the fresh room actually reaching BLIND_SELECT (vanilla's own run-
-- start animation) -- input is briefly genuinely unlocked with no overlay shown during that
-- narrow span. Not solved here: closing it fully would need either a synchronous overlay
-- recreate inside the room-teardown call itself (invasive, vanilla-internal surgery this
-- feature shouldn't own) or a separate input-block mechanism independent of the driver lock.
-- Worth a follow-up if this narrow window is ever confirmed clickable in practice.
--
-- CONFIRMED LIVE (broad sweep testing, real production match 636b473d-.../8b4de509-...): a
-- SEPARATE overlay-less gap exists even on a plain FORWARD seek that never itself takes the
-- explicit-stop restart branch above -- one that happens to fast-forward THROUGH a recorded
-- run_died/run_restarted/divergent-death transition partway to its target
-- (SPDRN._playback_handle_run_transition, playback_launch.lua, called mid-dispatch from
-- Driver:_dispatch_next). That handler calls driver:pause() (NOT :stop()), so unlike the gap
-- documented above, G.CONTROLLER.locks.mpapi_playback stays set for its whole duration (the
-- driver is never removed from MPAPI.playback._active_drivers, only its own `pause()` toggles
-- `_playing`, per Driver:_update_lock's own logic) -- input is NOT actually clickable during
-- this window, unlike the explicit-stop case. But the overlay itself is still just as absent:
-- `_playback_handle_run_transition` calls G.FUNCS.exit_overlay_menu() (dismissing whatever this
-- seek's own overlay was showing) BEFORE SPDRN.restart_current_run(), and only re-shows it (via
-- this same function) once the fresh room reaches BLIND_SELECT -- with nothing shown in between.
-- Reproduced live via a frame-by-frame cctl script sample immediately after a seek reported
-- itself settled (session.seeking == false): G.STATE read a non-standard `-1`, G.hand/G.deck/
-- G.jokers were all nil, G.GAME.dollars read a transient negative value, and G.OVERLAY_MENU was
-- nil throughout -- unchanged across 121 consecutive real frames (~0.26s) before the sample
-- ended; a later poll of the same instance confirmed the run eventually recovered to a normal,
-- playable state (consistent with this landing inside the underlying divergent-death recovery's
-- own up-to-20s real-time window, ui/lose_screen.lua's SPDRN.REPLAY_DIVERGENT_DEATH_TIMEOUT_SECONDS,
-- not a permanent hang). Net effect: a viewer whose seek happens to cross an internal restart can
-- see several seconds of raw broken-looking state (no cards, no jokers, wrong money, no "Seeking
-- to..." overlay) with no way to interact with it (input genuinely locked), rather than either a
-- clean freeze-frame or the intended overlay. Same fix tradeoff as the gap documented above
-- (no cheap fix without either invasive vanilla-internal surgery or a separate always-on
-- input-block layer) -- flagged here as a distinct, now-confirmed instance of the same root
-- limitation, not fixed in this pass.
function SPDRN._reshow_seek_overlay()
	if _seek_overlay_text then
		SPDRN._show_seek_overlay(_seek_overlay_text)
	end
end

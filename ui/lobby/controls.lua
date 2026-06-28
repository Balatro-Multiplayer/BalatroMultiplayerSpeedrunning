SPDRN.lobby = SPDRN.lobby or { buttons = {} }

local function code_panel()
	local b = SPDRN.lobby.buttons
	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.1, r = 0.2, colour = G.C.BLACK },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = 'cm', maxh = 1.4 },
				nodes = {
					{ n = G.UIT.T, config = { text = localize('k_lobby_code_cap'), scale = 0.45, colour = G.C.UI.TEXT_LIGHT, vert = true, maxh = 1.4 } },
				},
			},
			{
				n = G.UIT.C,
				config = { align = 'cm', padding = 0.1 },
				nodes = {
					{ n = G.UIT.R, config = { align = 'cm' }, nodes = { b.view_code.node } },
					{ n = G.UIT.R, config = { align = 'cm' }, nodes = { b.copy_code.node } },
				},
			},
		},
	}
end

-- Host gets a deck-picker button; guests see the chosen deck as a read-only label. Rebuilt
-- with the lobby view, so it reflects the current metadata deck (refreshed on metadata_changed).
local function deck_panel()
	local lobby = SPDRN.lobby.ref
	local meta = (lobby and lobby:get_metadata()) or {}
	local deck_name = SPDRN.deck_label(meta.deck)
	if lobby and lobby.is_host then
		return { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
			UIBox_button({ id = 'spdrn_choose_deck', button = 'spdrn_choose_deck', colour = G.C.PURPLE, minw = 2.65, minh = 1.35, label = { 'Deck', deck_name }, scale = 0.4, col = true }),
		} }
	end
	return { n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.1, colour = G.C.L_BLACK, minw = 2.65, minh = 1.35, emboss = 0.05 }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = 'Deck', scale = 0.32, colour = G.C.UI.TEXT_INACTIVE } } } },
		{ n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = deck_name, scale = 0.42, colour = G.C.UI.TEXT_LIGHT, shadow = true } } } },
	} }
end

-- Private lobbies: host gets START + LOBBY OPTIONS, guests get a READY toggle; both get the
-- deck/code panels and LEAVE.
local function build_private_controls()
	local b = SPDRN.lobby.buttons
	local lobby = SPDRN.lobby.ref
	local row_nodes = {}
	if lobby and lobby.is_host then
		row_nodes[#row_nodes + 1] = b.start_game.node
		row_nodes[#row_nodes + 1] = b.lobby_options.node
	else
		row_nodes[#row_nodes + 1] = b.ready.node
	end
	row_nodes[#row_nodes + 1] = deck_panel()
	row_nodes[#row_nodes + 1] = code_panel()
	row_nodes[#row_nodes + 1] = b.leave.node

	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.1, r = 0.1, emboss = 0.1, colour = G.C.L_BLACK, mid = true },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = row_nodes },
		},
	}
end

-- Reactive status panel: the deck-ban draft while one is active, otherwise the waiting line.
-- Held as a single ui_element so the draft refreshes in place (:update swaps children by id)
-- instead of rebuilding the lobby view on every ban. SPDRN.lobby.refresh_mm_status drives it.
local _mm_status_el = nil

local function build_mm_status()
	if MPAPI.BanPick.is_active() then
		return { nodes = MPAPI.BanPick.build_contents() }
	end
	return { nodes = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { id = 'spdrn_mm_status', text = localize('k_waiting_for_players') or 'Waiting for players...', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	} }
end

-- Matchmaking lobbies (ranked / casual): no action buttons; the run auto-starts once every
-- client has signalled ready.
local function build_matchmaking_controls()
	_mm_status_el = _mm_status_el or MPAPI.ui_element(build_mm_status)
	return {
		n = G.UIT.C,
		config = { align = 'cm', padding = 0.2, r = 0.1, emboss = 0.1, colour = G.C.L_BLACK, mid = true },
		nodes = { _mm_status_el.node },
	}
end

function SPDRN.lobby.refresh_mm_status()
	if _mm_status_el then
		_mm_status_el:update()
	end
end

function SPDRN.lobby.build_controls()
	if SPDRN.is_matchmaking() then
		return build_matchmaking_controls()
	end
	return build_private_controls()
end

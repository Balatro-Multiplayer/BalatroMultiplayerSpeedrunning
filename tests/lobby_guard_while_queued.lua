--[[
  Lobby create/join queue-guard test (consumer side).

  Feature: you should not be able to create or join a lobby while in
  matchmaking. The API exposes MPAPI.matchmaking.guard_queued(replay) (shows a
  "Leave Queue & Continue" overlay and stashes `replay` to run after leaving);
  the Speedrun mod calls it at its lobby entry points.

  Bug this guards against: the guard must replay the CONSUMER entry point
  (create_lobby_with_gamemode / SPDRN._join_lobby_with_code), NOT the API
  primitive (MPAPI.create_lobby / MPAPI.join_lobby). Those consumer functions
  call SPDRN.setup_lobby_events(lobby) after obtaining the lobby -- that setup
  wires the lobby-event subscriptions and the CONNECTED handler that transitions
  the client into the lobby. Replaying the API primitive alone joins/creates
  server-side (the host sees you) but skips setup_lobby_events, stranding the
  client on the menu. This test pins that: the replay runs setup_lobby_events.

  Run from the repo root:
    luajit tests/lobby_guard_while_queued.lua
]]

-- ── Stubs to load the real ui/main_menu entry points ───────────────────────
SPDRN = {
	id = "spdrn",
	LobbyKind = { PRIVATE = "private" },
	Deck = { DEFAULT = "default" },
	Ruleset = { ORDER = "order" },
	Gamemode = { WHITE_STAKE_TRIPLE = "white_stake_triple", GOLD_STAKE_SINGLE = "gold_stake_single" },
	sendDebugMessage = function() end,
}
G = { FUNCS = { exit_overlay_menu = function() end } }
love = { system = { setClipboardText = function() end } }

-- Controllable guard mirroring MPAPI.matchmaking.guard_queued's contract.
local searching = false
local stashed = nil
local overlay_shown = 0
MPAPI = {
	id = "spdrn",
	GameModes = {},
	shallow_copy = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end,
	matchmaking = {
		guard_queued = function(replay)
			if searching then
				stashed = replay
				overlay_shown = overlay_shown + 1
				return true
			end
			return false
		end,
	},
}

-- Fake lobby + API primitives, with call counters.
local api_join_calls, api_create_calls, setup_calls = 0, 0, 0
local function fake_lobby()
	return { code = "ABC123", on = function() end, set_metadata = function() end }
end
MPAPI.join_lobby = function(_mod, _code) api_join_calls = api_join_calls + 1; return fake_lobby() end
MPAPI.create_lobby = function(_mod, _opts) api_create_calls = api_create_calls + 1; return fake_lobby() end

-- Load the REAL consumer entry points, then stub the mod-side collaborator the
-- guarded functions call (defined after dofile so it isn't clobbered).
dofile("ui/main_menu/create_lobby.lua")
dofile("ui/main_menu/join.lua")
SPDRN.setup_lobby_events = function(_lobby) setup_calls = setup_calls + 1 end

-- ── Harness ────────────────────────────────────────────────────────────────
local failures = 0
local function check(cond, msg)
	if cond then print("PASS: " .. msg) else failures = failures + 1; print("FAIL: " .. msg) end
end
local function reset() searching, stashed, overlay_shown = false, nil, 0; api_join_calls, api_create_calls, setup_calls = 0, 0, 0 end

-- ── join: blocked while searching ───────────────────────────────────────────
print()
print("-- join: blocked while searching --")
reset(); searching = true
SPDRN._join_lobby_with_code("ABC123")
check(api_join_calls == 0, "join: MPAPI.join_lobby NOT called while searching")
check(setup_calls == 0, "join: setup_lobby_events NOT called while searching")
check(overlay_shown == 1 and type(stashed) == "function", "join: overlay shown and a replay closure stashed")

-- ── join: Leave Queue & Continue replays the FULL consumer flow ─────────────
print()
print("-- join: leave queue & continue runs the full consumer setup --")
searching = false
stashed() -- the overlay's replay
check(api_join_calls == 1, "join replay: MPAPI.join_lobby called after leaving")
check(setup_calls == 1, "join replay: setup_lobby_events ran (client transitions into the lobby)")

-- ── join: proceeds normally when not searching ──────────────────────────────
print()
print("-- join: not searching -> proceeds --")
reset()
SPDRN._join_lobby_with_code("ABC123")
check(api_join_calls == 1 and setup_calls == 1, "join: joins and sets up when not searching")
check(overlay_shown == 0, "join: no overlay when not searching")

-- ── create: blocked while searching, replay runs full setup ─────────────────
print()
print("-- create: blocked while searching; replay runs full setup --")
reset(); searching = true
G.FUNCS.spdrn_select_white_stake_triple()
check(api_create_calls == 0 and setup_calls == 0, "create: nothing allocated while searching")
check(overlay_shown == 1 and type(stashed) == "function", "create: overlay shown and replay stashed")
searching = false
stashed()
check(api_create_calls == 1 and setup_calls == 1, "create replay: create_lobby + setup_lobby_events both ran")

-- ── RED control: replaying the API primitive strands the client ─────────────
-- Reproduces the original bug -- the stashed replay called MPAPI.join_lobby
-- directly, so setup_lobby_events never ran and the client stayed on the menu.
print()
print("-- control: replaying the API primitive skips setup (reproduces the bug) --")
reset()
local pre_fix_replay = function() return MPAPI.join_lobby(SPDRN.id, "ABC123") end
pre_fix_replay()
check(api_join_calls == 1, "control: server-side join happened (host sees you)")
check(setup_calls == 0, "control: setup_lobby_events NEVER ran -- client stranded on the menu")

-- ── Summary ─────────────────────────────────────────────────────────────────
print()
if failures == 0 then
	print("ALL TESTS PASSED")
	os.exit(0)
else
	print(failures .. " TEST(S) FAILED")
	os.exit(1)
end

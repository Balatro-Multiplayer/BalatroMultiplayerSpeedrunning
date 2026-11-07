-- luajit tests/blind_select_test.lua
SPDRN = {}
G = { STATES = { BLIND_SELECT = 7, SHOP = 5 } }
dofile("objects/replay_log/blind_select.lua")

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed = failed + 1
		print("FAIL: " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	else
		print("PASS: " .. name)
	end
end

G.STATE, G.blind_select = G.STATES.BLIND_SELECT, {}
check("up when the state is Blind Select and the screen is built", SPDRN.blind_select_is_up(), true)
G.STATE, G.blind_select = G.STATES.BLIND_SELECT, nil
check("not up before the screen is built", SPDRN.blind_select_is_up(), false)
G.STATE, G.blind_select = G.STATES.SHOP, {}
check("not up in another state", SPDRN.blind_select_is_up(), false)

if failed > 0 then
	os.exit(1)
end

--[[
  Guard: debug, info and trace lines carry match data, so they reach the log only
  through MPAPI.match_log (written only when the Dev mod is installed). This test
  checks that SPDRN's helper uses the gate and that no other file calls the
  Steamodded or MPAPI log globals for those levels.

  Run from the repo root:
    luajit tests/match_log_guard.lua
]]

local failures = 0
local function check(ok, msg)
	if not ok then
		failures = failures + 1
		print('FAIL: ' .. msg)
	end
end

local function read(path)
	local f = assert(io.open(path, 'rb'))
	local s = f:read('*a')
	f:close()
	return s
end

-- The helper sends its line through the gate with the SPDRN tag.
local calls = {}
SPDRN = { id = 'spdrn' }
MPAPI = {
	match_log = function(level, msg, tag)
		calls[#calls + 1] = { level = level, msg = msg, tag = tag }
	end,
}
SMODS = { current_mod = SPDRN }
sendDebugMessage = function()
	check(false, 'helper called sendDebugMessage directly')
end
sendWarnMessage = function() end
-- core.lua also loads the whole mod, so run only its helper section.
local core = read('core.lua')
local helper_src = core:match('^(.-)function SPDRN%.load_spdrn_file')
check(helper_src ~= nil, 'core.lua defines the log helpers before the loader')
assert(loadstring(helper_src))()
SPDRN.sendDebugMessage('hello')
check(#calls == 1, 'helper makes exactly one gate call')
check(calls[1] and calls[1].level == 'debug' and calls[1].msg == 'hello' and calls[1].tag == 'spdrn', 'helper passes level, message and SPDRN tag')

-- No direct debug/info/trace calls outside the helper.
local files = {}
local p = io.popen('find . -name "*.lua" -not -path "./tests/*" -not -path "./.git/*"')
for line in p:lines() do
	files[#files + 1] = line
end
p:close()
check(#files > 0, 'found source files')

local FORBIDDEN = { 'sendDebugMessage', 'sendInfoMessage', 'sendTraceMessage' }
for _, path in ipairs(files) do
	local n = 0
	for line in (read(path) .. '\n'):gmatch('(.-)\n') do
		n = n + 1
		for _, name in ipairs(FORBIDDEN) do
			-- SPDRN.sendDebugMessage is the helper and is allowed everywhere.
			local from = 1
			while true do
				local s, e = line:find(name, from, true)
				if not s then
					break
				end
				local before = line:sub(1, s - 1)
				local is_helper = before:sub(-6) == 'SPDRN.'
				if not is_helper then
					check(false, path .. ':' .. n .. ' calls ' .. name .. ' directly')
				end
				from = e + 1
			end
		end
	end
end

if failures > 0 then
	print(failures .. ' failure(s)')
	os.exit(1)
end
print('ok')

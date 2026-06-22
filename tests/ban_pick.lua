-----------------------------
-- Ban-pick host authority (MPAPI.BanPick.apply_ban)
-----------------------------
--
-- apply_ban is the canonical host-side mutation: it validates turn + legality, records the
-- ban, advances the rotation, and on the final ban marks the draft complete with the
-- surviving deck names. These tests drive it directly on a plain state table (no lobby
-- networking needed -- apply_ban only reads lobby._ban_pick).

-- Three real deck keys so survivor names resolve via G.P_CENTERS.
local POOL = { 'b_red', 'b_blue', 'b_yellow' }

local function make_lobby(pool, keep, order)
	return {
		is_host = true,
		player_id = order[1],
		_ban_pick = {
			pool = pool,
			banned = {},
			order = order,
			turn_index = 1,
			bans_remaining = #pool - keep,
			keep = keep,
			complete = false,
		},
	}
end

BInt.register_test('spdrn:ban_pick_rejects_off_turn', function(test)
	-- turn_index 1 => p1's turn; p2 banning should be rejected and change nothing.
	local lobby = make_lobby(POOL, 1, { 'p1', 'p2' })
	local ok, err = pcall(function()
		local applied = MPAPI.BanPick.apply_ban(lobby, 'p2', 'b_red')
		test:assert_false(applied, 'off-turn ban should be rejected')
		test:assert_false(lobby._ban_pick.banned['b_red'] == true, 'off-turn ban must not record')
		test:assert_eq(lobby._ban_pick.turn_index, 1, 'turn must not advance on a rejected ban')
	end)
	assert(ok, err)
end)

BInt.register_test('spdrn:ban_pick_applies_and_advances_turn', function(test)
	local lobby = make_lobby(POOL, 1, { 'p1', 'p2' })
	local ok, err = pcall(function()
		local applied = MPAPI.BanPick.apply_ban(lobby, 'p1', 'b_red')
		local s = lobby._ban_pick
		test:assert_true(applied, 'on-turn ban should apply')
		test:assert_true(s.banned['b_red'] == true, 'banned deck should be recorded')
		test:assert_eq(s.bans_remaining, 1, 'bans_remaining should decrement (2 -> 1)')
		test:assert_eq(s.turn_index, 2, 'turn should advance to the next player')
		test:assert_false(s.complete == true, 'draft should not be complete yet')
	end)
	assert(ok, err)
end)

BInt.register_test('spdrn:ban_pick_rejects_invalid_targets', function(test)
	local lobby = make_lobby(POOL, 1, { 'p1', 'p2' })
	local ok, err = pcall(function()
		-- Not in the pool.
		test:assert_false(MPAPI.BanPick.apply_ban(lobby, 'p1', 'b_nonexistent'), 'deck not in pool should be rejected')
		-- Apply a real ban, then try to ban it again (now p2's turn).
		MPAPI.BanPick.apply_ban(lobby, 'p1', 'b_red')
		test:assert_false(MPAPI.BanPick.apply_ban(lobby, 'p2', 'b_red'), 'already-banned deck should be rejected')
	end)
	assert(ok, err)
end)

BInt.register_test('spdrn:ban_pick_completes_with_survivors', function(test)
	-- 3 decks, keep 1 => 2 bans. p1 bans red, p2 bans blue => yellow survives.
	local lobby = make_lobby(POOL, 1, { 'p1', 'p2' })
	local ok, err = pcall(function()
		MPAPI.BanPick.apply_ban(lobby, 'p1', 'b_red')
		MPAPI.BanPick.apply_ban(lobby, 'p2', 'b_blue')
		local s = lobby._ban_pick
		test:assert_true(s.complete == true, 'draft should complete after the final ban')
		test:assert_eq(#s.survivors, 1, 'one deck should survive')
		test:assert_eq(s.survivors[1], 'b_yellow', 'the unbanned deck key should survive')
	end)
	assert(ok, err)
end)

BInt.register_test('spdrn:ban_pick_triple_keeps_three_in_order', function(test)
	-- White Stake Triple shape: 5-deck pool, keep 3, ban 2. Survivors stay in pool order.
	local pool = { 'b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black' }
	local lobby = make_lobby(pool, 3, { 'p1', 'p2' })
	local ok, err = pcall(function()
		MPAPI.BanPick.apply_ban(lobby, 'p1', 'b_blue')
		MPAPI.BanPick.apply_ban(lobby, 'p2', 'b_green')
		local s = lobby._ban_pick
		test:assert_true(s.complete == true, 'draft should complete')
		test:assert_eq(#s.survivors, 3, 'three decks should survive')
		test:assert_eq(s.survivors[1], 'b_red', 'survivor 1 in pool order')
		test:assert_eq(s.survivors[2], 'b_yellow', 'survivor 2 in pool order')
		test:assert_eq(s.survivors[3], 'b_black', 'survivor 3 in pool order')
	end)
	assert(ok, err)
end)

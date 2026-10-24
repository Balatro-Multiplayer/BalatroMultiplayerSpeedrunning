-- SPDRN's opcode semantics for MPAPI's generic playback engine
-- (BalatroMultiplayerAPI/api/playback/{registry,driver,timeline}.lua) --
-- ported from BalatroMultiplayerPvP's lib/playback_handlers.lua, stripped of
-- everything PvP-specific: SPDRN is solo, so every handler is always POV
-- (ctx.is_pov checked defensively, not because a non-POV branch is expected),
-- and there is no opponent-HUD projection, ready/ante-key handshake, or
-- hand_result opcode (SPDRN never records one -- see record.lua's call
-- sites). Every real handler calls the exact real G.FUNCS a live click would
-- call, fed the exact real Card/CardArea objects the recording's positional
-- indices point to -- this works because SPDRN._start_playback
-- (playback_launch.lua) starts a fresh run from the recorded manifest's own
-- seed/deck/stake, and Balatro's RNG is a deterministic hash chain keyed only
-- by seed + call sequence, so the same positional indices point at the same
-- cards again.
--
-- AREA is looked up fresh inside area_object, not captured at file scope --
-- see record.lua's own comment on why (SPDRN.load_spdrn_dir's directory
-- iteration order isn't guaranteed, so utils.lua isn't guaranteed to have
-- run before this file).
local function area_object(area_id)
	local AREA = SPDRN.RLOG_UTILS.AREA
	if area_id == AREA.shop_jokers then return G.shop_jokers end
	if area_id == AREA.shop_booster then return G.shop_booster end
	if area_id == AREA.shop_vouchers then return G.shop_vouchers end
	if area_id == AREA.jokers then return G.jokers end
	if area_id == AREA.consumeables then return G.consumeables end
	if area_id == AREA.hand then return G.hand end
	if area_id == AREA.pack_cards then return G.pack_cards end
	return nil
end

-- Resolves recorded hand-card references back to live Card objects via
-- MPAPI.replay.resolve_card_ref (identity, immune to reordering/reshuffling)
-- when `refs` was recorded, falling back to the plain positional lookup above
-- only when there's no ref for a slot (recordings predating played_refs/
-- discarded_refs/target_refs). This mirrors the same fix in MPAPI's own
-- api/replay/generic_codes.lua -- see that file's comment for the full
-- rationale -- duplicated here because register_handler('spdrn', ...) below
-- overwrites MPAPI's generic RLOG_CODE.replay baseline entirely (see that
-- file's own header comment on "a later register_handler call... simply
-- overwrites this one"), so SPDRN's actual playback path never runs MPAPI's
-- version at all. Confirmed live: this exact gap crashed replaying a real,
-- flagged (hash_mismatch) production SPDRN match -- a stale positional index
-- fed a malformed card selection into play_cards_from_highlighted, which
-- crashed deep in vanilla's evaluate_play (functions/state_events.lua:589,
-- "attempt to index a nil value" in the retrigger loop). A ref that fails to
-- resolve means this replay has ALREADY desynced -- skip that card and warn
-- loudly, never fall back to the very position that just proved unreliable.
-- Confirmed live against a real, flagged (hash_mismatch) production match: a
-- 'play' opcode dispatched while G.hand itself was nil (mid round-transition --
-- G.hand is torn down and rebuilt across a run restart/new round, not just
-- emptied like the shop card areas below) crashed here with "attempt to index
-- field 'hand' (a nil value)" the moment ANY ref needed resolving, before the
-- existing per-card skip-and-warn logic below even got a chance to run. Same
-- root cause class as the shop-readiness gate in replay_buy/etc further down
-- this file (a card area not actually ready yet when a recorded opcode fires),
-- just for the hand area instead of a shop one -- and unlike those, this one
-- has no natural "wait for it" moment to gate on (a hand can legitimately not
-- exist for reasons ranging from mundane timing to a replay that's desynced
-- itself all the way into the wrong game state), so this skips-and-warns
-- immediately rather than pausing the driver to retry.
local function highlight_resolved_hand_indices(indices, refs, ctx, opcode)
	if not (G.hand and G.hand.cards) then
		MPAPI.sendWarnMessage(
			'[replay] ' .. tostring(opcode) .. ': G.hand is not available -- replay has desynced from the recording, skipping this action entirely'
		)
		return
	end
	local resolver = ctx and ctx.card_resolver
	for i, idx in ipairs(indices or {}) do
		local ref = refs and refs[i]
		local card
		if ref then
			if resolver then
				card = MPAPI.replay.resolve_card_ref(resolver, ref, G.hand.cards)
			end
			if not card then
				MPAPI.sendWarnMessage(
					'[replay] ' .. tostring(opcode) .. ': could not resolve hand card ref for index '
						.. tostring(idx) .. ' -- replay has desynced from the recording, skipping this card'
				)
			end
		else
			card = G.hand.cards[idx]
		end
		if card then G.hand:add_to_highlighted(card) end
	end
end

MPAPI.playback.register_handler('spdrn', 'manifest', function(_args, _ctx) end)
MPAPI.playback.register_handler('spdrn', 'end', function(_args, _ctx) end)
MPAPI.playback.register_handler('spdrn', 'chk', function(_args, _ctx) end)
-- Pure bookkeeping (see record.lua's ease_dollars hook) -- the real dollar
-- change already happens as a side effect of whatever action caused it
-- (buy/sell/etc, each already replayed by its own handler), nothing to apply.
MPAPI.playback.register_handler('spdrn', 'money_delta', function(_args, _ctx) end)

-- Same real-UIBox technique PvP's equivalent handler needed (confirmed live
-- there, a crash risk from calling select_blind before G.blind_select's own
-- (re)built UIBox exists on this frame) -- deferred via
-- SPDRN._playback_wait_for the same way SPDRN._start_playback reaches
-- BLIND_SELECT in the first place.
local function do_select_blind()
	local blind_key = G.GAME.round_resets.blind_choices[G.GAME.blind_on_deck]
	G.FUNCS.select_blind({ config = { ref_table = G.P_BLINDS[blind_key] }, UIBox = G.blind_select })
end

-- Leaving the shop (the "Next Round" button, G.FUNCS.toggle_shop) has no RLOG_CODE
-- of its own anywhere in this codebase -- it was simply never recorded. A recorded
-- select_blind/skip_blind opcode can only exist because the real player already
-- left the shop to reach that screen, so synthesizing the click here (once, only
-- when actually still in the shop) is safe and correct for every recording,
-- including every one already stored server-side before this fix existed --
-- unlike a fix on the recording side, this doesn't need new data to take effect.
-- Confirmed live: without this, select_blind's own wait_for (below) waits forever
-- once the driver correctly stops advancing during it (see that fix's own
-- comment) -- replay would hang at the shop on every single round transition.
local function leave_shop_if_needed()
	if G.STATE == G.STATES.SHOP then
		G.FUNCS.toggle_shop({ config = {} })
	end
end

-- Defensive readiness gate for any opcode that touches the shop's own card
-- areas (reroll/buy/voucher/open_pack/sell). Confirmed live: G.shop_jokers can
-- read non-nil while G.shop_jokers.cards is itself still nil -- checked once
-- (in cashout's own wait, above) right after entering the shop is not enough,
-- since the SAME gap reproduced again later in the SAME shop visit (jokers_
-- purchased:0 at the crash, i.e. the very first shop action, not necessarily
-- the one immediately after cash_out -- some OTHER mid-shop event can leave
-- the area in this same not-quite-ready state momentarily). Every shop-area
-- opcode gets its own last-moment check rather than trusting an earlier one to
-- still hold. If already ready, `fn` runs immediately with no driver pause at
-- all (the overwhelmingly common case) -- only pauses when genuinely caught
-- mid-gap.
-- Bounded like select_blind's own hand-dealt wait above: a shop-area opcode
-- can be dispatched after the replay has ALREADY moved on past that shop
-- visit entirely (the same "recorded opcode fires later than replay's own
-- actual progress" class of desync as cashout firing mid-round, elsewhere in
-- this file) -- in that case G.shop_jokers never becomes ready again and this
-- would hang the driver forever. Give up after a real-time timeout rather
-- than waiting indefinitely; the specific action (buy/reroll/etc) just never
-- happens, which is a strictly better outcome than a permanently stuck
-- replay.
-- `fn` may return true to take over resuming the driver itself (e.g. buying a
-- Booster Pack needs a FURTHER wait afterward, for the pack it opens -- see
-- replay_buy below) -- anything else (including no return at all) resumes
-- immediately once fn() returns, same as before.
local SHOP_READY_TIMEOUT_SECONDS = 10
local function with_shop_ready(ctx, fn)
	if G.shop_jokers ~= nil and G.shop_jokers.cards ~= nil then
		if not fn() and ctx.driver then ctx.driver:play() end
		return
	end
	local driver = ctx.driver
	if driver then driver:pause() end
	local deadline = love.timer.getTime() + SHOP_READY_TIMEOUT_SECONDS
	SPDRN._playback_wait_for(function()
		if G.shop_jokers ~= nil and G.shop_jokers.cards ~= nil then
			return true
		end
		if love.timer.getTime() >= deadline then
			MPAPI.sendWarnMessage('[replay] shop never became ready after ' .. SHOP_READY_TIMEOUT_SECONDS .. 's -- giving up on this action and resuming')
			return true
		end
		return false
	end, function()
		local deferred = false
		if G.shop_jokers ~= nil and G.shop_jokers.cards ~= nil then
			deferred = fn()
		end
		if not deferred and driver then driver:play() end
	end)
end

-- SPDRN._playback_wait_for is its own independent poll (Game:update, see
-- playback_launch.lua), completely invisible to the Driver's own pacing
-- (api/playback/driver.lua's _tick, gated on _queues_empty()). Registering a
-- waiter and returning immediately -- as this used to do -- means the DRIVER
-- considers this opcode's dispatch already finished (nothing was queued
-- synchronously), so it advances straight to the NEXT recorded opcode while
-- the actual blind selection + hand deal haven't happened yet. Confirmed
-- live: this let a recorded post-blind-select `discard` dispatch while
-- G.STATE was still SHOP and G.hand.cards was completely empty (0 cards) --
-- the single biggest source of the "could not resolve hand card ref" desync
-- warnings seen replaying real production matches, since it happens at every
-- round transition. Fixed the same way playback_launch.lua's own
-- _playback_handle_run_transition already handles an equivalent deferred-
-- wait case: pause the driver first, resume it only once the real action has
-- actually run.
-- Second wait phase after actually clicking select/skip blind: the hand deal
-- itself is a further async step (queues its own blocking events on a LATER
-- frame, not synchronously within this call) -- resuming the driver as soon
-- as the click itself returns can dispatch the NEXT recorded opcode (a
-- reorder/discard/play, expecting a full hand) while G.hand.cards is still
-- completely empty. Confirmed live: this let a reorder splice garbage into an
-- empty G.hand.cards, permanently breaking that reorder's own card-identity
-- registration (see the reorder handler's own comment below) even though the
-- reorder call itself didn't error -- a quiet data-corruption bug, not a
-- crash, which is exactly why it went unnoticed until traced back from a
-- much later "could not resolve" warning.
-- Confirmed live: the click that selects the blind (do_select_blind/skip_blind)
-- can silently no-op the very first time it fires here -- reproduced with
-- G.blind_select's own readiness predicate (offset.x == 0) already true, no
-- error thrown, yet G.STATE stayed BLIND_SELECT and G.hand stayed empty for
-- well over the ~0.2s+ vanilla's own select_blind takes internally (it queues
-- its own delayed events, see functions/button_callbacks.lua's select_blind:
-- a `trigger='before', delay=0.2` event that touches G.blind_select). Likely a
-- transient controller/UI lock left over from the blind-select screen's own
-- entrance animation that the existing readiness check doesn't account for.
--
-- Retrying the click is NOT simply idempotent, though: vanilla's select_blind
-- queues that same delayed event on every call, unconditionally, assuming
-- G.blind_select will still exist when it fires -- retrying every frame (or
-- any time a genuinely-successful first click just hasn't finished its own
-- 0.2s+ deferred chain yet) stacks up multiple overlapping event chains, and
-- once the FIRST one's own click actually completes and tears down
-- G.blind_select, every OTHER still-pending chain crashes indexing it as nil.
-- Confirmed live. Fixed with a real-time cooldown (RETRY_COOLDOWN_SECONDS)
-- between attempts, giving each click's own deferred chain time to either
-- finish naturally or prove it's truly stuck before trying again -- not a
-- frame-count throttle, since frame timing says nothing about vanilla's own
-- wall-clock delays.
local SELECT_BLIND_RETRY_LIMIT = 10
local SELECT_BLIND_RETRY_COOLDOWN_SECONDS = 1.0
local function wait_for_hand_dealt(driver, retry, callback)
	local attempts = 0
	local next_retry_at = love.timer.getTime() + SELECT_BLIND_RETRY_COOLDOWN_SECONDS
	SPDRN._playback_wait_for(function()
		if G.hand ~= nil and #G.hand.cards > 0 then
			return true
		end
		if love.timer.getTime() < next_retry_at then
			return false
		end
		-- Only re-click while genuinely still ON the blind-select screen: once
		-- the first click actually took, G.blind_select gets torn down as part
		-- of leaving that screen, and there's a real (if brief) further gap
		-- before G.hand is populated -- retrying blindly during that gap calls
		-- G.FUNCS.select_blind/skip_blind with a now-nil G.blind_select and
		-- crashes vanilla (see comment above).
		if G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil then
			attempts = attempts + 1
			if attempts > SELECT_BLIND_RETRY_LIMIT then
				-- Give up for real: resolve the wait anyway rather than hanging the
				-- driver forever. Whatever opcode comes next will most likely also
				-- fail (no hand to act on), but that's an existing, already-handled
				-- failure mode (see highlight_resolved_hand_indices's own warn-and-
				-- skip) -- a stuck driver is strictly worse than a few more skipped
				-- cards.
				MPAPI.sendWarnMessage('[replay] select_blind: hand never appeared after ' .. SELECT_BLIND_RETRY_LIMIT .. ' retries -- giving up and resuming anyway')
				return true
			end
			next_retry_at = love.timer.getTime() + SELECT_BLIND_RETRY_COOLDOWN_SECONDS
			retry()
		end
		return false
	end, callback)
end

-- skip_blind's own version of wait_for_hand_dealt above -- NOT a shared call
-- with select_blind, despite looking like it should be one at a glance (both
-- just "click the blind-select button and wait for it to take"). Confirmed
-- live: skip_blind used to reuse wait_for_hand_dealt verbatim, which waits on
-- `#G.hand.cards > 0` -- a condition skipping a blind never satisfies, since
-- skipping doesn't deal a hand at all, it just returns to BLIND_SELECT for
-- the NEXT blind. With no leftover hand cards sitting around from an earlier
-- round (the common case right after a shop visit fully consumes the hand --
-- see the reorder handler's own comment on leftover hand cards for the
-- opposite, non-empty case), that condition can NEVER become true, so every
-- one of wait_for_hand_dealt's retries fired: the SAME real skip click
-- (G.FUNCS.skip_blind, via the `retry` callback) got re-invoked up to
-- SELECT_BLIND_RETRY_LIMIT (10) more times, each one further advancing
-- G.GAME.blind_on_deck AGAIN -- vanilla's skip_blind has no idempotency
-- guard against being called on an already-skipped blind. A single recorded
-- skip (e.g. Big) silently fast-forwarded blind_on_deck several extra steps
-- past where the recording actually was, so the round REPLAY actually landed
-- on (whichever blind blind_on_deck happened to land on after ~10 unwanted
-- extra skips) no longer matched the recording's own Boss-blind round at
-- all -- surfacing several opcodes later as a totally unrelated-looking
-- "could not resolve" cascade on that round's use/discard/play, the same
-- deceptive-distance-from-root-cause failure mode documented on
-- resolve_own_card above. The correct success signal for a skip is "we're
-- back at a ready BLIND_SELECT screen for a DIFFERENT blind than before"
-- (mirroring ctx:skip_blind's own condition in ClaudeControl's own
-- api/actions.lua), not "a hand got dealt" -- skip_blind never deals one.
local function wait_for_skip_applied(driver, retry, callback, blind_before)
	local attempts = 0
	local next_retry_at = love.timer.getTime() + SELECT_BLIND_RETRY_COOLDOWN_SECONDS
	SPDRN._playback_wait_for(function()
		if G.GAME.blind_on_deck ~= blind_before and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil then
			return true
		end
		if love.timer.getTime() < next_retry_at then
			return false
		end
		-- Same crash-avoidance guard as wait_for_hand_dealt's own retry gate:
		-- only re-click while genuinely still on the blind-select screen.
		if G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil then
			attempts = attempts + 1
			if attempts > SELECT_BLIND_RETRY_LIMIT then
				MPAPI.sendWarnMessage('[replay] skip_blind: blind_on_deck never advanced after ' .. SELECT_BLIND_RETRY_LIMIT .. ' retries -- giving up and resuming anyway')
				return true
			end
			next_retry_at = love.timer.getTime() + SELECT_BLIND_RETRY_COOLDOWN_SECONDS
			retry()
		end
		return false
	end, callback)
end

-- Same "recorded opcode fires later than replay's own actual progress" class
-- of desync as cashout/with_shop_ready elsewhere in this file: a recorded
-- select_blind/skip_blind can dispatch after the replay has ALREADY moved
-- past blind-select into real round gameplay (G.STATE == SELECTING_HAND, a
-- full hand dealt) -- confirmed live. Waiting for G.STATE == BLIND_SELECT
-- forever in that case hangs the driver permanently, since blind-select
-- isn't coming back this round. Bounded the same way with_shop_ready is: give
-- up and resume (skipping this opcode's own action entirely -- there's
-- nothing sensible to click, we're already past this screen) after a
-- real-time timeout instead of waiting indefinitely.
local BLIND_SELECT_SCREEN_TIMEOUT_SECONDS = 10
local function wait_for_blind_select_screen(driver, on_ready)
	leave_shop_if_needed()
	local deadline = love.timer.getTime() + BLIND_SELECT_SCREEN_TIMEOUT_SECONDS
	SPDRN._playback_wait_for(function()
		if G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil and G.blind_select.alignment.offset.x == 0 then
			return true
		end
		if love.timer.getTime() >= deadline then
			MPAPI.sendWarnMessage('[replay] blind-select screen never appeared after ' .. BLIND_SELECT_SCREEN_TIMEOUT_SECONDS .. 's -- replay has likely already moved past it, skipping this action')
			return true
		end
		return false
	end, function()
		if G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil then
			on_ready()
		elseif driver then
			driver:play()
		end
	end)
end

MPAPI.playback.register_handler('spdrn', 'select_blind', function(_args, ctx)
	if not ctx.is_pov then return end
	local driver = ctx.driver
	if driver then driver:pause() end
	wait_for_blind_select_screen(driver, function()
		do_select_blind()
		wait_for_hand_dealt(driver, do_select_blind, function()
			if driver then driver:play() end
		end)
	end)
end)

MPAPI.playback.register_handler('spdrn', 'skip_blind', function(_args, ctx)
	if not ctx.is_pov then return end
	local driver = ctx.driver
	if driver then driver:pause() end
	wait_for_blind_select_screen(driver, function()
		local blind_before = G.GAME.blind_on_deck
		local function do_skip_blind()
			-- vanilla's skip reads the tag from the first tag_container of the UIBox it is handed;
			-- G.blind_select holds all three panels, so its first one is always the Small blind's.
			-- Hand it the current blind's own panel (a replayed Big skip granted the Small tag).
			local panel = G.blind_select_opts and G.blind_select_opts[string.lower(G.GAME.blind_on_deck or 'Small')]
			G.FUNCS.skip_blind({ UIBox = panel or G.blind_select })
		end
		do_skip_blind()
		wait_for_skip_applied(driver, do_skip_blind, function()
			if driver then driver:play() end
		end, blind_before)
	end)
end)

-- Confirmed live against a real, flagged (hash_mismatch) production match: a
-- recorded play whose EVERY card ref failed to resolve (a full desync, not
-- just a partial one) left G.hand.highlighted completely empty, but this
-- still called G.FUNCS.play_cards_from_highlighted() unconditionally --
-- vanilla has no empty-hand guard on that path (the real UI only ever gets
-- there via the Play button, which is disabled with nothing highlighted), so
-- it crashed deep in evaluate_play (functions/state_events.lua:589, "attempt
-- to index a nil value" on an empty scoring_hand). A PARTIAL resolve (some
-- but not all cards) is fine to play through as-is -- that's the existing
-- per-card skip-and-warn behavior in highlight_resolved_hand_indices -- only
-- the all-failed case needs its own guard here, since vanilla can't handle a
-- literally empty selection.
MPAPI.playback.register_handler('spdrn', 'play', function(args, ctx)
	if not ctx.is_pov then return end
	local indices, refs = args and args[1], args and args[2]
	if not indices then return end
	highlight_resolved_hand_indices(indices, refs, ctx, 'play')
	-- G.hand can be nil here too (highlight_resolved_hand_indices already
	-- warned and no-opped in that case, above) -- checked via G.hand's own
	-- presence rather than assuming it survived that call, not just #==0.
	local highlighted = G.hand and G.hand.highlighted
	if not highlighted or #highlighted == 0 then
		if G.hand then
			MPAPI.sendWarnMessage('[replay] play: no cards resolved out of ' .. #indices .. ' -- replay has desynced from the recording, skipping this play entirely')
		end
		return
	end
	G.FUNCS.play_cards_from_highlighted()
end)

MPAPI.playback.register_handler('spdrn', 'discard', function(args, ctx)
	if not ctx.is_pov then return end
	local indices, refs = args and args[1], args and args[2]
	if not indices then return end
	highlight_resolved_hand_indices(indices, refs, ctx, 'discard')
	local highlighted = G.hand and G.hand.highlighted
	if not highlighted or #highlighted == 0 then
		if G.hand then
			MPAPI.sendWarnMessage('[replay] discard: no cards resolved out of ' .. #indices .. ' -- replay has desynced from the recording, skipping this discard entirely')
		end
		return
	end
	G.FUNCS.discard_cards_from_highlighted(nil, false)
end)

-- Registers a card's OWN identity ref (not a hand-target ref) into the shared
-- resolver -- sell/buy/use/pack_pick all record one (args[3], previously
-- unused on replay) for the specific card being acted on. Same rationale as
-- reorder's own registration above: RLOG.card_ref's id counter is shared
-- across every opcode, so a card first-referenced here (e.g. a Standard
-- Pack's playing-card pick, or a joker later sold/discarded elsewhere) must
-- be learned here too, or a later "already-seen" reference to it elsewhere
-- permanently fails to resolve.
-- Resolves the PRIMARY card an opcode acts on (not a hand-target -- see
-- highlight_resolved_hand_indices for that) by identity when a ref was
-- recorded, falling back to the plain positional lookup only when there's no
-- ref at all (pre-existing recordings). Confirmed live: sell/buy/use/pack_pick
-- used to resolve their own card purely by area.cards[idx] (only registering
-- the ref for OTHER opcodes' future lookups, never using it for their own
-- resolution) -- if that area's order has drifted even slightly from an
-- earlier, unrelated divergence (a different purchase/use order shifting
-- positions), this silently acted on a COMPLETELY DIFFERENT card than the one
-- actually recorded. Traced live to a real production match: a `use` resolved
-- the wrong Tarot card by position, which then converted a target playing
-- card to the wrong suit -- surfacing several opcodes later as a totally
-- unrelated-looking "wrong card dealt" desync warning.
local function resolve_own_card(ctx, ref, area, idx, opcode)
	if not ref then
		return area and area.cards and area.cards[idx]
	end
	local resolver = ctx.card_resolver
	local card = resolver and MPAPI.replay.resolve_card_ref(resolver, ref, area and area.cards or {})
	if not card then
		MPAPI.sendWarnMessage(
			'[replay] ' .. tostring(opcode) .. ': could not resolve this action\'s own card ref -- replay has desynced from the recording, skipping this action'
		)
	end
	return card
end

MPAPI.playback.register_handler('spdrn', 'sell', function(args, ctx)
	if not ctx.is_pov then return end
	local area_id, idx, ref = args and args[1], args and args[2], args and args[3]
	local card = resolve_own_card(ctx, ref, area_object(area_id), idx, 'sell')
	if card then
		card:sell_card()
		SMODS.calculate_context({ selling_card = true, card = card })
	end
end)

-- buy/open_pack/voucher all draw their card from a SHOP area (shop_jokers/
-- shop_booster/shop_vouchers, per area_object above) -- gated on with_shop_ready
-- for the same reason reroll is below, since resolving against a not-yet-
-- populated shop area would silently pick the wrong (or no) card, same class
-- of hazard as the hand-card resolution fix elsewhere in this file, just for
-- the shop instead of the hand.
-- Confirmed live: vanilla's own G.FUNCS.buy_from_shop calls
-- G.FUNCS.check_for_buy_space(c1) unless e.config.id == 'buy_and_use' --
-- and that check ONLY recognizes Voucher/Enhanced/Default/Joker/consumeable
-- cards as things it knows how to validate space for. A Booster Pack is none
-- of those (card.ability.set == 'Booster', card.ability.consumeable is nil),
-- so the check unconditionally fails and buy_from_shop silently returns
-- false -- no error, nothing added anywhere -- UNLESS the buy_and_use id is
-- set, which is how the real "BUY" button on a pack card is actually wired
-- (functions/UI_definitions.lua). The recorded `open_pack` opcode never
-- captured this id (it wasn't part of the RLOG_CODE's write shape at all,
-- and doesn't need to be -- every open_pack IS a Booster Pack purchase by
-- construction, since that's the opcode key generic_codes.lua's own
-- buy_from_shop hook chooses specifically because the card's set is
-- 'Booster'). Every replayed open_pack was therefore silently failing to
-- buy anything, permanently starving that player's consumeables/pack
-- pipeline for the rest of the match -- traced live to a real production
-- match's replay expecting a Booster Pack that no recorded action appeared
-- to ever add.
-- buy_and_use's own vanilla implementation opens the pack via a further
-- G.E_MANAGER-deferred chain (functions/button_callbacks.lua's buy_from_shop,
-- id == 'buy_and_use' branch calls G.FUNCS.use_card internally, itself async)
-- -- NOT synchronously within this call. Without waiting for it, the driver
-- resuming immediately can dispatch the recorded pack_pick that's supposed to
-- choose from this exact pack before G.pack_cards is actually populated,
-- same "driver races ahead of an async vanilla operation" hazard as
-- with_shop_ready itself, select_blind's hand-dealt wait, etc. elsewhere in
-- this file. Confirmed live. (The original recording also has a separate,
-- now-redundant `use` opcode for this same purchase -- vanilla's buy_and_use
-- internally calling use_card gets caught by the SAME hook that records a
-- normal manual "use" -- which is harmless on replay: by the time it
-- dispatches the card's already fully consumed by this buy, so it correctly
-- no-ops via resolve_own_card's own desync warning rather than doing
-- anything wrong.)
local function replay_buy(args, ctx)
	if not ctx.is_pov then return end
	local driver = ctx.driver
	with_shop_ready(ctx, function()
		local area_id, idx, ref = args and args[1], args and args[2], args and args[3]
		local card = resolve_own_card(ctx, ref, area_object(area_id), idx, 'buy')
		if not card then return false end
		local is_booster = card.ability and card.ability.set == 'Booster'
		-- args[5]: the player pressed "Buy & Use" (a consumable bought and used at once).
		-- Logs from before the flag existed have no args[5] and replay as a plain buy.
		local bought_and_used = args and args[5] == true
		G.FUNCS.buy_from_shop({ config = { id = (is_booster or bought_and_used) and 'buy_and_use' or nil, ref_table = card } })
		if not is_booster then return false end
		if driver then driver:pause() end
		SPDRN._playback_wait_for(function()
			return G.pack_cards ~= nil and #G.pack_cards.cards > 0
		end, function()
			if driver then driver:play() end
		end)
		return true
	end)
end
MPAPI.playback.register_handler('spdrn', 'buy', replay_buy)
MPAPI.playback.register_handler('spdrn', 'open_pack', replay_buy)
MPAPI.playback.register_handler('spdrn', 'voucher', replay_buy)

MPAPI.playback.register_handler('spdrn', 'use', function(args, ctx)
	if not ctx.is_pov then return end
	local idx, targets, ref, target_refs = args and args[1], args and args[2], args and args[3], args and args[4]
	local card = resolve_own_card(ctx, ref, G.consumeables, idx, 'use')
	if not card then return end
	if targets then highlight_resolved_hand_indices(targets, target_refs, ctx, 'use') end
	G.FUNCS.use_card({ config = { ref_table = card } })
end)

MPAPI.playback.register_handler('spdrn', 'pack_pick', function(args, ctx)
	if not ctx.is_pov then return end
	local idx, targets, ref, target_refs = args and args[1], args and args[2], args and args[3], args and args[4]
	local card = resolve_own_card(ctx, ref, G.pack_cards, idx, 'pack_pick')
	if not card then return end
	if targets then highlight_resolved_hand_indices(targets, target_refs, ctx, 'pack_pick') end
	G.FUNCS.use_card({ config = { ref_table = card } })
end)

MPAPI.playback.register_handler('spdrn', 'pack_skip', function(_args, ctx)
	if ctx.is_pov then G.FUNCS.skip_booster({ config = {} }) end
end)

-- Confirmed live: G.shop_jokers.cards can read nil at the exact moment a
-- recorded reroll dispatches (even well into an otherwise-normal shop visit,
-- not just immediately after cash_out), crashing vanilla's own reroll_shop
-- ("attempt to get length of field 'cards' (a nil value)",
-- functions/button_callbacks.lua, inside reroll_shop's own deferred
-- G.E_MANAGER event, per the lovely game-dump).
MPAPI.playback.register_handler('spdrn', 'reroll', function(_args, ctx)
	if not ctx.is_pov then return end
	with_shop_ready(ctx, function()
		G.FUNCS.reroll_shop({ config = {} })
	end)
end)

-- reorder's perm is "new-position -> old-index" (SPDRN.RLOG_UTILS.reorder_permutation):
-- new_cards[j] = old_cards[perm[j]]. Same direct-splice technique as PvP's
-- equivalent handler (mirrors vanilla's own sort-button pattern).
--
-- `moved` entries are {ref, old_pos, new_pos} (RLOG.card_ref, recorded at write
-- time in api/replay/generic_codes.lua's CardArea:update hook) for every card
-- whose position actually changed. RLOG.card_ref's id counter is GLOBAL across
-- every opcode that ever references a card (play/discard/sell/buy/use/
-- pack_pick/pack_skip/reorder, all of them) -- a card CAN be first-referenced
-- here, in a reorder, rather than in a play/discard/use-target. Registering
-- these refs into ctx.card_resolver (even though the splice below doesn't
-- itself need identity resolution -- perm is already positional and correct)
-- keeps the replay's resolver in sync with the recording's own id-space.
-- Confirmed live: without this, a card whose id was first assigned via a
-- reorder is never learned by the resolver, so every LATER "already-seen"
-- reference to that same physical card (an ordinary discard/play, potentially
-- many rounds later) permanently fails to resolve -- the single largest
-- source of residual "could not resolve hand card ref" warnings once the
-- shop/round-transition timing bugs elsewhere in this file were fixed.
-- Confirmed live: a recorded hand reorder can legitimately fire while the
-- player is browsing the shop -- vanilla doesn't clear leftover (unplayed)
-- hand cards on cash_out, they just sit there hidden until the next round's
-- deal overwrites them, and idly sorting them mid-shop is a real (if
-- pointless) action a player can take. If replay's OWN hand ended up fully
-- consumed by the time this fires (e.g. an earlier, unrelated small
-- divergence caused this round to use one more discard/play than the
-- original before winning, leaving nothing behind), `old_cards` won't match
-- `perm`'s expected length -- splicing anyway would write nils into
-- area.cards (corrupting it for whatever reads it next) and can never
-- register any of `moved`'s refs correctly. Skip the whole opcode rather than
-- guess: this is strictly better than a corrupted area, even though it means
-- any card first-referenced by a skipped reorder stays unresolvable later.
-- Same guard applies when old_cards is LONGER than perm, not just shorter:
-- RLOG.reorder_permutation (MPAPI's area_utils.lua) only ever produces a perm
-- when the recorder's own old/new counts matched exactly, so any mismatch
-- either direction means this replay has already desynced. An earlier skipped
-- opcode (a sell/discard/play/use whose own card ref failed to resolve) can
-- leave extra cards behind that the original recording no longer had at this
-- point -- splicing against a too-long old_cards silently drops every card
-- beyond #perm from area.cards (new_cards below is only ever built out to
-- #perm), the same data loss as the too-short case, just silent instead of
-- an obvious nil-splice.
MPAPI.playback.register_handler('spdrn', 'reorder', function(args, ctx)
	if not ctx.is_pov then return end
	local area_id, perm, moved = args and args[1], args and args[2], args and args[3]
	local area = area_object(area_id)
	if not (area and perm) then return end
	local old_cards = area.cards
	if not old_cards or #old_cards ~= #perm then
		-- Every OTHER skip-and-recover path in this file (with_shop_ready,
		-- wait_for_hand_dealt/wait_for_skip_applied, resolve_own_card,
		-- highlight_resolved_hand_indices, cashout's own timeouts) warns loudly
		-- when it gives up rather than acting -- this guard used to be the one
		-- silent exception, which would leave a real desync invisible in the
		-- lovely log to anyone diagnosing a later "could not resolve" cascade
		-- (the card(s) this skipped reorder should have registered into
		-- ctx.card_resolver never get learned, so THEIR eventual failure is
		-- what actually surfaces, several opcodes later and looking unrelated --
		-- same deceptive-distance problem documented on resolve_own_card
		-- above). Warn here too, matching house style.
		if old_cards then
			MPAPI.sendWarnMessage(
				'[replay] reorder: area ' .. tostring(area_id) .. ' has ' .. #old_cards
					.. ' cards but the recording expected ' .. #perm
					.. ' -- replay has desynced from the recording, skipping this reorder'
			)
		end
		return
	end
	local new_cards = {}
	for j = 1, #perm do
		new_cards[j] = old_cards[perm[j]]
	end
	area.cards = new_cards
	if area.set_ranks then area:set_ranks() end

	local resolver = ctx.card_resolver
	if resolver and moved then
		for _, entry in ipairs(moved) do
			local ref, new_pos = entry[1], entry[3]
			local card = new_pos and new_cards[new_pos]
			if ref and card then
				MPAPI.replay.resolve_card_ref(resolver, ref, { card })
			end
		end
	end
end)

-- Same driver-pacing hazard as select_blind/skip_blind above: cash_out's real
-- effect is normally the ROUND_EVAL -> SHOP transition, which builds
-- G.shop_jokers/etc asynchronously (not synchronously within this call) --
-- without waiting for it, the driver's next dispatched opcode (buy/reroll/
-- sell/pack_pick/pack_skip targeting the still-nil shop areas) can run before
-- the shop actually exists. Confirmed live: a replayed reroll crashed with
-- "attempt to get length of field 'cards' (a nil value)"
-- (functions/button_callbacks.lua:2925) from exactly this gap.
--
-- Accepts either "reached the fully-built shop" (the normal case -- still
-- gated on G.shop_jokers.cards specifically, not just G.shop_jokers existing:
-- confirmed live that G.shop_jokers itself can be non-nil (the CardArea
-- object constructed) while .cards is still nil (not yet populated), and a
-- reroll dispatched into that gap crashes vanilla's reroll_shop with "attempt
-- to get length of field 'cards' (a nil value)" -- functions/button_callbacks.lua,
-- inside reroll_shop's own deferred G.E_MANAGER event, per the lovely
-- game-dump) OR "left ROUND_EVAL for some state that isn't SHOP at all": a
-- match-winning cash-out (e.g. clearing the final ante) skips the shop
-- entirely and goes straight to a win/end-of-run sequence instead -- confirmed
-- live that a SHOP-only predicate here hangs forever on exactly that cash-out,
-- since G.STATE never becomes SHOP for it.
-- Bounded the same way as the other waits in this file: cash_out is the most
-- reliable of the bunch in practice, but nothing here guarantees the replay
-- hasn't already drifted past this round entirely -- give up after a
-- real-time timeout rather than risk hanging forever on an edge case not yet
-- seen live.
local CASHOUT_TRANSITION_TIMEOUT_SECONDS = 10

-- The Cash Out button is its own UIBox, built by a delayed event some time after the
-- round_eval screen. A player can only press it once it exists. If the replay calls cash_out
-- earlier, G.round_eval is removed first and the button UIBox is then built with no major
-- to follow: it stays forever, off screen (one leaked UIBox per round). Confirmed live:
-- one orphan per replayed cash-out, none in live play.
local function find_cash_out_button()
	for _, box in pairs(G.I.UIBOX) do
		local found
		local function walk(node)
			if found or not node then return end
			if node.config and node.config.button == 'cash_out' then found = node return end
			for _, child in ipairs(node.children or {}) do walk(child) end
		end
		walk(box.UIRoot)
		if found then return found end
	end
end

-- True when the Cash Out wait can end: the button exists, the round was already cashed out
-- (no round_eval and the state is past ROUND_EVAL), or time ran out. The same "no
-- round_eval" holds before the round is evaluated, so those states keep waiting.
function SPDRN._cashout_wait_over(button_exists, round_eval_built, state, timed_out)
	if button_exists or timed_out then return true end
	local S = G.STATES
	local before_round_eval = state == S.SELECTING_HAND or state == S.HAND_PLAYED or state == S.DRAW_TO_HAND or state == S.NEW_ROUND
	return not round_eval_built and state ~= S.ROUND_EVAL and not before_round_eval
end

MPAPI.playback.register_handler('spdrn', 'cashout', function(_args, ctx)
	if not ctx.is_pov then return end
	local driver = ctx.driver
	if driver then driver:pause() end
	local button_deadline = love.timer.getTime() + CASHOUT_TRANSITION_TIMEOUT_SECONDS
	SPDRN._playback_wait_for(function()
		return SPDRN._cashout_wait_over(find_cash_out_button() ~= nil, G.round_eval ~= nil, G.STATE, love.timer.getTime() >= button_deadline)
	end, function()
		G.FUNCS.cash_out(find_cash_out_button() or { config = {} })
		SPDRN._await_cashout_transition(driver)
	end)
end)

function SPDRN._await_cashout_transition(driver)
	local deadline = love.timer.getTime() + CASHOUT_TRANSITION_TIMEOUT_SECONDS
	SPDRN._playback_wait_for(function()
		if G.STATE == G.STATES.ROUND_EVAL then
			if love.timer.getTime() >= deadline then
				MPAPI.sendWarnMessage('[replay] cashout: still in ROUND_EVAL after ' .. CASHOUT_TRANSITION_TIMEOUT_SECONDS .. 's -- giving up and resuming anyway')
				return true
			end
			return false
		end
		if G.STATE == G.STATES.SHOP then
			if G.shop_jokers ~= nil and G.shop_jokers.cards ~= nil then return true end
			if love.timer.getTime() >= deadline then
				MPAPI.sendWarnMessage('[replay] cashout: shop never became ready after ' .. CASHOUT_TRANSITION_TIMEOUT_SECONDS .. 's -- giving up and resuming anyway')
				return true
			end
			return false
		end
		return true
	end, function()
		if driver then driver:play() end
	end)
end

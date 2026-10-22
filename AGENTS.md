# AGENTS.md

SPDRN: Balatro speedrun-race mod (Lua, Steamodded + Lovely). Mod id `MultiplayerSPDRN`, prefix
`spdrn`, global `SPDRN`. Everything networked (lobbies, matchmaking, actions, replays, ratings,
ban/pick) is MPAPI's (`BalatroMultiplayerAPI`, a sibling repo); this repo supplies gamemodes, UI
and match logic. The server side, including the Nakama runtime, is `BalatroMultiplayerServer`.
README.md has the gamemode list and folder map.

## Load order and where things go

- `core.lua` loads `domain/` and `ui/` at mod load, then `objects/` inside `MPAPI.on_loaded`.
  Registrations that need MPAPI fully up (`MPAPI.GameMode`, `MPAPI.Ruleset`, actions, providers)
  go in `objects/`. `MPAPI.on_loaded` only fires with the Steam client running, so without Steam
  nothing in `objects/` loads and SPDRN silently does nothing. File order within a directory is
  not guaranteed, so file-scope code must not depend on a sibling file having loaded.
- New gamemode: add its key to `domain/gamemode.lua`, an `MPAPI.GameMode` in
  `objects/gamemodes/`, and a pillar in `ui/main_menu/game_select.lua` (`PRACTICE_LOBBY_MODES`,
  plus `FIND_GAME_MODES` if matchmade). Casual entries in `FIND_GAME_MODES` automatically
  become group-queueable.
- Per-frame polling (wall-clock timers, deferred run starts, loss detection) lives in the
  `Game:update` hook in `core.lua`. Each check is `pcall`ed, so its errors are swallowed silently;
  each must return early unless SPDRN is active.

## Coding style

1. Self-describing names; comments only for a non-obvious *why* (the existing long comments
   record live-confirmed failures; keep them accurate when you change the code they explain).
2. Structure as namespace: hang functions off `SPDRN.<area>` tables and module-local `local`s,
   and let the folder say what a file is about.
3. One responsibility per file and function; split UI building from the action it triggers.
4. Depend on contracts: reach networking, storage and the server only through MPAPI.
5. Errors as values at I/O boundaries: network/file calls return `ok, err` or a result table that
   the caller handles; keep `error()` for programmer mistakes.
6. Domain concepts are named constants (`SPDRN.Gamemode`, `SPDRN.Ruleset`, `SPDRN.LobbyKind`,
   `SPDRN.Deck`), referenced by name rather than as string literals.
7. Pure computation (seed derivation, result ranking, pools) separated from effects (UI, network,
   `G` mutation) so it can run against fake data.

Format with StyLua (`stylua.toml`: tabs, single quotes, 240 columns).

## Gotchas

- **Run transitions**: start or restart a run through `SPDRN.request_run_transition`
  (`ui/lobby/run_start.lua`), which runs it on the next `Game:update` tick, never from inside a
  queued `Event`.
  `G.FUNCS.start_run` clears the event queue, and doing that mid-iteration black-screens the game.
  A gamemode's own `start_run` calls `SPDRN.teardown_existing_run()` first so a stale blind HUD
  can't crash the next run.
- **Same seed for everyone**: multi-run modes get each run's seed from
  `SPDRN.derive_seed(base_seed, run_idx)`; deck pools must be identical on every client, so
  filter mod decks (`center.mod`) and other mods' content (`MPAPI.should_exclude_from_pool`).
- **Ban/pick pool items** that share a deck key (Challenge tiles) need a unique `id`; ban/pick
  tracks state by `id` when present, otherwise every tile with that key is banned at once.
- **Win detection** is `calculate` on `context.ante_change` reaching ante 9, guarded by a
  once-per-run flag that resets below ante 9. Beating ante 8 also fires vanilla `win_game`,
  which `core.lua` suppresses while an SPDRN lobby is active.
- **Trust the sender**: actions that decide a match wrap their receiver in
  `SPDRN.Sender.host_only` (`domain/sender.lua`). The server enforces the same rule; the client
  check is the second layer.
- **Coexistence with PvP**: both mods share MPAPI's global hooks and playback drivers. Gate hooks
  on `SPDRN.is_active()` and ask about replays with `SPDRN.is_replay_driving()` (namespaced),
  never by inspecting the shared driver table.
- **Lobby kind** is read from `SPDRN._lobby_kind` (`ui/lobby/kind.lua`), set synchronously by
  every entry path; lobby metadata arrives async. Practice is client-only and is neither
  matchmaking nor private.
- **Queue keys**: the wire game_mode is the bare gamemode key for casual and `ranked:<key>` for
  ranked (`SPDRN.LobbyKind.RANKED_PREFIX`); the server reads anything unprefixed as casual.
- Comments citing `§16.x` / `§17.x` refer to the platform roadmap, which lives outside this repo.

## Verifying changes

There is no in-repo test runner. Verify against live game instances with the ClaudeControl mod
and its `cctl` CLI: deploy the changed files to the game's `Mods` folder, run the SPDRN suites
(and the PvP ones when touching shared hooks), and pilot the changed flow end to end (queue, draft,
run transitions, results). For anything networked, use at least two instances against a local
server. Unit-level checks of pure functions can run in `cctl eval` / `cctl script`.

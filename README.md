# Multiplayer Speedrunning (SPDRN)

A Balatro mod for real-time speedrun races. Everyone in a match plays the same seed, deck and
stake at the same time; the first player to beat the ante 8 boss (reach ante 9) in every run of
the format wins. Players who don't finish are ranked by how far they got.

SPDRN is one gamemode mod on the **Balatro Multiplayer Platform**. Lobbies, matchmaking,
networking, replays and ratings come from
[Balatro Multiplayer API](https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI) (MPAPI),
which is a **required dependency**.

## Install

1. Install [Lovely](https://github.com/ethangreen-dev/lovely-injector) (0.8 or newer) and
   [Steamodded](https://github.com/Steamodded/smods) (1.0.0~BETA-1814a or newer).
2. Install [Balatro Multiplayer API](https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI).
3. Put this repository's folder in your Balatro `Mods` directory.
4. Launch the game and open **Speedrun** from the multiplayer menu.

SPDRN conflicts with the old standalone `Multiplayer` mod; remove it first. It runs alongside
the PvP mod ([BalatroMultiplayerPvP](https://github.com/Balatro-Multiplayer/BalatroMultiplayerPvP)).

## Gamemodes

| Gamemode | Format |
|----------|--------|
| White Stake Triple | Three White Stake runs, one drafted deck each; finish all three first. Ranked and casual. 45-minute cap. |
| Gold Stake Single | One Gold Stake run on a drafted deck. Ranked and casual. 25-minute cap. |
| Stake Climb | Eight runs on the same deck, climbing from White Stake to Gold Stake. |
| Challenge | One run of a challenge picked by a ban draft from five random challenges. |
| All Deck | One White Stake run on every vanilla deck; the ban draft decides the order. |
| Seed Scout | 60 seconds of free play with $500 on the match's seed, deck and stake, then the real race on that same seed. |

Multi-run formats derive each run's seed from one match seed, so every player gets the same
sequence. White Stake Triple, Stake Climb and Seed Scout lock the seed for the whole match.

## Ways to play

- **Find Game**: queue for White Stake Triple or Gold Stake Single.
  - **Casual**: 2 to 16 players, no rating change.
  - **Ranked**: up to 4 players, Elo rated per gamemode. Needs the server to have verified your
    client; the Ranked buttons stay disabled until it has.
- **Group queue**: the host of a private lobby queues the whole lobby into a casual match, and
  everyone returns to that lobby afterwards.
- **Create Lobby / Join**: private lobbies for any gamemode, shared by code. The host picks the
  deck, the ruleset (*The Order*, which keeps shop and card RNG identical across players, or
  *Vanilla*) and whether the duration cap applies.
- **Practice**: an offline solo run of any gamemode, with no server lobby.

During a match players can vote to change the seed or to end the match as a draw, or forfeit.
Matches are recorded: **My Replays** plays a past match back from any player's view, and a
crashed client can rejoin a match still in progress. A leaderboard shows the fastest times per
gamemode.

## Speedrun timer

An on-screen timer counts up the run time. If the
[SystemClock](https://github.com/Breezebuilder/SystemClock) mod is installed, the timer takes
over that clock for the match, keeping your SystemClock style and position, and returns it to the
system time when the run ends. Without SystemClock a built-in clock is shown.

## Repository layout

| Path | Contents |
|------|----------|
| `core.lua` | Entry point: loads files, registers pages and the mod with MPAPI, installs game hooks |
| `domain/` | Enum-like constants (gamemodes, rulesets, lobby kinds, decks) and the sender guard |
| `objects/gamemodes/` | One `MPAPI.GameMode` per gamemode |
| `objects/rulesets/` | The Order and Vanilla rulesets |
| `objects/actions/` | Networked lobby/match actions (ready, start, results, votes, forfeit, ban/pick) |
| `objects/matchmaking/` | Queues, group queue, results ranking, progress, duration cap, enemy location |
| `objects/replay_log/` | Replay recording, the replay browser, playback and crash rejoin |
| `ui/main_menu/` | Speedrun menu, gamemode select, Find Game, Create/Join, Practice |
| `ui/lobby/` | In-lobby view, options, seed/deck pickers, votes, run start and restarts |
| `ui/timer/` | Speedrun timer and the SystemClock integration |
| `ui/` (other) | Win/lose/timeout screens, leaderboard, enemy location HUD, pickers |
| `localization/`, `assets/` | Strings and sprites |

## Legacy version

The pre-Nakama version of SPDRN, which ran on the older MQTT-based server, is kept unchanged on
the [`legacy`](https://github.com/Balatro-Multiplayer/BalatroMultiplayerSpeedrunning/tree/legacy)
branch. `main` is the current version.

## License

This mod is licensed under the **GNU General Public License v3.0** (see [LICENSE](LICENSE)).

The on-screen clock UI in [ui/timer/clock_ui.lua](ui/timer/clock_ui.lua) is a minimal, modified
adaptation of the **SystemClock** mod by **Breezebuilder**
(https://github.com/Breezebuilder/SystemClock), used with permission and under GPL-3.0. Many
thanks to Breezebuilder for the clock UI and for allowing its reuse.

Authors: Virtualized, Bean, ArtifexDigital.

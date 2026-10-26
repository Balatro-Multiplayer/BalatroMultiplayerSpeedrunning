![ModIcon](assets/2x/modicon.png)

# Balatro Multiplayer Speedrunning

Head-to-head Balatro Speedrunning. There are many ways to play but generally 2-16 people in a lobby face off on the same seed, the first one to get to the end of the seed wins.

This is the Speedrunning mod of the Balatro Multiplayer Platform. It runs on top of [MultiplayerAPI](https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI), which owns the connection, accounts, lobbies, matchmaking, and leaderboards. Sibling mods on the same API include [PvP](https://github.com/Balatro-Multiplayer/BalatroMultiplayerPvP). The server lives in [BalatroMultiplayerServer](https://github.com/Balatro-Multiplayer/BalatroMultiplayerServer).

## Installation

### Launchers

Launchers are the easiest ways to get modded Balatro running quickly. We have two main launchers we support:

#### R2 Mod Man

We recommend downloading the mod with r2mm if you intend to play it casually. You can download r2mm here: [https://r2modman.com/](https://r2modman.com/)

#### BET

Otherwise you can use own custom closed source launcher called BET, which is intended to be a successor of BMM. You can download BET here: [https://new.balatromp.com/download](https://new.balatromp.com/download)

### Manual

Requirements:

- [Steamodded](https://github.com/Steamodded/smods) (>= 1.0.0~BETA-1814a)
- [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) (>= 0.10)
- [MultiplayerAPI](https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI) (required dependency)
- Balatro running through Steam (the API signs in with your Steam account)

Steps:

1. Install Steamodded, Lovely and MultiplayerAPI.
2. Download the latest release of this mod from the [Releases page](https://github.com/Balatro-Multiplayer/BalatroMultiplayerSpeedrunning/releases).
3. Extract it into its own folder in your Balatro `Mods` directory. Make sure the folder is not nested inside a second folder of the same name.
4. Launch the game and pick **Speedrun** from the multiplayer menu.

## AI Content Disclaimer

This mod does NOT use AI for art or other assets. This mod uses generative AI in it's development as a tool for writing code.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup and guidelines.

Content changes (new cards, blinds, rulesets, formats, or anything that alters competitive balance) are heavily scrutinized, so open an issue or ask on Discord first. Bug fixes and quality-of-life work are always welcome, check the [issues](https://github.com/Balatro-Multiplayer/BalatroMultiplayerSpeedrunning/issues), especially those tagged "Help Wanted".

Testing happens against real, running game instances: launch two or more clients, put them in a lobby and play the change through.

## License

GNU General Public License v3.0. See [LICENSE.md](LICENSE.md).

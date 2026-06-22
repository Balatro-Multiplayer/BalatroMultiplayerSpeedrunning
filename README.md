# Multiplayer Speedrunning

A Balatro mod that lets players compete in real-time speedrun matches. Built on the
Balatro Multiplayer API (MultiplayerAPI).

## On-screen speedrun timer

During a match an on-screen timer counts up the elapsed run time. If you have the
[SystemClock](https://github.com/Breezebuilder/SystemClock) mod installed, the timer takes
over your existing clock for the duration of the match — using all of your SystemClock
styling, position and customization — and reverts to showing the system time when the run
ends. SystemClock is optional; without it, a built-in clock is shown instead.

## License

This mod is licensed under the **GNU General Public License v3.0** (see [LICENSE](LICENSE)).

The on-screen clock UI in [ui/speedrun_timer.lua](ui/speedrun_timer.lua) is a minimal,
modified adaptation of the **SystemClock** mod by **Breezebuilder**
(https://github.com/Breezebuilder/SystemClock), used with permission and under GPL-3.0.
Many thanks to Breezebuilder for the great clock UI and for allowing its reuse.

Authors: Virtualized, Bean, ArtifexDigital.

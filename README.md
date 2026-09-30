# HD2 Stratagem Hotkeys 0.1.0-test

Hold your game's Stratagem List key, then press number-row 1, 2, 3 or 4.
The addon inputs the equipped slot's direction command. Aim and throw manually.
Keep the list key held until the command finishes. Release it to cancel.
The current player's four loadout slots, command definitions and saved keyboard
bindings are read from the game. No HUD+, Helper preset or stratagem catalog is required.

## Install

1. Close Helldivers 2. Import the release ZIP into Arsenal.
2. Enable this addon and Bingus Shared Loader v18 / API 1.
3. Under default Arsenal priority, put the shared loader last. Purge / Deploy.
4. Restart the game. Do not enable two copies of this addon.

When also using HD2 AutoReload, update that addon to 0.3.24-test or newer.
This prevents the command shortcuts from starting weapon-switch reload checks.
The mods own separate Lua resources and preserve the existing update/shutdown chains.
Neither boot nor content/input.config is replaced. Mod Bindings Menu is not a dependency.

## Test Scope

This is an initial experimental release, not a live gameplay certification.
Offline tests cover reader bounds, identity checks, saved binding changes,
sequence timing, cancellation, key release, callback chaining and input conflicts.
Actual mission loadout order, host/client play and ball preparation still need a live test.

Supported binaries: Steam build 25480438 / EXE 1.8.46015.0, guarded by both file hashes.
The first release supports a keyboard Hold binding for opening the list and Press
bindings for the four directions. It declines unbound, modified, controller-only,
mouse-only, duplicated or unsupported mappings rather than guessing keys.
Number-row keys are distinct from Numpad keys. A command is not repeated while a number is held.
Direction keys already held, fire, Enter, Escape, another menu or loss of game focus cancel/block input.
Input steps hold and release for at least 15 ms and one update each; there is no busy wait.
The addon does not bypass cooldowns, ammunition, jammers or game restrictions.
Game memory is read only; only normal keyboard input is generated. No mouse throw is generated.

Log: `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/hd2_helper_stratagem_hotkeys.log`.
Look for `COMMAND slot=... kind=...`, then `command-complete`.
`SKIP` / `WAIT` record a refused input and its reason.

## Build

Run `node build.cjs`, then `./test.ps1 -LuaDll '../bin/lua51.dll'` on Windows.
Package only `dist/HD2-Stratagem-Hotkeys-0.1.0-test/*`; never package scratch captures.
The optional tools read local game references for research without changing game state.

AI-assisted implementation and documentation.

# HD2 Stratagem Hotkeys 0.1.1-test

Hold Mouse Button 4, move toward an icon, then release to enter its command.
Release in the center to cancel. Aim and throw manually. The radial menu reads
the local player's equipped stratagems, native icons, cooldowns and remaining uses.
Unavailable or unreadable entries cannot be selected. Availability and saved
direction bindings are checked again immediately before command input.

## Arsenal Options

All feature settings are changed in Arsenal, not an in-game MODS menu.
After importing, review the checkboxes; Arsenal controls initial checkbox states.
Close the game, change options, Purge / Deploy, and restart to apply them.

- `원형 오버레이 ON/OFF`: enables the radial menu; default key is Mouse Button 4.
- `Stratagem Hotkeys`: separately enables List key + number-row 1 to 4.
- `공용/임무 스트라타젬 표시`: includes shared/mission entries; otherwise equipped four only.
- `오버레이 키: F6`: checked uses F6, unchecked uses Mouse Button 4.
- `큰 원형 메뉴`: checked uses 130% size, unchecked uses 100%.
- `커맨드 입력: 30ms`: checked uses 30 ms, unchecked uses 15 ms per down/up step.

Neither Mod Options Menu nor Mod Bindings Menu is required. Unchecking both
feature options omits this addon's runtime and GUI. No in-game settings are registered.
Choose an overlay key not used by another game/mod action. Small viewports clamp
menu size to fit the screen, even when the larger option is selected.

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

This is an experimental release, not a live gameplay certification.
Offline tests cover reader bounds, identity checks, saved binding changes,
sequence timing, cancellation, key release, callback chaining and input conflicts.
Actual mission loadout order, host/client play, icon rendering, camera capture,
cursor restoration and ball preparation still need a live test. Names use the
game's debug labels in this first radial version, not translated OCR text.
The GUI has its own material names on the existing overlay world; it does not reuse HUD+ widgets.

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
Look for `OVERLAY opened rows=...` and `COMMAND kind=...`, then `command-complete`.
`SKIP` / `WAIT` record a refused input and its reason.

## Build

Run `node build.cjs`, then `./test.ps1 -LuaDll '../bin/lua51.dll'` on Windows.
Package only `dist/HD2-Stratagem-Hotkeys-0.1.1-test/*`; never package scratch captures.
Building icon materials requires the supported local game's vanilla data bundles.
The optional tools read local game references for research without changing game state.

AI-assisted implementation and documentation.

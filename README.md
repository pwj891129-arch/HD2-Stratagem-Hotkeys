# HD2 Stratagem Hotkeys 0.1.6-test

Hold your game-configured Stratagem List key, move toward a named sector, then
release the key to enter its command. F6 and Mouse Button 4 are no longer separate
overlay bindings; no fixed Alt key is assumed.
Release in the center to cancel. Aim and throw manually. The radial menu reads
the local player's equipped stratagems, cooldowns and remaining uses.
Unavailable or unreadable entries cannot be selected. Availability and saved
direction bindings are checked again immediately before command input.

## Release Selection And Command Dispatch

The user confirmed that 0.1.5-test displays the interface, but reported that the
game does not execute its commands. The log has 33 menu openings, only two
`COMMAND` records and one menu-activation timeout. A completed input sequence is
not proof that the game accepted it.

The old release path drew the radial again before confirming the selection. If
the game recenters its cursor on key-up, that draw replaces the last highlighted
row with the center/dead-zone result. The new path commits the last held-frame
highlight without querying the release-frame cursor. Moving to the center while
still holding the key continues to cancel normally.

Previously, cursor capture was restored and the list key was reacquired during
the same update as physical release. Dispatch now waits at least 30 ms, observes
the old game list closed for another 30 ms, then presses the saved list key.
Directions wait at least 50 ms and a further active-menu observation 15 ms later
before the sequence starts. Timeout, a new physical list press, changed bindings
or loadout, fire, chat and focus loss cancel the queued choice. Owned keys are
released on cancellation. Menu waits have deadlines; there is no busy wait.

`OVERLAY highlight`, `OVERLAY selected`, center/unavailable cancellation, `INPUT waiting-list-close`,
`INPUT list-key-acquired` and the actual direction key values now distinguish
selection, activation and delivery failures. Successful OS input completion is
logged as `command-sent; game-result-unverified`, not confirmed ball preparation.
Fire, chat, game-menu and focus cancellation reasons are logged even when the
menu was already open. Left click remains a fire/cancel action, not confirmation;
select by highlighting while holding the list key and then releasing that key.
The regular List + number shortcut retains its existing held-key flow.

463 LuaJIT checks pass, including release-frame cursor recentering, delayed menu
closure, transient menu activation, loadout/binding changes, a second physical
press and focus loss after reacquisition. These prove the revised sequencing
offline; actual game acceptance still needs another user test. Replace this mod
with 0.1.6-test while the game is closed, then Purge / Deploy in Arsenal.
Auto Reload 0.3.27-test can stay installed unchanged.

## Overlay Native API Fix

The 0.1.4-test log reached `BOOT platform-ready`, `START`, binding detection and
`OVERLAY list-key pressed`, then stopped before `OVERLAY opened`. The new dump
records an access violation reading address `0x3` at `helldivers2.exe+0x108062`;
it is not the earlier option-archive crash. The dump has no symbolized Lua/native
stack, so it does not by itself prove which GUI call faulted.

Inspection found a definite API-contract error: `Gui.resolution(self.gui)`.
[Stingray's API reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Gui.html)
defines an optional **viewport**, not a GUI, as its first argument. Omitting it
returns the back-buffer dimensions. The installed vehicle HUD also uses the
no-argument form. Both opening and drawing now call `Gui.resolution()`; native
access violations cannot be recovered by Lua `pcall`.

Dimensions are checked before creating a GUI, and both the existing debug font
and its material must be available before drawing text. A failed first draw
closes the menu and restores the cursor instead of reporting success. Open-stage
logs distinguish resources, dimensions, world, GUI creation, cursor and drawing.
Startup or a binding change with the list key already held requires a release
before a fresh press can activate either the radial or the number shortcut.

The strict GUI mock rejects arguments to `Gui.resolution`, checks the screen-GUI
scale and text resource contracts, and covers invalid dimensions, missing
material, first-draw failure, resource loss and held startup/rebound keys.
That build passed 435 LuaJIT checks offline. The user subsequently confirmed
that its interface appears; the command-delivery fix is described above.
Auto Reload 0.3.27-test does not need a new build for this GUI fix.

## List-Key Overlay And Loadout Fix

The user confirmed normal startup with 0.1.3-test, but the addon log reported
`OVERLAY four-equipped-slots-unavailable` during a mission. This was an inventory
read failure, not evidence that F6/mouse input was ignored.

Native consumers at `game.dll+0x66e658` and `+0x66e73d` add `0x38` to the matched
peer record before reading the `+0x788` count and `+0x188` entry array. The old
reader omitted this embedded-data offset. The existing read-only capture has
zero at the old count offset and four entries at the native offset; the corrected
reader now parses those actual captured entries in an offline regression test.
Local-peer matching, exact four personal slots, shared-entry filtering and
snapshot validation remain required. No speculative slot coordinates are used.

The radial opens while the saved list key is held and confirms on release.
To finish the command after physical release, the addon briefly reacquires the
same list key, waits for the game menu and inputs the saved directions. That
synthetic hold cannot reopen the radial. A configured List key + number shortcut
takes priority, closing the radial if already open, without a second command on
release. Changing bindings while selecting cancels the stale selection.

Arsenal no longer has a separate F6 option. Enable `원형 오버레이 ON/OFF`, Purge /
Deploy with the game closed and restart. `CONFIG`, `BINDING list-key vk=...`, and
`OVERLAY list-key pressed` logs distinguish option, binding and inventory failures.
Actual in-game overlay rendering and ball preparation still need confirmation.

## Startup Package Fix

Startup still crashed after removing icon materials in 0.1.2-test. The new
`NxStorage` log names both mods' 224-byte option archives with error
`0x89240007` (`E_DSTORAGE_END_OF_FILE`: a read exceeds the file size).
The latest dump repeats `0xc0000005` at `helldivers2.exe+0x5f2eb0` before
fresh shared-loader/addon logs. Icon materials were therefore not a sufficient
explanation or fix.

This build adds the minimum `256 * resource count` allocation used by
[HD2SDK's package writer](https://github.com/RaidingForPants/HD2SDK-CommunityEdition/blob/3a488b42f10669790a5fff1f9d55b9c049cb734b/__init__.py#L827).
All option archives now contain 256 bytes, with trailing zero padding;
Lua payload sizes and option values are unchanged. The writer also applies
the rule to multiple-resource packages, and regression tests reject the old
224-byte output. The user confirmed that the fixed packages allow game startup.
No symbolized native stack is available.

When using Auto Reload, replace it with **0.3.27-test** as well: its old option
archives have the same defect and also appear in the error log. Replacing only
Stratagem Hotkeys leaves those failing reads in place.

Every shipped resource remains Lua. The radial still shows names, slot numbers
and readiness instead of icons. Cursor selection and command shortcuts are
unchanged; actual overlay rendering still needs validation.

Remove/replace both previous packages in Arsenal, Purge, Deploy the fixed
versions, and restart. Do not keep old option or `Icons` archives deployed.
New `BOOT ... platform-init`, `BOOT platform-ready` and `START` log messages
locate initialization if the game reaches Lua startup. Installed game files
are not changed by building or publishing this release.

## Arsenal Options

All feature settings are changed in Arsenal, not an in-game MODS menu.
After importing, review the checkboxes; Arsenal controls initial checkbox states.
Close the game, change options, Purge / Deploy, and restart to apply them.

- `원형 오버레이 ON/OFF`: enables the radial on the game's saved Stratagem List key.
- `Stratagem Hotkeys`: separately enables List key + number-row 1 to 4.
- `공용/임무 스트라타젬 표시`: includes shared/mission entries; otherwise equipped four only.
- `큰 원형 메뉴`: checked uses 130% size, unchecked uses 100%.
- `커맨드 입력: 30ms`: checked uses 30 ms, unchecked uses 15 ms per down/up step.

Neither Mod Options Menu nor Mod Bindings Menu is required. Unchecking both
feature options omits this addon's runtime and GUI. No in-game settings are registered.
The list key follows game settings. Small viewports clamp
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

When also using HD2 AutoReload, update that addon to 0.3.27-test or newer.
This prevents the command shortcuts from starting weapon-switch reload checks.
The mods own separate Lua resources and preserve the existing update/shutdown chains.
Neither boot nor content/input.config is replaced. Mod Bindings Menu is not a dependency.

## Test Scope

This is an experimental release, not a live gameplay certification.
Offline tests cover reader bounds, identity checks, saved binding changes,
sequence timing, cancellation, key release, callback chaining and input conflicts.
Actual mission loadout order, host/client play, text rendering, camera capture,
cursor restoration and ball preparation still need a live test. Names use the
game's debug labels in this first radial version, not translated OCR text.
The GUI uses the game's existing debug font on an overlay world; it does not
reuse HUD+ widgets or ship any binary GUI assets. Missing font/material/API data prevents
the overlay from opening rather than invoking a missing resource.

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
Look for `OVERLAY selected kind=...`, `INPUT list-key-acquired` and `COMMAND kind=...`,
then `command-sent; game-result-unverified`. This last message confirms only the
OS input sequence, not the game's response.
`SKIP` / `WAIT` record a refused input and its reason.

## Build

Run `node build.cjs`, then `./test.ps1 -LuaDll '../bin/lua51.dll'` on Windows.
Run `node tools/package.test.cjs` to verify minimum sizes, padding, Lua-only
archives and option includes.
Package only `dist/HD2-Stratagem-Hotkeys-0.1.6-test/*`; never package scratch captures.
Building no longer reads the game's material bundles.
The optional tools read local game references for research without changing game state.

AI-assisted implementation and documentation.

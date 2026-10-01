# HD2 Stratagem Hotkeys 0.1.11-test

Hold your game-configured Stratagem List key, move toward an icon sector, then
release the key to enter its command. F6 and Mouse Button 4 are no longer separate
overlay bindings; no fixed Alt key is assumed.
Release in the center to cancel. Aim and throw manually. The radial menu reads
the local player's equipped stratagems, cooldowns and remaining uses.
Unavailable or unreadable entries cannot be selected. Availability and saved
direction bindings are checked again immediately before command input.

## Atlas And RGB-mask Icons (0.1.11-test)

The user's 0.1.10-test screenshot still had no visible icons despite
`OVERLAY icons=10/10`. A bitmap ID proves allocation, not a visible image.
The native tile renderer reads definition +176 as an image mask, +184 as a
palette index, and applies three shader color vectors. The game's renderer
also resolves the image's region in a texture atlas. Direct resource material
calls did not reproduce that setup.

This version reads the atlas map through ReadProcessMemory, without calling
the engine's internal query functions or writing game memory. The hash-pinned
EXE's query at +0x3438e0 follows root +0x1a10238, manager +0x3f8 and the map at
+0x2a0. It hashes the high resource word modulo capacity and follows bounded,
24-byte chained entries. Payload +8 is the atlas texture; +24 is the four-float
offset/scale. Offsets and sizes become opposite UV corners for
[Gui.bitmap_uv](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Gui.html).
Pointers, capacity/count, finite UVs and repeated snapshots are validated.
Unreadable, changed, unmapped or malformed data falls back to the name.

The existing native RGB-mask material `c0f3797849262087` is used only on
isolated mod-owned GUIs. It receives the resolved atlas texture, exact region
and raw color vectors from the five-entry native palette at +0x331b610 and the
two constants at +0x21e89e0/+0x21e8a10. Vector4, not Color's ARGB constructor,
preserves the shader's component order. GUI-local instances keep icons with
different regions/colors independent even when they share one atlas. Hover
redraws reuse bindings; closing or resource loss retires owned icon GUIs.
No vanilla/HUD+ GUI or material is modified.

Only the radial display requests this metadata. Command requests skip icon
reads, and existing character-menu eligibility, numbering, key bindings and
input sequencing stay unchanged. Labels still use the game's internal English
development names; this release does not introduce a localization hook.
`OVERLAY icon-source kind=... slot=... picture=... atlas=... uv=... name=...`
records the actual binding. `OVERLAY icon-fallback ... reason=...` diagnoses
missing metadata/API/resources or draw failures without per-frame spam.

3,713 LuaJIT checks pass without OS input. Tests cover atlas hash collisions,
invalid/cyclic chains, bounds, nonfinite/invalid regions, changing snapshots,
raw palette order, shared atlases with independent regions/colors, binding and
draw failures, retained redraws, owned-GUI cleanup and 1-16 image layouts at
320x240, 1280x720 and 3840x2160. The optional native regression checks 130 nonzero
definitions/110 textures, the RGB-mask material and native color/query code.
The live process's atlas query code was captured read-only; the game exited
before a live atlas-data snapshot could be captured. Actual rendering still
requires an in-game test. No game functions were invoked during research.

Replace this mod with 0.1.11-test while the game is closed, then Purge / Deploy
in Arsenal. The Lua-only package includes no game icons, shaders, materials,
fonts or binary GUI resources. Auto Reload 0.3.28-test remains unchanged.

## Previous Direct-material Attempt (0.1.10-test)

The user's 0.1.9-test log showed the menu opening with `OVERLAY icons=0/10`.
Its generic image template, `ccf39a02b444fa01`, is actually the hash of
`core/performance_hud/debug`: a debug font material with a different shader
from the native stratagem icon materials. The previous texture-binding path
was incorrect. Its total-only log did not identify which check rejected each
icon, so it does not establish one specific runtime failure stage.

Definition +176 names a per-stratagem native material that already binds the
corresponding same-hash texture and correct image shader. This version draws
that already-available material directly with
[Gui.bitmap](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Gui.html).
It does not require a generic template, separately query texture availability,
replace textures, or mutate GUI materials. Icons share the owned radial GUI
with sector backgrounds and labels, using explicit draw layers. No extra icon
GUIs are allocated, and no game/HUD+ material is modified.

Personal numbers remain above the square images; names and readiness are below.
Unavailable entries are dimmed. One-to-sixteen item layouts clamp icon sizes
on small screens and with the 130% option. Missing resources/API failures retain
the name layout and log `OVERLAY icon-fallback kind=... material=... reason=...`.
Logs distinguish invalid references, unavailable APIs, material ID/query
failures, unavailable native materials and bitmap failures. Unchanged fallback
reasons are not repeated on every hover redraw.

`OVERLAY icons=4/4` means four bitmap calls returned shape IDs, not that native
rendering or a game command succeeded. 3,591 LuaJIT checks pass without OS input.
Tests cover distinct native materials with no texture setters, resource changes,
unloading/recovery, API/ID/query/draw failures, retained redraws, shutdown,
stale worlds and non-overlapping image bounds for 1-16 entries at 320x240,
1280x720 and 3840x2160. A separate read-only native archive regression verifies
130 nonzero definitions / 110 distinct icon materials, their image shader and
matching textures, and confirms the old template is a debug font material.
Captured game references and game assets are excluded from source/releases.

This attempt was superseded by the atlas/RGB-mask path in 0.1.11-test after
the user's in-game screenshot showed that allocating bitmaps was not enough.
No icons, shaders, materials, font files or GUI binaries ship in this Lua-only
release. Auto Reload 0.3.28-test and installed game files remain unchanged.

## Native Menu Gate And Slot Numbers (0.1.8-test)

Number-row 1-4 targets the player's four equipped slots, not the radial row
index. Personal sectors now display those same slot numbers even when shared
entries appear between them. Shared/mission sectors have no number shortcut;
they remain selectable with the mouse when their status is ready.

The overlay waits for the character's actual native stratagem menu to open,
rather than treating a pressed List key as proof of availability. The pinned
game's menu-open query at `game.dll+0xa8e780` resolves the avatar and tests bit 9
at avatar manager + `0x53e888` + seat * `0x1238`. The reader follows the local
unit/owner/avatar maps, validates identities and rereads the snapshot. It does
not invoke the native eligibility function or guess its restrictions.

A fresh key press allows at most 350 ms for native activation. No overlay or
mouse capture is created while the native menu is inactive or unreadable.
Character replacement, unreadable state or native menu closure while holding
the key cancels the choice and any remaining command input. Normal key release
still commits the last held-frame choice; dispatch waits for native closure and
actual native reactivation. Number shortcuts also require the native open state
before sending directions.

903 LuaJIT checks pass without sending OS input, including mixed shared/personal
slot labels, inactive native menus despite raw Alt input, delayed activation,
bounded waits, death/respawn identity changes and cancellation during a command.
The native field was verified against cached code from the hash-pinned game;
state-machine and character-menu snapshots are tested with mock data. Live
character-state gating and successful command acceptance still need user testing.
Replace this mod with 0.1.8-test while the game is closed, then Purge / Deploy in
Arsenal. Auto Reload 0.3.28-test stays unchanged. Installed mod files are not
automatically changed by building or publishing this release.

## Direction Input And Game Observation

The user confirmed that holding Alt and manually pressing the configured arrow
keys works, while this mod's automatic commands do not. Existing logs record
saved VK values 37, 38, 39 and 40, not WASD. Windows input insertion succeeded,
but that does not establish game receipt. The exact reason for the missing
automatic commands is not yet confirmed.

This compatibility test keeps the working list-key scan-code path and sends
command directions using their explicit saved virtual-key values instead of
scan-code-only events. Arrow keys keep the extended flag; Numpad and number-row
bindings remain distinct. The sender follows the
[Windows KEYBDINPUT contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-keybdinput).
It does not switch to guessed WASD keys or retry an uncertain command.

Each direction now waits for the game's corresponding native input action.
The pinned game's direction consumers at `game.dll+0x597030` read group 5's
action bytes at input owner + `0x3fc8`, spaced 32 bytes apart. The addon reads a
bounded 160-byte snapshot through ReadProcessMemory, validates boolean values
and rechecks that the owner still matches the saved bindings. No game memory
is written and no native game input function is invoked.

The input sequence observes a clear direction state before pressing, latches
even a one-frame press, holds for the selected 15/30 ms minimum, releases, then
waits for the native action to clear before the next key. Missing press/reset
observations time out after 250 ms. Conflicting directions, unreadable state,
input-owner replacement and existing cancellation guards stop the command and
release owned keys. Each observed direction and the exact missing step are
logged. `command-input-observed; game-result-unverified` means all direction
actions were observed, not that a ball was prepared or a stratagem was called.

624 LuaJIT checks pass without sending OS input, including mocked Windows
INPUT fields, delayed/missing/one-frame action receipt, repeated directions,
30 FPS sequences, release failure and input-owner replacement. Package checks
retain six unique Lua-only archives with the required minimum sizes.
Replace this mod with 0.1.7-test while the game is closed, then Purge / Deploy in
Arsenal. Auto Reload 0.3.28-test can stay installed unchanged. Actual mission
command acceptance still requires user testing; live game files were not edited.

## Release Selection And Command Dispatch (0.1.6-test)

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
The GUI uses the game's existing debug font and loaded icon textures on owned
overlay surfaces; it does not reuse HUD+ widgets or ship binary GUI assets.
Missing required font/material/API data prevents the overlay from opening.
Unavailable optional icon resources or APIs fall back to the existing name layout.

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
and `OVERLAY icons=...` for native icon availability. Missing images also log
`OVERLAY icon-fallback kind=... material=... reason=...`,
then `game-direction-observed step=...` for each direction. A missing action
produces `game-direction-not-observed step=... direction=... vk=...` and stops.
`command-input-observed; game-result-unverified` confirms native direction input
observation only, not successful ball preparation or a completed call.
`SKIP` / `WAIT` record a refused input and its reason.

## Build

Run `node build.cjs`, then `./test.ps1 -LuaDll '../bin/lua51.dll'` on Windows.
Run `node tools/package.test.cjs` to verify minimum sizes, padding, Lua-only
archives and option includes.
Run `node tools/native-icons.test.cjs` for the optional pinned-game material
regression when local reference captures and game bundles are available.
Package only `dist/HD2-Stratagem-Hotkeys-0.1.11-test/*`; never package scratch captures.
Building no longer reads the game's material bundles.
The optional tools read local game references for research without changing game state.

AI-assisted implementation and documentation.

return function(equal, read_file, source)
    local Radial = dofile("radial.lua")
    equal(Radial.pick(0.5, 0.5, 1280, 720, 4, 1), nil, "radial dead zone")
    for index, point in ipairs({{0.5, 0.9}, {0.8, 0.5}, {0.5, 0.1}, {0.2, 0.5}}) do
        equal(Radial.pick(point[1], point[2], 1280, 720, 4, 1), index, "clockwise sectors")
    end
    local x, y, foreground, worlds = 0.5, 0.5, true, {1, 2}
    local show, focus, created, destroyed, shapes, next_id = false, true, 0, 0, {}, 0
    local width, height, resolutions, phases = 1280, 720, 0, {}
    local resources = {font = true, material = true}
    local channel = {
        foreground = function() return foreground end,
        cursor = function() return x, y end,
        center_cursor = function() x, y = 0.5, 0.5; return true end,
    }
    local function v(a, b, c) return {x = a, y = b, z = c} end
    local sr = {Vector2 = v, Vector3 = v, Color = function(...) return {...} end,
        Application = {worlds = function() return worlds end, main_world = function() return 1 end,
            can_get = function(kind, resource)
                if resource ~= "core/performance_hud/debug" then return false end
                assert(resource == "core/performance_hud/debug", "existing debug resource only")
                return resources[kind] == true
            end},
        World = {create_screen_gui = function(w, option, sx, sy)
                equal(w, 2, "own overlay world")
                assert(option == "scale" and sx == 1 and sy == 1, "native screen GUI scale contract")
                created = created + 1; return 99
            end,
            destroy_gui = function() destroyed = destroyed + 1 end},
        Window = {show_cursor = function() return show end, mouse_focus = function() return focus end,
            set_show_cursor = function(b) show = b end, set_mouse_focus = function(b) focus = b end},
        Gui = {resolution = function(...)
                assert(select("#", ...) == 0, "Gui.resolution must not receive a Gui object")
                resolutions = resolutions + 1; return width, height
            end,
            material = function() error("custom material path must stay disabled") end,
            text_extents = function(_, text, _, size) return v(0, 0), v(#text * size * 0.5, size) end},
        Material = {set_texture = function() error("native texture mutation must stay disabled") end},
        IdString64 = {from_hex = function(t) return t end},
    }
    for _, kind in ipairs({"triangle", "bitmap", "text"}) do
        sr.Gui[kind] = function(gui, ...)
            assert(gui == 99, "own GUI receives draw primitives")
            if kind == "text" then
                local text, font, size, material = ...
                assert(type(text) == "string" and font == "core/performance_hud/debug" and
                    material == font and resources.font and resources.material and size > 0,
                    "loaded text font/material and positive size required")
            end
            next_id = next_id + 1; shapes[next_id] = {kind, gui, ...}; return next_id
        end
        sr.Gui["destroy_" .. kind] = function(_, id) equal(shapes[id] ~= nil, true, "only own shape destroyed"); shapes[id] = nil end
    end
    local inventory = {token = "TOKEN", rows = {}}
    for index = 1, 4 do inventory.rows[index] = {kind = index, slot = index, ready = index ~= 2,
        picture = "0000000100000001", name = "ITEM", status = index == 2 and "5s" or "READY"} end
    local radial = Radial.new(sr, channel, 1, function(line)
        if not line:find("icon-fallback", 1, true) then phases[#phases + 1] = line end
    end)
    equal(radial:open(inventory), true, "radial opens")
    equal(table.concat(phases, "|"), "OVERLAY stage=resources|OVERLAY stage=dimensions|OVERLAY stage=world|" ..
        "OVERLAY stage=create-gui|OVERLAY stage=cursor|OVERLAY stage=draw|OVERLAY icons=0/4|OVERLAY stage=ready",
        "open phases distinguish native API failures")
    equal(resolutions, 2, "opening and drawing both query back buffer without a GUI argument")
    local labels, bitmaps = 0, 0
    for _, shape in pairs(shapes) do
        if shape[1] == "text" and shape[3] == "ITEM" then labels = labels + 1 end
        if shape[1] == "bitmap" then bitmaps = bitmaps + 1 end
    end
    equal(labels, 4, "text fallback displays each equipped name")
    local numbers = {}
    for _, shape in pairs(shapes) do
        if shape[1] == "text" and shape[3]:match("^%d+$") then numbers[shape[3]] = true end
    end
    for slot = 1, 4 do equal(numbers[tostring(slot)], true, "personal slot number rendered") end
    local shared_inventory = {token = "TOKEN", rows = {inventory.rows[1],
        {kind = 5, shared = true, ready = true, name = "SHARED", status = "READY"},
        inventory.rows[2], inventory.rows[3], inventory.rows[4]}}
    equal(radial:draw(shared_inventory), true)
    numbers = {}
    for _, shape in pairs(shapes) do
        if shape[1] == "text" and shape[3]:match("^%d+$") then numbers[shape[3]] = true end
    end
    for slot = 1, 4 do equal(numbers[tostring(slot)], true, "interleaved shared row preserves personal number") end
    equal(numbers["5"], nil, "shared row has no misleading number 5")
    local numbered_before = next_id
    inventory.rows[1].slot = nil; radial:draw(shared_inventory)
    equal(next_id > numbered_before, true, "slot label change redraws retained GUI")
    inventory.rows[1].slot = 1; radial:draw(inventory)
    equal(bitmaps, 0, "text fallback does not load icon materials")
    equal(show, true); equal(focus, false); equal(radial.selected, nil)
    x, y = 0.8, 0.5; equal(radial:draw(inventory), true); equal(radial.selected, 2)
    local before = next_id; radial:draw(inventory)
    equal(next_id, before, "retained GUI avoids redraw")
    foreground = false; radial:close()
    equal(show, true, "focus loss defers cursor restore")
    foreground = true; radial:restore()
    equal(show, false); equal(focus, true, "cursor capture restored")
    equal(radial:open(inventory), true); worlds = {1}; radial:dispose()
    equal(destroyed, 0, "stale world is never dereferenced")
    worlds = {1, 2}; equal(radial:open(inventory), true); radial:dispose()
    equal(destroyed, 1, "only own live GUI destroyed")
    equal(radial:open({rows = {inventory.rows[1]}}), true, "single sector opens")
    local name_size
    for _, shape in pairs(shapes) do
        if shape[1] == "text" and shape[3] == "ITEM" then name_size = shape[5] end
    end
    equal(name_size ~= nil and name_size > 0, true, "single sector keeps positive font size")
    radial:dispose()
    resources.font = false
    local opened, why = radial:open(inventory)
    equal(opened, false, "missing native font declines overlay")
    equal(why, "overlay-font-unavailable")
    local creations = created
    resources.font, resources.material = true, false
    opened, why = radial:open(inventory)
    equal(opened, false, "missing material declines before GUI allocation")
    equal(why, "overlay-material-unavailable")
    equal(created, creations)
    resources.material = true
    for _, dimensions in ipairs({{0, 720}, {1280, 0}, {"1280", 720}, {math.huge, 720}, {0 / 0, 720}}) do
        width, height = dimensions[1], dimensions[2]
        opened, why = radial:open(inventory)
        equal(opened, false, "invalid dimensions decline before native GUI creation")
        equal(why, "overlay-resolution-unavailable")
        equal(created, creations)
    end
    width, height = 1280, 720
    channel.cursor = function() return nil end
    opened, why = radial:open(inventory)
    equal(opened, false, "failed initial draw must not report an open overlay")
    equal(why, "overlay-surface-unavailable")
    equal(radial.opened, false)
    equal(show, false, "failed first draw restores cursor visibility")
    equal(focus, true, "failed first draw restores mouse capture")
    channel.cursor = function() return x, y end
    equal(radial:open(inventory), true)
    before = next_id
    resources.material = false
    equal(radial:draw(inventory), false, "resource loss declines before native drawing")
    equal(next_id, before, "resource loss creates no native primitives")
    radial:dispose()
    resources.material = true

    -- Actual addon sequencing with GUI/cursor and input adapters; no OS input.
    local current, held, events, ready, token, focused, idle, menu = 0, {}, {}, true, "TOKEN", true, true, true
    local menu_override, hover, acknowledge = nil, 1, true
    local game_available, game_token, game_active_override = true, "CHARACTER", nil
    local mouse_latch, up_failures, ignore_up, mouse_observation = nil, 0, false, true
    local options = {radial = true}
    local binding = {start_vk = 164, directions = {38, 39, 40, 37}}
    local fake = {base = 1, foreground = function() return focused end,
        down = function(vk) return held[vk] or false end,
        key = function(vk, down)
            events[#events + 1] = {vk, down, "list"}
            if (vk == 5 or vk == 6) and not down and up_failures > 0 then
                up_failures = up_failures - 1; return false
            end
            held[vk] = down
            if vk == binding.start_vk and mouse_latch ~= nil and (down or not ignore_up) then mouse_latch = down end
            return true
        end,
        command_key = function(vk, down) events[#events + 1] = {vk, down, "command"}; held[vk] = down; return true end}
    local request = function() if ready then return {token = token, kind = 1, keys = {38, 39},
        directions = {1, 2}, bindings = binding} end end
    local function list_down()
        if (binding.start_vk == 5 or binding.start_vk == 6) and mouse_latch ~= nil then return mouse_latch end
        return held[binding.start_vk] == true
    end
    local fake_reader = {bindings = function() return binding, "ready" end,
        game_menu = function()
            if not game_available then return nil, "no-local-character" end
            local active = menu and list_down()
            if game_active_override ~= nil then active = game_active_override end
            return {active = active, token = game_token}, "ready"
        end,
        idle = function() return idle end, menu_active = function()
            if menu_override ~= nil then return menu_override end
            return menu and list_down()
        end,
        command_state = function()
            if not mouse_observation then return nil end
            return {start = menu and list_down(),
                directions = {acknowledge and held[38] == true, acknowledge and held[39] == true, false, false}}
        end,
        loadout = function() return {token = token} end,
        request = request, request_kind = request,
        radial = function() return {token = token, rows = {{kind = 1, ready = ready, status = "READY"}}}, "ready" end}
    local opened_count = 0
    local mock_radial = {restore = function() end, dispose = function() end}
    function mock_radial:open(value)
        self.inventory, self.opened = value, true
        opened_count = opened_count + 1
        return true
    end
    function mock_radial:draw() self.selected = hover; return true end
    function mock_radial:close() self.opened, self.selected, self.inventory = false, nil, nil end
    local messages = {}
    local env = setmetatable({fake = fake, fake_reader = fake_reader}, {__index = _G}); env._G = env
    env.CowboyBingusModLoader = {api = 1, open_log = function()
        return {write = function(_, line) messages[#messages + 1] = line end,
            flush = function() end, close = function() end}
    end}
    env.require = function(name)
        local option = name:match("stratagem_option_(.+)$")
        if option then return options[option] end
        return require(name)
    end
    env.stingray = {Application = {time_since_launch = function() return current end,
        can_get = function(_, resource) return options[resource:match("stratagem_option_(.+)$")] == true end}}
    local glue = read_file("addon.lua"):gsub('%-%- @PLATFORM@', function() return "return { create = function() return fake end }" end)
        :gsub('%-%- @READER@', function() return "return { new = function() return fake_reader end }" end)
        :gsub('%-%- @POLICY@', function() return read_file("policy.lua") end)
        :gsub('%-%- @RADIAL@', function() return "return {new=function() return mock_radial end}" end)
    env.mock_radial = mock_radial
    local init = assert(loadstring(glue)); setfenv(init, env); init()
    local function step(dt) current = current + dt; env.update() end
    local function finish() for i = 1, 20 do step(0.02) end end
    step(0); held[5], held[117] = true, true; step(0.02)
    equal(mock_radial.opened, nil, "retired mouse/F6 shortcuts do not open overlay")
    held[5], held[117], held[164] = false, false, true; step(0.02)
    equal(mock_radial.opened, true, "saved list key opens overlay")
    equal(#events, 0, "opening overlay never inputs command")
    equal(env.HD2StratagemHotkeys.blocking_inputs, true, "overlay blocks autoreload")
    held[164] = false; step(0.02); finish()
    equal(#events, 6, "release sends start plus two directions and releases start")
    equal(events[1][1], 164); equal(events[1][2], true)
    equal(events[1][3], "list", "Alt uses unchanged list input route")
    equal(events[2][3], "command", "direction uses distinct command input route")
    equal(events[6][1], 164); equal(events[6][2], false)
    equal(env.HD2StratagemHotkeys.blocking_inputs, false)
    equal(opened_count, 1, "synthetic list-key hold never reopens overlay")
    ready = false; held[164] = true; step(0.02); held[164] = false; step(0.02); finish()
    equal(#events, 6, "unavailable sector sends nothing")
    ready = true; held[164] = true; step(0.02); focused = false; step(0.02)
    held[164] = false; focused = true; finish()
    equal(#events, 6, "focus loss cancels selection")
    held[164] = true; step(0.02); token = "CHANGED"; step(0.06); held[164] = false; finish()
    equal(#events, 6, "loadout change cancels overlay")
    menu = false; held[164] = true; step(0.02); held[164] = false; step(0.02); finish(); finish()
    equal(#events, 6, "native menu unavailable never opens or injects list key")
    menu = true; idle = false; held[164] = true; step(0.02); held[164] = false; finish()
    equal(#events, 6, "menu or chat blocks overlay")
    idle = true; held[164], held[49] = true, true; finish()
    equal(#events, 6, "Arsenal hotkey option off")
    env.shutdown()

    -- Both paths share the list key without firing two commands or hiding shortcuts.
    env.update, env.shutdown, env.HD2StratagemHotkeys = nil, nil, nil
    options.hotkeys = true
    held, events, opened_count = {}, {}, 0
    init()
    step(0)
    held[164], held[49] = true, true; step(0.02); finish()
    equal(opened_count, 0, "same-frame number shortcut takes priority over overlay")
    equal(#events, 4, "physical list key shortcut sends directions only")
    held[164], held[49] = false, false; step(0.02)
    held[164] = true; step(0.02)
    equal(mock_radial.opened, true)
    held[50] = true; step(0.02); finish()
    equal(mock_radial.opened, false, "number shortcut closes an already open overlay")
    equal(#events, 8, "one number command replaces radial selection")
    held[164], held[50] = false, false; step(0.02); finish()
    equal(#events, 8, "list-key release after number command sends no second command")
    binding = {start_vk = 162, directions = {38, 39, 40, 37}}
    step(0.3); held[162] = true; step(0.02)
    equal(mock_radial.opened, true, "rebound list key opens overlay without fixed Alt")
    held[162] = false; step(0.02); finish()
    equal(#events, 14, "rebound list key release runs one radial command")
    equal(events[9][1], 162, "rebound list key reacquired for command")
    equal(events[14][1], 162); equal(events[14][2], false)
    equal(opened_count, 2, "rebound synthetic hold also cannot reopen overlay")
    held[162] = true; step(0.02)
    binding = {start_vk = 164, directions = {38, 39, 40, 37}}
    step(0.3)
    equal(mock_radial.opened, false, "binding change while overlay open cancels selection")
    held[162] = false; step(0.02); finish()
    equal(#events, 14, "binding change never enters stale command")
    env.shutdown()

    -- Keys held before startup or a binding change are not fresh activation edges.
    env.update, env.shutdown, env.HD2StratagemHotkeys = nil, nil, nil
    held, events, opened_count = {[164] = true, [49] = true}, {}, 0
    init(); step(0); finish()
    equal(opened_count, 0, "startup with held list key never opens the radial")
    equal(#events, 0, "startup chord never inputs directions")
    held[164], held[49] = false, false; step(0.02)
    held[164] = true; step(0.02)
    equal(mock_radial.opened, true, "release and fresh press arm the list key")
    held[162] = true
    binding = {start_vk = 162, directions = {38, 39, 40, 37}}
    step(0.3)
    equal(mock_radial.opened, false, "rebinding to an already held key cancels the old overlay")
    finish()
    equal(opened_count, 1, "held rebound key never opens a new overlay")
    equal(#events, 0, "held rebound key never confirms the cancelled selection")
    held[164], held[162] = false, false; step(0.02)
    held[162] = true; step(0.02)
    equal(mock_radial.opened, true, "released rebound key can open normally")
    held[162] = false; step(0.02); finish()
    equal(#events, 6, "fresh rebound hold-release inputs exactly one command")
    env.shutdown()

    local function restart()
        env.update, env.shutdown, env.HD2StratagemHotkeys = nil, nil, nil
        held, events, opened_count, messages = {}, {}, 0, {}
        menu_override, hover, focused, idle, menu, ready, acknowledge = nil, 1, true, true, true, true, true
        game_available, game_token, game_active_override = true, "CHARACTER", nil
        mouse_latch, up_failures, ignore_up, mouse_observation = nil, 0, false, true
        binding = {start_vk = 164, directions = {38, 39, 40, 37}}
        init(); step(0)
    end
    restart()
    held[164] = true; step(0.02)
    equal(mock_radial.selected, 1, "held frame highlights desired row")
    hover, held[164], menu_override = nil, false, true
    step(0.02)
    equal(env.HD2StratagemHotkeys.pending.kind, 1, "key-up recenter cannot erase last highlighted row")
    equal(mock_radial.opened, false, "restore capture before reacquiring the list key")
    for index = 1, 5 do step(0.02) end
    equal(#events, 0, "never inject a new list press while the old menu is still open")
    menu_override = false
    step(0.02); step(0.02)
    equal(#events, 0, "menu closure settles across frames before reacquisition")
    step(0.02)
    equal(#events, 1, "fresh list key press after stable closure")
    equal(events[1][1], 164); equal(events[1][2], true)
    for index = 1, 5 do step(0.02) end
    equal(#events, 1, "no directions before the reopened menu is active")
    menu_override = true; step(0.02)
    equal(#events, 1, "menu activation must be observed across frames")
    menu_override = false; step(0.02)
    equal(env.HD2StratagemHotkeys.pending.menu_ready, nil, "transient menu activation is not enough")
    menu_override = true; finish()
    equal(#events, 6, "stable reopened menu receives directions and one list release")
    equal(opened_count, 1, "injected reacquisition does not reopen the radial")
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    hover = nil; step(0.02)
    held[164] = false; step(0.02); finish()
    equal(#events, 0, "moving to center while holding still cancels deliberately")
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    held[164], menu_override = false, true; step(0.02); finish(); finish()
    equal(#events, 0, "old menu never closing times out without any injected input")
    equal(env.HD2StratagemHotkeys.pending, nil)
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    held[164] = false; step(0.02)
    token = "REPLACED-BEFORE-REACQUIRE"; finish()
    equal(#events, 0, "loadout change while closing the menu cancels without injecting list key")
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    held[164] = false; step(0.02)
    held[164] = true; step(0.06); held[164] = false; finish()
    equal(#events, 0, "a second physical list press cancels the queued radial choice")
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    held[164], menu_override = false, true; step(0.02)
    binding = {start_vk = 162, directions = {38, 39, 40, 37}}
    step(0.3)
    equal(#events, 0, "binding change while waiting for close never presses a different list key")
    equal(env.HD2StratagemHotkeys.pending, nil)
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    held[164] = false; step(0.02)
    menu_override = false
    for index = 1, 4 do step(0.02) end
    equal(#events, 1, "pending command owns the reacquired list key")
    focused = false; step(0.02)
    equal(#events, 2, "focus loss releases the reacquired list key before any directions")
    equal(events[2][1], 164); equal(events[2][2], false)
    equal(env.HD2StratagemHotkeys.pending, nil)
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    held[1] = true; step(0.02)
    equal(mock_radial.opened, false, "left click remains fire/cancel rather than radial confirmation")
    equal(messages[#messages], "OVERLAY cancelled fire\n", "fire cancellation after opening is diagnosed")
    held[1], held[164] = false, false; step(0.02); finish()
    equal(#events, 0, "release after a fire-cancelled menu never inputs a command")
    env.shutdown()

    restart()
    acknowledge = false
    held[164] = true; step(0.02); held[164] = false; step(0.02)
    finish(); finish()
    equal(#events, 4, "missing game direction stops after first down/up and releases list")
    equal(events[2][1], 38); equal(events[2][2], true)
    equal(events[3][1], 38); equal(events[3][2], false)
    equal(events[4][1], 164); equal(events[4][2], false)
    equal(table.concat(messages):find("game-direction-not-observed step=1 direction=1 vk=38", 1, true) ~= nil,
        true, "missing game receipt identifies exact failed step")
    equal(table.concat(messages):find("command-input-observed", 1, true), nil, "Windows insertion alone is not completion")
    equal(env.HD2StratagemHotkeys.blocking_inputs, false)
    env.shutdown()

    restart()
    held[164] = true; step(0.02); held[164] = false; step(0.02); finish()
    equal(table.concat(messages):find("game-direction-observed step=1 direction=1 vk=38", 1, true) ~= nil, true)
    equal(table.concat(messages):find("game-direction-observed step=2 direction=2 vk=39", 1, true) ~= nil, true)
    equal(table.concat(messages):find("command-input-observed; game-result-unverified", 1, true) ~= nil, true,
        "game input observation remains distinct from successful stratagem use")
    env.shutdown()

    restart()
    binding.owner = 100
    held[164] = true; step(0.02); held[164], menu_override = false, true; step(0.02)
    binding = {start_vk = 164, directions = {38, 39, 40, 37}, owner = 200}
    step(0.3)
    equal(#events, 0, "same keys with replaced input owner cancel queued command")
    equal(env.HD2StratagemHotkeys.pending, nil)
    env.shutdown()

    -- Raw Alt input does not prove that the character can use stratagems.
    restart()
    game_active_override = false
    held[164] = true; step(0.02); finish()
    equal(opened_count, 0, "raw list action without native character menu never opens overlay")
    equal(#events, 0, "unavailable character menu never captures or injects input")
    equal(env.HD2StratagemHotkeys.open_pending, nil, "native activation wait is bounded")
    game_active_override = true; step(0.02)
    equal(opened_count, 0, "late activation after timeout requires a fresh key press")
    held[164] = false; step(0.02); finish()
    equal(#events, 0, "release after blocked overlay does not confirm anything")
    env.shutdown()

    restart()
    game_active_override = false
    held[164] = true; step(0.02)
    equal(opened_count, 0, "overlay waits for native menu activation")
    step(0.10); game_active_override = true; step(0.02)
    equal(opened_count, 1, "delayed native menu activation opens once")
    game_active_override = nil; held[164] = false; step(0.02); finish()
    equal(#events, 6, "normal key release after native closure still commits selected command")
    env.shutdown()

    restart()
    game_active_override = false
    held[164] = true; step(0.02); held[164] = false; step(0.02)
    game_active_override = true; finish()
    equal(opened_count, 0, "release before menu activation cancels waiting overlay")
    equal(#events, 0)
    env.shutdown()

    restart()
    game_available = false
    held[164] = true; step(0.02)
    game_available = true; finish()
    equal(opened_count, 0, "death or spectator state cannot arm a later character while key held")
    equal(#events, 0)
    held[164] = false; step(0.02); env.shutdown()

    restart()
    game_active_override = false
    held[164] = true; step(0.02)
    game_token, game_active_override = "NEW-CHARACTER", true; step(0.02)
    equal(opened_count, 0, "character replacement cancels native activation wait")
    equal(env.HD2StratagemHotkeys.open_pending, nil)
    held[164] = false; step(0.02); finish(); equal(#events, 0)
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    game_active_override = false; step(0.02)
    equal(mock_radial.opened, false, "native menu closure while held closes overlay")
    equal(table.concat(messages):find("game-stratagem-menu-closed", 1, true) ~= nil, true)
    held[164] = false; step(0.02); finish(); equal(#events, 0, "forced menu closure discards selection")
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    game_available = false; held[164] = false; step(0.02); finish()
    equal(#events, 0, "unreadable character on release never commits last highlight")
    env.shutdown()

    restart()
    held[164] = true; step(0.02)
    game_token = "NEW-CHARACTER"; held[164] = false; step(0.02); finish()
    equal(#events, 0, "respawn identity change on key release cancels selection")
    env.shutdown()

    restart()
    held[164] = true; step(0.02); held[164] = false; step(0.02)
    for index = 1, 4 do step(0.02) end
    equal(#events, 1, "reacquired list key waits for actual reopened menu")
    game_active_override = false; finish(); finish()
    equal(#events, 2, "raw active list alone never dispatches directions")
    equal(events[2][1], 164); equal(events[2][2], false, "native activation timeout releases owned list key")
    env.shutdown()

    restart()
    held[164], held[49] = true, true; step(0.02)
    step(0.06); step(0.06)
    equal(#events, 1, "first shortcut direction held before native closure")
    game_active_override = false; step(0.02); finish()
    equal(#events, 2, "native closure during command releases held direction without remaining sequence")
    equal(events[2][1], 38); equal(events[2][2], false)
    equal(env.HD2StratagemHotkeys.pending, nil)
    env.shutdown()

    restart()
    game_active_override = false
    held[164], held[49] = true, true; step(0.02); finish()
    equal(#events, 0, "number shortcut also refuses inactive native character menu")
    equal(opened_count, 0)
    env.shutdown()

    for _, vk in ipairs({5, 6}) do
        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); held[vk] = true; step(0.02)
        equal(mock_radial.opened, true, "saved thumb button opens the radial")
        equal(#events, 0, "mouse menu opening never injects an input")
        held[vk] = false; step(0.02); finish()
        equal(#events, 6, "thumb release runs exactly one command after reacquisition")
        equal(events[1][1], vk); equal(events[1][2], true); equal(events[1][3], "list")
        equal(events[2][1], 38); equal(events[2][3], "command")
        equal(events[6][1], vk); equal(events[6][2], false)
        equal(opened_count, 1, "owned mouse hold cannot reopen the radial")
        equal(env.HD2StratagemHotkeys.blocking_inputs, false)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); held[vk], held[49] = true, true; step(0.02); finish()
        equal(opened_count, 0, "thumb plus number shortcut takes priority over the radial")
        equal(#events, 4, "physical thumb shortcut sends only directions")
        for _, event in ipairs(events) do equal(event[3], "command") end
        held[vk], held[49] = false, false; step(0.02); finish()
        equal(#events, 4, "thumb shortcut release does not send another command")
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        held[vk] = true; step(0.3); finish()
        equal(opened_count, 0, "rebinding to a held thumb button waits for release")
        equal(#events, 0)
        held[vk] = false; step(0.02); held[vk] = true; step(0.02)
        equal(opened_count, 1, "fresh thumb press opens after release")
        focused = false; step(0.02); held[vk] = false; focused = true; finish()
        equal(#events, 0, "focus loss cancels a mouse selection without input")
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); held[vk] = true; step(0.02); held[vk] = false; step(0.02)
        menu_override = false
        for index = 1, 4 do step(0.02) end
        equal(env.HD2StratagemHotkeys.owned_start, vk, "pending command owns the reacquired thumb button")
        equal(#events, 1)
        focused = false; step(0.02)
        equal(#events, 2, "focus loss releases only the owned thumb button before directions")
        equal(events[2][1], vk); equal(events[2][2], false)
        equal(env.HD2StratagemHotkeys.owned_start, nil)
        equal(env.HD2StratagemHotkeys.pending, nil)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); game_active_override = false
        held[vk] = true; step(0.02); finish()
        equal(opened_count, 0, "thumb button cannot bypass native character-menu eligibility")
        equal(#events, 0)
        held[vk] = false; step(0.02); env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); mouse_latch, held[vk] = true, true; step(0.02)
        hover = nil; step(0.02); held[vk] = false; step(0.02); finish()
        equal(#events, 1, "center cancel repairs a lost physical mouse up, not a new list press")
        equal(events[1][1], vk); equal(events[1][2], false)
        equal(mouse_latch, false); equal(env.HD2StratagemHotkeys.mouse_release, nil)
        equal(env.HD2StratagemHotkeys.pending, nil); equal(opened_count, 1)
        equal(table.concat(messages):find("mouse-release-observed vk=" .. vk, 1, true) ~= nil, true)
        equal(table.concat(messages):find("COMMAND kind=", 1, true), nil)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); mouse_latch, held[vk] = true, true; step(0.02)
        held[vk] = false; step(0.02); finish(); finish()
        equal(#events, 7, "lost physical up is repaired before one selected command")
        equal(events[1][1], vk); equal(events[1][2], false)
        equal(events[2][1], vk); equal(events[2][2], true)
        equal(events[3][1], 38); equal(events[7][1], vk); equal(events[7][2], false)
        equal(opened_count, 1, "repair and owned list press cannot reopen the radial")
        equal(table.concat(messages):find("SKIP list-close-timeout", 1, true), nil)
        equal(env.HD2StratagemHotkeys.mouse_release, nil)
        equal(env.HD2StratagemHotkeys.blocking_inputs, false)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); mouse_latch, held[vk] = true, true; step(0.02)
        focused = false; step(0.02); finish()
        equal(#events, 0, "never release a physically held thumb button")
        held[vk] = false; finish()
        equal(#events, 0, "never replay physical release into another foreground app")
        focused = true; finish()
        equal(#events, 1); equal(events[1][2], false)
        equal(env.HD2StratagemHotkeys.mouse_release, nil)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); mouse_latch, held[vk] = true, true; step(0.02)
        up_failures = 3; held[vk] = false; step(0.02); finish(); finish()
        equal(#events, 3, "failed mouse up insertion has bounded retries and no new press")
        for _, event in ipairs(events) do equal(event[1], vk); equal(event[2], false) end
        equal(env.HD2StratagemHotkeys.owned_start, nil)
        equal(env.HD2StratagemHotkeys.blocking_inputs, true)
        equal(table.concat(messages):find("mouse-release-send-failed", 1, true) ~= nil, true)
        mouse_latch = false; finish()
        equal(env.HD2StratagemHotkeys.mouse_release, nil)
        equal(env.HD2StratagemHotkeys.blocking_inputs, false)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); mouse_latch, held[vk] = true, true; step(0.02)
        ignore_up = true; held[vk] = false; step(0.02); finish(); finish()
        equal(#events, 1, "Windows success without game release never presses again or sends directions")
        equal(events[1][2], false)
        equal(env.HD2StratagemHotkeys.blocking_inputs, true)
        equal(table.concat(messages):find("mouse-release-not-observed", 1, true) ~= nil, true)
        mouse_latch = false; finish()
        equal(env.HD2StratagemHotkeys.mouse_release, nil)
        env.shutdown()

        restart()
        binding = {start_vk = vk, directions = {38, 39, 40, 37}}
        step(0.3); mouse_latch, held[vk] = true, true; step(0.02)
        mouse_observation = false; held[vk] = false; step(0.02); finish(); finish()
        equal(#events, 0, "unreadable game state cannot trigger a guessed mouse release")
        equal(table.concat(messages):find("mouse-release-state-unreadable", 1, true) ~= nil, true)
        env.shutdown()
    end
end

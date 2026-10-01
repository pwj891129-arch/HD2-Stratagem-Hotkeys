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
    for index = 1, 4 do inventory.rows[index] = {kind = index, ready = index ~= 2,
        picture = "0000000100000001", name = "ITEM", status = index == 2 and "5s" or "READY"} end
    local radial = Radial.new(sr, channel, 1, function(line) phases[#phases + 1] = line end)
    equal(radial:open(inventory), true, "radial opens")
    equal(table.concat(phases, "|"), "OVERLAY stage=resources|OVERLAY stage=dimensions|OVERLAY stage=world|" ..
        "OVERLAY stage=create-gui|OVERLAY stage=cursor|OVERLAY stage=draw|OVERLAY stage=ready",
        "open phases distinguish native API failures")
    equal(resolutions, 2, "opening and drawing both query back buffer without a GUI argument")
    local labels, bitmaps = 0, 0
    for _, shape in pairs(shapes) do
        if shape[1] == "text" and shape[3] == "ITEM" then labels = labels + 1 end
        if shape[1] == "bitmap" then bitmaps = bitmaps + 1 end
    end
    equal(labels, 4, "text fallback displays each equipped name")
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

    -- Actual addon sequencing with GUI/cursor and keyboard adapters; no OS input.
    local current, held, events, ready, token, focused, idle, menu = 0, {}, {}, true, "TOKEN", true, true, true
    local menu_override, hover = nil, 1
    local options = {radial = true}
    local binding = {start_vk = 164, directions = {38, 39, 40, 37}}
    local fake = {base = 1, foreground = function() return focused end,
        down = function(vk) return held[vk] or false end,
        key = function(vk, down) events[#events + 1] = {vk, down}; held[vk] = down; return true end}
    local request = function() if ready then return {token = token, kind = 1, keys = {38, 39}, bindings = binding} end end
    local fake_reader = {bindings = function() return binding, "ready" end,
        idle = function() return idle end, menu_active = function()
            if menu_override ~= nil then return menu_override end
            return menu and held[binding.start_vk] == true
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
    equal(#events, 8, "menu timeout releases owned start without directions")
    menu = true; idle = false; held[164] = true; step(0.02); held[164] = false; finish()
    equal(#events, 8, "menu or chat blocks overlay")
    idle = true; held[164], held[49] = true, true; finish()
    equal(#events, 8, "Arsenal hotkey option off")
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
        menu_override, hover, focused, idle, menu, ready = nil, 1, true, true, true, true
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
end

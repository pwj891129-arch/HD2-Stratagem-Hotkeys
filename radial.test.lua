return function(equal, read_file, source)
    local Radial = dofile("radial.lua")
    equal(Radial.pick(0.5, 0.5, 1280, 720, 4, 1), nil, "radial dead zone")
    for index, point in ipairs({{0.5, 0.9}, {0.8, 0.5}, {0.5, 0.1}, {0.2, 0.5}}) do
        equal(Radial.pick(point[1], point[2], 1280, 720, 4, 1), index, "clockwise sectors")
    end
    local x, y, foreground, worlds = 0.5, 0.5, true, {1, 2}
    local show, focus, created, destroyed, shapes, next_id = false, true, 0, 0, {}, 0
    local channel = {
        foreground = function() return foreground end,
        cursor = function() return x, y end,
        center_cursor = function() x, y = 0.5, 0.5; return true end,
    }
    local function v(a, b, c) return {x = a, y = b, z = c} end
    local sr = {Vector2 = v, Vector3 = v, Color = function(...) return {...} end,
        Application = {worlds = function() return worlds end, main_world = function() return 1 end,
            can_get = function() return true end},
        World = {create_screen_gui = function(w) equal(w, 2, "own overlay world"); created = created + 1; return 99 end,
            destroy_gui = function() destroyed = destroyed + 1 end},
        Window = {show_cursor = function() return show end, mouse_focus = function() return focus end,
            set_show_cursor = function(b) show = b end, set_mouse_focus = function(b) focus = b end},
        Gui = {resolution = function() return 1280, 720 end,
            material = function() error("custom material path must stay disabled") end,
            text_extents = function(_, text, _, size) return v(0, 0), v(#text * size * 0.5, size) end},
        Material = {set_texture = function() error("native texture mutation must stay disabled") end},
        IdString64 = {from_hex = function(t) return t end},
    }
    for _, kind in ipairs({"triangle", "bitmap", "text"}) do
        sr.Gui[kind] = function(...) next_id = next_id + 1; shapes[next_id] = {kind, ...}; return next_id end
        sr.Gui["destroy_" .. kind] = function(_, id) equal(shapes[id] ~= nil, true, "only own shape destroyed"); shapes[id] = nil end
    end
    local inventory = {token = "TOKEN", rows = {}}
    for index = 1, 4 do inventory.rows[index] = {kind = index, ready = index ~= 2,
        picture = "0000000100000001", name = "ITEM", status = index == 2 and "5s" or "READY"} end
    local radial = Radial.new(sr, channel, 1)
    equal(radial:open(inventory), true, "radial opens")
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
    sr.Application.can_get = function() return false end
    local opened, why = radial:open(inventory)
    equal(opened, false, "missing native font declines overlay")
    equal(why, "overlay-font-unavailable")

    -- Actual addon sequencing with GUI/cursor and keyboard adapters; no OS input.
    local current, held, events, ready, token, focused, idle, menu = 0, {}, {}, true, "TOKEN", true, true, true
    local options = {radial = true}
    local binding = {start_vk = 164, directions = {38, 39, 40, 37}}
    local fake = {base = 1, foreground = function() return focused end,
        down = function(vk) return held[vk] or false end,
        key = function(vk, down) events[#events + 1] = {vk, down}; held[vk] = down; return true end}
    local request = function() if ready then return {token = token, kind = 1, keys = {38, 39}, bindings = binding} end end
    local fake_reader = {bindings = function() return binding, "ready" end,
        idle = function() return idle end, menu_active = function() return menu end,
        loadout = function() return {token = token} end,
        request = request, request_kind = request,
        radial = function() return {token = token, rows = {{kind = 1, ready = ready, status = "READY"}}}, "ready" end}
    local mock_radial = {restore = function() end, dispose = function() end}
    function mock_radial:open(value) self.inventory, self.opened = value, true; return true end
    function mock_radial:draw() self.selected = 1; return true end
    function mock_radial:close() self.opened, self.selected, self.inventory = false, nil, nil end
    local env = setmetatable({fake = fake, fake_reader = fake_reader}, {__index = _G}); env._G = env
    env.CowboyBingusModLoader = {api = 1}
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
    step(0); held[5] = true; step(0.02)
    equal(#events, 0, "opening overlay never inputs command")
    equal(env.HD2StratagemHotkeys.blocking_inputs, true, "overlay blocks autoreload")
    held[5] = false; step(0.02); finish()
    equal(#events, 6, "release sends start plus two directions and releases start")
    equal(events[1][1], 164); equal(events[1][2], true)
    equal(events[6][1], 164); equal(events[6][2], false)
    equal(env.HD2StratagemHotkeys.blocking_inputs, false)
    ready = false; held[5] = true; step(0.02); held[5] = false; step(0.02); finish()
    equal(#events, 6, "unavailable sector sends nothing")
    ready = true; held[5] = true; step(0.02); focused = false; step(0.02)
    held[5] = false; focused = true; finish()
    equal(#events, 6, "focus loss cancels selection")
    held[5] = true; step(0.02); token = "CHANGED"; step(0.06); held[5] = false; finish()
    equal(#events, 6, "loadout change cancels overlay")
    menu = false; held[5] = true; step(0.02); held[5] = false; step(0.02); finish(); finish()
    equal(#events, 8, "menu timeout releases owned start without directions")
    menu = true; idle = false; held[5] = true; step(0.02); held[5] = false; finish()
    equal(#events, 8, "menu or chat blocks overlay")
    idle = true; held[164], held[49] = true, true; finish()
    equal(#events, 8, "Arsenal hotkey option off")
    env.shutdown()
end

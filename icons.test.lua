return function(equal)
    local Radial = dofile("radial.lua")
    local font = "core/performance_hud/debug"
    local guis, shapes, next_gui, next_shape, created, image_queries, logs = {}, {}, 0, 0, 0, 0, {}
    local loaded, worlds, width, height, x, y = {}, {1, 2}, 1280, 720, 0.5, 0.5
    local show, focus, fail = false, true, nil
    local function vec(a, b, c) return {x = a, y = b, z = c} end
    local function add(gui, kind, ...)
        assert(guis[gui], "only owned live GUI receives drawing")
        next_shape = next_shape + 1
        shapes[next_shape] = {gui = gui, kind = kind, args = {...}}
        return next_shape
    end
    local sr = {Vector2 = vec, Vector3 = vec, Color = function(...) return {...} end,
        IdString64 = {from_hex = function(hex)
            assert(#hex == 16 and hex:match("^[0-9a-fA-F]+$"), "validated native resource hash")
            if fail == "idstring" then error("idstring failed") end
            return {hex = hex}
        end},
        Application = {worlds = function() return worlds end, main_world = function() return 1 end,
            can_get = function(kind, name)
                if name == font then return kind == "font" or kind == "material" end
                assert(kind == "material", "native material only; no separate texture query")
                assert(type(name) == "table", "native image resources use IdString64, not guessed paths")
                image_queries = image_queries + 1
                if fail == "query" then error("resource query failed") end
                return loaded[name.hex] == true and fail ~= "unloaded-material"
            end},
        Window = {show_cursor = function() return show end, mouse_focus = function() return focus end,
            set_show_cursor = function(value) show = value end, set_mouse_focus = function(value) focus = value end},
        World = {create_screen_gui = function(world, mode, sx, sy)
                assert(world == 2 and mode == "scale" and sx == 1 and sy == 1, "known screen GUI contract")
                next_gui, created = next_gui + 1, created + 1
                guis[next_gui] = {world = world}
                return next_gui
            end,
            destroy_gui = function(world, gui)
                assert(worlds[2] == world and guis[gui], "never destroy stale or unowned GUI")
                for _, shape in pairs(shapes) do assert(shape.gui ~= gui, "shapes released before surface") end
                guis[gui] = nil
            end},
        Gui = {resolution = function(...) assert(select("#", ...) == 0); return width, height end,
            material = function() error("native icon drawing must not mutate any GUI material") end,
            bitmap = function(gui, name, position, size, colour)
                if fail == "bitmap" then error("bitmap failed") end
                if fail == "bitmap-nil" then return nil end
                assert(loaded[name.hex] and name.hex ~= "ccf39a02b444fa01", "native icon material, not debug font")
                assert(size.x > 0 and size.y == size.x and position.z == 11, "square aspect and bitmap layer")
                return add(gui, "bitmap", position, size, colour, name.hex)
            end,
            triangle = function(gui, ...) return add(gui, "triangle", ...) end,
            text = function(gui, text, resource, size, material, at, colour)
                assert(resource == font and material == font and size > 0)
                return add(gui, "text", text, size, at, colour)
            end,
            text_extents = function(_, text, _, size) return vec(0, 0), vec(#text * size * 0.5, size) end},
        Material = {set_texture = function() error("native textures/shaders must remain unchanged") end},
    }
    for _, kind in ipairs({"text", "triangle", "bitmap"}) do
        sr.Gui["destroy_" .. kind] = function(gui, id)
            assert(shapes[id] and shapes[id].gui == gui and shapes[id].kind == kind, "owned shape destruction")
            shapes[id] = nil
        end
    end
    local channel = {foreground = function() return true end, cursor = function() return x, y end,
        center_cursor = function() x, y = 0.5, 0.5; return true end}
    local function inventory(count)
        local rows = {}
        for index = 1, count do
            local picture = string.format("%016x", index)
            loaded[picture] = true
            rows[index] = {kind = index, slot = index <= 4 and index or nil, picture = picture,
                name = "ITEM " .. index, ready = index ~= 2, status = index == 2 and "5s" or "READY"}
        end
        return {token = "EQUIPPED", rows = rows}
    end
    local function bitmaps()
        local found = {}
        for _, shape in pairs(shapes) do if shape.kind == "bitmap" then found[#found + 1] = shape end end
        return found
    end
    local radial = Radial.new(sr, channel, 1, function(line) logs[#logs + 1] = line end)
    local inv = inventory(4)
    equal(radial:open(inv), true, "native icons open without custom resource archives")
    equal(created, 1, "icons and text share one owned radial surface")
    equal(#bitmaps(), 4, "four equipped icons rendered")
    local materials = {}
    for _, shape in ipairs(bitmaps()) do
        local material = shape.args[4]
        equal(shape.gui, radial.gui, "same GUI gives predictable native draw ordering")
        equal(materials[material], nil, "each icon retains its own native material")
        materials[material] = true
        local p, s = shape.args[1], shape.args[2]
        equal(s.x, 72, "normal four-slot icon size")
        equal(p.x >= 0 and p.y >= 0 and p.x + s.x <= width and p.y + s.y <= height, true, "icon within viewport")
        equal(shape.args[3][1], material == inv.rows[2].picture and 190 or 255, "cooldown icon dimming")
        for _, text in pairs(shapes) do
            if text.kind == "text" and text.args[1] == "ITEM " .. tonumber(material, 16) then
                equal(text.args[3].y + text.args[2] < p.y, true, "name remains below image without overlap")
            end
        end
    end
    for _, row in ipairs(inv.rows) do equal(materials[row.picture], true, "correct native art for each equipped item") end
    equal(table.concat(logs, "|"):find("OVERLAY icons=4/4", 1, true) ~= nil, true)
    local drawn = next_shape
    radial:draw(inv)
    equal(next_shape, drawn, "unchanged retained menu does not recreate primitives")
    x, y = 0.8, 0.5; radial:draw(inv)
    equal(created, 1, "hover redraw allocates no extra image surface")
    inv.rows[1].picture = "00000000000000ff"; loaded[inv.rows[1].picture] = true
    radial:draw(inv)
    equal(#bitmaps(), 4, "changed native material replaces one image without shared mutation")
    local replaced = false
    for _, shape in ipairs(bitmaps()) do if shape.args[4] == inv.rows[1].picture then replaced = true end end
    equal(replaced, true)
    loaded[inv.rows[1].picture] = false; radial:draw(inv)
    equal(#bitmaps(), 3, "unavailable native material falls back to name")
    equal(table.concat(logs, "|"):find("icon-fallback kind=1 material=00000000000000ff reason=native-material-unavailable",
        1, true) ~= nil, true, "fallback identifies exact kind, material and cause")
    local fallback_count = #logs
    x, y = 0.2, 0.5; radial:draw(inv)
    equal(#logs, fallback_count, "unchanged fallback reason does not spam hover logs")
    for _, text in pairs(shapes) do
        if text.kind == "text" and text.args[1] == "ITEM 1" then equal(text.args[2], 16, "larger readable name fallback") end
    end
    loaded[inv.rows[1].picture] = true; radial:draw(inv)
    equal(#bitmaps(), 4, "native resource recovery restores image")
    equal(created, 1, "native materials need no auxiliary GUI or texture binding")
    radial:close()
    equal(#bitmaps(), 0, "closing removes all owned bitmap shapes")
    equal(show, false); equal(focus, true)
    equal(radial:open(inv), true); equal(created, 1, "reopening reuses only owned radial surface")
    radial:dispose()
    equal(next(guis), nil); equal(next(shapes), nil)

    for _, failure in ipairs({"idstring", "query", "bitmap", "bitmap-nil", "unloaded-material"}) do
        fail, logs = failure, {}
        local menu = Radial.new(sr, channel, 1, function(line) logs[#logs + 1] = line end)
        local before = created
        equal(menu:open(inventory(4)), true, failure .. " keeps name fallback usable")
        equal(#bitmaps(), 0, failure .. " leaves no broken image shapes")
        equal(table.concat(logs, "|"):find("OVERLAY icon-fallback kind=", 1, true) ~= nil, true, "failure diagnosed")
        x, y = 0.8, 0.5; menu:draw(menu.inventory)
        equal(created, before + 1, "failed icons never create extra GUIs")
        menu:dispose(); equal(next(guis), nil); equal(next(shapes), nil)
    end
    fail = nil
    local bitmap = sr.Gui.bitmap
    sr.Gui.bitmap, logs = nil, {}
    local fallback = Radial.new(sr, channel, 1, function(line) logs[#logs + 1] = line end)
    equal(fallback:open(inventory(4)), true, "bitmap API absent still shows names")
    equal(table.concat(logs, "|"):find("reason=bitmap-api-unavailable", 1, true) ~= nil, true)
    fallback:dispose(); sr.Gui.bitmap = bitmap
    local queried = image_queries
    for _, picture in ipairs({"", "not-a-hash", "0000000000000000", "../../bad-texture", false}) do
        local data, reason = radial:icon_data(picture)
        equal(data, nil); equal(reason, "invalid-reference")
    end
    equal(image_queries, queried, "malformed references never reach native resource query")
    sr.Gui.material, sr.Material = nil, nil
    local direct = Radial.new(sr, channel)
    equal(direct:open(inventory(4)), true, "no material-mutation API required")
    equal(#bitmaps(), 4, "direct native bitmap path works without texture setters")
    direct:dispose()

    for _, viewport in ipairs({{1280, 720}, {3840, 2160}, {320, 240}}) do
        width, height = viewport[1], viewport[2]
        for count = 1, 16 do
            local menu = Radial.new(sr, channel, 1.3)
            equal(menu:open(inventory(count)), true)
            local images = bitmaps()
            equal(#images, count, "all personal and shared icons drawn")
            for index, a in ipairs(images) do
                local p, s = a.args[1], a.args[2]
                equal(p.x >= 0 and p.y >= 0 and p.x + s.x <= width and p.y + s.y <= height, true, "responsive icon bounds")
                for j = index + 1, #images do
                    local b, t = images[j].args[1], images[j].args[2]
                    local overlap = p.x < b.x + t.x and b.x < p.x + s.x and p.y < b.y + t.y and b.y < p.y + s.y
                    equal(overlap, false, "adjacent native icons never overlap")
                end
            end
            menu:dispose()
            equal(next(shapes), nil)
        end
    end
    width, height = 1280, 720
    local stale = Radial.new(sr, channel)
    equal(stale:open(inventory(4)), true)
    worlds = {1}; stale:dispose()
    equal(#stale.ids, 0, "stale-world disposal drops handles without dereferencing native objects")
    guis, shapes, worlds = {}, {}, {1, 2}
end

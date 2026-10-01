return function(equal)
    local Radial = dofile("radial.lua")
    local material_id, slot_id = "ccf39a02b444fa01", "3aa8b87e00000000"
    local font = "core/performance_hud/debug"
    local guis, shapes, next_gui, next_shape, created, binds, logs = {}, {}, 0, 0, 0, 0, {}
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
            return {hex = hex}
        end},
        Application = {worlds = function() return worlds end, main_world = function() return 1 end,
            can_get = function(kind, name)
                if name == font then return kind == "font" or kind == "material" end
                assert(type(name) == "table", "native image resources use IdString64, not guessed paths")
                if kind == "material" then return name.hex == material_id and fail ~= "unloaded-material" end
                assert(kind == "texture", "only texture availability queried for art")
                return loaded[name.hex] == true
            end},
        Window = {show_cursor = function() return show end, mouse_focus = function() return focus end,
            set_show_cursor = function(value) show = value end, set_mouse_focus = function(value) focus = value end},
        World = {create_screen_gui = function(world, mode, sx, sy)
                assert(world == 2 and mode == "scale" and sx == 1 and sy == 1, "known screen GUI contract")
                if next_gui > 0 and fail == "create" then error("icon GUI unavailable") end
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
            material = function(gui, name)
                assert(guis[gui] and name.hex == material_id, "only native template on own surface")
                if fail == "material" then return nil end
                assert(not guis[gui].material, "one material instance per icon GUI")
                local ink = {gui = gui}
                guis[gui].material = ink
                return ink
            end,
            bitmap = function(gui, name, position, size, colour)
                if fail == "bitmap" then error("bitmap failed") end
                local ink = assert(guis[gui].material)
                assert(name.hex == material_id and loaded[ink.texture], "only loaded bound native textures drawn")
                assert(size.x > 0 and size.y == size.x and position.z == 11, "square aspect and bitmap layer")
                return add(gui, "bitmap", position, size, colour, ink.texture)
            end,
            triangle = function(gui, ...) return add(gui, "triangle", ...) end,
            text = function(gui, text, resource, size, material, at, colour)
                assert(resource == font and material == font and size > 0)
                return add(gui, "text", text, size, at, colour)
            end,
            text_extents = function(_, text, _, size) return vec(0, 0), vec(#text * size * 0.5, size) end},
        Material = {set_texture = function(ink, slot, texture)
                assert(guis[ink.gui] and guis[ink.gui].material == ink, "only GUI-local instance may be mutated")
                assert(slot.hex == slot_id and loaded[texture.hex], "verified diffuse slot and loaded art")
                if fail == "bind" then error("binding failed") end
                ink.texture, binds = texture.hex, binds + 1
            end},
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
    equal(created, 5, "base surface and four isolated icon surfaces")
    equal(binds, 4, "one native binding per equipped image")
    equal(#bitmaps(), 4, "four equipped icons rendered")
    local materials, textures = {}, {}
    for _, shape in ipairs(bitmaps()) do
        local ink = guis[shape.gui].material
        equal(materials[ink], nil, "each icon has independent material instance")
        materials[ink], textures[ink.texture] = true, true
        local p, s = shape.args[1], shape.args[2]
        equal(s.x, 72, "normal four-slot icon size")
        equal(p.x >= 0 and p.y >= 0 and p.x + s.x <= width and p.y + s.y <= height, true, "icon within viewport")
        equal(shape.args[3][1], ink.texture == inv.rows[2].picture and 190 or 255, "cooldown icon dimming")
        for _, text in pairs(shapes) do
            if text.gui == radial.gui and text.kind == "text" and text.args[1] == "ITEM " .. tonumber(ink.texture, 16) then
                equal(text.args[3].y + text.args[2] < p.y, true, "name remains below image without overlap")
            end
        end
    end
    for _, row in ipairs(inv.rows) do equal(textures[row.picture], true, "correct native art for each equipped item") end
    equal(table.concat(logs, "|"):find("OVERLAY icons=4/4", 1, true) ~= nil, true)
    local drawn = next_shape
    radial:draw(inv)
    equal(next_shape, drawn, "unchanged retained menu does not recreate primitives")
    x, y = 0.8, 0.5; radial:draw(inv)
    equal(created, 5, "hover redraw reuses isolated surfaces")
    equal(binds, 4, "hover does not rebind unchanged textures")
    local replacement = "00000000000000ff"; loaded[replacement] = true
    inv.rows[1].picture = replacement; radial:draw(inv)
    equal(binds, 5, "changed native icon reference is rebound once")
    equal(#bitmaps(), 4, "icon hash change triggers redraw")
    loaded[replacement] = false; radial:draw(inv)
    equal(#bitmaps(), 3, "unloaded image immediately loses its retained bitmap")
    equal(binds, 5, "unloaded art is never passed into native texture setter")
    local fallback = false
    for _, shape in pairs(shapes) do
        if shape.kind == "text" and shape.args[1] == "ITEM 1" and shape.args[2] == 16 then fallback = true end
    end
    equal(fallback, true, "unavailable icon retains readable name fallback")
    loaded[replacement] = true; radial:draw(inv)
    equal(#bitmaps(), 4, "loaded native icon resumes without restarting")
    equal(created, 6, "resource recovery replaces the old native surface once")
    equal(binds, 6, "recovered resource gets a fresh texture binding")
    radial:close()
    equal(#bitmaps(), 0, "closing removes all icon primitives")
    local live_gui_count = 0
    for _ in pairs(guis) do live_gui_count = live_gui_count + 1 end
    equal(live_gui_count, 1, "closing releases icon surfaces before resources can unload")
    equal(show, false); equal(focus, true, "cursor restored with icons")
    equal(radial:open(inv), true)
    equal(created, 10, "reopening gets fresh image surfaces but reuses main GUI")
    radial:dispose()
    equal(next(guis), nil, "shutdown releases all owned icon and main surfaces")
    equal(next(shapes), nil)

    for _, reason in ipairs({"create", "material", "bind", "bitmap", "unloaded-material"}) do
        next_gui, created, binds, fail = 0, 0, 0, reason
        local broken = Radial.new(sr, channel, 1)
        equal(broken:open(inv), true, "optional icon failure keeps overlay working: " .. reason)
        equal(#bitmaps(), 0, "failed icons never leave an old/default bitmap")
        local allocations = created
        x = 0.8; broken:draw(inv); x = 0.2; broken:draw(inv)
        equal(created, allocations, "failure redraw does not repeatedly allocate native surfaces")
        broken:dispose(); equal(next(guis), nil, "failure cleanup releases allocated native surfaces")
    end
    fail = nil
    local absent = Radial.new(sr, channel, 1)
    local original_material = sr.Gui.material
    sr.Gui.material = nil
    equal(absent:open(inv), true, "missing optional native bitmap API falls back to names")
    equal(#bitmaps(), 0)
    absent:dispose(); sr.Gui.material = original_material
    for _, value in ipairs({"", "not-a-hash", "0000000000000000", "../../bad-texture", false}) do
        equal(absent:icon_data(value), nil, "malformed icon reference never reaches native resource lookup")
    end

    for count = 1, 16 do
        for _, dims in ipairs({{1280, 720}, {3840, 2160}, {320, 240}}) do
            width, height = dims[1], dims[2]
            local many = Radial.new(sr, channel, 1.3)
            equal(many:open(inventory(count)), true, "one-to-sixteen item icon layout")
            equal(#bitmaps(), count, "all available native icons are displayed")
            local seen = bitmaps()
            for i, image in ipairs(seen) do
                local p, s = image.args[1], image.args[2]
                equal(p.x >= 0 and p.y >= 0 and p.x + s.x <= width and p.y + s.y <= height, true,
                    "scaled icons remain on small and wide screens")
                for j = i + 1, #seen do
                    local q, t = seen[j].args[1], seen[j].args[2]
                    equal(p.x + s.x <= q.x or q.x + t.x <= p.x or p.y + s.y <= q.y or q.y + t.y <= p.y,
                        true, "neighboring icon rectangles never overlap")
                end
            end
            many:dispose()
        end
    end

    width, height = 1280, 720
    local stale = Radial.new(sr, channel, 1)
    equal(stale:open(inv), true)
    worlds = {1}; stale:dispose()
    equal(#stale.icons, 0, "stale world drops cached icon handles without native dereference")
    -- The engine owns destruction of the removed world; simulate that teardown.
    guis, shapes, worlds = {}, {}, {1, 2}
end

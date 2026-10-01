return function(equal)
    local Radial = dofile("radial.lua")
    local font, template = "core/performance_hud/debug", "c0f3797849262087"
    local guis, shapes, next_gui, next_shape, created, binds, logs = {}, {}, 0, 0, 0, 0, {}
    local loaded, worlds, width, height, x, y = {}, {1, 2}, 1280, 720, 0.5, 0.5
    local show, focus, fail = false, true, nil
    local function vec(a, b, c, d) return {x = a, y = b, z = c, w = d} end
    local function add(gui, kind, ...)
        assert(guis[gui], "only owned live GUI receives drawing")
        next_shape = next_shape + 1
        shapes[next_shape] = {gui = gui, kind = kind, args = {...}}
        return next_shape
    end
    local sr = {Vector2 = vec, Vector3 = vec, Vector4 = vec, Color = function(...) return {...} end,
        IdString64 = {from_hex = function(hex)
            assert(#hex == 16 and hex:match("^[0-9a-fA-F]+$"))
            if fail == "idstring" then error("idstring failed") end
            return {hex = hex}
        end},
        Application = {worlds = function() return worlds end, main_world = function() return 1 end,
            can_get = function(kind, name)
                if name == font then return kind == "font" or kind == "material" end
                assert(type(name) == "table")
                if fail == "query" then error("resource query failed") end
                if kind == "material" then return name.hex == template and fail ~= "unloaded-material" end
                assert(kind == "texture", "only resolved atlas queried, not per-definition bitmap material")
                return loaded[name.hex] == true
            end},
        Window = {show_cursor = function() return show end, mouse_focus = function() return focus end,
            set_show_cursor = function(value) show = value end, set_mouse_focus = function(value) focus = value end},
        World = {create_screen_gui = function(world, mode, sx, sy)
                assert(world == 2 and mode == "scale" and sx == 1 and sy == 1)
                if next_gui > 0 and fail == "create" then return 0 end
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
                assert(guis[gui] and name.hex == template and not guis[gui].material)
                if fail == "material" then return nil end
                if fail == "material-zero" then return 0 end
                local ink = {gui = gui, colors = {}}
                guis[gui].material = ink
                return ink
            end,
            bitmap = function() error("raw definition material path must not be used") end,
            bitmap_uv = function(gui, name, lo, hi, position, size, colour)
                if fail == "bitmap" then error("bitmap failed") end
                if fail == "bitmap-nil" then return nil end
                local ink = assert(guis[gui].material)
                assert(name.hex == template and loaded[ink.texture] and ink.colors["10c353af00000000"])
                assert(lo.x < hi.x and lo.y < hi.y and hi.x <= 1 and hi.y <= 1)
                assert(size.x > 0 and size.y == size.x and position.z == 11)
                local id = add(gui, "bitmap", position, size, colour, ink, lo, hi)
                if fail == "bitmap-zero" then shapes[0], shapes[id] = shapes[id], nil; return 0 end
                return id
            end,
            triangle = function(gui, ...) return add(gui, "triangle", ...) end,
            text = function(gui, text, resource, size, material, at, colour)
                assert(resource == font and material == font and size > 0)
                return add(gui, "text", text, size, at, colour)
            end,
            text_extents = function(_, text, _, size) return vec(0, 0), vec(#text * size * 0.5, size) end},
        Material = {set_texture = function(ink, slot, texture)
                assert(guis[ink.gui].material == ink and slot.hex == "3aa8b87e00000000" and loaded[texture.hex])
                if fail == "bind" then error("binding failed") end
                ink.texture, binds = texture.hex, binds + 1
            end,
            set_vector4 = function(ink, slot, value)
                assert(guis[ink.gui].material == ink, "mutate only owned GUI-local material")
                if fail == "color" then error("color failed") end
                ink.colors[slot.hex] = {value.x, value.y, value.z, value.w}
            end},
    }
    for _, kind in ipairs({"text", "triangle", "bitmap"}) do
        sr.Gui["destroy_" .. kind] = function(gui, id)
            assert(shapes[id] and shapes[id].gui == gui and shapes[id].kind == kind)
            shapes[id] = nil
        end
    end
    local channel = {foreground = function() return true end, cursor = function() return x, y end,
        center_cursor = function() x, y = 0.5, 0.5; return true end}
    local function inventory(count)
        local rows = {}
        for index = 1, count do
            local texture = string.format("%016x", 256 + index)
            loaded[texture] = true
            rows[index] = {kind = index, slot = index <= 4 and index or nil, picture = string.format("%016x", index),
                art = {texture = texture, uv = {0.125, 0.25, 0.375, 0.5},
                    colors = {{0.8, 0.34, 0.84, 0.98}, {1, 1, 1, 0.93}, {0.2, 0, 0, 0}}},
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
    equal(radial:open(inv), true)
    equal(created, 5, "only radial and isolated owned icon surfaces")
    equal(binds, 4)
    equal(#bitmaps(), 4)
    local materials, textures = {}, {}
    for _, shape in ipairs(bitmaps()) do
        local ink, p, s = shape.args[4], shape.args[1], shape.args[2]
        equal(materials[ink], nil, "images have independent material instances")
        materials[ink], textures[ink.texture] = true, true
        equal(s.x, 72)
        equal(p.x >= 0 and p.y >= 0 and p.x + s.x <= width and p.y + s.y <= height, true)
        equal(shape.args[5].x, 0.125); equal(shape.args[6].x, 0.375, "atlas offset+width converted to opposite corner")
        equal(table.concat(ink.colors["28723f4d00000000"], ","), "0.8,0.34,0.84,0.98", "raw shader vector order preserved")
        equal(shape.args[3][1], ink.texture == inv.rows[2].art.texture and 190 or 255)
    end
    for _, row in ipairs(inv.rows) do equal(textures[row.art.texture], true) end
    equal(table.concat(logs, "|"):find("icon-source kind=1 slot=1 picture=", 1, true) ~= nil, true)
    local drawn = next_shape
    radial:draw(inv); equal(next_shape, drawn, "unchanged retained menu does not recreate shapes")
    x, y = 0.8, 0.5; radial:draw(inv)
    equal(created, 5); equal(binds, 4, "hover reuses atlas/material bindings")
    inv.rows[1].art.uv[1] = 0.2; radial:draw(inv)
    equal(binds, 5, "UV change invalidates binding signature")
    inv.rows[1].art.colors[1][2] = 0.5; radial:draw(inv)
    equal(binds, 6, "color change updates shader parameters")
    loaded[inv.rows[1].art.texture] = false; radial:draw(inv)
    equal(#bitmaps(), 3)
    equal(table.concat(logs, "|"):find("reason=native-atlas-unavailable", 1, true) ~= nil, true)
    local fallback_count = #logs
    x, y = 0.2, 0.5; radial:draw(inv); equal(#logs, fallback_count, "unchanged fallback does not spam logs")
    loaded[inv.rows[1].art.texture] = true; radial:draw(inv)
    equal(#bitmaps(), 4); equal(created, 6, "resource recovery creates fresh owned icon instance")
    radial:close(); equal(#bitmaps(), 0); equal(show, false); equal(focus, true)
    equal(radial:open(inv), true); equal(created, 10, "reopening reuses base GUI and creates clean icon instances")
    radial:dispose(); equal(next(guis), nil); equal(next(shapes), nil)
    local shared = inventory(4)
    for index, row in ipairs(shared.rows) do
        row.art.texture = shared.rows[1].art.texture
        row.art.uv = {(index - 1) / 4, 0, index / 4, 0.25}
        row.art.colors[1][2] = index / 4
    end
    local shared_menu = Radial.new(sr, channel)
    equal(shared_menu:open(shared), true)
    local independent = {}
    for _, shape in ipairs(bitmaps()) do
        local ink, uv = shape.args[4], shape.args[5]
        equal(independent[ink], nil); independent[ink] = true
        equal(ink.colors["28723f4d00000000"][2], uv.x + 0.25,
            "same atlas retains each icon's own region and RGB color")
    end
    shared_menu:dispose(); equal(next(guis), nil); equal(next(shapes), nil)
    for _, failure in ipairs({"idstring", "query", "unloaded-material", "create", "material", "material-zero", "bind", "color", "bitmap", "bitmap-nil"}) do
        fail, logs = failure, {}
        local menu = Radial.new(sr, channel, 1, function(line) logs[#logs + 1] = line end)
        local rows = inventory(4)
        equal(menu:open(rows), failure ~= "create", failure .. " safe fallback or decline")
        equal(#bitmaps(), 0)
        if failure ~= "create" then
            equal(table.concat(logs, "|"):find("OVERLAY icon-fallback kind=", 1, true) ~= nil, true)
            local before = created
            x, y = 0.8, 0.5; menu:draw(rows); equal(created, before, "failed icons do not allocate unbounded surfaces")
        end
        menu:dispose(); equal(next(guis), nil); equal(next(shapes), nil)
    end
    fail = nil
    local zero_id = Radial.new(sr, channel)
    fail = "bitmap-zero"
    equal(zero_id:open(inventory(1)), true)
    equal(#bitmaps(), 1, "zero is a valid shape ID, not a null material pointer")
    zero_id:dispose(); equal(next(guis), nil); equal(next(shapes), nil)
    fail = nil
    local bitmap = sr.Gui.bitmap_uv
    sr.Gui.bitmap_uv = nil
    local fallback = Radial.new(sr, channel)
    equal(fallback:open(inventory(4)), true); equal(#bitmaps(), 0)
    fallback:dispose(); sr.Gui.bitmap_uv = bitmap
    for _, picture in ipairs({"", "not-a-hash", "0000000000000000", "../../bad-texture", false}) do
        local data, reason = radial:icon_data({picture = picture})
        equal(data, nil); equal(reason, "invalid-reference")
    end
    local missing = inventory(1)
    missing.rows[1].art, missing.rows[1].art_error = nil, "atlas-changed"
    local data, reason = radial:icon_data(missing.rows[1]); equal(data, nil); equal(reason, "atlas-changed")
    for _, viewport in ipairs({{1280, 720}, {3840, 2160}, {320, 240}}) do
        width, height = viewport[1], viewport[2]
        for count = 1, 16 do
            local menu = Radial.new(sr, channel, 1.3)
            equal(menu:open(inventory(count)), true)
            local images = bitmaps(); equal(#images, count)
            for index, a in ipairs(images) do
                local p, s = a.args[1], a.args[2]
                equal(p.x >= 0 and p.y >= 0 and p.x + s.x <= width and p.y + s.y <= height, true)
                for j = index + 1, #images do
                    local b, t = images[j].args[1], images[j].args[2]
                    equal(p.x < b.x + t.x and b.x < p.x + s.x and p.y < b.y + t.y and b.y < p.y + s.y, false)
                end
            end
            menu:dispose(); equal(next(shapes), nil); equal(next(guis), nil)
        end
    end
    width, height = 1280, 720
    local stale = Radial.new(sr, channel); equal(stale:open(inventory(4)), true)
    worlds = {1}; stale:dispose(); equal(#stale.ids, 0); equal(next(stale.icons), nil)
end

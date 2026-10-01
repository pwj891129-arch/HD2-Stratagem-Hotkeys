local Radial = {}
Radial.__index = Radial
local ICON_MATERIAL, ICON_SLOT = "ccf39a02b444fa01", "3aa8b87e00000000"
function Radial.new(sr, channel, scale, trace)
    return setmetatable({sr = sr, channel = channel, scale = scale or 1, ids = {}, icons = {}, trace = trace}, Radial)
end
function Radial:dimensions()
    -- Gui.resolution accepts an optional viewport, never a Gui object.
    local width, height = self.sr.Gui.resolution()
    if type(width) == "number" and type(height) == "number" and
        width >= 320 and height >= 240 and width <= 32768 and height <= 32768 then
        return width, height
    end
end
function Radial.pick(x, y, width, height, count, scale)
    if not x or not y or count < 1 then return nil end
    local dx, dy = (x - 0.5) * width, (y - 0.5) * height
    if dx * dx + dy * dy < (38 * scale) ^ 2 then return nil end
    local angle = (math.pi / 2 - math.atan2(dy, dx)) % (2 * math.pi)
    return math.floor((angle + math.pi / count) / (2 * math.pi / count)) % count + 1
end
function Radial:world_live(world)
    local worlds = self.sr.Application.worlds()
    for _, value in pairs(worlds or {}) do if value == world then return true end end
    return false
end
function Radial:clear()
    local live = self.gui and self:world_live(self.world)
    if live then
        for _, item in ipairs(self.ids) do self.sr.Gui["destroy_" .. item[1]](self.gui, item[2]) end
    end
    for _, icon in pairs(self.icons) do
        if live and icon.id ~= nil then self.sr.Gui.destroy_bitmap(icon.gui, icon.id) end
        icon.id = nil
    end
    self.ids, self.signature = {}, nil
end
function Radial:restore()
    if self.mouse and self.channel.foreground() then
        self.channel.center_cursor()
        self.sr.Window.set_show_cursor(self.mouse.show)
        self.sr.Window.set_mouse_focus(self.mouse.focus)
        self.mouse = nil
    end
end
function Radial:close()
    self.opened, self.selected, self.inventory = false, nil, nil
    local good, why = pcall(function()
        self:clear()
        if self.gui and self:world_live(self.world) then
            for _, icon in pairs(self.icons) do
                if icon.gui then self.sr.World.destroy_gui(self.world, icon.gui) end
            end
        end
        self.icons, self.icon_report = {}, nil
    end)
    self:restore()
    if not good then error(why) end
end
function Radial:dispose()
    self:close()
    if self.gui and self:world_live(self.world) then
        self.sr.World.destroy_gui(self.world, self.gui)
    end
    self.icons, self.icon_material, self.icon_slot, self.icon_report = {}, nil, nil, nil
    self.gui, self.world = nil, nil
end
function Radial:icon_data(picture)
    local sr = self.sr
    if type(picture) ~= "string" or #picture ~= 16 or not picture:match("^[0-9a-fA-F]+$") or
        picture == "0000000000000000" then return nil end
    if not sr.Gui.bitmap or not sr.Gui.destroy_bitmap or not sr.Gui.material or not sr.Material or
        not sr.Material.set_texture or not sr.IdString64 or not sr.IdString64.from_hex then return nil end
    local ok, material, slot, texture = pcall(function()
        local ids = sr.IdString64.from_hex
        local mat, field = self.icon_material or ids(ICON_MATERIAL), self.icon_slot or ids(ICON_SLOT)
        local art = ids(picture)
        if not mat or not field or not art or not sr.Application.can_get("material", mat) or
            not sr.Application.can_get("texture", art) then return end
        return mat, field, art
    end)
    if not ok or not material then return nil end
    self.icon_material, self.icon_slot = material, slot
    return {picture = picture, texture = texture}
end
function Radial:icon(index, data, x, y, size, colour)
    if not data then return false end
    local sr, icon = self.sr, self.icons[index]
    if not icon then
        -- Gui.material is GUI-local; separate owned surfaces keep textures independent.
        local good, gui = pcall(sr.World.create_screen_gui, self.world, "scale", 1, 1)
        if not good or not gui or gui == 0 then
            self.icons[index] = {failed = true}
            return false
        end
        icon = {gui = gui}
        self.icons[index] = icon
        local bound, material = pcall(sr.Gui.material, gui, self.icon_material)
        if not bound or not material or material == 0 then icon.failed = true; return false end
        icon.material = material
    end
    if icon.failed then return false end
    if icon.picture ~= data.picture then
        local good = pcall(sr.Material.set_texture, icon.material, self.icon_slot, data.texture)
        if not good then icon.failed = true; return false end
        icon.picture = data.picture
    end
    local good, id = pcall(sr.Gui.bitmap, icon.gui, self.icon_material,
        sr.Vector3(x - size / 2, y - size / 2, 11), sr.Vector2(size, size), colour)
    if not good or id == nil then icon.failed = true; return false end
    icon.id = id
    return true
end
function Radial:open(inventory)
    local sr, app, win = self.sr, self.sr.Application, self.sr.Window
    local function stage(name) if self.trace then self.trace("OVERLAY stage=" .. name) end end
    if not app or not sr.Gui or not sr.World or not win or not sr.Vector3 or not sr.Vector2 or not sr.Color or
        not win.set_mouse_focus or not win.mouse_focus or not win.show_cursor or
        not win.set_show_cursor or not self.channel.cursor or not self.channel.center_cursor or
        not app.worlds or not app.main_world or not app.can_get or
        not sr.World.create_screen_gui or not sr.World.destroy_gui or not sr.Gui.resolution or
        not sr.Gui.triangle or not sr.Gui.destroy_triangle or not sr.Gui.text or
        not sr.Gui.text_extents or not sr.Gui.destroy_text then return false, "overlay-api-unavailable" end
    if not inventory or type(inventory.rows) ~= "table" or #inventory.rows < 1 or #inventory.rows > 16 then
        return false, "overlay-inventory-unavailable"
    end
    stage("resources")
    if not app.can_get("font", "core/performance_hud/debug") then
        return false, "overlay-font-unavailable"
    end
    if not app.can_get("material", "core/performance_hud/debug") then
        return false, "overlay-material-unavailable"
    end
    stage("dimensions")
    local width, height = self:dimensions()
    if not width then return false, "overlay-resolution-unavailable" end
    self.width, self.height = width, height
    if self.mouse then self:restore(); if self.mouse then return false, "cursor-restore-pending" end end
    stage("world")
    local main, target = app.main_world(), nil
    for _, world in pairs(app.worlds() or {}) do if world ~= main then target = world; break end end
    if not target then return false, "overlay-world-unavailable" end
    if self.world ~= target or not self.gui or not self:world_live(self.world) then
        self:dispose()
        stage("create-gui")
        self.gui = sr.World.create_screen_gui(target, "scale", 1, 1)
        if not self.gui then return false, "overlay-gui-unavailable" end
        self.world = target
    end
    stage("cursor")
    self.mouse = {show = win.show_cursor(), focus = win.mouse_focus()}
    if type(self.mouse.show) ~= "boolean" or type(self.mouse.focus) ~= "boolean" then
        self.mouse = nil; return false, "cursor-state-unavailable"
    end
    win.set_mouse_focus(false)
    win.set_show_cursor(true)
    if not self.channel.center_cursor() then self:close(); return false, "cursor-center-failed" end
    self.inventory, self.opened = inventory, true
    stage("draw")
    if not self:draw(inventory) then self:close(); return false, "overlay-surface-unavailable" end
    stage("ready")
    return true
end
function Radial:shape(kind, ...)
    local id = self.sr.Gui[kind](self.gui, ...)
    if id == nil then error("overlay-" .. kind .. "-failed") end
    self.ids[#self.ids + 1] = {kind, id}
end
function Radial:text(text, x, y, size, colour, maximum_width)
    local sr, font = self.sr, "core/performance_hud/debug"
    if not sr.Application.can_get("font", font) or not sr.Application.can_get("material", font) or
        not sr.Gui.text or not sr.Gui.text_extents then return end
    local lo, hi = sr.Gui.text_extents(self.gui, text, font, size)
    local width = hi.x - lo.x
    local limit = math.min(self.width - 40, maximum_width or self.width)
    if width > limit then
        size = size * limit / width
        lo, hi = sr.Gui.text_extents(self.gui, text, font, size)
        width = hi.x - lo.x
    end
    self:shape("text", text, font, size, font, sr.Vector3(x - width / 2, y, 12), colour)
end
function Radial:draw(inventory)
    if not self.opened or not self:world_live(self.world) then return false end
    local sr, rows, scale = self.sr, inventory.rows, self.scale
    local w, h = self:dimensions()
    if not w or #rows < 1 or #rows > 16 or
        not sr.Application.can_get("font", "core/performance_hud/debug") or
        not sr.Application.can_get("material", "core/performance_hud/debug") then return false end
    self.width, self.height = w, h
    local base_radius = #rows > 8 and 210 or 165
    scale = math.min(scale, h / (2 * (base_radius + 104)), w / (2 * (base_radius + 76)))
    local nx, ny = self.channel.cursor()
    if not nx then return false end
    self.selected = Radial.pick(nx, ny, w, h, #rows, scale)
    local mark, pictures = {tostring(self.selected), tostring(w), tostring(h)}, {}
    for index, row in ipairs(rows) do
        pictures[index] = self:icon_data(row.picture)
        mark[#mark + 1] = row.kind .. ":" .. row.status .. ":" .. tostring(row.name) .. ":" .. tostring(row.slot) ..
            ":" .. tostring(row.ready) .. ":" .. (pictures[index] and row.picture or "no-icon")
    end
    local signature = table.concat(mark, "|")
    if signature == self.signature then return true end
    self:clear()
    for index, icon in pairs(self.icons) do
        if not pictures[index] then
            if icon.gui then sr.World.destroy_gui(self.world, icon.gui) end
            self.icons[index] = nil
        end
    end
    local radius = base_radius * scale
    local inner, outer = 54 * scale, radius + 64 * scale
    local cx, cy = w / 2, h / 2
    local drawn_icons = 0
    local function vertex(r, a) return sr.Vector3(cx + r * math.cos(a), 0, cy + r * math.sin(a)) end
    for index, row in ipairs(rows) do
        local selected = index == self.selected
        local angle, half = math.pi / 2 - (index - 1) * math.pi * 2 / #rows, math.pi / #rows - 0.02
        local colour = selected and row.ready and sr.Color(225, 92, 110, 38) or
            (row.ready and sr.Color(205, 28, 32, 36) or sr.Color(200, 18, 20, 23))
        for step = 0, 5 do
            local a, b = angle - half + half * step / 3, angle - half + half * (step + 1) / 3
            self:shape("triangle", vertex(inner, a), vertex(outer, a), vertex(outer, b), 10, colour)
            self:shape("triangle", vertex(inner, a), vertex(outer, b), vertex(inner, b), 10, colour)
        end
        local x, y = cx + radius * math.cos(angle), cy + radius * math.sin(angle)
        local ink = row.ready and sr.Color(255, 255, 255, 240) or sr.Color(190, 125, 128, 130)
        local label_width = math.min(210 * scale, 2 * radius * math.sin(math.pi / math.max(2, #rows)) - 16 * scale)
        local icon_size = math.min(72 * scale,
            2 * radius * math.sin(math.pi / math.max(2, #rows)) / math.sqrt(2) - 8 * scale)
        local shown = self:icon(index, pictures[index], x, y + 5 * scale, icon_size, ink)
        if shown then drawn_icons = drawn_icons + 1 end
        self:text(row.name or ("STRATAGEM " .. row.kind), x, y - (shown and 49 or 7) * scale,
            (shown and 14 or 16) * scale, ink, label_width)
        if row.slot then self:text(tostring(row.slot), x, y + 48 * scale, 18 * scale, ink) end
        self:text(row.status, x, y - (shown and 70 or 50) * scale, shown and 13 * scale or 16 * scale, ink)
    end
    local report = drawn_icons .. "/" .. #rows
    if report ~= self.icon_report then
        self.icon_report = report
        if self.trace then self.trace("OVERLAY icons=" .. report) end
    end
    if self.selected then
        local row = rows[self.selected]
        self:text(row.name or tostring(row.kind), cx, cy - outer - 33 * scale, 20 * scale, sr.Color(255, 245, 240, 210))
    end
    self.signature = signature
    return true
end
return Radial

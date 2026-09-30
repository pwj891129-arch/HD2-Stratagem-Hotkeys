local Radial = {}
Radial.__index = Radial
function Radial.new(sr, channel, scale)
    return setmetatable({sr = sr, channel = channel, scale = scale or 1, ids = {}}, Radial)
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
    if self.gui and self:world_live(self.world) then
        for _, item in ipairs(self.ids) do self.sr.Gui["destroy_" .. item[1]](self.gui, item[2]) end
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
    local good, why = pcall(self.clear, self)
    self:restore()
    if not good then error(why) end
end
function Radial:dispose()
    self:close()
    if self.gui and self:world_live(self.world) then self.sr.World.destroy_gui(self.world, self.gui) end
    self.gui, self.world = nil, nil
end
function Radial:open(inventory)
    local sr, app, win = self.sr, self.sr.Application, self.sr.Window
    if not sr.Gui or not sr.World or not win or not sr.Vector3 or not sr.Vector2 or not sr.Color or
        not win.set_mouse_focus or not win.mouse_focus or not win.show_cursor or
        not win.set_show_cursor or not self.channel.cursor or not self.channel.center_cursor or
        not app.worlds or not app.main_world or not app.can_get or
        not sr.World.create_screen_gui or not sr.World.destroy_gui or not sr.Gui.resolution or
        not sr.Gui.triangle or not sr.Gui.destroy_triangle or not sr.Gui.text or
        not sr.Gui.text_extents or not sr.Gui.destroy_text then return false, "overlay-api-unavailable" end
    if not app.can_get("font", "core/performance_hud/debug") then
        return false, "overlay-font-unavailable"
    end
    if self.mouse then self:restore(); if self.mouse then return false, "cursor-restore-pending" end end
    local main, target = app.main_world(), nil
    for _, world in pairs(app.worlds() or {}) do if world ~= main then target = world; break end end
    if not target then return false, "overlay-world-unavailable" end
    if self.world ~= target or not self.gui or not self:world_live(self.world) then
        self:dispose()
        self.gui = sr.World.create_screen_gui(target, "scale", 1, 1)
        if not self.gui then return false, "overlay-gui-unavailable" end
        self.world = target
    end
    local width, height = sr.Gui.resolution(self.gui)
    if not width or not height or width < 320 or height < 240 then return false, "overlay-resolution-unavailable" end
    self.width, self.height = width, height
    self.mouse = {show = win.show_cursor(), focus = win.mouse_focus()}
    if type(self.mouse.show) ~= "boolean" or type(self.mouse.focus) ~= "boolean" then
        self.mouse = nil; return false, "cursor-state-unavailable"
    end
    win.set_mouse_focus(false)
    win.set_show_cursor(true)
    if not self.channel.center_cursor() then self:close(); return false, "cursor-center-failed" end
    self.inventory, self.opened = inventory, true
    self:draw(inventory)
    return true
end
function Radial:shape(kind, ...)
    local id = self.sr.Gui[kind](self.gui, ...)
    if id == nil then error("overlay-" .. kind .. "-failed") end
    self.ids[#self.ids + 1] = {kind, id}
end
function Radial:text(text, x, y, size, colour, maximum_width)
    local sr, font = self.sr, "core/performance_hud/debug"
    if not sr.Application.can_get("font", font) or not sr.Gui.text or not sr.Gui.text_extents then return end
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
    local w, h = sr.Gui.resolution(self.gui)
    if not w or not h or w < 320 or h < 240 or #rows < 1 or #rows > 16 then return false end
    self.width, self.height = w, h
    local base_radius = #rows > 8 and 210 or 165
    scale = math.min(scale, h / (2 * (base_radius + 104)), w / (2 * (base_radius + 76)))
    local nx, ny = self.channel.cursor()
    if not nx then return false end
    self.selected = Radial.pick(nx, ny, w, h, #rows, scale)
    local mark = {tostring(self.selected), tostring(w), tostring(h)}
    for _, row in ipairs(rows) do
        mark[#mark + 1] = row.kind .. ":" .. row.status .. ":" .. tostring(row.name)
    end
    local signature = table.concat(mark, "|")
    if signature == self.signature then return true end
    self:clear()
    local radius = base_radius * scale
    local inner, outer = 54 * scale, radius + 64 * scale
    local cx, cy = w / 2, h / 2
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
        self:text(row.name or ("STRATAGEM " .. row.kind), x, y - 7 * scale, 16 * scale, ink, label_width)
        self:text(tostring(index), x, y + 37 * scale, 18 * scale, ink)
        self:text(row.status, x, y - 50 * scale, 16 * scale, ink)
    end
    if self.selected then
        local row = rows[self.selected]
        self:text(row.name or tostring(row.kind), cx, cy - outer - 33 * scale, 20 * scale, sr.Color(255, 245, 240, 210))
    end
    self.signature = signature
    return true
end
return Radial

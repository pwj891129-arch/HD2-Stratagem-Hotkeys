local Reader = {}
Reader.__index = Reader
Reader.RVA = { players = 0x3326468, ui = 0x347ce28, loadouts = 0x347ce50,
    input = 0x347cf18, settings = 0x348e8f8, definitions = 0x37cb600 }
local DATA_SIZE, RECORD_SIZE = 80280, 400
local ACTION = { [1] = 3, [2] = 2, [3] = 4, [4] = 1 }
local function word(raw, at)
    if not raw or at < 0 or #raw < at + 4 then return nil end
    local a, b, c, d = raw:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function pointer(raw, at)
    local low, high = word(raw, at), word(raw, at + 4)
    if not low or not high then return nil end
    local value = high * 4294967296 + low
    if value < 65536 or value >= 140737488355328 then return nil end
    return value
end
function Reader.new(channel) return setmetatable({channel = channel}, Reader) end
function Reader:read(at, size) return self.channel:read(at, size) end
function Reader:word(at) return word(self:read(at, 4), 0) end
function Reader:ptr(at) return pointer(self:read(at, 8), 0) end
function Reader:root(name) return self:ptr(self.channel.base + Reader.RVA[name]) end

function Reader:definitions()
    local base = self:root("settings")
    if not base then return nil, "settings-unavailable" end
    if self.settings_base == base and self.catalog then return self.catalog end
    local source = self:read(base, DATA_SIZE)
    if word(source, 0) ~= 11 then return nil, "settings-layout-mismatch" end
    local catalog, offset, total = {}, 4, 0
    for group = 1, 11 do
        if word(source, offset) ~= 0x444c444c or word(source, offset + 4) ~= 1 or
            word(source, offset + 8) ~= 0x30eb6399 or word(source, offset + 16) ~= 1 or
            word(source, offset + 20) ~= 0 then return nil, "settings-header-mismatch" end
        local root, length = offset + 24, word(source, offset + 12)
        if not length then return nil, "settings-group-unreadable" end
        local finish = root + length
        local records, count = pointer(source, root), word(source, root + 8)
        if not records or not count or count < 1 or count > 149 or
            finish > #source or records < base + root + 16 or
            records + count * RECORD_SIZE > base + finish then return nil, "settings-bounds" end
        for index = 0, count - 1 do
            local record = records - base + index * RECORD_SIZE
            local kind, command, steps = word(source, record), pointer(source, record + 64),
                word(source, record + 72)
            if not kind or kind < 1 or kind > 149 or catalog[kind] or not command or
                not steps or steps < 1 or steps > 12 or command < base + root or
                command + steps * 4 > base + finish or
                self:ptr(self.channel.base + Reader.RVA.definitions + kind * 8) ~= base + record then
                return nil, "definition-identity-mismatch"
            end
            local directions = {}
            for step = 0, steps - 1 do
                local direction = word(source, command - base + step * 4)
                if not ACTION[direction] then return nil, "invalid-command-direction" end
                directions[#directions + 1] = direction
            end
            catalog[kind] = {record = base + record, command = directions}
            total = total + 1
        end
        offset = finish
    end
    if offset ~= DATA_SIZE or total ~= 149 then return nil, "incomplete-settings" end
    self.settings_base, self.catalog = base, catalog
    return catalog
end

function Reader:bindings()
    local owner = self:root("input")
    local buckets = owner and self:ptr(owner + 686800)
    if not buckets or self:word(owner + 686808) ~= 256 then return nil, "bindings-unavailable" end
    local raw = self:read(buckets, 256 * 328)
    if not raw then return nil, "bindings-unreadable" end
    local actions = {}
    for index = 0, 255 do
        local at, code = index * 328, word(raw, index * 328)
        if code and code >= 0x50000 and code <= 0x50004 then
            local count = word(raw, at + 4)
            if actions[code] or not count or count > 16 then return nil, "bindings-layout-mismatch" end
            local chosen
            for mapping = 0, count - 1 do
                local entry = at + 8 + mapping * 20
                local flags, trigger = word(raw, entry), word(raw, entry + 8)
                if flags % 16 == 3 and math.floor(flags / 16) % 16 == 4 and
                    math.floor(flags / 256) % 256 == 255 then
                    local vk = math.floor(flags / 1048576)
                    if vk > 6 and vk <= 254 and ((code == 0x50000 and trigger == 2) or
                        (code ~= 0x50000 and trigger == 0)) then
                        if not chosen then chosen = vk end
                    end
                end
            end
            if not chosen then return nil, "keyboard-binding-or-trigger-unsupported" end
            actions[code] = chosen
        end
    end
    local keys, seen = {}, {}
    for direction = 1, 4 do
        local vk = actions[0x50000 + ACTION[direction]]
        if not vk or vk == actions[0x50000] or seen[vk] then return nil, "ambiguous-direction-bindings" end
        seen[vk], keys[direction] = true, vk
    end
    if not actions[0x50000] then return nil, "start-binding-unavailable" end
    return {start_vk = actions[0x50000], directions = keys, owner = owner}, "ready"
end

function Reader:idle()
    local ui = self:root("ui")
    return ui ~= nil and self:word(ui + 17032 + 12) == 0 and self:word(ui + 17032 + 40) == 0
end
function Reader:menu_active()
    local owner = self:root("input")
    local active = owner and self:read(owner + 808 + 32 * (5 * 97), 1)
    return active ~= nil and active ~= "\0"
end
function Reader:loadout()
    local players, history = self:root("players"), self:root("loadouts")
    if not players or not history or self:word(players + 132) ~= 1 or
        self:word(players + 136) ~= 1 then return nil, "no-local-player" end
    local peer = self:read(players + 0x2c8, 8)
    if not peer or peer == string.rep("\0", 8) then return nil, "local-peer-unavailable" end
    local count, selected = self:word(history + 0x2d200), nil
    if not count or count < 1 or count > 32 then return nil, "loadout-history-unavailable" end
    for index = 0, count - 1 do
        local record = history + index * 0x1690
        if self:read(record, 8) == peer then
            if selected then return nil, "ambiguous-local-loadout" end
            selected = record
        end
    end
    if not selected or self:word(selected + 0x788) ~= 4 then return nil, "four-equipped-slots-unavailable" end
    local slots, seen = {}, {}
    for index = 0, 3 do
        local kind = self:word(selected + 0x188 + index * 0x30)
        if not kind or kind == 0 or kind > 149 or seen[kind] then return nil, "invalid-equipped-slots" end
        slots[index + 1], seen[kind] = kind, true
    end
    -- Re-read identities after following the shared data; loading and respawn can replace them.
    if self:root("players") ~= players or self:root("loadouts") ~= history or
        self:read(players + 0x2c8, 8) ~= peer or self:word(selected + 0x788) ~= 4 then
        return nil, "loadout-changed"
    end
    for index = 0, 3 do
        if self:word(selected + 0x188 + index * 0x30) ~= slots[index + 1] then
            return nil, "loadout-changed"
        end
    end
    return {slots = slots, token = peer .. ":" .. table.concat(slots, ",")}, "ready"
end
function Reader:request(slot)
    if not self:idle() then return nil, "menu-or-chat-open" end
    local loadout, why = self:loadout()
    if not loadout then return nil, why end
    local bindings; bindings, why = self:bindings()
    if not bindings then return nil, why end
    local definitions; definitions, why = self:definitions()
    if not definitions then return nil, why end
    local kind = loadout.slots[slot]
    local definition = kind and definitions[kind]
    if not definition then return nil, "slot-definition-unavailable" end
    local keys = {}
    for index, direction in ipairs(definition.command) do keys[index] = bindings.directions[direction] end
    return {token = loadout.token, kind = kind, keys = keys, bindings = bindings}, "ready"
end
return Reader

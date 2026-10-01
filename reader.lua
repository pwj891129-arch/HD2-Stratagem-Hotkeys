local Reader = {}
Reader.__index = Reader
Reader.RVA = { players = 0x3326468, ui = 0x347ce28, loadouts = 0x347ce50,
    input = 0x347cf18, settings = 0x348e8f8, definitions = 0x37cb600,
    clock = 0x3326348, owner = 54968216, avatars = 0x3326d20 }
local DATA_SIZE, RECORD_SIZE, LOADOUT_DATA = 80280, 400, 0x38
local ACTION = { [1] = 3, [2] = 2, [3] = 4, [4] = 1 }
local ACTION_BASE = 808 + 32 * (5 * 97)
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
function Reader:integer64(at)
    local raw = self:read(at, 8)
    local lo, hi = word(raw, 0), word(raw, 4)
    if not lo or not hi or hi >= 2097152 then return nil end
    return lo + hi * 4294967296
end
function Reader:hash(at)
    local raw = self:read(at, 8)
    local lo, hi = word(raw, 0), word(raw, 4)
    if not lo or not hi or (lo == 0 and hi == 0) then return nil end
    return string.format("%08x%08x", hi, lo)
end
local function float(raw, at)
    local bits = word(raw, at)
    if not bits then return nil end
    local exponent, fraction = math.floor(bits / 8388608) % 256, bits % 8388608
    if exponent == 255 then return nil end
    local value = exponent == 0 and fraction * 2 ^ -149 or (fraction + 8388608) * 2 ^ (exponent - 150)
    return bits >= 2147483648 and -value or value
end
local function vector(raw, at)
    local values = {}
    for index = 0, 3 do
        local value = float(raw, at + index * 4)
        if not value or value < 0 or value > 1 then return nil end
        values[index + 1] = value
    end
    return values
end
function Reader:atlas(picture)
    if type(picture) ~= "string" or #picture ~= 16 or not picture:match("^[0-9a-fA-F]+$") or
        picture == "0000000000000000" then return nil, "invalid-reference" end
    local exe = self.channel.exe_base
    if not exe then return nil, "atlas-root-unavailable" end
    -- Pinned EXE +0x3438e0: high hash word modulo capacity, chained 24-byte entries.
    local engine = self:ptr(exe + 0x1a10238)
    local manager = engine and self:ptr(engine + 0x3f8)
    local header = manager and self:read(manager + 0x2a0, 32)
    local rows, count, capacity = pointer(header, 0), word(header, 16), word(header, 20)
    if not rows or not count or not capacity or count > capacity or count < 1 or
        capacity < 1 or capacity > 1048576 then return nil, "atlas-layout-unavailable" end
    local low, high = tonumber(picture:sub(9), 16), tonumber(picture:sub(1, 8), 16)
    local node, seen = high % capacity, {}
    for probe = 1, 128 do
        if node >= capacity or seen[node] then return nil, "atlas-chain-invalid" end
        seen[node] = true
        local address = rows + node * 24
        local entry = self:read(address, 24)
        local link = word(entry, 16)
        if not link then return nil, "atlas-entry-unreadable" end
        if link == 4294967294 then return nil, "texture-not-atlased" end
        if word(entry, 0) == low and word(entry, 4) == high then
            local payload = pointer(entry, 8)
            local raw = payload and self:read(payload, 40)
            local atlas_low, atlas_high = word(raw, 8), word(raw, 12)
            local uv = vector(raw, 24)
            if not atlas_low or not atlas_high or (atlas_low == 0 and atlas_high == 0) or not uv or
                uv[3] <= 0 or uv[4] <= 0 or uv[1] + uv[3] > 1.00001 or uv[2] + uv[4] > 1.00001 then
                return nil, "atlas-payload-invalid"
            end
            if self:ptr(exe + 0x1a10238) ~= engine or self:ptr(engine + 0x3f8) ~= manager or
                self:read(manager + 0x2a0, 32) ~= header or self:read(address, 24) ~= entry or
                self:read(payload, 40) ~= raw then return nil, "atlas-changed" end
            return {texture = string.format("%08x%08x", atlas_high, atlas_low),
                uv = {uv[1], uv[2], math.min(1, uv[1] + uv[3]), math.min(1, uv[2] + uv[4])}}, "ready"
        end
        if link == 2147483647 then return nil, "texture-not-atlased" end
        node = link
    end
    return nil, "atlas-probe-limit"
end
function Reader:icon(definition, picture)
    local index = self:word(definition.record + 184)
    if not index or index > 4 then return nil, "icon-color-index-invalid" end
    local primary = vector(self:read(self.channel.base + 0x331b610 + index * 16, 16), 0)
    local secondary = vector(self:read(self.channel.base + 0x21e89e0, 16), 0)
    local tertiary = vector(self:read(self.channel.base + 0x21e8a10, 16), 0)
    if not primary or not secondary or not tertiary then return nil, "icon-colors-unreadable" end
    local art, why = self:atlas(picture)
    if not art then return nil, why end
    art.colors = {primary, secondary, tertiary}
    return art, "ready"
end
function Reader:name(at)
    local address = self:ptr(at)
    if not address then return nil end
    local parts = {}
    for offset = 0, 224, 32 do
        local raw = self:read(address + offset, 32)
        if not raw then return nil end
        local finish = raw:find("\0", 1, true)
        parts[#parts + 1] = finish and raw:sub(1, finish - 1) or raw
        if finish then return table.concat(parts) end
    end
end
function Reader:root(name) return self:ptr(self.channel.base + Reader.RVA[name]) end
function Reader:lookup(at, key)
    local header = self:read(at, 20)
    local rows, capacity, empty, multiplier = pointer(header, 0), word(header, 8), word(header, 12), word(header, 16)
    if not rows or not capacity or capacity < 1 or capacity > 1048576 or not empty or not multiplier then return nil end
    local power = capacity
    while power > 1 and power % 2 == 0 do power = power / 2 end
    if power ~= 1 then return nil end
    local a, b, c, d = key % 65536, math.floor(key / 65536), multiplier % 65536, math.floor(multiplier / 65536)
    local seed = (a * c + ((a * d + b * c) % 65536) * 65536) % 4294967296
    for probe = 0, math.min(capacity, 128) - 1 do
        local row = self:read(rows + ((seed + probe) % capacity) * 8, 8)
        local found = word(row, 0)
        if not found or found == empty then return nil end
        if found == key then return word(row, 4) end
    end
end

function Reader:game_menu()
    local players, owner, avatars = self:root("players"), self:root("owner"), self:root("avatars")
    if not players or not owner or not avatars or self:word(players + 132) ~= 1 or
        self:word(players + 136) ~= 1 then return nil, "no-local-character" end
    local unit = self:word(players + 936)
    if not unit or unit == 0 or unit == 0x7fff or unit == 0xffffffff then return nil, "no-local-character" end
    local index = self:lookup(owner + 15871688, unit)
    if not index or index > 1000000 then return nil, "character-owner-unavailable" end
    local address = owner + 15937304 + index * 24
    local identity = self:read(address, 24)
    local avatar = word(identity, 8)
    if not avatar or avatar == 0 or avatar == 0x7fff or avatar == 0xffffffff then
        return nil, "no-local-character"
    end
    local seat, count = self:lookup(avatars + 248, avatar), self:word(avatars + 108)
    if not seat or not count or seat >= count or seat > 1000000 or
        self:word(avatars + 5495040 + seat * 4664 + 2948) ~= avatar then
        return nil, "character-identity-mismatch"
    end
    -- game.dll+0xa8e780 checks this bit for the character's actual open stratagem menu.
    local at = avatars + 0x53e888 + seat * 0x1238
    local flags = self:word(at)
    if not flags then return nil, "stratagem-menu-state-unreadable" end
    if self:root("players") ~= players or self:root("owner") ~= owner or self:root("avatars") ~= avatars or
        self:word(players + 132) ~= 1 or self:word(players + 136) ~= 1 or self:word(players + 936) ~= unit or
        self:lookup(owner + 15871688, unit) ~= index or self:read(address, 24) ~= identity or
        self:lookup(avatars + 248, avatar) ~= seat or self:word(avatars + 108) ~= count or
        self:word(avatars + 5495040 + seat * 4664 + 2948) ~= avatar or self:word(at) ~= flags then
        return nil, "character-state-changed"
    end
    return {active = math.floor(flags / 512) % 2 == 1,
        token = players .. ":" .. owner .. ":" .. avatars .. ":" .. unit .. ":" .. seat .. ":" .. identity}, "ready"
end

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
                if math.floor(flags / 16) % 16 == 4 and math.floor(flags / 256) % 256 == 255 then
                    local kind, index, vk = flags % 16, math.floor(flags / 1048576), nil
                    if kind == 3 and index > 6 and index <= 254 then vk = index end
                    if kind == 4 and code == 0x50000 and self.channel.mouse_vk and
                        word(raw, entry + 4) == 32 + index then
                        local mouse = self.channel.mouse_vk(index)
                        if mouse == 5 or mouse == 6 then vk = mouse end
                    end
                    if vk and ((code == 0x50000 and trigger == 2) or (code ~= 0x50000 and trigger == 0)) then
                        if not chosen then chosen = vk end
                    end
                end
            end
            if not chosen then return nil, code == 0x50000 and "list-binding-or-trigger-unsupported" or
                "keyboard-direction-binding-or-trigger-unsupported" end
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
    local active = owner and self:read(owner + ACTION_BASE, 1)
    return active ~= nil and active ~= "\0"
end
function Reader:command_state(binding)
    local owner = self:root("input")
    if not binding or not owner or owner ~= binding.owner then return nil end
    -- Native direction consumers read group 5's five action bytes, spaced 32 bytes apart.
    local raw = self:read(owner + ACTION_BASE, 160)
    if not raw or #raw ~= 160 or self:root("input") ~= owner then return nil end
    local state = {directions = {}}
    for action = 0, 4 do
        local active = raw:byte(action * 32 + 1)
        if active ~= 0 and active ~= 1 then return nil end
    end
    state.start = raw:byte(1) == 1
    for direction = 1, 4 do state.directions[direction] = raw:byte(ACTION[direction] * 32 + 1) == 1 end
    return state
end
function Reader:inventory(include_shared)
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
    if not selected then return nil, "local-loadout-unavailable" end
    -- Native consumers use record + 0x38 before the count/entry offsets.
    local data = selected + LOADOUT_DATA
    local total = self:word(data + 0x788)
    if not total or total < 4 or total > 16 then
        return nil, "equipped-slot-count-unavailable:" .. tostring(total)
    end
    local slots, seen, rows, identities = {}, {}, {}, {}
    for index = 0, total - 1 do
        local at = data + 0x188 + index * 0x30
        local raw = self:read(at, 48)
        local kind = word(raw, 0)
        local shared = raw and raw:byte(10)
        if not kind or kind == 0 or kind > 149 or seen[kind] or
            (shared ~= 0 and shared ~= 1) then return nil, "invalid-equipped-slots" end
        seen[kind], identities[#identities + 1] = true, kind
        if shared == 0 then slots[#slots + 1] = kind end
        if shared == 0 or include_shared then
            rows[#rows + 1] = {kind = kind, address = at, shared = shared == 1, slot = shared == 0 and #slots or nil,
                uses = word(raw, 4)}
        end
    end
    if #slots ~= 4 then return nil, "equipped-slot-count-mismatch:" .. #slots .. "/" .. total end
    -- Re-read identities after following the shared data; loading and respawn can replace them.
    if self:root("players") ~= players or self:root("loadouts") ~= history or
        self:read(players + 0x2c8, 8) ~= peer or self:word(data + 0x788) ~= total then
        return nil, "loadout-changed"
    end
    for index = 0, total - 1 do
        if self:word(data + 0x188 + index * 0x30) ~= identities[index + 1] then
            return nil, "loadout-changed"
        end
    end
    return {slots = slots, rows = rows, token = peer .. ":" .. table.concat(identities, ",")}, "ready"
end
function Reader:loadout() return self:inventory(false) end
function Reader:radial(include_shared, read_icons)
    local inventory, why = self:inventory(include_shared)
    if not inventory then return nil, why end
    local definitions; definitions, why = self:definitions()
    if not definitions then return nil, why end
    local clock = self:root("clock")
    local now = clock and self:integer64(clock + 24)
    if not now then return nil, "mission-clock-unavailable" end
    for _, row in ipairs(inventory.rows) do
        local definition = definitions[row.kind]
        local call_due, reuse_due = self:integer64(row.address + 32), self:integer64(row.address + 24)
        row.command = definition.command
        definition.name = definition.name or self:name(definition.record + 16)
        row.name = (definition.name or ("STRATAGEM " .. row.kind)):gsub("^.-%.%s*", "")
        row.picture = self:hash(definition.record + 176)
        if read_icons ~= false then row.art, row.art_error = self:icon(definition, row.picture) end
        row.ready = row.uses ~= nil and row.uses > 0 and call_due ~= nil and
            reuse_due ~= nil and call_due <= now and reuse_due <= now
        row.seconds = call_due and reuse_due and math.ceil(math.max(0, call_due - now, reuse_due - now) / 1000000)
        row.status = row.uses == 0 and "EMPTY" or (row.seconds and row.seconds > 0 and
            tostring(row.seconds) .. "s" or (row.ready and "READY" or "UNKNOWN"))
    end
    local current = self:inventory(include_shared)
    if not current or current.token ~= inventory.token then return nil, "loadout-changed" end
    return inventory, "ready"
end
function Reader:request_kind(kind, include_shared)
    if not self:idle() then return nil, "menu-or-chat-open" end
    local inventory, why = self:radial(include_shared, false)
    if not inventory then return nil, why end
    local bindings; bindings, why = self:bindings()
    if not bindings then return nil, why end
    for _, row in ipairs(inventory.rows) do
        if row.kind == kind then
            if not row.ready then return nil, "stratagem-unavailable" end
            local keys = {}
            for index, direction in ipairs(row.command) do keys[index] = bindings.directions[direction] end
            return {token = inventory.token, kind = kind, keys = keys, directions = row.command, bindings = bindings}, "ready"
        end
    end
    return nil, "stratagem-not-equipped"
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
    return {token = loadout.token, kind = kind, keys = keys, directions = definition.command, bindings = bindings}, "ready"
end
return Reader

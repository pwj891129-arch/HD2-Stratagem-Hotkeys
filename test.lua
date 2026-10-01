local Reader, Policy, Platform = dofile("reader.lua"), dofile("policy.lua"), dofile("platform.lua")
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "check") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a"); file:close(); return bytes
end
assert(loadstring(read_file("dist/stratagem_hotkeys.generated.lua")))
local function word(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function pointer(n) return word(n % 4294967296) .. word(math.floor(n / 4294967296)) end
local function uint(raw, at)
    local a, b, c, d = raw:byte(at + 1, at + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end
local function address(raw, at) return uint(raw, at) + uint(raw, at + 4) * 4294967296 end
local memory, channel = {}, {base = 0x10000000}
local function put(at, bytes) for i = 1, #bytes do memory[at + i - 1] = bytes:sub(i, i) end end
function channel:read(at, size)
    local out = {}
    for i = 0, size - 1 do if not memory[at + i] then return nil end; out[#out + 1] = memory[at + i] end
    return table.concat(out)
end
local function root(name, at) put(channel.base + Reader.RVA[name], pointer(at)) end
local owner, buckets, players, history, ui = 0x20000000, 0x21000000, 0x22000000, 0x23000000, 0x24000000
root("input", owner); root("players", players); root("loadouts", history); root("ui", ui)
put(owner + 686800, pointer(buckets) .. word(256))
put(buckets, string.rep("\255", 256 * 328))
local function binding(action, vk, trigger)
    local at = buckets + action * 328
    local flags = vk * 1048576 + trigger * 65536 + 255 * 256 + 0x43
    put(at, word(0x50000 + action) .. word(1) .. word(flags) .. word(vk + 49) .. word(trigger) .. word(0) .. word(0))
end
binding(0, 164, 2); binding(1, 37, 0); binding(2, 39, 0); binding(3, 38, 0); binding(4, 40, 0)
put(owner + 808 + 32 * (5 * 97), "\1" .. string.rep("\0", 159))

local settings = 0x25000000
root("settings", settings)
put(settings, string.rep("\0", 80280))
put(settings, word(11))
local offset, kind, first_record = 4, 1, nil
for group = 1, 11 do
    local count = group < 11 and 14 or 9
    local records = offset + 24 + 16
    local finish = group < 11 and records + count * 400 or 80280
    put(settings + offset, word(0x444c444c) .. word(1) .. word(0x30eb6399) ..
        word(finish - offset - 24) .. word(1) .. word(0))
    put(settings + offset + 24, pointer(settings + records) .. word(count))
    for index = 0, count - 1 do
        local record = settings + records + index * 400
        first_record = first_record or record
        put(record, word(kind))
        put(record + 64, pointer(record + 80)); put(record + 72, word(4))
        put(record + 80, word(1) .. word(2) .. word(3) .. word(4))
        put(channel.base + Reader.RVA.definitions + kind * 8, pointer(record))
        kind = kind + 1
    end
    offset = finish
end
equal(table.concat(assert(Reader.new(channel):definitions())[149].command, ","), "1,2,3,4", "synthetic definitions")
put(first_record + 80, word(5))
equal(Reader.new(channel):definitions(), nil, "invalid arrow rejected")
put(first_record + 80, word(1))
put(first_record + 64, pointer(settings + 80279))
equal(Reader.new(channel):definitions(), nil, "out of bounds command rejected")
put(first_record + 64, pointer(first_record + 80))
put(channel.base + Reader.RVA.definitions + 8, pointer(first_record + 400))
equal(Reader.new(channel):definitions(), nil, "definition table mismatch rejected")
put(channel.base + Reader.RVA.definitions + 8, pointer(first_record))
put(settings + 4 + 8, word(123))
equal(Reader.new(channel):definitions(), nil, "unexpected schema rejected")
put(settings + 4 + 8, word(0x30eb6399))
put(ui + 17032 + 12, word(0)); put(ui + 17032 + 40, word(0))
put(players + 132, word(1)); put(players + 136, word(1))
local peer = "TESTPEER"
put(players + 0x2c8, peer)
put(history + 0x2d200, word(2)); put(history, "NOTLOCAL"); put(history + 0x7c0, word(4))
local local_record = history + 0x1690
local local_data = local_record + 0x38
put(local_record, peer); put(local_data + 0x788, word(4))
put(local_record + 0x788, word(0))
for index, kind in ipairs({113, 101, 66, 1}) do
    put(local_data + 0x188 + (index - 1) * 0x30, word(kind) .. word(3) .. string.rep("\0", 40))
end
local reader = Reader.new(channel)
local keys = assert(reader:bindings())
equal(keys.start_vk, 164, "saved Alt")
equal(table.concat(keys.directions, ","), "38,39,40,37", "game direction enum to native actions")
local synthetic_request = assert(Reader.new(channel):request(1))
equal(synthetic_request.kind, 113)
equal(table.concat(synthetic_request.keys, ","), "38,39,40,37", "native commands use saved mappings")
equal(table.concat(synthetic_request.directions, ","), "1,2,3,4", "native direction identity accompanies each key")
local action_base = owner + 808 + 32 * (5 * 97)
local action_map = {3, 2, 4, 1}
equal(assert(reader:command_state(keys)).start, true, "native list action observed")
for direction = 1, 4 do
    put(action_base + action_map[direction] * 32, "\1")
    local state = assert(reader:command_state(keys))
    for index = 1, 4 do equal(state.directions[index], index == direction, "direction action enum mapping") end
    put(action_base + action_map[direction] * 32, "\0")
end
put(action_base + 32, "\2")
equal(reader:command_state(keys), nil, "unexpected action value rejected")
put(action_base + 32, "\0")
root("input", owner + 0x1000)
equal(reader:command_state(keys), nil, "replaced input owner rejects old bindings")
root("input", owner)
local original_read = channel.read
channel.read = function(self, at, size)
    local raw = original_read(self, at, size)
    if at == action_base then root("input", owner + 0x1000) end
    return raw
end
equal(reader:command_state(keys), nil, "input owner replacement during snapshot rejected")
channel.read = original_read; root("input", owner)
memory[action_base + 159] = nil
equal(reader:command_state(keys), nil, "partial action snapshot rejected")
put(action_base + 159, "\0")
binding(3, 87, 0); binding(4, 83, 0); binding(1, 65, 0); binding(2, 68, 0)
equal(table.concat(assert(reader:bindings()).directions, ","), "87,68,83,65", "rebound WASD")
binding(3, 104, 0)
equal(assert(reader:bindings()).directions[1], 104, "Numpad8 retained")
binding(3, 56, 0)
equal(assert(reader:bindings()).directions[1], 56, "number row8 retained")
binding(3, 83, 0)
equal(reader:bindings(), nil, "duplicate directions declined")
binding(3, 87, 4)
equal(reader:bindings(), nil, "long press direction declined")
binding(3, 87, 0)
binding(0, 164, 0)
equal(reader:bindings(), nil, "non-hold start declined")
binding(0, 164, 2)
local loadout = assert(reader:loadout())
equal(table.concat(loadout.slots, ","), "113,101,66,1", "local peer and slot order")
equal(reader:word(local_record + 0x788), 0, "legacy count offset is not the equipped count")
put(local_data + 0x788, word(0))
equal(reader:loadout(), nil, "empty ship loadout")
put(local_data + 0x788, word(17))
equal(reader:loadout(), nil, "unexpected extra slots")
put(local_data + 0x788, word(4))
put(local_data + 0x188, word(1))
equal(reader:loadout(), nil, "duplicate equipped slots")
put(local_data + 0x188, word(113))
put(history, peer)
equal(reader:loadout(), nil, "ambiguous history peer")
put(history, "NOTLOCAL")
put(ui + 17032 + 40, word(1))
equal(reader:idle(), false, "menu blocks input")
put(ui + 17032 + 40, word(0))
equal(reader:idle(), true)
equal(reader:menu_active(), true)
put(owner + 808 + 32 * (5 * 97), "\0")
equal(reader:menu_active(), false)
put(owner + 808 + 32 * (5 * 97), "\1")

local clock = 0x26000000
root("clock", clock); put(clock + 24, pointer(10000000))
local native_definitions = assert(reader:definitions())
for index, kind in ipairs({113, 101, 66, 1}) do
    put(native_definitions[kind].record + 176, word(index) .. word(1))
end
local snapshot = assert(reader:radial(false))
equal(#snapshot.rows, 4, "radial equipped slots")
equal(snapshot.rows[1].picture, "0000000100000001", "texture hash")
equal(snapshot.rows[1].ready, true, "native ready state")
local row1 = local_data + 0x188
put(row1 + 24, pointer(12500000))
equal(assert(reader:radial(false)).rows[1].status, "3s", "cooldown rounds up")
equal(reader:request_kind(113, false), nil, "cooldown blocks release request")
put(row1 + 24, pointer(0)); put(row1 + 4, word(0))
equal(assert(reader:radial(false)).rows[1].status, "EMPTY", "zero uses blocks")
put(row1 + 4, word(3)); put(row1 + 32, string.rep("\255", 8))
equal(assert(reader:radial(false)).rows[1].ready, false, "invalid timestamp fails closed")
put(row1 + 32, pointer(0))
equal(assert(reader:request_kind(113, false)).kind, 113, "fresh command by kind")
equal(table.concat(assert(reader:request_kind(113, false)).directions, ","), "1,2,3,4", "radial also carries direction identity")
equal(reader:request_kind(149, false), nil, "unequipped kind blocked")
local extra = local_data + 0x188 + 4 * 48
put(extra, word(2) .. word(2) .. "\0\1" .. string.rep("\0", 38))
put(local_data + 0x788, word(5))
equal(#assert(reader:radial(false)).rows, 4, "shared hidden")
equal(#assert(reader:radial(true)).rows, 5, "shared shown")
equal(assert(reader:loadout()).slots[4], 1, "shared does not shift equipped slots")
put(extra + 9, "\2")
equal(reader:loadout(), nil, "invalid shared flag blocked")
put(local_data + 0x788, word(4))

-- Validate the parser against the local read-only capture when it is available.
local capture = io.open("scratch/game-module.bin", "rb")
if capture then
    capture:close()
    local module = read_file("scratch/game-module.bin")
    local settings = read_file("scratch/stratagem-settings.bin")
    local captured_players = read_file("scratch/players.bin")
    local captured_loadouts = read_file("scratch/loadouts.bin")
    local base = tonumber(read_file("scratch/reference.json"):match('"Base"%s*:%s*(%d+)'))
    local settings_base = address(module, Reader.RVA.settings)
    local players_base = address(module, Reader.RVA.players)
    local loadouts_base = address(module, Reader.RVA.loadouts)
    local reference = {base = base}
    function reference:read(at, size)
        if at >= base and at + size <= base + #module then return module:sub(at - base + 1, at - base + size) end
        if at >= settings_base and at + size <= settings_base + #settings then
            return settings:sub(at - settings_base + 1, at - settings_base + size)
        end
        if at >= players_base and at + size <= players_base + #captured_players then
            return captured_players:sub(at - players_base + 1, at - players_base + size)
        end
        if at >= loadouts_base and at + size <= loadouts_base + #captured_loadouts then
            return captured_loadouts:sub(at - loadouts_base + 1, at - loadouts_base + size)
        end
    end
    local catalog = assert(Reader.new(reference):definitions())
    equal(table.concat(catalog[113].command, ","), "3,2,3,4,1,2", "Harpoon command from game")
    equal(table.concat(catalog[126].command, ","), "1,2,4,2", "Eagle gas command from game")
    local count = 0
    for _ in pairs(catalog) do count = count + 1 end
    equal(count, 149, "all native definitions")
    equal(table.concat(assert(Reader.new(reference):loadout()).slots, ","), "1,121,101,113",
        "real capture uses embedded loadout at peer record + 0x38")
    reference.read = function() return nil end
    equal(Reader.new(reference):definitions(), nil, "unreadable definitions")
end

local sent, policy_held = {}, {}
local function observer()
    return {start = true, directions = {policy_held[38] == true, policy_held[39] == true, false, false}}
end
local policy = Policy.new(function(vk, pressed)
    sent[#sent + 1] = {vk, pressed}; policy_held[vk] = pressed; return true
end, observer)
local request = {keys = {38, 38, 39}, directions = {1, 1, 2}}
equal(policy:start(request, 0), true)
equal(policy:start(request, 0), false, "no queue while busy")
policy:step(0.049, true)
equal(#sent, 0, "opening delay")
policy:step(0.05, true)
equal(sent[1][1], 38); equal(sent[1][2], true)
policy:step(0.051, true)
equal(#sent, 1, "minimum key hold")
policy:step(0.066, true)
equal(sent[2][2], false)
policy:step(0.082, true); policy:step(0.098, true)
equal(sent[3][1], 38, "repeated arrow receives a fresh edge")
policy:step(0.114, true)
equal(policy:step(0.13, true), "command-complete")
equal(#sent, 6); equal(policy.held, nil)
policy:start(request, 1); policy:step(1.05, true)
equal(policy:step(1.06, false), "cancelled")
equal(sent[#sent][2], false, "cancel releases owned key")
equal(policy.job, nil)
local fails = 0
local retry = Policy.new(function(_, pressed)
    if not pressed then fails = fails + 1; return fails > 1 end
    return true
end, observer)
retry:start(request, 0); retry:step(0.05, true)
equal(retry:step(0.07, false), "key-release-failed")
equal(retry.held, 38, "failed release is retried")
equal(retry.job, nil, "cancelled job cannot resume after release failure")
equal(retry:step(0.08, false), "cancelled")
equal(retry.held, nil)

-- Execute the actual addon glue with mock adapters; never send OS input in tests.
local current, held, events, logs = 0, {}, {}, {}
local focused, idle, menu, token = true, true, true, "LOADOUT"
local binding_value = {start_vk = 164, directions = {38, 39, 40, 37}}
local fake = {base = 1,
    foreground = function() return focused end,
    down = function(vk) return held[vk] or false end,
    key = function(vk, down) events[#events + 1] = {vk, down}; held[vk] = down; return true end}
fake.command_key = fake.key
local fake_reader = {
    bindings = function() return binding_value, "ready" end,
    idle = function() return idle end, menu_active = function() return menu end,
    command_state = function() return {start = menu, directions = {
        held[38] == true, held[39] == true, held[40] == true, held[37] == true}} end,
    loadout = function() return {token = token} end,
    request = function(_, slot) return {token = token, kind = slot, keys = {38, 39},
        directions = {1, 2}, bindings = binding_value} end,
}
local env = setmetatable({fake = fake, fake_reader = fake_reader}, {__index = _G})
env._G = env
env.CowboyBingusModLoader = {api = 1, open_log = function()
    return {write = function(_, text) logs[#logs + 1] = text end, flush = function() end, close = function() end}
end}
env.stingray = {Application = {time_since_launch = function() return current end}}
local calls = 0
env.update = function(value) calls = calls + 1; return value, "original" end
env.shutdown = function() return "shutdown" end
local source = read_file("addon.lua")
source = source:gsub('%-%- @PLATFORM@', function() return "return { create = function() return fake end }" end)
source = source:gsub('%-%- @READER@', function() return "return { new = function() return fake_reader end }" end)
source = source:gsub('%-%- @POLICY@', function() return read_file("policy.lua") end)
source = source:gsub('%-%- @RADIAL@', function() return read_file("radial.lua") end)
local init = assert(loadstring(source)); setfenv(init, env); init()
local function step(dt) current = current + dt; return env.update("kept") end
local a, b = step(0)
equal(a, "kept"); equal(b, "original", "original callback return values")
held[164], held[49] = true, true
step(0.016); step(0.06); step(0.06); step(0.02); step(0.02); step(0.02)
equal(#events, 4, "complete command uses only keyboard down/up")
for index = 1, 15 do step(0.02) end
equal(#events, 4, "held number does not repeat")
equal(env.HD2StratagemHotkeys.blocking_inputs, true, "autoreload coordination")
held[49], held[164] = false, false; step(0.02)
held[50] = true; step(0.02)
held[164] = true; step(0.02)
equal(#events, 4, "modifier after number does not trigger")
held[50] = false; step(0.02)
idle = false; held[50] = true; step(0.1); step(0.1)
equal(#events, 4, "menu blocks hotkey")
idle = true; held[50] = false; step(0.02); held[50] = true
step(0.02); step(0.06); step(0.06)
equal(#events, 5)
focused = false; step(0.02)
equal(#events, 6, "focus loss releases direction")
equal(events[6][2], false)
equal(env.shutdown(), "shutdown", "shutdown chain")
equal(env.HD2StratagemHotkeys.blocking_inputs, false)

dofile("radial.test.lua")(equal, read_file, source)
dofile("policy.test.lua")(equal)

local ffi = require("ffi")
ffi.cdef(Platform.declarations)
equal(ffi.sizeof("HD2SH_INPUT"), 40)
equal(ffi.sizeof("HD2SH_POINT"), 8); equal(ffi.sizeof("HD2SH_RECT"), 16)
local input, encoded, mappings = ffi.new("HD2SH_INPUT[1]"), {}, {
    [37] = 0xe04b, [38] = 0xe048, [39] = 0xe04d, [40] = 0xe050,
    [104] = 0x48, [56] = 0x09, [87] = 0x11, [164] = 0x38}
input[0].type = 1
local user = {HD2SH_MapVirtualKeyW = function(vk, mode) assert(mode == 4); return mappings[vk] or 0 end,
    HD2SH_SendInput = function(count, data, size)
        assert(count == 1 and size == 40 and data[0].type == 1)
        local key = data[0].value.key
        encoded[#encoded + 1] = {tonumber(key.vk), tonumber(key.scan), tonumber(key.flags)}
        return 1
    end}
for _, vk in ipairs({37, 38, 39, 40}) do
    equal(Platform.send_key(user, input, vk, true, true), true)
    equal(encoded[#encoded][1], vk, "command uses saved virtual key")
    equal(encoded[#encoded][2], mappings[vk] % 256)
    equal(encoded[#encoded][3], 1, "arrows retain extended flag without scan-only flag")
    equal(Platform.send_key(user, input, vk, false, true), true)
    equal(encoded[#encoded][3], 3, "extended arrow key-up")
end
for _, vk in ipairs({104, 56, 87}) do
    equal(Platform.send_key(user, input, vk, true, true), true)
    equal(encoded[#encoded][1], vk, "Numpad, number row and rebound letter preserved")
    equal(encoded[#encoded][3], 0, "non-extended binding is not sent as arrow")
end
equal(Platform.send_key(user, input, 164, true, false), true)
equal(encoded[#encoded][1], 0, "list key clears command VK in shared INPUT buffer")
equal(encoded[#encoded][2], 0x38); equal(encoded[#encoded][3], 8, "working list scan-code route retained")
equal(Platform.send_key(user, input, 164, false, false), true)
equal(encoded[#encoded][3], 10)
local encoded_count = #encoded
for _, vk in ipairs({0, 1, 6, 255, 38.5, "38", 120}) do
    equal(Platform.send_key(user, input, vk, true, true), false, "invalid or unmapped key declined")
end
equal(#encoded, encoded_count, "declined keys send no input")
user.HD2SH_SendInput = function() return 0 end
equal(Platform.send_key(user, input, 38, true, true), false, "failed Windows insertion reported")
local user32 = ffi.load("user32")
for _, name in ipairs({"GetCursorPos", "ScreenToClient", "ClientToScreen", "GetClientRect", "SetCursorPos"}) do
    equal(user32["HD2SH_" .. name] ~= nil, true, "cursor symbol resolved without calling it")
end
local companion = io.open("../BingusAutoReload/native.lua", "rb")
if companion then
    companion:close()
    ffi.cdef(dofile("../BingusAutoReload/native.lua").declarations)
    equal(ffi.sizeof("HD2AR_INPUT"), 40, "shared VM input layout compatibility")
end
print("PASS " .. checks .. " stratagem hotkey checks; no OS input sent")

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
put(owner + 808 + 32 * (5 * 97), "\1")

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
put(history + 0x2d200, word(2)); put(history, "NOTLOCAL"); put(history + 0x788, word(4))
local local_record = history + 0x1690
put(local_record, peer); put(local_record + 0x788, word(4))
for index, kind in ipairs({113, 101, 66, 1}) do put(local_record + 0x188 + (index - 1) * 0x30, word(kind)) end
local reader = Reader.new(channel)
local keys = assert(reader:bindings())
equal(keys.start_vk, 164, "saved Alt")
equal(table.concat(keys.directions, ","), "38,39,40,37", "game direction enum to native actions")
local synthetic_request = assert(Reader.new(channel):request(1))
equal(synthetic_request.kind, 113)
equal(table.concat(synthetic_request.keys, ","), "38,39,40,37", "native commands use saved mappings")
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
put(local_record + 0x788, word(0))
equal(reader:loadout(), nil, "empty ship loadout")
put(local_record + 0x788, word(5))
equal(reader:loadout(), nil, "unexpected extra slots")
put(local_record + 0x788, word(4))
put(local_record + 0x188, word(1))
equal(reader:loadout(), nil, "duplicate equipped slots")
put(local_record + 0x188, word(113))
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

-- Validate the parser against the local read-only capture when it is available.
local capture = io.open("scratch/game-module.bin", "rb")
if capture then
    capture:close()
    local module = read_file("scratch/game-module.bin")
    local settings = read_file("scratch/stratagem-settings.bin")
    local base = tonumber(read_file("scratch/reference.json"):match('"Base"%s*:%s*(%d+)'))
    local settings_base = address(module, Reader.RVA.settings)
    local reference = {base = base}
    function reference:read(at, size)
        if at >= base and at + size <= base + #module then return module:sub(at - base + 1, at - base + size) end
        if at >= settings_base and at + size <= settings_base + #settings then
            return settings:sub(at - settings_base + 1, at - settings_base + size)
        end
    end
    local catalog = assert(Reader.new(reference):definitions())
    equal(table.concat(catalog[113].command, ","), "3,2,3,4,1,2", "Harpoon command from game")
    equal(table.concat(catalog[126].command, ","), "1,2,4,2", "Eagle gas command from game")
    local count = 0
    for _ in pairs(catalog) do count = count + 1 end
    equal(count, 149, "all native definitions")
    reference.read = function() return nil end
    equal(Reader.new(reference):definitions(), nil, "unreadable definitions")
end

local sent = {}
local policy = Policy.new(function(vk, pressed) sent[#sent + 1] = {vk, pressed}; return true end)
local request = {keys = {38, 38, 39}}
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
end)
retry:start(request, 0); retry:step(0.05, true)
equal(retry:step(0.07, false), "key-release-failed")
equal(retry.held, 38, "failed release is retried")
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
local fake_reader = {
    bindings = function() return binding_value, "ready" end,
    idle = function() return idle end, menu_active = function() return menu end,
    loadout = function() return {token = token} end,
    request = function(_, slot) return {token = token, kind = slot, keys = {38, 39}, bindings = binding_value} end,
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

local ffi = require("ffi")
ffi.cdef(Platform.declarations)
equal(ffi.sizeof("HD2SH_INPUT"), 40)
local companion = io.open("../BingusAutoReload/native.lua", "rb")
if companion then
    companion:close()
    ffi.cdef(dofile("../BingusAutoReload/native.lua").declarations)
    equal(ffi.sizeof("HD2AR_INPUT"), 40, "shared VM input layout compatibility")
end
print("PASS " .. checks .. " stratagem hotkey checks; no OS input sent")

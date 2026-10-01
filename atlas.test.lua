return function(equal)
    local Reader, ffi = dofile("reader.lua"), require("ffi")
    local memory, channel = {}, {base = 0x10000000, exe_base = 0x18000000}
    local function word(n)
        return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    end
    local function pointer(n) return word(n % 4294967296) .. word(math.floor(n / 4294967296)) end
    local function put(at, bytes) for i = 1, #bytes do memory[at + i - 1] = bytes:sub(i, i) end end
    function channel:read(at, size)
        local out = {}
        for offset = 0, size - 1 do
            if not memory[at + offset] then return nil end
            out[#out + 1] = memory[at + offset]
        end
        return table.concat(out)
    end
    local function vector(a, b, c, d) return ffi.string(ffi.new("float[4]", {a, b, c, d}), 16) end
    local reader = Reader.new(channel)
    local engine, manager, rows, payload, record = 0x20000000, 0x21000000, 0x22000000, 0x23000000, 0x24000000
    local root = channel.exe_base + 0x1a10238
    put(root, pointer(engine)); put(engine + 0x3f8, pointer(manager))
    local header = pointer(rows) .. string.rep("\0", 8) .. word(2) .. word(8) .. string.rep("\0", 8)
    put(manager + 0x2a0, header)
    local picture = "1234567000000071"
    put(rows, word(99) .. word(0x12345670) .. pointer(payload + 128) .. word(5) .. word(0))
    local entry = word(0x71) .. word(0x12345670) .. pointer(payload) .. word(0x7fffffff) .. word(0)
    put(rows + 5 * 24, entry)
    local atlas = word(0x87654321) .. word(0xabcdef01)
    local raw = string.rep("\0", 8) .. atlas .. string.rep("\0", 8) .. vector(0.125, 0.25, 0.25, 0.5)
    put(payload, raw)
    local art, why = reader:atlas(picture)
    equal(why, "ready"); equal(art.texture, "abcdef0187654321", "64-bit atlas hash retains all bits")
    equal(table.concat(art.uv, ","), "0.125,0.25,0.375,0.75", "offset+scale becomes UV corners")
    equal(reader:atlas("1234567000000072"), nil, "missing key stops at chain sentinel")
    put(rows + 16, word(0xfffffffe))
    equal(reader:atlas(picture), nil, "native empty bucket sentinel")
    put(rows + 16, word(8)); equal(reader:atlas(picture), nil, "out-of-bounds chain rejected")
    put(rows + 16, word(0)); equal(reader:atlas(picture), nil, "cyclic chain bounded")
    put(rows + 16, word(5))
    put(manager + 0x2b4, word(0)); equal(reader:atlas(picture), nil, "zero divisor rejected")
    put(manager + 0x2b4, word(1048577)); equal(reader:atlas(picture), nil, "oversized table rejected")
    put(manager + 0x2b4, word(1)); equal(reader:atlas(picture), nil, "count exceeds table capacity")
    put(manager + 0x2b4, word(8))
    for _, uv in ipairs({vector(-0.01, 0, 1, 1), vector(0, 0, 0, 1), vector(0.5, 0, 0.75, 1),
        vector(0, 0, 1, 0), vector(0/0, 0, 1, 1), vector(math.huge, 0, 1, 1)}) do
        put(payload + 24, uv); equal(reader:atlas(picture), nil, "invalid/nonfinite UV rejected")
    end
    put(payload, raw)
    local original, reads = channel.read, 0
    function channel:read(at, size)
        if at == manager + 0x2a0 then
            reads = reads + 1
            if reads == 2 then return header:sub(1, 23) .. "\1" .. header:sub(25) end
        end
        return original(self, at, size)
    end
    art, why = reader:atlas(picture); equal(art, nil); equal(why, "atlas-changed", "atlas replacement rejected")
    channel.read = original
    channel.exe_base = nil; equal(reader:atlas(picture), nil, "absent EXE base safe fallback")
    channel.exe_base = 0x18000000
    put(record + 184, word(2))
    local primary, secondary, tertiary = vector(0.8, 0.34, 0.84, 0.98), vector(1, 1, 1, 0.93), vector(0.2, 0, 0, 0)
    put(channel.base + 0x331b610 + 32, primary)
    put(channel.base + 0x21e89e0, secondary); put(channel.base + 0x21e8a10, tertiary)
    art, why = reader:icon({record = record}, picture)
    equal(why, "ready")
    equal(art.colors[1][1] > 0.79 and art.colors[1][1] < 0.81, true)
    equal(art.colors[1][4] > 0.97 and art.colors[1][4] < 0.99, true, "raw vector component order")
    equal(art.colors[2][1], 1); equal(art.colors[3][2], 0)
    put(record + 184, word(5)); equal(reader:icon({record = record}, picture), nil, "color array bounds")
    put(record + 184, word(2)); put(channel.base + 0x21e89e0, vector(13, 0, 0, 0))
    equal(reader:icon({record = record}, picture), nil, "incorrect color constant location cannot become shader data")
end

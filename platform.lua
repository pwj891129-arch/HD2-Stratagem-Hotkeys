local Platform = {}
Platform.PIN = {
    exe = "f5fee03dcfdb2e553a4752c283590950ac13316b376d8196aa556ff0400d5f06",
    game = "2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e",
}
Platform.declarations = [[
typedef struct { unsigned short vk, scan; unsigned int flags, time; uintptr_t extra; } HD2SH_KEY;
typedef struct { int x, y; unsigned int data, flags, time; uintptr_t extra; } HD2SH_MOUSE;
typedef union { HD2SH_KEY key; HD2SH_MOUSE mouse; } HD2SH_UNION;
typedef struct { unsigned int type; HD2SH_UNION value; } HD2SH_INPUT;
void* HD2SH_GetForegroundWindow(void) __asm__("GetForegroundWindow");
unsigned int HD2SH_GetWindowThreadProcessId(void*, unsigned int*) __asm__("GetWindowThreadProcessId");
unsigned int HD2SH_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");
short HD2SH_GetAsyncKeyState(int) __asm__("GetAsyncKeyState");
unsigned int HD2SH_SendInput(unsigned int, const HD2SH_INPUT*, int) __asm__("SendInput");
unsigned int HD2SH_MapVirtualKeyW(unsigned int, unsigned int) __asm__("MapVirtualKeyW");
void* HD2SH_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");
unsigned int HD2SH_GetModuleFileNameW(void*, unsigned short*, unsigned int) __asm__("GetModuleFileNameW");
void* HD2SH_GetCurrentProcess(void) __asm__("GetCurrentProcess");
int HD2SH_ReadProcessMemory(void*, const void*, void*, size_t, size_t*) __asm__("ReadProcessMemory");
void* HD2SH_CreateFileW(const unsigned short*, unsigned int, unsigned int, void*, unsigned int, unsigned int, void*) __asm__("CreateFileW");
int HD2SH_ReadFile(void*, void*, unsigned int, unsigned int*, void*) __asm__("ReadFile");
int HD2SH_CloseHandle(void*) __asm__("CloseHandle");
typedef struct { int x, y; } HD2SH_POINT;
typedef struct { int left, top, right, bottom; } HD2SH_RECT;
int HD2SH_GetCursorPos(HD2SH_POINT*) __asm__("GetCursorPos");
int HD2SH_ScreenToClient(void*, HD2SH_POINT*) __asm__("ScreenToClient");
int HD2SH_ClientToScreen(void*, HD2SH_POINT*) __asm__("ClientToScreen");
int HD2SH_GetClientRect(void*, HD2SH_RECT*) __asm__("GetClientRect");
int HD2SH_SetCursorPos(int, int) __asm__("SetCursorPos");
int HD2SH_BCryptOpenAlgorithmProvider(void**, const unsigned short*, const unsigned short*, unsigned int) __asm__("BCryptOpenAlgorithmProvider");
int HD2SH_BCryptCloseAlgorithmProvider(void*, unsigned int) __asm__("BCryptCloseAlgorithmProvider");
int HD2SH_BCryptCreateHash(void*, void**, void*, unsigned int, const void*, unsigned int, unsigned int) __asm__("BCryptCreateHash");
int HD2SH_BCryptHashData(void*, const void*, unsigned int, unsigned int) __asm__("BCryptHashData");
int HD2SH_BCryptFinishHash(void*, void*, unsigned int, unsigned int) __asm__("BCryptFinishHash");
int HD2SH_BCryptDestroyHash(void*) __asm__("BCryptDestroyHash");
]]

function Platform.mouse_keys(mouse)
    local keys = {}
    if not mouse or type(mouse.button_id) ~= "function" or type(mouse.button_name) ~= "function" then return keys end
    for _, button in ipairs({{"extra_1", 5}, {"extra_2", 6}}) do
        local good, index = pcall(mouse.button_id, button[1])
        if good and type(index) == "number" and index == math.floor(index) and index >= 0 and index < 4096 then
            local named, name = pcall(mouse.button_name, index)
            if named and name == button[1] then keys[index] = button[2] end
        end
    end
    return keys
end

function Platform.send_key(user, input, vk, pressed, virtual)
    if type(vk) ~= "number" or vk ~= math.floor(vk) or vk <= 6 or vk > 254 then return false end
    local scan = user.HD2SH_MapVirtualKeyW(vk, 4)
    if scan == 0 then return false end
    input[0].type = 1
    input[0].value.key.vk = virtual and vk or 0
    input[0].value.key.scan = scan % 256
    input[0].value.key.flags = (scan >= 256 and 1 or 0) + (virtual and 0 or 8) + (pressed and 0 or 2)
    input[0].value.key.time, input[0].value.key.extra = 0, 0
    return user.HD2SH_SendInput(1, input, 40) == 1
end

function Platform.send_list(user, input, vk, pressed)
    if vk ~= 5 and vk ~= 6 then return Platform.send_key(user, input, vk, pressed, false) end
    input[0].type = 0
    local mouse = input[0].value.mouse
    mouse.x, mouse.y, mouse.data = 0, 0, vk == 5 and 1 or 2
    mouse.flags, mouse.time, mouse.extra = pressed and 0x80 or 0x100, 0, 0
    return user.HD2SH_SendInput(1, input, 40) == 1
end

function Platform.create(ffi)
    assert(ffi.abi("64bit"), "Windows x64 required")
    ffi.cdef(Platform.declarations)
    local kernel, user, bcrypt = ffi.load("kernel32"), ffi.load("user32"), ffi.load("bcrypt")
    local exe, game = kernel.HD2SH_GetModuleHandleA(nil), kernel.HD2SH_GetModuleHandleA("game.dll")
    assert(exe ~= nil and game ~= nil, "game modules unavailable")
    local function digest(module)
        local path = ffi.new("unsigned short[32768]")
        local length = kernel.HD2SH_GetModuleFileNameW(module, path, 32768)
        if length == 0 or length >= 32768 then return nil end
        local file = kernel.HD2SH_CreateFileW(path, 0x80000000, 7, nil, 3, 0, nil)
        if file == ffi.cast("void*", -1) then return nil end
        local algorithm, hash = ffi.new("void*[1]"), ffi.new("void*[1]")
        local name = ffi.new("unsigned short[7]", {83, 72, 65, 50, 53, 54, 0})
        local buffer, size = ffi.new("unsigned char[65536]"), ffi.new("unsigned int[1]")
        local output, good = ffi.new("unsigned char[32]"), false
        if bcrypt.HD2SH_BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0 and
            bcrypt.HD2SH_BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) == 0 then
            good = true
            while true do
                if kernel.HD2SH_ReadFile(file, buffer, 65536, size, nil) == 0 then good = false; break end
                if size[0] == 0 then break end
                if bcrypt.HD2SH_BCryptHashData(hash[0], buffer, size[0], 0) ~= 0 then good = false; break end
            end
            if good then good = bcrypt.HD2SH_BCryptFinishHash(hash[0], output, 32, 0) == 0 end
        end
        if hash[0] ~= nil then bcrypt.HD2SH_BCryptDestroyHash(hash[0]) end
        if algorithm[0] ~= nil then bcrypt.HD2SH_BCryptCloseAlgorithmProvider(algorithm[0], 0) end
        kernel.HD2SH_CloseHandle(file)
        if not good then return nil end
        local result = {}
        for i = 0, 31 do result[#result + 1] = string.format("%02x", output[i]) end
        return table.concat(result)
    end
    assert(digest(exe) == Platform.PIN.exe and digest(game) == Platform.PIN.game,
        "unsupported game binary; native reads disabled")
    local process, pid = kernel.HD2SH_GetCurrentProcess(), ffi.new("unsigned int[1]")
    local process_id = kernel.HD2SH_GetCurrentProcessId()
    local actual, input = ffi.new("size_t[1]"), ffi.new("HD2SH_INPUT[1]")
    assert(ffi.sizeof("HD2SH_INPUT") == 40, "INPUT layout mismatch")
    input[0].type = 1
    local mouse_keys = Platform.mouse_keys((rawget(_G, "stingray") or {}).Mouse)
    local cursor, rect = ffi.new("HD2SH_POINT[1]"), ffi.new("HD2SH_RECT[1]")
    local function window()
        local handle = user.HD2SH_GetForegroundWindow()
        user.HD2SH_GetWindowThreadProcessId(handle, pid)
        if pid[0] == process_id then return handle end
    end
    return {
        base = tonumber(ffi.cast("uintptr_t", game)),
        exe_base = tonumber(ffi.cast("uintptr_t", exe)),
        read = function(_, at, size)
            if type(at) ~= "number" or at < 65536 or at >= 140737488355328 or
                size < 1 or size > 262144 then return nil end
            local buffer = ffi.new("unsigned char[?]", size)
            if kernel.HD2SH_ReadProcessMemory(process, ffi.cast("void*", at), buffer,
                size, actual) == 0 or tonumber(actual[0]) ~= size then return nil end
            return ffi.string(buffer, size)
        end,
        foreground = function()
            user.HD2SH_GetWindowThreadProcessId(user.HD2SH_GetForegroundWindow(), pid)
            return pid[0] == process_id
        end,
        down = function(vk) return user.HD2SH_GetAsyncKeyState(vk) < 0 end,
        mouse_vk = function(index) return mouse_keys[index] end,
        cursor = function()
            local handle = window()
            if not handle or user.HD2SH_GetCursorPos(cursor) == 0 or
                user.HD2SH_ScreenToClient(handle, cursor) == 0 or
                user.HD2SH_GetClientRect(handle, rect) == 0 then return nil end
            local width, height = rect[0].right, rect[0].bottom
            if width < 100 or height < 100 then return nil end
            return cursor[0].x / width, 1 - cursor[0].y / height
        end,
        center_cursor = function()
            local handle = window()
            if not handle or user.HD2SH_GetClientRect(handle, rect) == 0 then return false end
            cursor[0].x, cursor[0].y = math.floor(rect[0].right / 2), math.floor(rect[0].bottom / 2)
            if user.HD2SH_ClientToScreen(handle, cursor) == 0 then return false end
            return user.HD2SH_SetCursorPos(cursor[0].x, cursor[0].y) ~= 0
        end,
        key = function(vk, pressed)
            return Platform.send_list(user, input, vk, pressed)
        end,
        command_key = function(vk, pressed)
            return Platform.send_key(user, input, vk, pressed, true)
        end,
    }
end
return Platform

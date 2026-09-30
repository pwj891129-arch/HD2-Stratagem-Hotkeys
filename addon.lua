-- HD2-Addon: mods/hd2_helper/stratagem_hotkeys
if rawget(_G, "HD2StratagemHotkeys") then return end
local Platform = (function()
-- @PLATFORM@
end)()
local Reader = (function()
-- @READER@
end)()
local Policy = (function()
-- @POLICY@
end)()
local loader = rawget(_G, "CowboyBingusModLoader")
if not loader or loader.api ~= 1 then return end
local file
pcall(function() file = loader.open_log("hd2_helper_stratagem_hotkeys.log") end)
local function log(line)
    if file then pcall(function() file:write(tostring(line) .. "\n"); file:flush() end) end
end
local ok, channel = pcall(function() return Platform.create(require("ffi")) end)
if not ok then log("DISABLED " .. tostring(channel)); return end
local sr = rawget(_G, "stingray") or {}
local app = sr.Application or {}
if type(app.time_since_launch) ~= "function" then log("DISABLED monotonic clock unavailable"); return end
local reader, policy = Reader.new(channel), Policy.new(channel.key)
local state = {version = "0.1.0-test", keys = {}, blocking_inputs = false}
rawset(_G, "HD2StratagemHotkeys", state)
log("START 0.1.0-test; native loadout/commands/saved keyboard bindings; no automatic throw")
local function note(reason)
    if reason ~= state.reason then log(reason); state.reason = reason end
end
local function tick()
    local now = app.time_since_launch()
    if type(now) ~= "number" then return end
    local focused = channel.foreground()
    local escape, enter, fire = channel.down(27), channel.down(13), channel.down(1)
    if focused then
        if enter and not state.enter then state.chat = not state.chat end
        if escape and not state.escape then state.chat = false end
    end
    state.enter, state.escape = enter, escape
    if not state.bindings or now >= (state.binding_due or 0) then
        local bindings, why = reader:bindings()
        state.bindings, state.binding_due = bindings, now + 0.25
        if not bindings then note("WAIT " .. why) end
    end
    local binding = state.bindings
    local modifier = binding and channel.down(binding.start_vk) or false
    local numbers, pressed, count = {}, nil, 0
    for slot = 1, 4 do
        numbers[slot] = channel.down(48 + slot)
        if numbers[slot] and not state.keys[slot] then pressed = slot; count = count + 1 end
    end
    state.keys = numbers
    local allowed = focused and modifier and not state.chat and not escape and not enter and
        not fire and reader:idle()
    state.blocking_inputs = focused and (modifier or policy.job ~= nil)
    if not allowed then
        policy:step(now, false)
        state.pending = nil
        return
    end
    if pressed and count == 1 and not policy.job and not state.pending then
        state.pending = {slot = pressed, due = now + 0.05, expires = now + 0.35}
    end
    if state.pending and now >= state.pending.due then
        if now > state.pending.expires then note("SKIP stratagem-menu-not-active"); state.pending = nil
        elseif reader:menu_active() then
            local slot = state.pending.slot
            state.pending = nil
            local request, why = reader:request(slot)
            if request then
                local clean = true
                for _, vk in ipairs(request.bindings.directions) do
                    if channel.down(vk) then clean = false end
                end
                if clean and request.bindings.start_vk == binding.start_vk then
                    policy:start(request, now)
                    log("COMMAND slot=" .. slot .. " kind=" .. request.kind .. " steps=" .. #request.keys)
                else note("SKIP direction-key-already-held-or-binding-changed") end
            else note("SKIP " .. why) end
        end
    end
    if policy.job then
        local loadout = reader:loadout()
        local request = policy.job.request
        local same_binding = binding.start_vk == request.bindings.start_vk
        for direction = 1, 4 do
            same_binding = same_binding and binding.directions[direction] == request.bindings.directions[direction]
        end
        local same = loadout and loadout.token == request.token and same_binding and reader:menu_active()
        local result = policy:step(now, same)
        if result then log(result) end
    end
end
local previous = rawget(_G, "update")
rawset(_G, "update", function(...)
    local good, why = pcall(tick)
    if not good then
        policy:cancel(); state.pending, state.blocking_inputs = nil, false
        log("ERROR " .. tostring(why))
    end
    if type(previous) == "function" then return previous(...) end
end)
local shutdown = rawget(_G, "shutdown")
rawset(_G, "shutdown", function(...)
    policy:cancel(); state.blocking_inputs = false
    if file then pcall(function() file:close() end); file = nil end
    if type(shutdown) == "function" then return shutdown(...) end
end)

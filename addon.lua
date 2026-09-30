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
local Radial = (function()
-- @RADIAL@
end)()
local loader = rawget(_G, "CowboyBingusModLoader")
if not loader or loader.api ~= 1 then return end
local file
pcall(function() file = loader.open_log("hd2_helper_stratagem_hotkeys.log") end)
local function log(line)
    if file then pcall(function() file:write(tostring(line) .. "\n"); file:flush() end) end
end
log("BOOT 0.1.4-test lua-only; platform-init")
local ok, channel = pcall(function() return Platform.create(require("ffi")) end)
if not ok then log("DISABLED " .. tostring(channel)); return end
log("BOOT platform-ready")
local sr = rawget(_G, "stingray") or {}
local app = sr.Application or {}
if type(app.time_since_launch) ~= "function" then log("DISABLED monotonic clock unavailable"); return end
local function option(name, fallback)
    if not app.can_get then return fallback end
    local resource = "mods/hd2_helper/stratagem_option_" .. name
    local good, present = pcall(app.can_get, "lua", resource)
    if not good or not present then return false end
    local loaded, value = pcall(require, resource)
    return loaded and value == true
end
local config = {radial = option("radial", false), hotkeys = option("hotkeys", true),
    shared = option("shared", false),
    scale = option("large", false) and 1.3 or 1,
    delay = option("slow", false) and 0.030 or 0.015}
local reader, policy = Reader.new(channel), Policy.new(channel.key)
policy.delay = config.delay
local radial = Radial.new(sr, channel, config.scale)
local state = {version = "0.1.4-test", keys = {}, blocking_inputs = false, config = config}
rawset(_G, "HD2StratagemHotkeys", state)
log("START 0.1.4-test; Arsenal-only options; list-key radial; command only; no automatic throw")
log("CONFIG radial=" .. tostring(config.radial) .. " hotkeys=" .. tostring(config.hotkeys))
local function note(reason)
    if reason ~= state.reason then log(reason); state.reason = reason end
end
local function release_start()
    if state.owned_start then
        if not channel.key(state.owned_start, false) then return false end
        state.owned_start = nil
    end
    state.release_due = nil
    return true
end
local function stop()
    policy:cancel()
    state.pending = nil
    state.radial_binding = nil
    local good, why = pcall(radial.close, radial)
    state.release_due = 0
    release_start()
    if not good then error(why) end
end
local function same_binding(a, b)
    if not a or not b or a.start_vk ~= b.start_vk then return false end
    for direction = 1, 4 do if a.directions[direction] ~= b.directions[direction] then return false end end
    return true
end
local function clean(request)
    for _, vk in ipairs(request.bindings.directions) do if channel.down(vk) then return false end end
    return true
end
local function tick()
    local now = app.time_since_launch()
    if type(now) ~= "number" then return end
    local focused = channel.foreground()
    if state.release_due and (now >= state.release_due or not focused) then release_start() end
    if policy.cancelled then
        policy:cancel(); state.release_due = 0; release_start()
        state.blocking_inputs = policy.held ~= nil or state.owned_start ~= nil
        return
    end
    if not radial.opened then radial:restore() end
    local escape, enter, fire = channel.down(27), channel.down(13), channel.down(1)
    if focused then
        if enter and not state.enter then state.chat = not state.chat end
        if escape and not state.escape then state.chat = false end
    end
    state.enter, state.escape = enter, escape
    if not state.bindings or now >= (state.binding_due or 0) then
        local bindings, why = reader:bindings()
        if bindings and not same_binding(bindings, state.bindings) then
            log("BINDING list-key vk=" .. bindings.start_vk)
        end
        state.bindings, state.binding_due = bindings, now + 0.25
        if not bindings then note("WAIT " .. why) end
    end
    local binding = state.bindings
    local modifier = binding and channel.down(binding.start_vk) or false
    -- An injected list-key hold finishes a command; it must not reopen the radial.
    local overlay = config.radial and modifier and not state.owned_start or false
    local overlay_pressed, overlay_released = overlay and not state.overlay, not overlay and state.overlay
    state.overlay = overlay
    local numbers, pressed, count = {}, nil, 0
    for slot = 1, 4 do
        numbers[slot] = channel.down(48 + slot)
        if numbers[slot] and not state.keys[slot] then pressed = slot; count = count + 1 end
    end
    state.keys = numbers
    local allowed = focused and binding and not state.chat and not escape and not enter and not fire and reader:idle()
    if not allowed then
        stop()
        if overlay_pressed then note("OVERLAY blocked focus-chat-menu-or-fire") end
        state.blocking_inputs = focused and modifier
        return
    end
    -- Number shortcuts take priority over the radial on the same list-key hold.
    local shortcut = config.hotkeys and modifier and pressed and count == 1 and
        not policy.job and not state.pending and not state.owned_start
    if shortcut then
        radial:close()
        state.radial_binding = nil
        state.pending = {slot = pressed, due = now + 0.05, expires = now + 0.35}
    end
    if overlay_pressed and not shortcut and not policy.job and not state.pending and not state.owned_start and not state.radial_failed then
        log("OVERLAY list-key pressed vk=" .. binding.start_vk)
        local inventory, why = reader:radial(config.shared)
        if inventory then
            local opened; opened, why = radial:open(inventory)
            if opened then
                state.radial_binding, state.radial_read_due = binding, now + 0.05
                log("OVERLAY opened rows=" .. #inventory.rows)
            end
        end
        if why ~= "ready" and why ~= nil then note("OVERLAY " .. why) end
    end
    if radial.opened then
        if not same_binding(binding, state.radial_binding) then
            stop(); note("OVERLAY cancelled binding-changed")
        elseif now >= (state.radial_read_due or 0) then
            local current = reader:radial(config.shared)
            if not current or current.token ~= radial.inventory.token then
                stop(); note("OVERLAY cancelled loadout-or-state-changed")
            else radial.inventory, state.radial_read_due = current, now + 0.05 end
        end
        if radial.opened and not radial:draw(radial.inventory) then
            stop(); note("OVERLAY cancelled surface-unavailable")
        elseif radial.opened and overlay_released then
            local row = radial.selected and radial.inventory.rows[radial.selected]
            radial:close()
            state.radial_binding = nil
            if row and row.ready then
                local request, why = reader:request_kind(row.kind, config.shared)
                if request and clean(request) and same_binding(binding, request.bindings) then
                    if modifier or channel.key(binding.start_vk, true) then
                        if not modifier then state.owned_start = binding.start_vk end
                        state.pending = {kind = row.kind, token = request.token, due = now + 0.05, expires = now + 0.5}
                    else note("SKIP stratagem-start-key-failed") end
                else note("SKIP " .. (why or "direction-held-or-binding-changed")) end
            end
        end
    end
    if state.pending and now >= state.pending.due then
        local pending = state.pending
        if now > pending.expires or (not modifier and not state.owned_start) then
            stop(); note("SKIP stratagem-menu-not-active")
        elseif reader:menu_active() then
            state.pending = nil
            local request, why
            if pending.kind then request, why = reader:request_kind(pending.kind, config.shared)
            else request, why = reader:request(pending.slot) end
            if request and (not pending.token or pending.token == request.token) and
                clean(request) and same_binding(binding, request.bindings) then
                policy:start(request, now)
                log("COMMAND kind=" .. request.kind .. " steps=" .. #request.keys)
            else release_start(); note("SKIP " .. (why or "loadout-binding-or-direction-changed")) end
        end
    end
    if policy.job then
        local loadout = reader:loadout()
        local request = policy.job.request
        local same = (modifier or state.owned_start ~= nil) and loadout and loadout.token == request.token and
            same_binding(binding, request.bindings) and reader:menu_active()
        local result = policy:step(now, same)
        if result then
            log(result)
            if not policy.job then state.release_due = now + 0.03 end
        end
    end
    state.blocking_inputs = modifier or radial.opened or state.pending ~= nil or policy.job ~= nil or state.owned_start ~= nil
end
local previous = rawget(_G, "update")
rawset(_G, "update", function(...)
    local good, why = pcall(tick)
    if not good then
        pcall(stop)
        state.blocking_inputs = policy.held ~= nil or state.owned_start ~= nil
        state.radial_failed = true
        log("ERROR " .. tostring(why))
    end
    if type(previous) == "function" then return previous(...) end
end)
local shutdown = rawget(_G, "shutdown")
rawset(_G, "shutdown", function(...)
    pcall(stop); pcall(radial.dispose, radial); state.blocking_inputs = false
    if file then pcall(function() file:close() end); file = nil end
    if type(shutdown) == "function" then return shutdown(...) end
end)

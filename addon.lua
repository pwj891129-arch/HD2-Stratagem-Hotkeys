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
log("BOOT 0.1.12-test lua-only; platform-init")
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
local reader = Reader.new(channel)
local policy = Policy.new(channel.command_key, function(binding) return reader:command_state(binding) end)
policy.delay = config.delay
local radial = Radial.new(sr, channel, config.scale, log)
local state = {version = "0.1.12-test", keys = {}, blocking_inputs = false, config = config}
rawset(_G, "HD2StratagemHotkeys", state)
log("START 0.1.12-test; Arsenal-only options; list-key radial; command only; no automatic throw")
log("OVERLAY icon-path=atlas-rgb-mask; read-only lookup; owned-GUI materials")
log("INPUT direction-mode=virtual-key; game-action-observation=required")
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
    state.open_pending = nil
    state.radial_binding = nil
    state.radial_menu_token = nil
    state.highlight = nil
    local good, why = pcall(radial.close, radial)
    state.release_due = 0
    release_start()
    if not good then error(why) end
end
local function same_binding(a, b)
    if not a or not b or a.start_vk ~= b.start_vk or a.owner ~= b.owner then return false end
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
            log("BINDING list-key vk=" .. bindings.start_vk .. " device=" ..
                ((bindings.start_vk == 5 or bindings.start_vk == 6) and "mouse-thumb" or "keyboard"))
            state.list_ready = not channel.down(bindings.start_vk)
            if not state.list_ready then log("WAIT list-key-release") end
        end
        if not bindings then state.list_ready = false end
        state.bindings, state.binding_due = bindings, now + 0.25
        if not bindings then note("WAIT " .. why) end
    end
    local binding = state.bindings
    local modifier = binding and channel.down(binding.start_vk) or false
    if binding and not modifier then state.list_ready = true end
    -- An injected list-key hold finishes a command; it must not reopen the radial.
    local overlay = config.radial and state.list_ready and modifier and not state.owned_start or false
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
        local was_open, was_pending = radial.opened, state.pending ~= nil or state.open_pending ~= nil
        stop()
        if overlay_pressed or was_open or was_pending then
            local why = not focused and "focus-lost" or not binding and "binding-unavailable" or
                (state.chat or enter) and "chat" or escape and "escape" or fire and "fire" or "game-menu"
            note((was_open and "OVERLAY cancelled " or was_pending and "INPUT cancelled " or "OVERLAY blocked ") .. why)
        end
        state.blocking_inputs = focused and modifier
        return
    end
    local game, game_why
    if modifier or radial.opened or state.pending or policy.job then game, game_why = reader:game_menu() end
    local native_active = game and game.active == true
    -- Number shortcuts take priority over the radial on the same list-key hold.
    local shortcut = config.hotkeys and state.list_ready and modifier and pressed and count == 1 and
        not policy.job and not state.pending and not state.owned_start
    if shortcut and game then
        radial:close()
        state.open_pending = nil
        state.radial_binding = nil
        state.radial_menu_token = nil
        state.pending = {slot = pressed, menu_token = game.token, bindings = binding,
            due = now + 0.05, expires = now + 0.35}
    elseif shortcut then
        note("SKIP " .. (game_why or "stratagem-menu-state-unavailable"))
    end
    if overlay_pressed and not shortcut and not policy.job and not state.pending and not state.owned_start and not state.radial_failed then
        log("OVERLAY list-key pressed vk=" .. binding.start_vk)
        if game then
            state.open_pending = {expires = now + 0.35, binding = binding, menu_token = game.token}
        else note("OVERLAY blocked " .. (game_why or "stratagem-menu-state-unavailable")) end
    end
    if state.open_pending then
        local waiting = state.open_pending
        if not overlay or not same_binding(binding, waiting.binding) then
            state.open_pending = nil
        elseif not game or game.token ~= waiting.menu_token then
            state.open_pending = nil
            note("OVERLAY blocked character-state-changed")
        elseif now > waiting.expires then
            state.open_pending = nil
            note("OVERLAY blocked " .. (game_why or "game-stratagem-menu-not-active"))
        elseif native_active then
            state.open_pending = nil
            local inventory, why = reader:radial(config.shared)
            if inventory then
                local opened; opened, why = radial:open(inventory)
                if opened then
                    state.radial_binding, state.radial_read_due = binding, now + 0.05
                    state.radial_menu_token = game.token
                    state.highlight = nil
                    log("OVERLAY opened rows=" .. #inventory.rows)
                end
            end
            if why ~= "ready" and why ~= nil then note("OVERLAY " .. why) end
        end
    end
    if radial.opened then
        if not game or game.token ~= state.radial_menu_token then
            stop(); note("OVERLAY cancelled character-state-changed")
        elseif overlay and not native_active then
            stop(); note("OVERLAY cancelled game-stratagem-menu-closed")
        elseif not same_binding(binding, state.radial_binding) then
            stop(); note("OVERLAY cancelled binding-changed")
        elseif now >= (state.radial_read_due or 0) then
            local current = reader:radial(config.shared)
            if not current or current.token ~= radial.inventory.token then
                stop(); note("OVERLAY cancelled loadout-or-state-changed")
            else radial.inventory, state.radial_read_due = current, now + 0.05 end
        end
        if radial.opened and overlay_released then
            -- The game can recenter the cursor on key-up; keep the last held-frame selection.
            local row = radial.selected and radial.inventory.rows[radial.selected]
            radial:close()
            state.radial_binding = nil
            state.radial_menu_token = nil
            state.highlight = nil
            if row and row.ready then
                log("OVERLAY selected kind=" .. row.kind)
                local request, why = reader:request_kind(row.kind, config.shared)
                if request and clean(request) and same_binding(binding, request.bindings) then
                    state.pending = {kind = row.kind, token = request.token, menu_token = game.token,
                        bindings = request.bindings, stage = "release",
                        due = now + 0.03, expires = now + 0.75}
                    log("INPUT waiting-list-close kind=" .. row.kind)
                else note("SKIP " .. (why or "direction-held-or-binding-changed")) end
            else note(row and ("OVERLAY cancelled unavailable kind=" .. row.kind .. " status=" .. row.status) or
                "OVERLAY cancelled center-or-no-selection") end
        elseif radial.opened and not radial:draw(radial.inventory) then
            stop(); note("OVERLAY cancelled surface-unavailable")
        elseif radial.opened and radial.selected ~= state.highlight then
            state.highlight = radial.selected
            local row = radial.selected and radial.inventory.rows[radial.selected]
            log(row and ("OVERLAY highlight kind=" .. row.kind) or "OVERLAY highlight center")
        end
    end
    if state.pending and now >= state.pending.due then
        local pending = state.pending
        if now > pending.expires then
            stop(); note(pending.stage == "release" and "SKIP list-close-timeout" or "SKIP stratagem-menu-not-active")
        elseif pending.bindings and not same_binding(binding, pending.bindings) then
            stop(); note("SKIP binding-changed")
        elseif not game or game.token ~= pending.menu_token then
            stop(); note("SKIP character-state-changed")
        elseif pending.stage == "release" then
            if modifier then
                stop(); note("SKIP list-key-pressed-again")
            elseif radial.mouse or native_active or reader:menu_active() then
                pending.settled = nil
            elseif not pending.settled then
                pending.settled = now + 0.03
            elseif now >= pending.settled then
                local request, why = reader:request_kind(pending.kind, config.shared)
                if request and request.token == pending.token and clean(request) and
                    same_binding(binding, request.bindings) then
                    if channel.key(binding.start_vk, true) then
                        state.owned_start = binding.start_vk
                        pending.stage, pending.due, pending.expires = "menu", now + 0.05, now + 0.5
                        log("INPUT list-key-acquired vk=" .. binding.start_vk)
                    else stop(); note("SKIP stratagem-start-key-failed") end
                else stop(); note("SKIP " .. (why or "loadout-binding-or-direction-changed")) end
            end
        elseif not modifier and not state.owned_start then
            stop(); note("SKIP stratagem-menu-not-active")
        elseif native_active and reader:menu_active() then
            if pending.stage == "menu" and not pending.menu_ready then
                pending.menu_ready = now + 0.015
            elseif not pending.menu_ready or now >= pending.menu_ready then
                state.pending = nil
                local request, why
                if pending.kind then request, why = reader:request_kind(pending.kind, config.shared)
                else request, why = reader:request(pending.slot) end
                if request and (not pending.token or pending.token == request.token) and
                    clean(request) and same_binding(binding, request.bindings) then
                    request.menu_token = game.token
                    local started; started, why = policy:start(request, now)
                    if started then
                        log("COMMAND kind=" .. request.kind .. " steps=" .. #request.keys ..
                            " keys=" .. table.concat(request.keys, ",") .. " list_vk=" .. binding.start_vk)
                    else release_start(); note("SKIP " .. why) end
                else release_start(); note("SKIP " .. (why or "loadout-binding-or-direction-changed")) end
            end
        else
            pending.menu_ready = nil
        end
    end
    if policy.job then
        local loadout = reader:loadout()
        local request = policy.job.request
        local same = (modifier or state.owned_start ~= nil) and loadout and loadout.token == request.token and
            same_binding(binding, request.bindings) and native_active and game.token == request.menu_token and reader:menu_active()
        local result, observed = policy:step(now, same)
        if observed then log(observed) end
        if result then
            log(result == "command-complete" and "command-input-observed; game-result-unverified" or result)
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

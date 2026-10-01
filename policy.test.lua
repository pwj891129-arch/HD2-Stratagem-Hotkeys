return function(equal)
    local Policy = dofile("policy.lua")
    local events, held, state, readable, failures = {}, {}, nil, true, {}
    local function snapshot()
        if not readable then return nil end
        return state or {start = true, directions = {held[38] == true, held[39] == true,
            held[40] == true, held[37] == true}}
    end
    local function sender(vk, down)
        events[#events + 1] = {vk, down}
        local key = down and "press" or "release"
        if failures[key] then failures[key] = failures[key] - 1; if failures[key] >= 0 then return false end end
        held[vk] = down
        return true
    end
    local request = {keys = {38, 38, 39}, directions = {1, 1, 2}, bindings = {owner = 123}}
    local function restart()
        events, held, state, readable, failures = {}, {}, nil, true, {}
        return Policy.new(sender, snapshot)
    end
    equal(Policy.new(sender):start(request, 0), false, "no blind sending without observer")
    equal(Policy.new(nil, snapshot):start(request, 0), false, "no fallback input route")
    local observed_binding
    local binding_policy = Policy.new(sender, function(binding) observed_binding = binding; return snapshot() end)
    binding_policy:start(request, 0); binding_policy:step(0, true)
    equal(observed_binding, request.bindings, "observer checks exact request input owner")
    for _, invalid in ipairs({{}, {keys = {}}, {keys = {38}, directions = {}},
        {keys = {38}, directions = {5}}, {keys = {38}, directions = {1.5}},
        {keys = {38.5}, directions = {1}}, {keys = {1}, directions = {1}},
        {keys = {255}, directions = {1}}, {keys = {"38"}, directions = {1}}}) do
        equal(restart():start(invalid, 0), false, "invalid key/direction declined before input")
    end
    local p = restart()
    equal(p:start(request, 0), true)
    state = {start = true, directions = {false, false, false, false}}
    p:step(0.05, true)
    equal(#events, 1)
    p:step(0.08, true)
    equal(#events, 1, "unobserved key held rather than advancing after fixed delay")
    state.directions[1] = true
    local result, observed = p:step(0.1, true)
    equal(result, nil); equal(observed, "game-direction-observed step=1 direction=1 vk=38")
    equal(#events, 2, "observed first direction released")
    p:step(0.12, true)
    equal(#events, 2, "next repeated arrow waits for native action to clear")
    state.directions[1] = false; p:step(0.13, true)
    equal(#events, 3, "fresh edge only after clear action")
    state.directions[1] = true; p:step(0.15, true)
    state.directions[1] = false; p:step(0.17, true)
    state.directions[2] = true
    equal(p:step(0.19, true), "command-complete")
    equal(#events, 6); equal(p.held, nil)

    p = restart(); p:start(request, 0); p:step(0.05, true)
    local _, once = p:step(0.051, true)
    equal(once ~= nil, true, "one-frame action is latched before minimum hold time")
    state = {start = true, directions = {false, false, false, false}}
    equal(#events, 1)
    result, observed = p:step(0.066, true)
    equal(#events, 2, "latched press releases even after native press pulse ended")
    equal(observed, nil, "observed action logs only once")
    p:cancel()

    p = restart(); p:start(request, 0)
    state = {start = true, directions = {false, false, false, false}}
    p:step(0.05, true)
    equal(p:step(0.301, true), "game-direction-not-observed step=1 direction=1 vk=38")
    equal(#events, 2, "missing receipt releases first direction without retry or remaining command")
    equal(p.job, nil); equal(p.held, nil)
    p:step(0.4, true); equal(#events, 2, "timeout cannot resume or duplicate input")

    p = restart(); p:start(request, 0); p:step(0.05, true); p:step(0.07, true)
    state = {start = true, directions = {true, false, false, false}}
    equal(p:step(0.321, true), "game-direction-reset-timeout step=2")
    equal(#events, 2, "uncleared prior press never receives another down")

    p = restart(); state = {start = true, directions = {false, true, false, false}}
    p:start(request, 0); p:step(0.05, true)
    equal(#events, 0, "stale game input must clear before first key")
    equal(p:step(0.301, true), "game-direction-reset-timeout step=1")
    equal(#events, 0)

    p = restart(); p:start(request, 0); p:step(0.05, true)
    state = {start = true, directions = {true, true, false, false}}
    equal(p:step(0.07, true), "game-direction-conflict step=1")
    equal(#events, 2); equal(p.job, nil)

    for _, broken in ipairs({{start = false, directions = {false, false, false, false}},
        {start = true, directions = {true, 1, false, false}}, {start = true}}) do
        p = restart(); p:start(request, 0); p:step(0.05, true); state = broken
        equal(p:step(0.07, true), "game-action-state-unavailable")
        equal(#events, 2); equal(p.held, nil)
    end
    p = restart(); p:start(request, 0); p:step(0.05, true); readable = false
    equal(p:step(0.07, true), "game-action-state-unavailable")
    equal(#events, 2, "unreadable action snapshot releases owned key")

    p = restart(); p:start(request, 0); p:step(0.05, true); failures.release = 1
    equal(p:step(0.07, true), "key-release-failed")
    equal(p.job, nil, "failed key-up cancels whole command")
    equal(p.held, 38)
    equal(p:step(0.09, true), "cancelled", "failed release retried without new direction")
    equal(p.held, nil); equal(#events, 3)

    p = restart(); failures.press = 1; p:start(request, 0)
    equal(p:step(0.05, true), "key-press-failed")
    equal(p.job, nil); equal(p.held, nil); equal(#events, 1)

    p = restart(); p.delay = 0.03; p:start(request, 0); p:step(0.05, true)
    p:step(0.07, true); equal(#events, 1, "30ms option still bounds hold despite observed input")
    p:step(0.081, true); equal(#events, 2)
    p:step(0.10, true); equal(#events, 2, "30ms option bounds released gap")
    p:step(0.112, true); equal(#events, 3)
    p:cancel()

    p = restart(); p:start(request, 0); p:step(0.05, true)
    equal(p:step(2.1, true), "cancelled", "whole sequence bounded despite long frame stall")
    equal(#events, 2); equal(p.held, nil)

    p = restart()
    local longest = {keys = {}, directions = {}}
    for index = 1, 12 do longest.keys[index], longest.directions[index] = 38, 1 end
    equal(p:start(longest, 0), true)
    local completed
    for frame = 1, 50 do
        local value = p:step(frame * 0.0334, true)
        if value then completed = value end
    end
    equal(completed, "command-complete", "12-step repeat sequence works at 30 FPS")
    equal(#events, 24); equal(p.held, nil)
    longest.keys[13], longest.directions[13] = 38, 1
    equal(p:start(longest, 2), false, "overlong command declined")
end

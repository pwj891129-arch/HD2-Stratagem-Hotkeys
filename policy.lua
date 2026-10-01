local Policy = {}
Policy.__index = Policy
function Policy.new(sender, observer)
    return setmetatable({sender = sender, observer = observer, delay = 0.015, timeout = 0.25}, Policy)
end
function Policy:cancel()
    self.job = nil
    if self.held and not self.sender(self.held, false) then
        self.cancelled = true
        return false, "key-release-failed"
    end
    self.held, self.cancelled = nil, nil
    return true
end
function Policy:start(request, now)
    if self.job or self.held then return false, "busy" end
    if type(self.sender) ~= "function" or type(self.observer) ~= "function" then
        return false, "input-observer-unavailable"
    end
    if not request or type(request.keys) ~= "table" or type(request.directions) ~= "table" or
        #request.keys < 1 or #request.keys > 12 or #request.directions ~= #request.keys then
        return false, "invalid-command"
    end
    for index, vk in ipairs(request.keys) do
        local direction = request.directions[index]
        if type(vk) ~= "number" or vk ~= math.floor(vk) or vk <= 6 or vk > 254 or
            type(direction) ~= "number" or direction ~= math.floor(direction) or direction < 1 or direction > 4 then
            return false, "invalid-command"
        end
    end
    self.job = {request = request, index = 1, phase = "clear", due = now + 0.05,
        deadline = now + 0.05 + self.timeout, expires = now + 2.0}
    return true
end
function Policy:abort(reason)
    local good = self:cancel()
    return good and reason or "key-release-failed"
end
function Policy:step(now, allowed)
    if self.cancelled then
        local good = self:cancel()
        return good and "cancelled" or "key-release-failed"
    end
    local job = self.job
    if not job then return nil end
    if not allowed or now > job.expires then
        local ok = self:cancel()
        return ok and "cancelled" or "key-release-failed"
    end
    local state = self.observer(job.request.bindings)
    if not state or type(state.directions) ~= "table" or state.start ~= true then
        return self:abort("game-action-state-unavailable")
    end
    local clear, direction, observed = true, job.request.directions[job.index], nil
    for index = 1, 4 do
        if type(state.directions[index]) ~= "boolean" then return self:abort("game-action-state-unavailable") end
        if state.directions[index] then
            clear = false
            if job.phase == "press" and index ~= direction then
                return self:abort("game-direction-conflict step=" .. job.index)
            end
        end
    end
    if job.phase == "press" then
        if state.directions[direction] and not job.observed then
            job.observed = true
            observed = "game-direction-observed step=" .. job.index .. " direction=" .. direction ..
                " vk=" .. job.request.keys[job.index]
        end
        if not job.observed then
            if now >= job.deadline then
                return self:abort("game-direction-not-observed step=" .. job.index .. " direction=" .. direction ..
                    " vk=" .. job.request.keys[job.index])
            end
            return nil
        end
        if now < job.due then return nil, observed end
        if not self.sender(self.held, false) then
            self.job, self.cancelled = nil, true
            return "key-release-failed", observed
        end
        self.held = nil
        job.index, job.due = job.index + 1, now + self.delay
        job.phase, job.deadline, job.observed = "clear", now + self.timeout, nil
        if job.index > #job.request.keys then self.job = nil; return "command-complete", observed end
    elseif clear and now >= job.due then
        local vk = job.request.keys[job.index]
        if not self.sender(vk, true) then self:cancel(); return "key-press-failed" end
        self.held, job.due = vk, now + self.delay
        job.phase, job.deadline = "press", now + self.timeout
    elseif now >= job.deadline then
        return self:abort("game-direction-reset-timeout step=" .. job.index)
    end
    return nil, observed
end
return Policy

local Policy = {}
Policy.__index = Policy
function Policy.new(sender)
    return setmetatable({sender = sender, delay = 0.015}, Policy)
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
    if not request or #request.keys < 1 or #request.keys > 12 then return false, "invalid-command" end
    self.job = {request = request, index = 1, due = now + 0.05, expires = now + 2.0}
    return true
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
    if now < job.due then return nil end
    if self.held then
        if not self.sender(self.held, false) then return "key-release-failed" end
        self.held = nil
        job.index, job.due = job.index + 1, now + self.delay
        if job.index > #job.request.keys then self.job = nil; return "command-complete" end
    else
        local vk = job.request.keys[job.index]
        if not self.sender(vk, true) then self:cancel(); return "key-press-failed" end
        self.held, job.due = vk, now + self.delay
    end
    return nil
end
return Policy

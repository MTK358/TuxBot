
local socket = require 'socket'

local EventLoop = {}
EventLoop.__index = EventLoop

setmetatable(EventLoop, {__call = function (_)
    local self = {}
    setmetatable(self, EventLoop)
    self._readable_handlers = {}
    setmetatable(self._readable_handlers, {__mode='v'})
    self._writable_handlers = {}
    setmetatable(self._writable_handlers, {__mode='v'})
    self._timers = {}
    -- timers always eventually run out, so no risk of memory leaks.
    return self
end})

local timer_mt = {
    cancel = function (self)
        self._running = false
    end,
    isrunning = function (self)
        return self._running
    end,
}
timer_mt.__index = timer_mt

function EventLoop:timer(timeout, cb)
    local tbl = {
        _time = socket.gettime() + timeout,
        _running = true,
    }
    setmetatable(tbl, timer_mt)
    self._timers[tbl] = cb
    return tbl
end

function EventLoop:add_readable_handler(sock, callback)
    self._readable_handlers[{sock}] = callback
end

function EventLoop:add_writable_handler(sock, callback)
    self._writable_handlers[{sock}] = callback
end

function EventLoop:remove_readable_handler(sock, callback)
    for k, v in pairs(self._readable_handlers) do
        if k[1] == sock and v == callback then self._readable_handlers[k] = nil end
    end
end

function EventLoop:remove_writable_handler(sock, callback)
    for k, v in pairs(self._writable_handlers) do
        if k[1] == sock and v == callback then self._writable_handlers[k] = nil end
    end
end

function EventLoop:remove_socket_handlers(sock, callback)
    self:remove_readable_handler(sock, callback)
    self:remove_writable_handler(sock, callback)
end

function EventLoop:step()
    local rsockets, wsockets = {}, {}
    for k, v in pairs(self._readable_handlers) do
        rsockets[#rsockets+1] = k[1]
    end
    for k, v in pairs(self._writable_handlers) do
        wsockets[#wsockets+1] = k[1]
    end
    local r, w, _ = socket.select(rsockets,
                                  wsockets,
                                  self:_seconds_to_next_timer())
    local readable_handlers, writable_handlers = {}, {}
    for k, v in pairs(self._readable_handlers) do readable_handlers[k] = v end
    for k, v in pairs(self._writable_handlers) do writable_handlers[k] = v end
    for _, sock in pairs(r) do
        for k, v in pairs(readable_handlers) do
            if k[1] == sock then
                local success, errmsg = pcall(v)
                if not success then
                    io.stderr:write(('error in socket readable event handler: %s\n'):format(tostring(errmsg)))
                    self._writable_handlers[k] = nil
                else
                    if not errmsg then self._readable_handlers[k] = nil end
                end
            end
        end
    end
    for _, sock in pairs(w) do
        for k, v in pairs(writable_handlers) do
            if k[1] == sock then
                local success, errmsg = pcall(v)
                if not success then
                    io.stderr:write(('error in socket writable event handler: %s\n'):format(tostring(errmsg)))
                    self._writable_handlers[k] = nil
                else
                    if not errmsg then self._writable_handlers[k] = nil end
                end
            end
        end
    end
    for k, v in pairs(self._timers) do
        if k._time <= socket.gettime() then
            if k._running then
                local success, errmsg = pcall(v)
                if not success then
                    io.stderr:write(('error in timer event handler: %s\n'):format(tostring(errmsg)))
                end
            end
            self._timers[k] = nil
        end
    end
end

function EventLoop:run()
    self._exit = false
    repeat self:step() until self._exit
end

function EventLoop:exit()
    self._exit = true
end

function EventLoop:_seconds_to_next_timer()
    local t = socket.gettime() + 5
    for k, v in pairs(self._timers) do
        if k._time < t then
            t = k._time
        end
    end
    t = t - socket.gettime()
    return t < 0 and 0 or t
end

return EventLoop



local permtypes = {}

local function permspec2func(ps)
    if type(ps) ~= 'table' then ps = {ps} end
    return assert(permtypes[ps[1]], 'no such permission type: '..tostring(ps[1]))(ps)
end

-- FIXME networks with superop and owner modes
permtypes.halfop = function (args)--{{{
    return function (client, chan, nick)
        local tracker = bot.clients[client].tracker
        if tracker then
            local cs = tracker.chanstates[chan]
            if cs and cs.members[nick] and cs.members[nick].mode:match('[ho]') then
                return true
            end
        end
        return false
    end
end--}}}
permtypes.op = function (args)--{{{
    return function (client, chan, nick)
        local tracker = bot.clients[client].tracker
        if tracker then
            local cs = tracker.chanstates[chan]
            if cs and cs.members[nick] and cs.members[nick].mode:match('o') then
                return true
            end
        end
        return false
    end
end--}}}
permtypes.chanwhitelist = function (args)--{{{
    return function (client, chan, nick)
        for i = 2, #args do
            local arg = args[i]
            if type(arg) == 'string' then
                if chan:match(arg) then return true end
            else
                if client.netinfo.name:match(arg[1]) and chan:match(arg[2]) then return true end
            end
        end
        return false
    end
end--}}}
permtypes.and_ = function (args)--{{{
    for i = 2, #args do
        args[i] = permspec2func(args[i])
    end
    return function (client, chan, nick)
        for i = 2, #args do
            if not args[i](client, chan, nick) then
                return false
            end
        end
        return true
    end
end--}}}
permtypes.or_ = function (args)--{{{
    for i = 2, #args do
        args[i] = permspec2func(args[i])
    end
    return function (client, chan, nick)
        for i = 2, #args do
            if args[i](client, chan, nick) then
                return true
            end
        end
        return false
    end
end--}}}

for action, perms in pairs(config) do
    config[action] = permspec2func(perms)
end

-- exposed
function check(action, client, chan, nick)
    if not config[action] then return false end
    return config[action](client, chan, nick)
end


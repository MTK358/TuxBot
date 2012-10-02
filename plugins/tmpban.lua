
--[[local lpeg = require 'lpeg'

local timestrpattern = lpeg.P {
    (days + hours + minutes + seconds)^1,
    days = lpeg.V'number' * 'd',
    hours = lpeg.V'number' * 'h',
    minutes = lpeg.V'number' * 'm',
    seconds = lpeg.V'number' * ('s' + ('' - lpeg.P(1))),
    number = lpeg.R'09'^1,
}--]]

local waiting_for_whoreply = {}

local function msgcallback(client, msg)
    if msg.cmd == '352' then -- RPL_WHOREPLY
        local channels = waiting_for_whoreply[tostring(msg.client)..' '..client:lower(msg.args[6])]
        if channels then
            for _, channel in pairs(channels) do
                msg.client:sendmessage('MODE', channel.name, '+b', '*!*@'..msg.args[4])
                msg.client:sendmessage('KICK', channel.name, msg.args[6], channel.msg)
                bot.eventloop:timer(channel.time, function ()
                    msg.client:sendmessage('MODE', channel.name, '-b', '*!*@'..msg.args[4])
                end)
            end
            waiting_for_whoreply[tostring(msg.client)..' '..client:lower('*!*@'..msg.args[6])] = nil
        end
    end
end

bot.event_callbacks['receivedmessage_post'] = msgcallback

-- global
function tmpban(client, chan, nick, time, message)
    local key = tostring(client)..' '..client:lower(nick)
    if not waiting_for_whoreply[key] then
        waiting_for_whoreply[key] = {}
    end
    local addmsg = ('Temporary ban: %s seconds'):format(time)
    waiting_for_whoreply[key][chan] = {
        name = chan,
        msg = message and ('%s (%s)'):format(message, addmsg) or addmsg,
        time = time,
    }
    client:sendmessage('WHO', nick)
    bot.eventloop:timer(15, function ()
        if waiting_for_whoreply[key] and waiting_for_whoreply[key][chan] then
            waiting_for_whoreply[key][chan] = nil
            if not next(waiting_for_whoreply[key]) then
                waiting_for_whoreply[key] = nil
            end
        end
    end)
end

local function tmpban_callback(msg, arg)
    if not bot.plugins.perms.check('tmpban', msg.client, msg.args[1], msg.sender.nick) then
        bot.reply(msg, msg.sender.nick..': You are not permitted to use this command.')
        return
    end
    local nick, time, message = arg:match('^ *([^ ]+) +(%d+) +([^ ].*)$')
    if not nick then
        local nick, time = arg:match('^ *([^ ]+) +(%d+) *$')
        if not nick then
            bot.reply(msg, msg.sender.nick..': Usage: tmpban <nick> <seconds> [<message>]')
            return
        end
    end
    tmpban(msg.client, msg.args[1], nick, tonumber(time), message)
end

bot.commands['tmpban'] = {tmpban_callback, help='tmpban <nick> <time> [<message>] -- temporarily ban a user'}


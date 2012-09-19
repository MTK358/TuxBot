
local pattern = config and config.pattern or '^.*$' -- 5 chars or less
local count = config and config.count or 10
local interval = config and config.interval or 1.6
local bantime = config and config.bantime or 30
local kickmsg = config and config.kickmsg or 'Flooding'

local timers = {}

local function msghandler(client, msg)
    if (msg.cmd == 'PRIVMSG' or msg.cmd == 'NOTICE') and msg.args[2]:match(pattern) and irc.ischanname(msg.args[1]) then
        local key = msg.args[1]..' '..bot.clients[client].name
        if timers[key] then
            local t = timers[key]
            t.count = t.count + 1
            if t.count >= count then
                timers[key] = nil
                if bot.plugins.tmpban then
                    bot.plugins.tmpban.env.tmpban(msg.client, msg.args[1], msg.sender.nick, bantime, kickmsg)
                else
                    msg.client:sendmessage('KICK', msg.args[1], msg.sender.nick, kickmsg)
                end
            else
                t.timer:cancel()
                t.timer = bot.eventloop:timer(interval, function () timers[key] = nil end)
            end
        else
            local t = {count=1, timer=bot.eventloop:timer(interval, function () timers[key] = nil end)}
            timers[key] = t
        end
    end
end

bot.event_handlers['receivedmessage_post'] = msghandler


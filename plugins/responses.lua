
local re = require 're'

local responses = {}

for k, v in pairs(config.responses) do
    local success, result = pcall(re.compile, k)
    if not success then
        error(('error in pattern [[%s]]: %s'):format(k, result))
    else
        responses[result] = v
    end
end

local function msghandler(client, msg, ignored)
    if msg.cmd == 'PRIVMSG' and not ignored then
        local text = msg.args[2]:lower():gsub('[!:;,.?]', ''):gsub('%s+', ' ')
        for k, v in pairs(responses) do
            local matches = {k:match(text)}
            if matches[1] then
                local reply = v[math.random(1, #v)]
                reply = reply:gsub('%%(.)', function (c)
                    if c:match('%d') then
                        return matches[tonumber(c)] or ''
                    elseif c == 's' then
                        return msg.sender.nick
                    elseif c == '%' then
                        return '%'
                    else
                        return '%'..c
                    end
                end)
                bot.queue(client, function ()
                    bot.reply(msg, reply)
                end)
                break
            end
        end
    end
end

bot.event_handlers['receivedmessage_post'] = msghandler


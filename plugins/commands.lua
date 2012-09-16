
local function commands_handler(msg, arg)
    lines[#lines+1] = 'Command list:'
    for pluginname, plugin in pairs(bot.plugins) do
        for cmdname, cmd in pairs(plugin.commands) do
            lines[#lines+1] = cmd.help or cmdname
        end
    end
    lines[#lines+1] = 'End of command list.'
    bot.send_multiline(msg.sender.nick, lines, 'notice')
end

bot.commands['commands'] = setmetatable({commands_handler, help='commands -- Get a list of commands and their descriptions'},
                                        {__index = function (tbl, key)
    if key == 'mininterval' then
        local count = 0
        for pluginname, plugin in pairs(bot.plugins) do
            for cmdname, cmd in pairs(plugin.commands) do
                count = count + 1
            end
        end
        return count * 1.5
    end
    return nil
end})


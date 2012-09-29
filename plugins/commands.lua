
local function commands_handler(msg, arg)
    local command = arg:match('[^ ]+')
    if command then
        for pluginname, plugin in pairs(bot.plugins) do
            for cmdname, cmd in pairs(plugin.commands) do
                if cmdname == command then
                    bot.reply(msg, msg.sender.nick..': '..(cmd.help or 'the command has no help message'))
                    return
                end
            end
        end
        bot.reply(msg, msg.sender.nick..': no such command')
    else
        local text = msg.sender.nick..': available commands:'
        for pluginname, plugin in pairs(bot.plugins) do
            for cmdname, cmd in pairs(plugin.commands) do
                text = text..' '..cmdname
            end
        end
        bot.reply(msg, text)
    end
end

bot.commands['commands'] = setmetatable({commands_handler, help='commands -- Get a list of commands and their descriptions'})


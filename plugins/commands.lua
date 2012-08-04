
local function commands_handler(msg, arg)
    msg.client:sendnotice(msg.sender.nick, 'Command list:')
    for pluginname, plugin in pairs(bot.plugins) do
        for cmdname, cmd in pairs(plugin.commands) do
            msg.client:sendnotice(msg.sender.nick, cmd.help or cmdname)
        end
    end
    msg.client:sendnotice(msg.sender.nick, 'End of command list.')
end

bot.commands['commands'] = {commands_handler, help='commands -- Get a list of commands and their descriptions'}


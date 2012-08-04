
local function time_handler(msg, arg)
    arg = arg:match('^ *([^ *].*)$')
    local timestr = os.date(arg and '!'..arg  or (config and config.timefmt or '!%A %Y-%m-%d %H:%M:%S %Z'))
    bot.reply(msg, msg.sender.nick..': '..timestr)
end

bot.commands['time'] = {time_handler, help='time [<strftime>] -- Get the current time.'}


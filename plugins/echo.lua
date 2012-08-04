
local function echo_handler(msg, arg)
    bot.reply(msg, arg:gsub('^ +', ''))
end

bot.commands['echo'] = {echo_handler, help='echo <text> -- Echo the supplied text.'}


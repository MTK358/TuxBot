
local function luaapi_handler(msg, arg)
    local name = arg:match('[^ ]+')
    if name then
        if name:match('^[%d.]+$') or name:match('^luaL?_') then
            bot.reply(msg, ('%s: http://www.lua.org/manual/5.1/manual.html#%s'):format(msg.sender.nick, name))
        else
            bot.reply(msg, ('%s: http://www.lua.org/manual/5.1/manual.html#pdf-%s'):format(msg.sender.nick, name))
        end
    else
        bot.reply(msg, ('%s: Usage: luaapi <section or function name>'):format(msg.sender.nick))
    end
end

bot.commands['luaapi'] = {luaapi_handler, help='luaapi <section or function name> -- Get a link to a part of the Lua manual.'}

